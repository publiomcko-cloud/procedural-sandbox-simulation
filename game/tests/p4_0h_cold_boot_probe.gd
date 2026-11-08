extends SceneTree

func _initialize() -> void:
	var runtime_script: Script = load("res://scripts/simulation/simulation_runtime.gd")
	if runtime_script == null:
		push_error("P4_0H_COLD_BOOT_RUNTIME_PARSE_FAIL")
		quit(1)
		return
	var terrain_script: Script = load("res://scripts/terrain/terrain_demo.gd")
	if terrain_script == null:
		push_error("P4_0H_COLD_BOOT_TERRAIN_PARSE_FAIL")
		quit(2)
		return
	var runtime: Node = runtime_script.new()
	var initialized: Dictionary = runtime.call("initialize_runtime")
	if not initialized.get("ok", false):
		push_error(
			"P4_0H_COLD_BOOT_RUNTIME_INIT_FAIL: %s"
			% initialized.get("reason", "unknown")
		)
		runtime.free()
		quit(3)
		return
	runtime.free()
	print("P4_0H_COLD_BOOT_PARSE_PASS")
	quit(0)
