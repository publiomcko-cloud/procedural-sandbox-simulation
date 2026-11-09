extends RefCounted
class_name EnvironmentHydrologyBatchJob

## P5.0E pure cross-scope boundary solve.
## Input entries already contain post-P5.0D local runoff state plus immutable
## P5.0C surface data. This job mutates only its private copies.

const EnvironmentStoreScript := preload("res://scripts/simulation/environment_state_store.gd")
const GRID_WIDTH := 8
const GRID_HEIGHT := 6
const CELL_COUNT := GRID_WIDTH * GRID_HEIGHT
const RUNOFF_FRACTION_DENOMINATOR := 4
const RESERVOIR_EXCHANGE_UL_PER_TICK := 1_000_000

var work_snapshot: Dictionary
var result: Dictionary = {}
var worker_started_usec := 0
var worker_finished_usec := 0
var worker_thread_id := 0


func _init(snapshot: Dictionary) -> void:
	work_snapshot = snapshot.duplicate(true)


func run() -> void:
	worker_started_usec = Time.get_ticks_usec()
	worker_thread_id = OS.get_thread_caller_id()
	result = _solve(work_snapshot)
	worker_finished_usec = Time.get_ticks_usec()
	result["worker_usec"] = worker_finished_usec - worker_started_usec
	result["worker_thread_id"] = worker_thread_id


