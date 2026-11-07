extends SceneTree

const Registry := preload("res://scripts/modding/content_definition_registry.gd")
const ObjectWorld := preload("res://scripts/objects/procedural_object_world.gd")
const Effect := preload("res://scripts/terrain/terrain_object_effect.gd")
const Frame := preload("res://scripts/terrain/terrain_object_effect_local_frame.gd")
const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const TerrainMeshJob := preload("res://scripts/terrain/terrain_mesh_job.gd")
const Transition := preload("res://scripts/experiments/lod01_transition_fixture.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")

const WORLD_ID := "issue108-d8-lod1-effects"
const WORLD_SEED := 424242
const CHUNK := Vector2i(1, 1)
const TEST_REGIONS := [
	Vector2i.ZERO,
	Vector2i(100000000, 100000000),
	Vector2i(-100000000, -100000000),
]

var assertions := 0
var failures := 0
var evidence: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry := Registry.new()
	var registered: Dictionary = registry.discover_and_register(
		["res://mods/first-party"]
	)
	_check(registered.get("ok", false), "D8 first-party registry initializes")
	if not registered.get("ok", false):
		_finish()
		return

	var generated: Dictionary = ObjectWorld.build_region_instances(
		WORLD_SEED, WORLD_ID, Vector2i.ZERO, registry
	)
	_check(generated.get("ok", false), "D8 reference procedural region generates")
	var source := _first_interacting(generated.get("instances", []))
	_check(not source.is_empty(), "D8 reference interacting source exists")
	if source.is_empty():
		_finish()
		return

	var baseline_planes: Array = []
	var baseline_bounds_min: Array = []
	var baseline_bounds_max: Array = []
	var baseline_cutter := NAN
	var region_results: Array[Dictionary] = []

	for index in range(TEST_REGIONS.size()):
		var region_key: Vector2i = TEST_REGIONS[index]
		var instance := _relocate(
			source,
			region_key,
			Vector3i(
				6000,
				(source["position_mm"] as Vector3i).y,
				4500
			),
			"r%d" % index
		)
		var built_effect: Dictionary = Effect.build_from_instance(instance, 7)
		_check(
			built_effect.get("ok", false),
			"D8 effect builds in signed region %s" % region_key
		)
		if not built_effect.get("ok", false):
			continue
		var built_frame: Dictionary = Frame.build_from_instance(
			instance, built_effect["effect"], 7
		)
		_check(
			built_frame.get("ok", false),
			"D8 local frame builds in signed region %s" % region_key
		)
		if not built_frame.get("ok", false):
			continue
		var frame: Dictionary = built_frame["frame"]

		if index == 0:
			baseline_planes = frame["local_planes"]
			baseline_bounds_min = frame["bounds_min_local"]
			baseline_bounds_max = frame["bounds_max_local"]
		else:
			_check(
				frame["local_planes"] == baseline_planes
					and frame["bounds_min_local"] == baseline_bounds_min
					and frame["bounds_max_local"] == baseline_bounds_max,
				"D8 effect frame geometry is translation-invariant in region-local space"
			)

		var ledger := Brush.new(WORLD_SEED, Field.GENERATOR_VERSION)
		var snapshot: Dictionary = ledger.get_meshing_snapshot_for_chunk(
			region_key, CHUNK
		)
		_check(
			snapshot.get("valid", false),
			"D8 chunk snapshot builds for region %s" % region_key
		)
		snapshot["terrain_object_effect_frames"] = [frame]
		snapshot["terrain_effect_frame_count"] = 1

		var interior := _array_to_vector3(frame["interior_point_local"])
		var cutter := Frame.sample_cutter_prevalidated(
			frame, region_key, interior
		)
		var without_effect := snapshot.duplicate(true)
		without_effect["terrain_object_effect_frames"] = []
		var density_without := Brush.sample_density_snapshot(
			WORLD_SEED, region_key, interior, false, without_effect
		)
		var density_with := Brush.sample_density_snapshot(
			WORLD_SEED, region_key, interior, false, snapshot
		)
		_check(
			is_finite(cutter)
				and density_with <= density_without
				and absf(density_with - minf(density_without, cutter)) < 0.000001,
			"D8 LOD sampler snapshot composes the anchored imprint in region-local space"
		)
		if index == 0:
			baseline_cutter = cutter
		else:
			_check(
				absf(cutter - baseline_cutter) <= 0.000000000001,
				"D8 cutter is invariant at +/-100M signed regions"
			)

		var job := TerrainMeshJob.new(
			WORLD_SEED,
			region_key,
			CHUNK,
			false,
			snapshot,
			Time.get_ticks_usec(),
			1
		)
		job.run()
		var result: Dictionary = job.result
		_check(
			result.get("valid", false)
				and int(result.get("lod_level", -1)) == 1
				and not bool(result.get("lod_fallback", false)),
			"D8 effect-bearing chunk remains LOD1 at region %s" % region_key
		)
		_check(
			_attributes_are_valid(result),
			"D8 LOD1 output is finite and attribute-matched at region %s" % region_key
		)
		_check(
			_positions_are_chunk_local(result.get("positions", PackedVector3Array())),
			"D8 LOD1 output remains bounded in chunk-local coordinates at region %s" % region_key
		)

		var chunk_origin := Grid.origin_for(CHUNK)
		var min_lattice := Vector3i(
			roundi(chunk_origin.x * 2.0),
			roundi(Grid.MIN_BOUND.y * 2.0),
			roundi(chunk_origin.z * 2.0)
		)
		var sampler := func(region_local_point: Vector3) -> float:
			return Brush.sample_density_snapshot(
				WORLD_SEED,
				region_key,
				region_local_point,
				false,
				snapshot
			)
		var transition: Dictionary = Transition.build_transition_cell(
			WORLD_SEED,
			min_lattice,
			[Transition.FACE_X_NEG],
			snapshot,
			sampler
		)
		_check(
			transition.get("valid", false)
				and _packed_finite(transition.get("vertices", PackedVector3Array()))
				and _packed_finite(transition.get("normals", PackedVector3Array())),
			"D8 LOD0/LOD1 transition cell accepts the same effect snapshot at region %s" % region_key
		)

		region_results.append({
			"region": [region_key.x, region_key.y],
			"triangle_count": int(result.get("triangle_count", 0)),
			"transition_cell_count": int(result.get("transition_cell_count", 0)),
			"cutter": cutter,
		})

	evidence = {
		"regions": region_results,
		"baseline_cutter": baseline_cutter,
		"production_frame": "source_region_local_v1",
		"lod1_effect_fallback_removed": true,
	}
	_finish()


