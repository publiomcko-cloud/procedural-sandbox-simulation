extends SceneTree

## Reproducible visual/geometry gallery. Headless images are documentation aids, never artistic acceptance.
const Registry := preload("res://scripts/modding/content_definition_registry.gd")
const RockAdapter := preload("res://scripts/objects/procedural_rock_mesh_adapter.gd")
const SLOT_IDS := ["firstparty.core_rocks:granite", "official.example.procedural_rock:basalt_stack"]
const GALLERY_SEED_BASE := 700100
const IMAGE_SIZE := Vector2i(1600, 1000)
const OUTPUT_ROOT := "user://p2_0a_geological_rock_gallery"

class DepthBuffer extends RefCounted:
	var values := PackedFloat32Array()

var _assertions := 0
var _failures := 0
var _measurements: Array[Dictionary] = []
var _render_objects: Array[Dictionary] = []
var _build_times: Dictionary = {"granite": [], "basalt": []}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry := Registry.new()
	var example_root := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("mods/examples")
	var registration: Dictionary = registry.discover_and_register(["res://mods/first-party", example_root])
	_expect(registration.get("ok", false), "gallery discovers both bundled data-only content packages")
	if not registration.get("ok", false):
		_finish()
		return
	var family_materials := {
		"granite": _stone_material(Color(0.52, 0.48, 0.42)),
		"basalt": _stone_material(Color(0.25, 0.29, 0.31)),
	}
	for family_index in range(SLOT_IDS.size()):
		var definition_id: String = SLOT_IDS[family_index]
		var family := "granite" if family_index == 0 else "basalt"
		for sample_index in range(12):
			var recipe_seed := GALLERY_SEED_BASE + sample_index
			var recipe: Dictionary = registry.evaluate_rock_recipe(definition_id, recipe_seed)
			_expect(recipe.get("ok", false), "%s gallery recipe %d evaluates" % [family, sample_index + 1])
			if not recipe.get("ok", false):
				continue
			var start_usec := Time.get_ticks_usec()
			var built: Dictionary = RockAdapter.build_mesh(recipe["geometry"], recipe["geometry_seeds"])
			var elapsed_usec := Time.get_ticks_usec() - start_usec
			_expect(built.get("ok", false), "%s gallery mesh %d builds" % [family, sample_index + 1])
			if not built.get("ok", false):
				continue
			_build_times[family].append(elapsed_usec)
			var global_column := family_index * 4 + sample_index % 4
			var row := int(sample_index / 4)
			var position := Vector3((float(global_column) - 3.5) * 1.95, 0.0, (1.0 - float(row)) * 3.5)
			var mesh_arrays: Array = built["mesh"].surface_get_arrays(0)
			_render_objects.append({
				"position": position,
				"vertices": mesh_arrays[Mesh.ARRAY_VERTEX],
				"normals": mesh_arrays[Mesh.ARRAY_NORMAL],
				"color": family_materials[family].albedo_color,
			})
			var bounds_min: Vector3 = built["bounds_min"]
			var bounds_max: Vector3 = built["bounds_max"]
			_measurements.append({
				"family": family,
				"definition_id": definition_id,
				"profile": recipe["profile"],
				"sample_index": sample_index,
				"recipe_seed": recipe_seed,
				"geometry_seeds": recipe["geometry_seeds"],
				"triangle_count": built["triangle_count"],
				"unique_vertex_count": built["unique_vertex_count"],
				"surface_area_m2": built["surface_area_m2"],
				"volume_m3": built["volume_m3"],
				"bounds_min": [bounds_min.x, bounds_min.y, bounds_min.z],
				"bounds_max": [bounds_max.x, bounds_max.y, bounds_max.z],
				"build_usec": elapsed_usec,
			})
	var output_path := ProjectSettings.globalize_path(OUTPUT_ROOT)
	var make_result := DirAccess.make_dir_recursive_absolute(output_path)
	_expect(make_result == OK or make_result == ERR_ALREADY_EXISTS, "gallery output directory is available")
	for view in [
		{"name": "oblique", "position": Vector3(0.0, 13.0, 19.0)},
		{"name": "rear_oblique", "position": Vector3(0.0, 15.0, -19.0)},
		{"name": "side_oblique", "position": Vector3(19.0, 13.0, 0.0)},
	]:
		var image: Image = _render_gallery_view(view["position"])
		_expect(image != null and image.get_size() == IMAGE_SIZE, "gallery software render %s has the configured image size" % String(view["name"]))
		if image != null:
			var image_path := output_path.path_join("rock_gallery_%s.png" % String(view["name"]))
			_expect(image.save_png(image_path) == OK, "gallery view %s exports as PNG" % String(view["name"]))
	var metrics := {
		"schema_version": 1,
		"status": "UNSCORED_EXPLORATORY_SOFTWARE_PREVIEW",
		"godot_version": Engine.get_version_info(),
		"generator_algorithm": RockAdapter.ALGORITHM,
		"geometry_version": RockAdapter.GEOMETRY_VERSION,
		"sample_count_per_family": 12,
		"recipe_seed_base": GALLERY_SEED_BASE,
		"fixed_environment": {"ambient": 0.30, "key_light_direction": [-0.45, 0.82, 0.35], "key_light_intensity": 0.82, "fill": 0.12, "renderer": "deterministic CPU triangle preview; not Godot shading or artistic acceptance"},
		"family_timings_usec": {"granite": _timing_summary(_build_times["granite"]), "basalt": _timing_summary(_build_times["basalt"])},
		"samples": _measurements,
		"images": ["rock_gallery_oblique.png", "rock_gallery_rear_oblique.png", "rock_gallery_side_oblique.png"],
		"assertions": _assertions,
		"failures": _failures,
	}
	var metrics_file := FileAccess.open(output_path.path_join("gallery_metrics.json"), FileAccess.WRITE)
	_expect(metrics_file != null, "gallery metrics sidecar opens")
	if metrics_file != null:
		metrics["assertions"] = _assertions
		metrics["failures"] = _failures
		metrics_file.store_string(JSON.stringify(metrics, "\t", true))
		metrics_file.close()
	_finish()