func _solve(snapshot: Dictionary) -> Dictionary:
	if typeof(snapshot.get("entries")) != TYPE_ARRAY:
		return _failure("environment_hydrology_batch_entries_invalid")
	var raw_entries: Array = snapshot["entries"]
	if raw_entries.is_empty():
		return {
			"ok": true,
			"reason": "ok",
			"updates": [],
			"scope_results": [],
			"cross_region_transfer_ul": 0,
			"reservoir_inflow_ul": 0,
			"reservoir_outflow_ul": 0,
			"boundary_transfer_count": 0,
		}

	var entries: Array[Dictionary] = []
	var by_region: Dictionary = {}
	var by_scope: Dictionary = {}
	for value in raw_entries:
		if typeof(value) != TYPE_DICTIONARY:
			return _failure("environment_hydrology_batch_entry_invalid")
		var entry: Dictionary = value.duplicate(true)
		var check := _validate_entry(entry)
		if not check.get("ok", false):
			return check
		var scope_id := String(entry["scope_id"])
		var region_key: Vector2i = entry["region_key"]
		if by_scope.has(scope_id) or by_region.has(_region_id(region_key)):
			return _failure("environment_hydrology_batch_duplicate_scope")
		var index := entries.size()
		entries.append(entry)
		by_scope[scope_id] = index
		by_region[_region_id(region_key)] = index

	# Private mutable arrays.
	for index in range(entries.size()):
		var entry: Dictionary = entries[index]
		entry["surface_water_ul"] = (
			entry["surface_water_ul"] as PackedInt64Array
		).duplicate()
		entry["soil_water_ul"] = (
			entry["soil_water_ul"] as PackedInt64Array
		).duplicate()
		entry["reservoir_kind"] = (
			entry["reservoir_kind"] as PackedByteArray
		).duplicate()
		entry["reservoir_level_mm"] = (
			entry["reservoir_level_mm"] as PackedInt64Array
		).duplicate()
		entry["reservoir_inflow_ul_delta"] = int(
			entry.get("reservoir_inflow_ul_delta", 0)
		)
		entry["reservoir_outflow_ul_delta"] = int(
			entry.get("reservoir_outflow_ul_delta", 0)
		)
		entries[index] = entry

	var base_surface: Array[PackedInt64Array] = []
	var outgoing: Array[PackedInt64Array] = []
	var incoming: Array[PackedInt64Array] = []
	for entry in entries:
		var surface: PackedInt64Array = entry["surface_water_ul"]
		base_surface.append(surface.duplicate())
		var out := PackedInt64Array()
		out.resize(CELL_COUNT)
		outgoing.append(out)
		var inc := PackedInt64Array()
		inc.resize(CELL_COUNT)
		incoming.append(inc)

	var reservoir_inflow_total := 0
	var reservoir_outflow_total := 0
	var cross_region_total := 0
	var transfer_count := 0

	# Same-scope reservoir exchange only. Finite-to-finite local flow was already
	# solved by P5.0D and must not be duplicated here.
	for entry_index in range(entries.size()):
		for z in range(GRID_HEIGHT):
			for x in range(GRID_WIDTH):
				var a := z * GRID_WIDTH + x
				if x + 1 < GRID_WIDTH:
					var b := z * GRID_WIDTH + (x + 1)
					var exchange := _reserve_pair_transfer(
						entries,
						base_surface,
						outgoing,
						incoming,
						entry_index,
						a,
						entry_index,
						b,
						false
					)
					reservoir_inflow_total += int(exchange["reservoir_inflow_ul"])
					reservoir_outflow_total += int(exchange["reservoir_outflow_ul"])
					transfer_count += int(exchange["transfer_count"])
				if z + 1 < GRID_HEIGHT:
					var b := (z + 1) * GRID_WIDTH + x
					var exchange := _reserve_pair_transfer(
						entries,
						base_surface,
						outgoing,
						incoming,
						entry_index,
						a,
						entry_index,
						b,
						false
					)
					reservoir_inflow_total += int(exchange["reservoir_inflow_ul"])
					reservoir_outflow_total += int(exchange["reservoir_outflow_ul"])
					transfer_count += int(exchange["transfer_count"])

	# Canonical +X / +Z cross-region edges. Each region pair is visited once.
	var region_order: Array[int] = []
	for i in range(entries.size()):
		region_order.append(i)
	region_order.sort_custom(func(a: int, b: int) -> bool:
		var ra: Vector2i = entries[a]["region_key"]
		var rb: Vector2i = entries[b]["region_key"]
		return ra.y < rb.y if ra.y != rb.y else ra.x < rb.x
	)
	for entry_index in region_order:
		var region: Vector2i = entries[entry_index]["region_key"]
		var east_id := _region_id(region + Vector2i(1, 0))
		if by_region.has(east_id):
			var other := int(by_region[east_id])
			for z in range(GRID_HEIGHT):
				var a := z * GRID_WIDTH + (GRID_WIDTH - 1)
				var b := z * GRID_WIDTH
				var exchange := _reserve_pair_transfer(
					entries, base_surface, outgoing, incoming,
					entry_index, a, other, b, true
				)
				reservoir_inflow_total += int(exchange["reservoir_inflow_ul"])
				reservoir_outflow_total += int(exchange["reservoir_outflow_ul"])
				cross_region_total += int(exchange["finite_cross_region_ul"])
				transfer_count += int(exchange["transfer_count"])
		var south_id := _region_id(region + Vector2i(0, 1))
		if by_region.has(south_id):
			var other := int(by_region[south_id])
			for x in range(GRID_WIDTH):
				var a := (GRID_HEIGHT - 1) * GRID_WIDTH + x
				var b := x
				var exchange := _reserve_pair_transfer(
					entries, base_surface, outgoing, incoming,
					entry_index, a, other, b, true
				)
				reservoir_inflow_total += int(exchange["reservoir_inflow_ul"])
				reservoir_outflow_total += int(exchange["reservoir_outflow_ul"])
				cross_region_total += int(exchange["finite_cross_region_ul"])
				transfer_count += int(exchange["transfer_count"])

	var updates: Array[Dictionary] = []
	var scope_results: Array[Dictionary] = []
	for index in range(entries.size()):
		var entry: Dictionary = entries[index]
		var surface: PackedInt64Array = entry["surface_water_ul"]
		for cell in range(CELL_COUNT):
			var next_surface := (
				int(base_surface[index][cell])
				- int(outgoing[index][cell])
				+ int(incoming[index][cell])
			)
			if next_surface < 0 or next_surface > EnvironmentStoreScript.MAX_WATER_UL_PER_CELL:
				return _failure("environment_hydrology_water_bound_violation")
			surface[cell] = next_surface
		entry["surface_water_ul"] = surface
		entries[index] = entry

		var update := {
			"scope_id": String(entry["scope_id"]),
			"expected_state_revision": int(entry["expected_state_revision"]),
			"last_environment_tick": int(entry["logical_tick"]),
			"surface_water_ul": (entry["surface_water_ul"] as PackedInt64Array).duplicate(),
			"soil_water_ul": (entry["soil_water_ul"] as PackedInt64Array).duplicate(),
			"reservoir_kind": (entry["reservoir_kind"] as PackedByteArray).duplicate(),
			"reservoir_level_mm": (entry["reservoir_level_mm"] as PackedInt64Array).duplicate(),
			"reservoir_inflow_ul_delta": int(entry["reservoir_inflow_ul_delta"]),
			"reservoir_outflow_ul_delta": int(entry["reservoir_outflow_ul_delta"]),
		}
		updates.append(update)
		scope_results.append({
			"scope_id": String(entry["scope_id"]),
			"logical_tick": int(entry["logical_tick"]),
			"expected_state_revision": int(entry["expected_state_revision"]),
			"surface_cache_token": (
				entry["surface_cache_token"] as Dictionary
			).duplicate(true),
			"finite_initial_ul": int(entry.get("finite_initial_ul", 0)),
			"pre_binding_finite_initial_ul": int(entry.get("pre_binding_finite_initial_ul", entry.get("finite_initial_ul", 0))),
			"finite_final_ul": _finite_total(entry),
			"precipitation_ul": int(entry.get("precipitation_ul", 0)),
			"evaporation_ul": int(entry.get("evaporation_ul", 0)),
			"local_runoff_ul": int(entry.get("local_runoff_ul", 0)),
			"binding_reservoir_inflow_ul": int(
				entry.get("binding_reservoir_inflow_ul", 0)
			),
		})

	return {
		"ok": true,
		"reason": "ok",
		"updates": updates,
		"scope_results": scope_results,
		"cross_region_transfer_ul": cross_region_total,
		"reservoir_inflow_ul": reservoir_inflow_total,
		"reservoir_outflow_ul": reservoir_outflow_total,
		"boundary_transfer_count": transfer_count,
	}


