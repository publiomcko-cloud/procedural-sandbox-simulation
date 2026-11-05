class_name TerrainAsyncCheckpointJob
extends RefCounted

## Worker-only checkpoint transaction.
##
## The main thread supplies an immutable snapshot of the current live tail.
## The worker reopens the last committed materialized world in an isolated
## TerrainMaterializedSdfStore, replays only that frozen tail, materializes it
## synchronously inside this worker, and commits a new head. The live state is
## not mutated here; the main thread later atomically advances its materialized
## base and preserves any newer edits that arrived while this job was running.

const Store := preload("res://scripts/terrain/terrain_materialized_sdf_store.gd")
const State := preload("res://scripts/terrain/terrain_scalable_sdf_state.gd")

var world_directory: String
var checkpoint_snapshot: Dictionary
var result: Dictionary = {}
var queued_usec := 0
var worker_started_usec := 0
var worker_finished_usec := 0
var worker_thread_id := 0


func _init(
	world_directory_value: String,
	checkpoint_snapshot_value: Dictionary,
	queued_value: int = 0
) -> void:
	world_directory = world_directory_value
	checkpoint_snapshot = checkpoint_snapshot_value.duplicate(true)
	queued_usec = queued_value


func run() -> void:
	worker_started_usec = Time.get_ticks_usec()
	worker_thread_id = OS.get_thread_caller_id()
	result = _run_checkpoint()
	worker_finished_usec = Time.get_ticks_usec()
	result["worker_usec"] = worker_finished_usec - worker_started_usec
	result["worker_thread_id"] = worker_thread_id


func _run_checkpoint() -> Dictionary:
	if world_directory.is_empty() or not bool(checkpoint_snapshot.get("valid", false)):
		return {"valid": false, "reason": "async_checkpoint_input_invalid"}

	var store := Store.new(world_directory)
	var loaded: Dictionary = store.load_world(Store.WORLD_ID)
	if not loaded.get("ok", false):
		return {
			"valid": false,
			"reason": "async_checkpoint_base_load_failed",
			"detail": loaded,
		}

	var state: RefCounted
	if loaded.get("found", false):
		state = loaded["state"]
	else:
		state = State.new(
			int(checkpoint_snapshot["world_seed"]),
			int(checkpoint_snapshot["generator_version"])
		)

	if int(state.world_seed) != int(checkpoint_snapshot["world_seed"]) \
		or int(state.generator_version) != int(checkpoint_snapshot["generator_version"]):
		return {"valid": false, "reason": "async_checkpoint_base_identity_mismatch"}

	var expected_archived := int(checkpoint_snapshot.get("token_archived_operation_count", -1))
	if state.get_edit_count() != expected_archived \
		or state.get_archived_edit_count() != expected_archived:
		return {
			"valid": false,
			"reason": "async_checkpoint_base_generation_mismatch",
			"base_count": state.get_edit_count(),
			"expected_archived": expected_archived,
		}

	var tail: Array = checkpoint_snapshot.get("tail_operations", [])
	for operation_value in tail:
		if typeof(operation_value) != TYPE_DICTIONARY:
			return {"valid": false, "reason": "async_checkpoint_tail_record_invalid"}
		var operation: Dictionary = operation_value
		if state.get_next_sequence() != int(operation.get("sequence", -1)):
			return {
				"valid": false,
				"reason": "async_checkpoint_tail_sequence_mismatch",
				"expected": state.get_next_sequence(),
				"actual": int(operation.get("sequence", -1)),
			}
		if not state.add_sphere(
			int(operation.get("mode", -1)),
			operation.get("center_world", Vector3.INF),
			float(operation.get("radius", -1.0))
		):
			return {
				"valid": false,
				"reason": "async_checkpoint_tail_replay_rejected",
				"sequence": int(operation.get("sequence", -1)),
				"detail": state.last_rejection_reason,
			}

	if state.revision != int(checkpoint_snapshot.get("token_revision", -1)) \
		or state.get_next_sequence() != int(checkpoint_snapshot.get("token_next_sequence", -1)) \
		or state.get_edit_count() != int(checkpoint_snapshot.get("token_lifetime_operation_count", -1)):
		return {"valid": false, "reason": "async_checkpoint_replay_token_mismatch"}

	# We are already in a worker thread. use_worker_pool=false prevents nested
	# worker tasks and keeps checkpoint work completely outside gameplay frames.
	var saved: Dictionary = store.checkpoint_state(Store.WORLD_ID, state, false)
	if not saved.get("ok", false):
		return {
			"valid": false,
			"reason": "async_checkpoint_store_commit_failed",
			"detail": saved,
		}

	return {
		"valid": true,
		"saved": saved,
		"head": store.get_head_metadata(),
		"store": store,
		"checkpoint_snapshot": checkpoint_snapshot,
	}