func _render_gallery_view(camera_position: Vector3) -> Image:
	var image := Image.create(IMAGE_SIZE.x, IMAGE_SIZE.y, false, Image.FORMAT_RGBA8)
	if image == null:
		return null
	image.fill(Color(0.075, 0.085, 0.09, 1.0))
	image.fill_rect(Rect2i(0, 0, IMAGE_SIZE.x, 34), Color(0.025, 0.03, 0.035, 1.0))
	var depth := DepthBuffer.new()
	depth.values.resize(IMAGE_SIZE.x * IMAGE_SIZE.y)
	depth.values.fill(INF)
	var direction := (Vector3(0.0, 0.72, 0.0) - camera_position).normalized()
	var right := direction.cross(Vector3.UP).normalized()
	var up := right.cross(direction).normalized()
	var light_direction := Vector3(-0.45, 0.82, 0.35).normalized()
	var world_height := 11.0
	var world_width := world_height * float(IMAGE_SIZE.x) / float(IMAGE_SIZE.y)
	for object_value in _render_objects:
		var object: Dictionary = object_value
		var vertices: PackedVector3Array = object["vertices"]
		var normals: PackedVector3Array = object["normals"]
		var origin: Vector3 = object["position"]
		var base_color: Color = object["color"]
		for triangle_start in range(0, vertices.size(), 3):
			var world_points: Array[Vector3] = [origin + vertices[triangle_start], origin + vertices[triangle_start + 1], origin + vertices[triangle_start + 2]]
			var screen_points: Array[Vector3] = []
			for point in world_points:
				var relative := point - camera_position
				var screen_x := (relative.dot(right) / world_width + 0.5) * float(IMAGE_SIZE.x)
				var screen_y := (0.5 - relative.dot(up) / world_height) * float(IMAGE_SIZE.y)
				var distance := relative.dot(direction)
				screen_points.append(Vector3(screen_x, screen_y, distance))
			_rasterize_triangle(image, depth, screen_points, normals[triangle_start], base_color, light_direction)
	return image


func _rasterize_triangle(image: Image, depth: DepthBuffer, points: Array[Vector3], normal: Vector3, base_color: Color, light_direction: Vector3) -> void:
	var min_x := maxi(0, floori(minf(points[0].x, minf(points[1].x, points[2].x))))
	var max_x := mini(IMAGE_SIZE.x - 1, ceili(maxf(points[0].x, maxf(points[1].x, points[2].x))))
	var min_y := maxi(34, floori(minf(points[0].y, minf(points[1].y, points[2].y))))
	var max_y := mini(IMAGE_SIZE.y - 1, ceili(maxf(points[0].y, maxf(points[1].y, points[2].y))))
	if min_x > max_x or min_y > max_y:
		return
	var x0 := points[0].x
	var y0 := points[0].y
	var x1 := points[1].x
	var y1 := points[1].y
	var x2 := points[2].x
	var y2 := points[2].y
	var denominator := (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
	if absf(denominator) < 1.0e-6:
		return
	var illumination := 0.30 + 0.12 + 0.82 * maxf(0.0, normal.normalized().dot(light_direction))
	var shaded := Color(minf(1.0, base_color.r * illumination), minf(1.0, base_color.g * illumination), minf(1.0, base_color.b * illumination), 1.0)
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var px := float(x) + 0.5
			var py := float(y) + 0.5
			var weight0 := ((y1 - y2) * (px - x2) + (x2 - x1) * (py - y2)) / denominator
			var weight1 := ((y2 - y0) * (px - x2) + (x0 - x2) * (py - y2)) / denominator
			var weight2 := 1.0 - weight0 - weight1
			if weight0 < -1.0e-5 or weight1 < -1.0e-5 or weight2 < -1.0e-5:
				continue
			var distance := weight0 * points[0].z + weight1 * points[1].z + weight2 * points[2].z
			var pixel_index := y * IMAGE_SIZE.x + x
			if distance < depth.values[pixel_index]:
				depth.values[pixel_index] = distance
				image.set_pixel(x, y, shaded)


func _stone_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.94
	return material


func _timing_summary(values: Array) -> Dictionary:
	var sorted: Array = values.duplicate()
	sorted.sort()
	if sorted.is_empty():
		return {"count": 0}
	var median := int(sorted[int((sorted.size() - 1) / 2)])
	var p95 := int(sorted[mini(sorted.size() - 1, ceili(sorted.size() * 0.95) - 1)])
	return {"count": sorted.size(), "median_usec": median, "p95_usec": p95, "max_usec": int(sorted.back())}


func _expect(condition: bool, description: String) -> void:
	_assertions += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)


func _finish() -> void:
	if _failures == 0:
		print("PROCEDURAL_ROCK_GALLERY_PASS: assertions=%d failures=0 output=%s" % [_assertions, ProjectSettings.globalize_path(OUTPUT_ROOT)])
	else:
		push_error("PROCEDURAL_ROCK_GALLERY_FAIL: assertions=%d failures=%d output=%s" % [_assertions, _failures, ProjectSettings.globalize_path(OUTPUT_ROOT)])
	quit(0 if _failures == 0 else 1)