func _reserve_pair_transfer(
	entries: Array[Dictionary],
	base_surface: Array[PackedInt64Array],
	outgoing: Array[PackedInt64Array],
	incoming: Array[PackedInt64Array],
	a_entry: int,
	a_cell: int,
	b_entry: int,
	b_cell: int,
	cross_region: bool
) -> Dictionary:
	var a: Dictionary = entries[a_entry]
	var b: Dictionary = entries[b_entry]
	if (
		int((a["surface_valid"] as PackedByteArray)[a_cell]) == 0
		or int((b["surface_valid"] as PackedByteArray)[b_cell]) == 0
	):
		return _zero_exchange()

	var a_kind := int((a["reservoir_kind"] as PackedByteArray)[a_cell])
	var b_kind := int((b["reservoir_kind"] as PackedByteArray)[b_cell])
	var a_reservoir := a_kind != EnvironmentStoreScript.RESERVOIR_FINITE
	var b_reservoir := b_kind != EnvironmentStoreScript.RESERVOIR_FINITE
	if a_reservoir and b_reservoir:
		return _zero_exchange()

	if not a_reservoir and not b_reservoir:
		if not cross_region:
			return _zero_exchange()
		var a_height := int((a["surface_height_mm"] as PackedInt64Array)[a_cell])
		var b_height := int((b["surface_height_mm"] as PackedInt64Array)[b_cell])
		if a_height == b_height:
			return _zero_exchange()
		if a_height > b_height:
			var amount := _reserve_finite_to_finite(
				entries, base_surface, outgoing, incoming,
				a_entry, a_cell, b_entry, b_cell
			)
			return {
				"reservoir_inflow_ul": 0,
				"reservoir_outflow_ul": 0,
				"finite_cross_region_ul": amount,
				"transfer_count": 1 if amount > 0 else 0,
			}
		var amount := _reserve_finite_to_finite(
			entries, base_surface, outgoing, incoming,
			b_entry, b_cell, a_entry, a_cell
		)
		return {
			"reservoir_inflow_ul": 0,
			"reservoir_outflow_ul": 0,
			"finite_cross_region_ul": amount,
			"transfer_count": 1 if amount > 0 else 0,
		}

	var reservoir_entry := a_entry if a_reservoir else b_entry
	var reservoir_cell := a_cell if a_reservoir else b_cell
	var finite_entry := b_entry if a_reservoir else a_entry
	var finite_cell := b_cell if a_reservoir else a_cell
	var reservoir: Dictionary = entries[reservoir_entry]
	var finite: Dictionary = entries[finite_entry]
	var level := int(
		(reservoir["reservoir_level_mm"] as PackedInt64Array)[reservoir_cell]
	)
	var finite_height := int(
		(finite["surface_height_mm"] as PackedInt64Array)[finite_cell]
	)
	if level > finite_height:
		var amount := _reserve_reservoir_to_finite(
			entries, base_surface, incoming,
			reservoir_entry, finite_entry, finite_cell
		)
		return {
			"reservoir_inflow_ul": 0,
			"reservoir_outflow_ul": amount,
			"finite_cross_region_ul": 0,
			"transfer_count": 1 if amount > 0 else 0,
		}
	if finite_height > level:
		var amount := _reserve_finite_to_reservoir(
			entries, base_surface, outgoing,
			finite_entry, finite_cell, reservoir_entry
		)
		return {
			"reservoir_inflow_ul": amount,
			"reservoir_outflow_ul": 0,
			"finite_cross_region_ul": 0,
			"transfer_count": 1 if amount > 0 else 0,
		}
	return _zero_exchange()