func _attributes_are_valid(result: Dictionary) -> bool:
	var positions: PackedVector3Array = result.get(
		"positions", PackedVector3Array()
	)
	var normals: PackedVector3Array = result.get(
		"normals", PackedVector3Array()
	)
	return positions.size() == normals.size() 		and not positions.is_empty() 		and _packed_finite(positions) 		and _packed_finite(normals)


func _positions_are_chunk_local(values: PackedVector3Array) -> bool:
	var size := Grid.size_for(CHUNK)
	for point in values:
		if point.x < -0.001 or point.x > size.x + 0.001:
			return false
		if point.z < -0.001 or point.z > size.z + 0.001:
			return false
		if point.y < Grid.MIN_BOUND.y - 0.001 				or point.y > Grid.MAX_BOUND.y + 0.001:
			return false
	return true


func _packed_finite(values: PackedVector3Array) -> bool:
	for value in values:
		if not value.is_finite():
			return false
	return true


func _first_interacting(instances_value: Variant) -> Dictionary:
	if typeof(instances_value) != TYPE_ARRAY:
		return {}
	for value in instances_value:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var instance: Dictionary = value
		if not (instance.get("terrain_interaction", {}) as Dictionary).is_empty():
			return instance.duplicate(true)
	return {}


func _relocate(
	source: Dictionary,
	region_key: Vector2i,
	position_mm: Vector3i,
	suffix: String
) -> Dictionary:
	var instance := source.duplicate(true)
	instance["instance_id"] = "%s/seed-%d/d8/%s" % [
		WORLD_ID, WORLD_SEED, suffix
	]
	instance["world_id"] = WORLD_ID
	instance["world_seed"] = WORLD_SEED
	instance["generator_version"] = Field.GENERATOR_VERSION
	instance["region_key"] = region_key
	instance["position_mm"] = position_mm
	# Schema-v2 effect construction is authoritative from signed region + local
	# position. Keep the compatibility field populated without using it for D8
	# sampling or lattice construction.
	var region_size_x_mm := roundi(Spatial.REGION_SIZE_X * 1000.0)
	var region_size_z_mm := roundi(Spatial.REGION_SIZE_Z * 1000.0)
	instance["world_position_mm"] = Vector3i(
		region_key.x * region_size_x_mm + position_mm.x,
		position_mm.y,
		region_key.y * region_size_z_mm + position_mm.z
	)
	return instance


func _array_to_vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func _finish() -> void:
	print("ISSUE108_D8_LOD1_EFFECT_EVIDENCE=" + JSON.stringify(evidence))
	print("ISSUE108_D8_LOD1_EFFECT_%s: assertions=%d failures=%d" % [
		"PASS" if failures == 0 else "FAIL", assertions, failures
	])
	quit(0 if failures == 0 else 1)
