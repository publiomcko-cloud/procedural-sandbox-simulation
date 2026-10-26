extends SceneTree

const Cache := preload("res://tests/prototypes/r3c_profile_cache.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 4:
		quit(2)
		return
	var root := args[0]
	var barrier := args[1]
	var ready_path := args[2]
	var output_path := args[3]
	var ready := FileAccess.open(ready_path, FileAccess.WRITE)
	if ready == null:
		quit(3)
		return
	ready.store_string(str(OS.get_process_id()))
	ready.close()
	var wait_started := Time.get_ticks_msec()
	while not FileAccess.file_exists(barrier) and Time.get_ticks_msec() - wait_started < 15000:
		OS.delay_msec(5)
	if not FileAccess.file_exists(barrier):
		quit(4)
		return
	var cache: RefCounted = Cache.new(root)
	var identity := {"fixture": "r3c-concurrent-same-key-v1", "chunk": Vector2i(-2, 3), "lod": 1}
	var mesh := _mesh()
	var result: Dictionary = cache.get_or_build(identity, func() -> Dictionary:
		OS.delay_msec(350)
		return mesh.duplicate(true)
	)
	var output := {"pid": OS.get_process_id(), "valid": result.get("valid", false),
		"cache_hit": result.get("cache_hit", false), "cache_layer": result.get("cache_layer", ""),
		"positions_sha256": _hash(var_to_bytes(result.get("positions", PackedVector3Array()))), "reason": result.get("reason", "")}
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		quit(5)
		return
	file.store_string(JSON.stringify(output))
	file.flush()
	file.close()
	quit(0 if bool(result.get("valid", false)) else 6)

func _mesh() -> Dictionary:
	var positions := PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	var normals := PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
	return {"valid": true, "positions": positions, "normals": normals, "vertex_count": 3, "triangle_count": 1, "sample_count": 3}

func _hash(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
