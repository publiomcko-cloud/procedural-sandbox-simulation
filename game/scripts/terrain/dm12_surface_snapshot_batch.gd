class_name DM12SurfaceSnapshotBatch
extends RefCounted

## Main-thread phase slicing of immutable environment SDF snapshot preparation.
## Preserves the exact 16-chunk ordering, all typed arrays, IDs and revisions.
## No worker starts, no publication and no scene mutation until completion.
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")

var region_key: Vector2i
var revision: int
var scope_id: int
var coordinates: Array[Vector2i] = []
var next_index := 0
var base_snapshots: Dictionary = {}
var effect_targets: Array[Dictionary] = []
var anchor_snapshot: Dictionary = {}
var elapsed_usec_total := 0
var calls := 0


func _init(key: Vector2i, expected_revision: int, expected_scope: int) -> void:
	region_key = key
	revision = expected_revision
	scope_id = expected_scope
	coordinates = Grid.all_coordinates()


func capture(brush_state: RefCounted, max_chunks: int = 3,
	budget_usec: int = 3000) -> Dictionary:
	if brush_state == null or int(brush_state.revision) != revision \
		or int(brush_state.get_instance_id()) != scope_id:
		return {"ok": false, "reason": "surface_snapshot_batch_revision_changed"}
	if max_chunks < 1 or budget_usec < 1:
		return {"ok": false, "reason": "surface_snapshot_batch_invalid_budget"}
	var started_usec := Time.get_ticks_usec()
	var processed := 0
	while next_index < coordinates.size() and processed < max_chunks:
		if processed > 0 and Time.get_ticks_usec() - started_usec >= budget_usec:
			break
		var coordinate: Vector2i = coordinates[next_index]
		var snapshot: Dictionary = brush_state.get_meshing_snapshot_for_chunk(
			region_key, coordinate
		)
		if not bool(snapshot.get("valid", false)):
			return {"ok": false,
				"reason": String(snapshot.get("storage_error", "surface_snapshot_batch_invalid"))}
		if int(snapshot.get("revision", -1)) != revision \
			or int(snapshot.get("cache_scope_id", -1)) != scope_id:
			return {"ok": false, "reason": "surface_snapshot_batch_stale"}
		base_snapshots[coordinate] = snapshot
		effect_targets.append({
			"region_key": region_key, "chunk_coordinate": coordinate
		})
		if anchor_snapshot.is_empty():
			anchor_snapshot = snapshot
		next_index += 1
		processed += 1
	calls += 1
	var elapsed_usec := Time.get_ticks_usec() - started_usec
	elapsed_usec_total += elapsed_usec
	return {
		"ok": true,
		"complete": next_index == coordinates.size(),
		"processed": processed,
		"captured": next_index,
		"remaining": coordinates.size() - next_index,
		"elapsed_usec": elapsed_usec,
	}


func prepared_inputs() -> Dictionary:
	if next_index != coordinates.size() or base_snapshots.size() != coordinates.size() \
		or effect_targets.size() != coordinates.size() or anchor_snapshot.is_empty():
		return {}
	return {
		"base_snapshots": base_snapshots,
		"effect_targets": effect_targets,
		"anchor_snapshot": anchor_snapshot,
		"capture_calls": calls,
		"capture_total_usec": elapsed_usec_total,
	}
