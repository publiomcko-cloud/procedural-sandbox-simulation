class_name TerrainWorldState
extends RefCounted

## Reproducible domain inputs and transient operations; owns no scene or rendering nodes.
const FIELD := preload("res://scripts/terrain/sdf_world.gd")
const BRUSH_STATE := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const CHUNK_GRID := preload("res://scripts/terrain/terrain_chunk_grid.gd")

const DEMO_SEED := 424242
const DEMO_REGION_KEY := Vector2i.ZERO

var world_seed: int
var generator_version: int
var region_key: Vector2i
var brush_edits: RefCounted


func _init(seed_value: int = DEMO_SEED, region_value: Vector2i = DEMO_REGION_KEY) -> void:
	world_seed = seed_value
	generator_version = FIELD.GENERATOR_VERSION
	region_key = region_value
	brush_edits = BRUSH_STATE.new()


func sample_density(local_position: Vector3, show_cave_section: bool = false) -> float:
	return brush_edits.sample_density(world_seed, region_key, local_position, show_cave_section)


func apply_sphere(mode: int, center: Vector3, radius: float) -> bool:
	return brush_edits.add_sphere(mode, center, radius)


func clear_edits() -> void:
	brush_edits.clear()


func chunk_id(chunk_coordinate: Vector2i) -> String:
	return CHUNK_GRID.stable_id(region_key, chunk_coordinate)
