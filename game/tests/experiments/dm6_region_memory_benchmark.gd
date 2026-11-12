extends SceneTree

## Precise serialized CPU payload of each derived terrain/decoration LOD.
## Do NOT label these numbers as entire process RSS or actual GPU VRAM:
## ArrayMesh, MeshInstance3D, draw driver and the game world add overhead.
const High := preload("res://scripts/experiments/b4_region_visual_job.gd")
const Field := preload("res://scripts/experiments/discrete_surface_nets_backend.gd")
const Low := preload("res://scripts/terrain/terrain_coarse_preview_job.gd")
const Decor := preload("res://scripts/experiments/b4_low_detail_decor_job.gd")
const Policy := preload("res://scripts/experiments/b4_region_stream_policy.gd")
const VEC3_BYTES := 12
const COLOR_BYTES := 16
const TRANSFORM3D_BYTES := 48
const MAX_PROXY_ROCKS := 64
const SAMPLES := [
	Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, -1),
	Vector2i(0, 3), Vector2i(4, -2), Vector2i(-4, 6),
	Vector2i(0, 11), Vector2i(3, 12)
]
var failed := 0

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var report: Array[Dictionary] = []
	for key in SAMPLES:
		var start := Time.get_ticks_usec()
		var high: Dictionary = High.build_data(424242, key, 0)
		var low: Dictionary = Low.build_cpu_data(424242, key)
		var decor: Dictionary = Decor.build_data(424242, "dm6", key, null)
		var field := Field.new()
		if not field.generate(424242, key, 0.5) or not high.get("valid", false) \
				or not low.get("valid", false) or not decor.get("valid", false):
			failed += 1
			push_error("DM6_MEMORY_SOURCE_FAILURE region=" + str(key))
			continue
		var vertices_high: PackedVector3Array = high["positions"]
		var normals_high: PackedVector3Array = high["normals"]
		var vertices_low: PackedVector3Array = low["positions"]
		var normals_low: PackedVector3Array = low["normals"]
		var water_pos: PackedVector3Array = decor["water_positions"]
		var water_color: PackedColorArray = decor["water_colors"]
		var high_bytes := vertices_high.size() * VEC3_BYTES \
			+ normals_high.size() * VEC3_BYTES
		var low_bytes := vertices_low.size() * VEC3_BYTES \
			+ normals_low.size() * VEC3_BYTES
		var water_bytes := water_pos.size() * VEC3_BYTES \
			+ water_color.size() * COLOR_BYTES
		var temp_bytes := field.byte_count()
		var max_rock_bytes := MAX_PROXY_ROCKS * TRANSFORM3D_BYTES
		if high_bytes <= 0 or low_bytes <= 0 or temp_bytes <= 0:
			failed += 1
		if vertices_high.size() != normals_high.size() or \
				vertices_low.size() != normals_low.size() or \
				water_pos.size() != water_color.size():
			failed += 1
		report.append({
			"region": [key.x, key.y],
			"high_vertices": vertices_high.size(),
			"high_triangles": int(high["triangle_count"]),
			"high_cpu_array_bytes": high_bytes,
			"low_terrain_triangles": int(low["triangle_count"]),
			"low_terrain_cpu_array_bytes": low_bytes,
			"water_low_triangles": int(decor["water_triangles"]),
			"water_low_cpu_array_bytes": water_bytes,
			"max_64_proxy_rock_transforms_bytes": max_rock_bytes,
			"temporary_high_q8_8_lattice_bytes": temp_bytes,
			"sample_usec": Time.get_ticks_usec() - start,
		})
	if report.is_empty():
		failed += 1
	var high_samples: Array[int] = []
	var low_samples: Array[int] = []
	var water_samples: Array[int] = []
	var field_samples: Array[int] = []
	for entry in report:
		high_samples.append(int(entry["high_cpu_array_bytes"]))
		low_samples.append(int(entry["low_terrain_cpu_array_bytes"]))
		water_samples.append(int(entry["water_low_cpu_array_bytes"]))
		field_samples.append(int(entry["temporary_high_q8_8_lattice_bytes"]))
	high_samples.sort()
	low_samples.sort()
	water_samples.sort()
	field_samples.sort()
	var high_mid := high_samples[int(high_samples.size() / 2)] if not high_samples.is_empty() else 0
	var low_mid := low_samples[int(low_samples.size() / 2)] if not low_samples.is_empty() else 0
	var water_mid := water_samples[int(water_samples.size() / 2)] if not water_samples.is_empty() else 0
	var receipt := {
		"sample_regions": report.size(),
		"failure_count": failed,
		"source": "PackedVector3Array/ColorArray raw payload; no RSS or VRAM",
		"assumptions": {
			"vec3_bytes": VEC3_BYTES, "color_bytes": COLOR_BYTES,
			"transform3d_bytes": TRANSFORM3D_BYTES,
		},
		"region_window_high_count": Policy.expected_region_count(),
		"external_high_count": Policy.expected_external_region_count(),
		"retention_square_count": (Policy.RETAIN_RADIUS * 2 + 1)
			* (Policy.RETAIN_RADIUS * 2 + 1),
		"high_median_raw_bytes": high_mid,
		"high_min_raw_bytes": high_samples[0] if not high_samples.is_empty() else 0,
		"high_max_raw_bytes": high_samples[-1] if not high_samples.is_empty() else 0,
		"low_terrain_median_raw_bytes": low_mid,
		"low_water_median_raw_bytes": water_mid,
		"high_generation_field_median_bytes": field_samples[0]
			if not field_samples.is_empty() else 0,
		"high_169_region_raw_bytes": high_mid * Policy.expected_region_count(),
		"high_441_region_raw_bytes": high_mid * (Policy.RETAIN_RADIUS * 2 + 1)
			* (Policy.RETAIN_RADIUS * 2 + 1),
		"low_169_region_raw_bytes": (low_mid + water_mid + 64 * 48)
			* Policy.expected_region_count(),
		"regions": report,
	}
	print("DM6_REGION_MEMORY_RESULT=" + JSON.stringify(receipt))
	print("DM6_REGION_MEMORY_%s" % ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
