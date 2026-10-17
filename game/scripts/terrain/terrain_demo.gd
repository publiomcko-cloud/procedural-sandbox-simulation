extends Node3D

const TerrainField := preload("res://scripts/terrain/sdf_world.gd")
const TerrainMesher := preload("res://scripts/terrain/marching_tetrahedra.gd")
const WORLD_SEED := 424242
const REGION_KEY := Vector2i.ZERO

@onready var terrain_mesh: MeshInstance3D = $Terrain
@onready var camera: Camera3D = $Camera3D
@onready var status_label: Label = $CanvasLayer/Status

var cave_section_enabled := false
var orbit_target := Vector3(8.0, 3.1, 6.0)
var orbit_offset := Vector3(14.0, 10.0, 18.0)
var orbit_dragging := false


func _ready() -> void:
	_update_camera()
	_rebuild_terrain()
	_update_status()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		orbit_dragging = event.pressed
	elif event is InputEventMouseMotion and orbit_dragging:
		orbit_offset = orbit_offset.rotated(Vector3.UP, -event.relative.x * 0.006)
		orbit_offset.y = clampf(orbit_offset.y - event.relative.y * 0.05, 2.0, 22.0)
		_update_camera()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_orbit_distance(orbit_offset.length() * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_orbit_distance(orbit_offset.length() * 1.1)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_C:
			cave_section_enabled = not cave_section_enabled
			_rebuild_terrain()
			_update_status()
		elif event.keycode == KEY_R:
			_rebuild_terrain()
			_update_status()


func _rebuild_terrain() -> void:
	var result: Dictionary = TerrainMesher.build_mesh(WORLD_SEED, REGION_KEY, cave_section_enabled)
	terrain_mesh.mesh = result["mesh"]
	print("TERRAIN_MESH_READY: version=%d samples=%d triangles=%d cave_section=%s" % [
		TerrainField.GENERATOR_VERSION,
		result["sample_count"],
		result["triangle_count"],
		cave_section_enabled,
	])


func _update_status() -> void:
	status_label.text = "P0.1 SDF terrain  |  seed %d  |  generator v%d\nRight-drag: orbit    Wheel: zoom    C: cave cross-section    R: regenerate" % [
		WORLD_SEED,
		TerrainField.GENERATOR_VERSION,
	]
	if cave_section_enabled:
		status_label.text += "\nCave section: ON"


func _update_camera() -> void:
	camera.position = orbit_target + orbit_offset
	camera.look_at(orbit_target, Vector3.UP)


func _set_orbit_distance(distance: float) -> void:
	orbit_offset = orbit_offset.normalized() * clampf(distance, 10.0, 42.0)
	_update_camera()