func _reserve_finite_to_finite(
	entries: Array[Dictionary],
	base_surface: Array[PackedInt64Array],
	outgoing: Array[PackedInt64Array],
	incoming: Array[PackedInt64Array],
	source_entry: int,
	source_cell: int,
	destination_entry: int,
	destination_cell: int
) -> int:
	var source_available := (
		int(base_surface[source_entry][source_cell])
		- int(outgoing[source_entry][source_cell])
	)
	if source_available <= 0:
		return 0
	var elapsed := int(entries[source_entry]["elapsed_ticks"])
	var requested := mini(
		source_available,
		_saturating_product(_ceil_div(
			int(base_surface[source_entry][source_cell]),
			RUNOFF_FRACTION_DENOMINATOR
		), elapsed)
	)
	var destination_room := maxi(
		0,
		EnvironmentStoreScript.MAX_WATER_UL_PER_CELL
			- int(base_surface[destination_entry][destination_cell])
			- int(incoming[destination_entry][destination_cell])
	)
	var amount := mini(requested, destination_room)
	if amount <= 0:
		return 0
	outgoing[source_entry][source_cell] = (
		int(outgoing[source_entry][source_cell]) + amount
	)
	incoming[destination_entry][destination_cell] = (
		int(incoming[destination_entry][destination_cell]) + amount
	)
	return amount


func _reserve_finite_to_reservoir(
	entries: Array[Dictionary],
	base_surface: Array[PackedInt64Array],
	outgoing: Array[PackedInt64Array],
	finite_entry: int,
	finite_cell: int,
	reservoir_entry: int
) -> int:
	var available := (
		int(base_surface[finite_entry][finite_cell])
		- int(outgoing[finite_entry][finite_cell])
	)
	if available <= 0:
		return 0
	var elapsed := int(entries[finite_entry]["elapsed_ticks"])
	var amount := mini(
		available,
		_saturating_product(_ceil_div(
			int(base_surface[finite_entry][finite_cell]),
			RUNOFF_FRACTION_DENOMINATOR
		), elapsed)
	)
	if amount <= 0:
		return 0
	outgoing[finite_entry][finite_cell] = (
		int(outgoing[finite_entry][finite_cell]) + amount
	)
	var reservoir: Dictionary = entries[reservoir_entry]
	reservoir["reservoir_inflow_ul_delta"] = (
		int(reservoir["reservoir_inflow_ul_delta"]) + amount
	)
	entries[reservoir_entry] = reservoir
	return amount


