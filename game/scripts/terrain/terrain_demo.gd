extends Node3D

const TerrainField := preload("res://scripts/terrain/sdf_world.gd")
const TerrainMesher := preload("res://scripts/terrain/marching_tetrahedra.gd")
const BrushEditState := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const BrushPicker := preload("res://scripts/terrain/terrain_brush_picker.gd")
const WORLD_SEED := 424242
const REGION_KEY := Vector2i.ZERO
const BRUSH_RADIUS := 1.25

@onready var terrain_mesh: MeshInstance3D = $Terrain
@onready var camera: Camera3D = $Camera3D
@onready var status_label: Label = $CanvasLayer/Status

var cave_section_enabled := false
var orbit_target := Vector3(8.0, 3.1, 6.0)
var orbit_offset := Vector3(14.0, 10.0, 18.0)
var orbit_dragging := false
var brush_edits: RefCounted = BrushEditState.new()
var selected_brush_mode: int = BrushEditState.Mode.CARVE
var last_brush_result := "Ready"
var last_mesh_diagnostics: Dictionary = {}


func _ready() -> void:
	_update_camera()
	_rebuild_terrain()
	_update_status()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			orbit_dragging = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			selected_brush_mode = BrushEditState.Mode.FILL if event.shift_pressed else BrushEditState.Mode.CARVE
			_apply_brush_at(event.position)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_orbit_distance(orbit_offset.length() * 0.9)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_orbit_distance(orbit_offset.length() * 1.1)
	elif event is InputEventMouseMotion and orbit_dragging:
		orbit_offset = orbit_offset.rotated(Vector3.UP, -event.relative.x * 0.006)
		orbit_offset.y = clampf(orbit_offset.y - event.relative.y * 0.05, 2.0, 22.0)
		_update_camera()
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_C:
			cave_section_enabled = not cave_section_enabled
			_rebuild_terrain()
			_update_status()
		elif event.keycode == KEY_R:
			_rebuild_terrain()
			_update_status()
		elif event.keycode == KEY_X:
			brush_edits.clear()
			last_brush_result = "Transient edits cleared"
			_rebuild_terrain()
			_update_status()


func _rebuild_terrain() -> void:
	var started_usec := Time.get_ticks_usec()
	var result: Dictionary = TerrainMesher.build_mesh(
		WORLD_SEED, REGION_KEY, cave_section_enabled, brush_edits
	)
	var elapsed_ms := float(Time.get_ticks_usec() - started_usec) / 1000.0
	terrain_mesh.mesh = result["mesh"]
	last_mesh_diagnostics = {
		"sample_count": result["sample_count"],
		"triangle_count": result["triangle_count"],
		"elapsed_ms": elapsed_ms,
	}
	print("TERRAIN_MESH_READY: version=%d samples=%d triangles=%d elapsed_ms=%.3f edits=%d cave_section=%s" % [
		TerrainField.GENERATOR_VERSION,
		result["sample_count"],
		result["triangle_count"],
		elapsed_ms,
		brush_edits.get_edit_count(),
		cave_section_enabled,
	])


func _update_status() -> void:
	var selected_mode_name := "FILL" if selected_brush_mode == BrushEditState.Mode.FILL else "CARVE"
	var diagnostics_line := "Mesh: pending"
	if not last_mesh_diagnostics.is_empty():
		diagnostics_line = "Mesh: %d samples, %d triangles, %.2f ms" % [
			last_mesh_diagnostics["sample_count"],
			last_mesh_diagnostics["triangle_count"],
			last_mesh_diagnostics["elapsed_ms"],
		]
	status_label.text = "P0.1 SDF terrain  |  seed %d  |  generator v%d\nRight-drag: orbit    Wheel: zoom    Left: carve    Shift+left: fill\nC: cave section    R: regenerate    X: reset edits\nSelected: %s    Edits: %d/%d    Radius: %.2f\n%s\n%s" % [
		WORLD_SEED,
		TerrainField.GENERATOR_VERSION,
		selected_mode_name,
		brush_edits.get_edit_count(),
		BrushEditState.MAX_EDITS,
		BRUSH_RADIUS,
		diagnostics_line,
		last_brush_result,
	]
	if cave_section_enabled:
		status_label.text += "\nCave section: ON"


func _apply_brush_at(screen_position: Vector2) -> void:
	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_direction := camera.project_ray_normal(screen_position)
	var density_sampler := func(point: Vector3) -> float:
		return brush_edits.sample_density(WORLD_SEED, REGION_KEY, point)
	var pick: Dictionary = BrushPicker.pick_surface(ray_origin, ray_direction, density_sampler)
	if not pick.get("hit", false) or not TerrainMesher.contains_mesh_point(pick["position"]):
		last_brush_result = "No visible terrain hit; no edit added"
		_update_status()
		return
	if not brush_edits.add_sphere(selected_brush_mode, pick["position"], BRUSH_RADIUS):
		last_brush_result = "Edit limit reached or brush rejected; terrain unchanged"
		_update_status()
		return
	var mode_name := "FILL" if selected_brush_mode == BrushEditState.Mode.FILL else "CARVE"
	last_brush_result = "%s sphere applied" % mode_name
	_rebuild_terrain()
	_update_status()


func _update_camera() -> void:
	camera.position = orbit_target + orbit_offset
	camera.look_at(orbit_target, Vector3.UP)


func _set_orbit_distance(distance: float) -> void:
	orbit_offset = orbit_offset.normalized() * clampf(distance, 10.0, 42.0)
	_update_camera()
