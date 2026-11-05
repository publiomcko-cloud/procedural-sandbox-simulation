extends SceneTree

const Store := preload("res://scripts/terrain/terrain_world_save_store_v2.gd")
const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 2:
		push_error("PERSISTENCE_PROBE_ARGUMENTS_INVALID")
		quit(2)
		return
	var phase := arguments[0]
	var directory := arguments[1]
	var store := Store.new(directory)
	if phase == "write":
		var ledger: RefCounted = Brush.new(24681357, Field.GENERATOR_VERSION)
		if not ledger.add_sphere(Brush.Mode.CARVE, Vector3(-16.1, 2.4, -12.1), 0.9):
			push_error("PERSISTENCE_PROBE_WRITE_EDIT_REJECTED")
			quit(3)
			return
		if not ledger.add_sphere(Brush.Mode.FILL, Vector3(-15.85, 2.6, -11.9), 0.7):
			push_error("PERSISTENCE_PROBE_WRITE_FILL_REJECTED")
			quit(4)
			return
		var saved: Dictionary = store.save_ledger(Store.WORLD_ID, ledger)
		if not saved.get("ok", false):
			push_error("PERSISTENCE_PROBE_WRITE_SAVE_FAILED: %s" % saved.get("reason", "unknown"))
			quit(5)
			return
		print("PERSISTENCE_PROBE_WRITE_PASS generation=%d revision=%d count=%d" % [saved["generation"], saved["revision"], saved["operation_count"]])
		quit(0)
		return
	if phase == "read":
		var loaded: Dictionary = store.load_world()
		if not loaded.get("ok", false) or not loaded.get("found", false):
			push_error("PERSISTENCE_PROBE_READ_LOAD_FAILED: %s" % loaded.get("reason", "unknown"))
			quit(6)
			return
		var payload: Dictionary = loaded["payload"]
		var ledger: RefCounted = Brush.new(int(payload["world_seed"]), int(payload["generator_version"]))
		var snapshot := {
			"world_seed": int(payload["world_seed"]),
			"generator_version": int(payload["generator_version"]),
			"revision": int(payload["ledger_revision"]),
			"next_sequence": int(payload["next_sequence"]),
			"storage_reference": payload["storage_reference"],
		}
		if not ledger.restore_persistence_snapshot(snapshot):
			push_error("PERSISTENCE_PROBE_READ_RESTORE_FAILED: %s" % ledger.last_restore_rejection_reason)
			quit(7)
			return
		if ledger.get_edit_count() != 2 or ledger.revision != 2 or ledger.get_last_sequence() != 1:
			push_error("PERSISTENCE_PROBE_READ_LEDGER_MISMATCH")
			quit(8)
			return
		var center := Vector3(-16.1, 2.4, -12.1)
		var original_mode: int = ledger.get_persistence_snapshot()["operations"][0]["mode"]
		if original_mode != Brush.Mode.CARVE:
			push_error("PERSISTENCE_PROBE_READ_ORDER_MISMATCH")
			quit(9)
			return
		print("PERSISTENCE_PROBE_READ_PASS generation=%d seed=%d revision=%d count=%d density=%.9f" % [loaded["generation"], payload["world_seed"], ledger.revision, ledger.get_edit_count(), ledger.sample_density(int(payload["world_seed"]), Vector2i(-1, -1), Vector3(15.9, 2.4, 11.9))])
		quit(0)
		return
	push_error("PERSISTENCE_PROBE_PHASE_INVALID")
	quit(10)
