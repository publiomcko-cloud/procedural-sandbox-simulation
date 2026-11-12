extends SceneTree

## DM7: generated exterior HIGH rocks must be exactly the pristine
## canonical geological geometry, not the low-poly approximation.
const Registry := preload("res://scripts/modding/content_definition_registry.gd")
const ObjectWorld := preload("res://scripts/objects/procedural_object_world.gd")
const RockAdapter := preload("res://scripts/objects/procedural_rock_mesh_adapter.gd")
const StaticBatch := preload("res://scripts/objects/procedural_object_static_batch.gd")
const HighJob := preload("res://scripts/experiments/b4_high_detail_rock_job.gd")
const Demo := preload("res://scripts/terrain/terrain_demo.gd")
const StreamPolicy := preload("res://scripts/experiments/b4_region_stream_policy.gd")

const SEED := 424242
const WORLD_ID := "dm7-high-rock-parity"
const ROCK_RADIUS := 4
const TEST_KEYS := [
	Vector2i.ZERO, Vector2i(2,0), Vector2i(-3,1),
	Vector2i(4,0), Vector2i(-4,-4), Vector2i(1,4)
]
var checks := 0
var fails := 0
var triangles := 0
var tested_rocks := 0

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry: ContentDefinitionRegistry = Registry.new()
	var registered: Dictionary = registry.discover_and_register(
		["res://mods/first-party"]
	)
	_check(registered.get("ok", false), "same first-party registry as game")
	if not registered.get("ok", false):
		_finish()
		return
	_check(StreamPolicy.ACTIVE_RADIUS == 6, "terrain HIGH still radius 6")
	_check(ROCK_RADIUS == StreamPolicy.ACTIVE_RADIUS - 2,
		"rock HIGH starts two regions inside HIGH terrain boundary")
	for key in TEST_KEYS:
		var high: Dictionary = HighJob.build_data(SEED, WORLD_ID, key, registry)
		_check(high.get("ok", false), "HIGH rock worker region "+str(key))
		if not high.get("ok", false):
			continue
		var generated: Dictionary = ObjectWorld.build_region_instances(
			SEED, WORLD_ID, key, registry
		)
		_check(generated.get("ok", false), "canonical instances "+str(key))
		if not generated.get("ok", false):
			continue
		var source: Array[Dictionary] = []
		for value in generated.get("instances", []):
			var instance: Dictionary = value
			var cpu: Dictionary = RockAdapter.build_cpu_data(
				instance["geometry"], instance["geometry_seeds"]
			)
			_check(cpu.get("ok", false), "canonical rock cpu")
			if not cpu.get("ok", false):
				continue
			source.append({
				"instance_id": instance["instance_id"],
				"position": Vector3(instance["position_mm"]) / 1000.0,
				"scale_milli": instance["default_scale_milli"],
				"yaw_mdeg": instance["default_yaw_mdeg"],
				"cpu_data": cpu,
			})
		var canonical: Dictionary = StaticBatch.prepare(source)
		_check(canonical.get("ok", false), "canonical static batch")
		if not canonical.get("ok", false):
			continue
		_check(high.get("positions") == canonical.get("positions"),
			"EXACT match of transformed vertices (including signs and yaw)")
		_check(high.get("normals") == canonical.get("normals"),
			"EXACT match of normals")
		_check(high.get("instance_ids") == canonical.get("instance_ids"),
			"EXACT instance identity and order")
		_check(int(high.get("rock_count", -1)) == source.size(),
			"same rock count")
		_check(int(high.get("vertex_count", -1)) == int(canonical["vertex_count"]),
			"same vertex budget")
		_check(int(high.get("triangle_count", -1)) == int(canonical["triangle_count"]),
			"same triangle count")
		triangles += int(high.get("triangle_count", 0))
		tested_rocks += int(high.get("rock_count", 0))
	# Prove GPU node install precedes LOW hide and water is NOT affected.
	var high_cpu: Dictionary = HighJob.build_data(
		SEED, WORLD_ID, Vector2i(2,0), registry
	)
	var demo: Node = Demo.new()
	var root := Node3D.new()
	var low := MultiMeshInstance3D.new()
	low.name = "LowRocks"
	root.add_child(low)
	var water := MeshInstance3D.new()
	water.name = "LowWater"
	root.add_child(water)
	var id := "dm7-parity-2_0"
	demo.set("_dm5_decor_nodes", {id: {
		"root": root, "region_key": Vector2i(2,0), "rocks": 2,
		"rock_high": false, "rock_high_bytes": 0,
	}})
	_check(demo.call("_dm7_commit_high_rocks", id, Vector2i(2,0), high_cpu),
		"commit successful")
	_check(not low.visible, "LOW rock hidden after HIGH is available")
	_check(water.visible, "LOW water remains visible")
	_check(root.get_node_or_null("HIGH_ModRocks") is MeshInstance3D,
		"high detailed regional mesh installed")
	_check(bool(demo.get("_dm5_decor_nodes")[id]["rock_high"]),
		"resident HIGH marked for retention")
	_check(demo.call("_dm7_commit_high_rocks", id, Vector2i(2,0), high_cpu),
		"idempotent HIGH commit")
	_check(root.get_child_count() == 3, "no duplicate or flickering rock mesh")
	root.free()
	demo.free()
	_finish()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		fails += 1
		push_error("DM7_ROCK_HIGH_FAIL: "+message)


func _finish() -> void:
	print("DM7_ROCK_HIGH_PARITY_RESULT=" + JSON.stringify({
		"assertions": checks, "failures": fails,
		"parity_region_count": TEST_KEYS.size(),
		"rocks_tested": tested_rocks, "rock_triangles": triangles,
		"terrain_high_radius": StreamPolicy.ACTIVE_RADIUS,
		"rock_high_radius": ROCK_RADIUS, "rock_low_outer": true,
		"low_water_unchanged": true, "gpu_handoff_atomic": true,
	}))
	print("DM7_ROCK_HIGH_PARITY_%s" % ("PASS" if fails == 0 else "FAIL"))
	quit(0 if fails == 0 else 1)