func _reserve_reservoir_to_finite(
	entries: Array[Dictionary],
	base_surface: Array[PackedInt64Array],
	incoming: Array[PackedInt64Array],
	reservoir_entry: int,
	finite_entry: int,
	finite_cell: int
) -> int:
	var room := maxi(
		0,
		EnvironmentStoreScript.MAX_WATER_UL_PER_CELL
			- int(base_surface[finite_entry][finite_cell])
			- int(incoming[finite_entry][finite_cell])
	)
	if room <= 0:
		return 0
	var elapsed := mini(
		int(entries[reservoir_entry]["elapsed_ticks"]),
		int(entries[finite_entry]["elapsed_ticks"])
	)
	var amount := mini(
		room,
		_saturating_product(RESERVOIR_EXCHANGE_UL_PER_TICK, elapsed)
	)
	if amount <= 0:
		return 0
	incoming[finite_entry][finite_cell] = (
		int(incoming[finite_entry][finite_cell]) + amount
	)
	var reservoir: Dictionary = entries[reservoir_entry]
	reservoir["reservoir_outflow_ul_delta"] = (
		int(reservoir["reservoir_outflow_ul_delta"]) + amount
	)
	entries[reservoir_entry] = reservoir
	return amount


func _validate_entry(entry: Dictionary) -> Dictionary:
	for field in [
		"scope_id", "region_key", "logical_tick", "elapsed_ticks",
		"expected_state_revision", "surface_water_ul", "soil_water_ul",
		"reservoir_kind", "reservoir_level_mm", "surface_valid",
		"surface_height_mm", "surface_cache_token",
	]:
		if not entry.has(field):
			return _failure("environment_hydrology_batch_entry_fields_invalid")
	if typeof(entry["scope_id"]) != TYPE_STRING or String(entry["scope_id"]).is_empty():
		return _failure("environment_hydrology_batch_scope_invalid")
	if typeof(entry["region_key"]) != TYPE_VECTOR2I:
		return _failure("environment_hydrology_batch_region_invalid")
	if int(entry["logical_tick"]) < 0 or int(entry["elapsed_ticks"]) <= 0:
		return _failure("environment_hydrology_batch_tick_invalid")
	if (
		typeof(entry["surface_water_ul"]) != TYPE_PACKED_INT64_ARRAY
		or typeof(entry["soil_water_ul"]) != TYPE_PACKED_INT64_ARRAY
		or typeof(entry["reservoir_kind"]) != TYPE_PACKED_BYTE_ARRAY
		or typeof(entry["reservoir_level_mm"]) != TYPE_PACKED_INT64_ARRAY
		or typeof(entry["surface_valid"]) != TYPE_PACKED_BYTE_ARRAY
		or typeof(entry["surface_height_mm"]) != TYPE_PACKED_INT64_ARRAY
	):
		return _failure("environment_hydrology_batch_array_type_invalid")
	for field in [
		"surface_water_ul", "soil_water_ul", "reservoir_kind",
		"reservoir_level_mm", "surface_valid", "surface_height_mm",
	]:
		if entry[field].size() != CELL_COUNT:
			return _failure("environment_hydrology_batch_array_size_invalid")
	return {"ok": true, "reason": "ok"}


func _finite_total(entry: Dictionary) -> int:
	var surface: PackedInt64Array = entry["surface_water_ul"]
	var soil: PackedInt64Array = entry["soil_water_ul"]
	var kinds: PackedByteArray = entry["reservoir_kind"]
	var total := 0
	for cell in range(CELL_COUNT):
		if int(kinds[cell]) == EnvironmentStoreScript.RESERVOIR_FINITE:
			total += int(surface[cell]) + int(soil[cell])
	return total


func _zero_exchange() -> Dictionary:
	return {
		"reservoir_inflow_ul": 0,
		"reservoir_outflow_ul": 0,
		"finite_cross_region_ul": 0,
		"transfer_count": 0,
	}


func _ceil_div(value: int, divisor: int) -> int:
	if value <= 0:
		return 0
	return 1 + ((value - 1) / divisor)


func _saturating_product(value: int, multiplier: int) -> int:
	if value <= 0 or multiplier <= 0:
		return 0
	var limit := EnvironmentStoreScript.MAX_WATER_UL_PER_CELL
	if value > limit / multiplier:
		return limit
	return mini(limit, value * multiplier)


func _region_id(region: Vector2i) -> String:
	return "%d,%d" % [region.x, region.y]


func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
