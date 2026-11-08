extends Node3D

const TerrainMesher := preload("res://scripts/terrain/marching_tetrahedra.gd")
const ChunkGrid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const SpatialGrid := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const WorldState := preload("res://scripts/terrain/terrain_world_state.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")
const BrushEditState := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const BrushPicker := preload("res://scripts/terrain/terrain_brush_picker.gd")
const TerrainMeshJob := preload("res://scripts/terrain/terrain_mesh_job.gd")
const TerrainLodPolicy := preload("res://scripts/terrain/terrain_lod_policy.gd")
const WorldSaveStore := preload("res://scripts/terrain/terrain_world_save_store_v2.gd")
const ScalableSdfState := preload("res://scripts/terrain/terrain_scalable_sdf_state.gd")
const MaterializedSdfStore := preload("res://scripts/terrain/terrain_materialized_sdf_store.gd")
const AsyncCheckpointJob := preload("res://scripts/terrain/terrain_async_checkpoint_job.gd")
const SharedBoundaryAuthority := preload("res://scripts/terrain/shared_surface_boundary_authority.gd")
const SharedBoundaryMeshJob := preload("res://scripts/terrain/shared_surface_boundary_mesh_job.gd")
const SharedZBoundaryMeshJob := preload("res://scripts/terrain/shared_surface_z_boundary_mesh_job.gd")
const SharedCornerMeshJob := preload("res://scripts/terrain/shared_surface_corner_mesh_job.gd")
const EntityStateContract := preload("res://scripts/objects/procedural_object_state_contract.gd")
const TerrainEffectRuntime := preload("res://scripts/terrain/terrain_object_effect_runtime.gd")
const MaterialEnvironmentDomainScript := preload("res://scripts/simulation/material_environment_domain.gd")
const SimulationRuntimeStoreScript := preload("res://scripts/simulation/simulation_runtime_store.gd")
const PerformanceTrace := preload("res://scripts/diagnostics/performance_trace.gd")

const BRUSH_RADIUS := 1.25
const REQUEST_RADIUS := 1
const UNLOAD_RADIUS := 2
const MAX_ACTIVE_REGIONS := 25
const MIN_MESH_JOBS_IN_FLIGHT := 4
const MAX_MESH_JOBS_IN_FLIGHT_HARD := 8
const MAX_MESH_JOB_DISPATCHES_PER_FRAME := 1
const MESH_SNAPSHOT_FRAME_BUDGET_USEC := 3500
const MAX_MESH_UPLOADS_PER_FRAME := 4
const MESH_UPLOAD_FRAME_BUDGET_USEC := 3500
const MAX_BUFFERED_BRUSH_REQUESTS := 64
const EDIT_TRACE_DEFAULT_ENABLED := false
const DIAGNOSTICS_REFRESH_INTERVAL := 0.25
const FOCUS_MOVE_STEP := 4.0
const MAX_STAGE_RETRIES := 2
const PREEDIT_DEFAULT_COUNT := 512
const FREE_EXPLORE_SPEED := 18.0
const FREE_EXPLORE_BOOST_MULTIPLIER := 3.0
const FREE_EXPLORE_MOUSE_SENSITIVITY := 0.0025
const FREE_EXPLORE_MAX_PITCH_RADIANS := 1.553343034

@onready var terrain_chunks_root: Node3D = $TerrainChunks
@onready var terrain_mesh_template: MeshInstance3D = $TerrainChunks/Terrain
@onready var camera: Camera3D = $Camera3D
@onready var ui_layer: CanvasLayer = $CanvasLayer
@onready var status_label: Label = $CanvasLayer/Status
@onready var object_stream: ProceduralObjectStream = $ProceduralObjects
@onready var simulation_runtime: SimulationRuntime = $SimulationRuntime

var cave_section_enabled := false
var orbit_target := Vector3(8.0, 3.1, 6.0)
var orbit_offset := Vector3(34.0, 24.0, 40.0)
var orbit_dragging := false
var free_explore_enabled := false
var _free_explore_yaw := 0.0
var _free_explore_pitch := 0.0
var _free_explore_previous_mouse_mode := Input.MOUSE_MODE_VISIBLE
var _free_explore_ui_was_visible := true
var focus_region_key := Vector2i.ZERO
var _last_reconciled_focus := Vector2i(2147483647, 2147483647)

# Rendering residency is transient. WorldState remains separate from these nodes.
var active_regions: Dictionary = {} # region id -> {region_key, world_state, chunk_nodes}
var loading_regions: Dictionary = {} # region id -> bounded incremental mesh staging state
var world_states: Dictionary = {} # active and currently staged domain states
var world_state: RefCounted # focused region compatibility alias for the demo/tests
var edit_ledger: RefCounted
var world_seed := WorldState.DEMO_SEED
var world_id := MaterializedSdfStore.WORLD_ID
var world_save_store: RefCounted
var _scalable_runtime_enabled := false
var _shared_boundary_runtime_enabled := false
var _checkpoint_task_id := -1
var _checkpoint_job: RefCounted
var _checkpoint_status := "checkpoint idle"
var _checkpoint_generation := 0
var _checkpoint_last_worker_ms := 0.0
var _checkpoint_started_usec := 0
var _checkpoint_overlap_observed := false
var _preedit_path := ""
var _preedit_count := PREEDIT_DEFAULT_COUNT
var _preedit_status := "F5: inject deterministic pre-edits"
var _pending_world_load: Dictionary = {}
var _persistence_status := "No saved world; press P to save or O to load"
var _persistence_blocked := false
var _procedural_object_status := "Procedural objects unavailable"
var object_state_directory_override := ""
var object_package_roots_override: Array[String] = []
var terrain_effect_directory_override := ""
var simulation_state_directory_override := ""
var terrain_effect_runtime: RefCounted
var _terrain_effect_status := "Terrain-object effects unavailable"
var _material_content_domain: MaterialEnvironmentDomain
var _simulation_material_profile_id := ""
var _simulation_streaming_status := "Simulation streaming unavailable"
var _simulation_persistence_status := "Simulation state not loaded"
var _simulation_persistence_blocked := false
var _simulation_store: SimulationRuntimeStore
var _simulation_storage_generation := 0
var _pending_simulation_save_terrain_generation := -1
var _selected_object_index := 0
var _selected_object_id := ""
var _object_state_action_status := "Entities: Ctrl+click select; M twice migrates entity save; B place; F6 cycle; F7 edit; F8 delete; F9 restore"
var _placement_target_marker: MeshInstance3D
var _placement_target_valid := false
var _placement_target_published := false
var _placement_target_region_key := Vector2i.ZERO
var _placement_target_world_position := Vector3.ZERO
var _placement_target_normal := Vector3.UP
var _last_pointer_viewport_position := Vector2.ZERO
var _has_pointer_viewport_position := false
var _last_placement_aim_mode := "center"
var _last_placement_mouse_mode := -1
var _placement_target_dirty := false
var _placement_target_invalidation_count := 0
var _entity_migration_confirmation_deadline_msec := 0
var chunk_nodes: Dictionary = {} # stable chunk id -> active MeshInstance3D
var _published_lod_by_chunk: Dictionary = {} # stable chunk id -> 0/1
var _lod_fallback_chunks: Dictionary = {} # stable chunk id -> deterministic LOD0 fallback until retry/toggle
var lod_enabled := false
var _lod_selection_dirty := true
var _edit_trace_enabled := EDIT_TRACE_DEFAULT_ENABLED
var _perf_trace_enabled := false
var _last_region_publish_profile: Dictionary = {}

var selected_brush_mode: int = BrushEditState.Mode.CARVE
var last_brush_result := "Ready"
var last_mesh_diagnostics: Dictionary = {}
var _last_shared_boundary_diagnostics: Dictionary = {}
var _last_shared_x_boundary_diagnostics: Dictionary = {}
var _last_shared_z_boundary_diagnostics: Dictionary = {}
var _last_shared_corner_diagnostics: Dictionary = {}
var last_stream_error := ""

var global_rebuild_pending := false
var global_rebuild_reason := ""
var _full_rebuild_target_ids: Array[String] = []
var _edit_transaction: Dictionary = {}
var _buffered_brush_requests: Array[Dictionary] = []
var _edit_trace_serial := 0
var _stage_retry_counts: Dictionary = {}
var _stream_errors_by_region: Dictionary = {}
var _superseded_stage_total := 0
var _next_stage_token := 1
var _mesh_jobs: Dictionary = {} # WorkerThreadPool task id -> immutable job/stage token
var _mesh_job_limit := MIN_MESH_JOBS_IN_FLIGHT
var _mesh_queue_wait_usec_samples: Array[int] = []
var _pool_queue_wait_usec_samples: Array[int] = []
var _mesh_upload_usec_samples: Array[int] = []
var _mesh_publish_usec_samples: Array[int] = []
var _global_rebuild_retry_count := 0
var debug_fail_next_mesh_stage := false
var debug_fail_next_load_stage := false
var debug_shared_runtime_diagnostics := false
var _mesh_stage_retry_total := 0
var _rendered_cave_section_enabled := false
var _operation_name := "initial_load"
var _operation_chunk_ids: Array[String] = []
var _operation_sample_count := 0
var _operation_started_usec := 0
var _operation_total_mesh_work_ms := 0.0
var _operation_stage_timings_usec: Dictionary = {}
var _last_mesh_upload_ms := 0.0
var _peak_mesh_upload_ms := 0.0
var _last_process_work_ms := 0.0
var _peak_process_work_ms := 0.0
var _last_frame_ms := 0.0
var _peak_frame_ms := 0.0
var _mesh_uploads_this_frame := 0
var _mesh_dispatches_this_frame := 0
var _peak_mesh_uploads_per_frame := 0
var _peak_mesh_dispatches_per_frame := 0
var _peak_mesh_jobs_in_flight := 0
var _brush_pick_serial := 0
var _last_brush_pick_snapshot_elapsed_usec := 0
var _last_brush_pick_elapsed_usec := 0
var _last_brush_pick_total_elapsed_usec := 0
var _last_brush_pick_sample_count := 0
var _last_brush_pick_hit := false
var _last_brush_pick_position := Vector3.ZERO
var _last_brush_pick_candidate_count := 0
var _frame_time_samples: Array[float] = []
var _frame_sample_write_index := 0
var _frame_sample_count := 0
var _diagnostics_refresh_elapsed := 0.0
var _peak_active_region_count := 0
var _peak_queue_depth := 0
var _peak_mesh_job_queue_depth := 0
var _streamed_region_loads := 0
var _streamed_region_unloads := 0
var _active_triangle_count := 0
var _active_vertex_count := 0
var _last_edit_support_region_count := 0
var _last_edit_rebuild_region_count := 0
var _last_edit_rebuild_chunk_count := 0
var _last_edit_mesh_jobs := 0
var _last_edit_rejection := ""


func _ready() -> void:
	_perf_trace_enabled = PerformanceTrace.is_enabled()
	if _perf_trace_enabled:
		PerformanceTrace.emit("terrain_trace_session", {
			"world_id": world_id,
			"world_seed": world_seed,
			"processor_count": OS.get_processor_count(),
			"trace_min_usec": PerformanceTrace.min_usec(),
		})
	_frame_time_samples.resize(512)
	_mesh_job_limit = clampi(
		OS.get_processor_count() - 1,
		MIN_MESH_JOBS_IN_FLIGHT,
		MAX_MESH_JOBS_IN_FLIGHT_HARD
	)
	_configure_preedit_arguments()
	_edit_trace_enabled = EDIT_TRACE_DEFAULT_ENABLED or OS.get_environment("SANDBOX_EDIT_TRACE") == "1"
	for argument in OS.get_cmdline_user_args():
		if argument == "--edit-trace":
			_edit_trace_enabled = true
		elif argument == "--no-edit-trace":
			_edit_trace_enabled = false
	# Existing tests may inject the legacy v2 store. Normal runtime defaults to
	# the materialized store and scalable edit state.
	if world_save_store == null:
		world_save_store = MaterializedSdfStore.new()
	_scalable_runtime_enabled = world_save_store.has_method("checkpoint_state") \
		and world_save_store.has_method("get_world_directory")
	_shared_boundary_runtime_enabled = _scalable_runtime_enabled

	if _scalable_runtime_enabled:
		var saved_world: Dictionary = world_save_store.load_world(world_id)
		if saved_world.get("found", false):
			if saved_world.get("ok", false):
				edit_ledger = saved_world["state"]
				world_seed = int(edit_ledger.world_seed)
				_checkpoint_generation = int(saved_world.get("generation", 0))
				_persistence_status = "Materialized generation %d loaded (%d archived edits, hot tail %d)" % [
					_checkpoint_generation,
					int(edit_ledger.get_archived_edit_count()),
					int(edit_ledger.get_tail_edit_count()),
				]
			else:
				_persistence_blocked = true
				edit_ledger = ScalableSdfState.new(world_seed, Field.GENERATOR_VERSION)
				_persistence_status = "Materialized world rejected (%s); new edits are blocked from persistence" % saved_world.get("reason", "invalid")
		else:
			edit_ledger = ScalableSdfState.new(world_seed, Field.GENERATOR_VERSION)
			_persistence_status = "New materialized world; async checkpoints every %d edits" % ScalableSdfState.CHECKPOINT_TAIL_TARGET
	else:
		edit_ledger = BrushEditState.new(world_seed, Field.GENERATOR_VERSION)
		var saved_world: Dictionary = world_save_store.load_world(world_id)
		if saved_world.get("found", false):
			if saved_world.get("ok", false):
				var loaded: Dictionary = _build_ledger_from_payload(saved_world.get("payload", {}))
				if loaded.get("ok", false):
					world_seed = int(loaded["world_seed"])
					edit_ledger = loaded["ledger"]
					_persistence_status = _loaded_world_message(saved_world)
				else:
					_persistence_blocked = true
					_persistence_status = "Saved world rejected (%s); edits remain untouched and saving is blocked" % loaded.get("reason", "invalid")
			else:
				_persistence_blocked = true
				_persistence_status = "Saved world unavailable (%s); edits remain untouched and saving is blocked" % saved_world.get("reason", "invalid")
		elif saved_world.get("legacy_available", false):
			_persistence_status = "Schema-1 terrain save detected and preserved; choose a new v2 world explicitly (no migration/import)"

	_material_content_domain = MaterialEnvironmentDomainScript.new()
	var material_handlers: Array[RefCounted] = [
		_material_content_domain.create_content_handler()
	]
	var object_initialization: Dictionary = object_stream.initialize(
		world_seed,
		world_id,
		object_package_roots_override,
		object_state_directory_override,
		material_handlers
	)
	if object_initialization.get("ok", false):
		_procedural_object_status = "Procedural objects ready"
		terrain_effect_runtime = TerrainEffectRuntime.new()
		var effect_initialization: Dictionary = terrain_effect_runtime.initialize(
			world_id,
			world_seed,
			Field.GENERATOR_VERSION,
			object_stream,
			terrain_effect_directory_override
		)
		if effect_initialization.get("ok", false):
			terrain_effect_runtime.set_incremental_prefetch_enabled(true)
			_terrain_effect_status = "Terrain-object effects ready"
		else:
			terrain_effect_runtime = null
			_terrain_effect_status = "Terrain-object effects unavailable (%s)" % effect_initialization.get("reason", "unknown")
	else:
		_procedural_object_status = "Procedural objects unavailable (%s)" % object_initialization.get("reason", "unknown")
		terrain_effect_runtime = null
		_terrain_effect_status = "Terrain-object effects unavailable (object stream unavailable)"
	_restore_simulation_for_terrain_generation(_checkpoint_generation)
	if not _simulation_persistence_blocked:
		_configure_simulation_streaming()
	_create_placement_target_marker()
	terrain_mesh_template.mesh = null
	terrain_mesh_template.visible = false
	_begin_operation("initial_load")
	_update_camera()
	_reconcile_region_window(true)
	_update_status()


func _ensure_simulation_store() -> void:
	if _simulation_store == null:
		_simulation_store = SimulationRuntimeStoreScript.new(
			simulation_state_directory_override
		)


func _read_simulation_candidate(
	seed_value: int,
	terrain_generation: int
) -> Dictionary:
	_ensure_simulation_store()
	var loaded: Dictionary = _simulation_store.load_snapshot(
		world_id,
		seed_value,
		Field.GENERATOR_VERSION,
		maxi(0, terrain_generation)
	)
	if not loaded.get("ok", false):
		return loaded
	if (
		not loaded.get("found", false)
		and loaded.get("reason") == "simulation_generation_not_found"
		and int(loaded.get("recognized_generation_count", 0)) > 0
	):
		return {
			"ok": false,
			"reason": "simulation_sidecar_generation_mismatch",
			"terrain_generation": terrain_generation,
		}
	if not loaded.get("found", false):
		return {
			"ok": true,
			"reason": "no_saved_simulation",
			"found": false,
			"generation": 0,
			"terrain_generation": terrain_generation,
		}

	var validator: SimulationRuntime = SimulationRuntime.new()
	var restored: Dictionary = validator.restore_runtime_snapshot(loaded["snapshot"])
	if not restored.get("ok", false):
		validator.free()
		return {
			"ok": false,
			"reason": "simulation_candidate_restore_invalid",
			"detail": String(restored.get("reason", "")),
		}
	var content_validation: Dictionary = validator.validate_material_state_content(
		object_stream.registry
	)
	validator.free()
	if not content_validation.get("ok", false):
		return {
			"ok": false,
			"reason": String(
				content_validation.get("reason", "simulation_candidate_content_invalid")
			),
		}
	return loaded


func _restore_simulation_for_terrain_generation(
	terrain_generation: int,
	explicit_load: bool = false
) -> bool:
	if not is_instance_valid(simulation_runtime):
		_simulation_persistence_status = "Simulation persistence unavailable (runtime node missing)"
		_simulation_persistence_blocked = true
		return false
	var loaded := _read_simulation_candidate(world_seed, terrain_generation)
	if not loaded.get("ok", false):
		_simulation_persistence_status = "Simulation load blocked (%s)" % loaded.get("reason", "invalid")
		_simulation_persistence_blocked = true
		return false
	if not loaded.get("found", false):
		_simulation_persistence_status = (
			"No persisted simulation for terrain generation %d"
			% terrain_generation
		)
		_simulation_storage_generation = 0
		_simulation_persistence_blocked = false
		return true

	var restored: Dictionary = simulation_runtime.restore_runtime_snapshot(
		loaded["snapshot"]
	)
	if not restored.get("ok", false):
		_simulation_persistence_status = "Simulation restore blocked (%s)" % restored.get("reason", "invalid")
		_simulation_persistence_blocked = true
		return false
	_simulation_storage_generation = int(loaded["generation"])
	_simulation_persistence_status = (
		"Loaded simulation generation %d for terrain generation %d"
		% [_simulation_storage_generation, terrain_generation]
	)
	if bool(loaded.get("recovered_temporary", false)):
		_simulation_persistence_status += " (recovered interrupted commit)"
	_simulation_persistence_blocked = false
	return true


func _save_simulation_state(terrain_generation: int) -> bool:
	if _simulation_persistence_blocked:
		return false
	if not is_instance_valid(simulation_runtime) or not simulation_runtime.initialized:
		_simulation_persistence_status = "Simulation save unavailable"
		return false
	var preflight: Dictionary = simulation_runtime.get_persistence_preflight()
	if not preflight.get("ok", false):
		_simulation_persistence_status = "Simulation snapshot deferred (%s)" % preflight.get("reason", "work_pending")
		return false
	var content_validation: Dictionary = simulation_runtime.validate_material_state_content(
		object_stream.registry
	)
	if not content_validation.get("ok", false):
		_simulation_persistence_status = "Simulation save blocked (%s)" % content_validation.get("reason", "invalid")
		_simulation_persistence_blocked = true
		return false
	_ensure_simulation_store()
	var snapshot: Dictionary = simulation_runtime.get_runtime_snapshot()
	var saved: Dictionary = _simulation_store.save_snapshot(
		world_id,
		world_seed,
		Field.GENERATOR_VERSION,
		maxi(0, terrain_generation),
		snapshot
	)
	if not saved.get("ok", false):
		_simulation_persistence_status = "Simulation save failed (%s)" % saved.get("reason", "unknown")
		return false
	_simulation_storage_generation = int(saved["generation"])
	_simulation_persistence_status = (
		"Saved simulation generation %d with terrain generation %d"
		% [_simulation_storage_generation, terrain_generation]
	)
	return true


func _queue_simulation_save(terrain_generation: int) -> void:
	_pending_simulation_save_terrain_generation = maxi(0, terrain_generation)
	_simulation_persistence_status = (
		"Simulation snapshot pending for terrain generation %d"
		% _pending_simulation_save_terrain_generation
	)


func _process_pending_simulation_save() -> void:
	if _pending_simulation_save_terrain_generation < 0:
		return
	if _simulation_persistence_blocked:
		return
	var terrain_generation := _pending_simulation_save_terrain_generation
	if _save_simulation_state(terrain_generation):
		_pending_simulation_save_terrain_generation = -1


func _apply_pending_simulation_candidate(pending: Dictionary) -> bool:
	if not is_instance_valid(simulation_runtime):
		_simulation_persistence_status = "Simulation apply failed (runtime node missing)"
		_simulation_persistence_blocked = true
		return false
	var result: Dictionary
	if bool(pending.get("simulation_found", false)):
		result = simulation_runtime.restore_runtime_snapshot(
			pending.get("simulation_snapshot", {})
		)
		if result.get("ok", false):
			_simulation_storage_generation = int(
				pending.get("simulation_generation", 0)
			)
	else:
		result = simulation_runtime.initialize_runtime()
		if result.get("ok", false):
			_simulation_storage_generation = 0
	if not result.get("ok", false):
		_simulation_persistence_status = "Simulation apply failed (%s)" % result.get("reason", "invalid")
		_simulation_persistence_blocked = true
		return false

	_simulation_persistence_blocked = false
	_configure_simulation_streaming()
	if not bool(
		simulation_runtime.get_world_scope_lifecycle_metrics().get(
			"initialized", false
		)
	):
		_simulation_persistence_status = "Simulation lifecycle reconfiguration failed"
		_simulation_persistence_blocked = true
		return false
	if bool(pending.get("simulation_found", false)):
		_simulation_persistence_status = (
			"Loaded simulation generation %d with terrain generation %d"
			% [
				_simulation_storage_generation,
				int(pending.get("generation", 0)),
			]
		)
	else:
		_simulation_persistence_status = (
			"No saved simulation for terrain generation %d; initialized deterministic baseline"
			% int(pending.get("generation", 0))
		)
	return true


func _configure_simulation_streaming() -> void:
	if not is_instance_valid(simulation_runtime):
		_simulation_streaming_status = "Simulation streaming unavailable (runtime node missing)"
		return
	if not simulation_runtime.initialized:
		var runtime_initialization: Dictionary = simulation_runtime.initialize_runtime()
		if not runtime_initialization.get("ok", false):
			_simulation_streaming_status = "Simulation runtime unavailable (%s)" % runtime_initialization.get("reason", "unknown")
			return

	_simulation_material_profile_id = ""
	if object_stream.registry != null:
		var profile_ids: Array[String] = object_stream.registry.get_content_record_ids(
			MaterialEnvironmentDomainScript.PROFILE_TYPE
		)
		if profile_ids.size() == 1:
			var profile_id := String(profile_ids[0])
			var material_config: Dictionary = simulation_runtime.configure_material_environment(
				object_stream.registry, profile_id
			)
			if material_config.get("ok", false):
				_simulation_material_profile_id = profile_id
			else:
				_simulation_streaming_status = "Material simulation unavailable (%s)" % material_config.get("reason", "unknown")
		elif profile_ids.size() > 1:
			# Selection policy belongs to world/content configuration, not discovery.
			_simulation_streaming_status = "Material simulation awaiting explicit profile selection (%d profiles)" % profile_ids.size()

	var lifecycle: Dictionary = simulation_runtime.configure_world_scope_lifecycle(
		_simulation_material_profile_id,
		MAX_ACTIVE_REGIONS,
		roundi(SpatialGrid.REGION_SIZE_X * 1000.0),
		roundi(SpatialGrid.REGION_SIZE_Z * 1000.0)
	)
	if lifecycle.get("ok", false):
		_simulation_streaming_status = (
			"Simulation streaming ready (%s)"
			% (
				_simulation_material_profile_id
				if not _simulation_material_profile_id.is_empty()
				else "tier lifecycle only"
			)
		)
	else:
		_simulation_streaming_status = "Simulation streaming unavailable (%s)" % lifecycle.get("reason", "unknown")




func _exit_tree() -> void:
	# Effect projection source workers hold the immutable content registry. Join
	# them before the object stream/registry can be released with the scene.
	if terrain_effect_runtime != null 		and terrain_effect_runtime.has_method("wait_for_prefetch_jobs"):
		terrain_effect_runtime.wait_for_prefetch_jobs()
	# Worker callbacks own only immutable input and CPU packed arrays, but complete
	# them before the scene and their result holders are released.
	for task_id_value in _mesh_jobs.keys().duplicate():
		WorkerThreadPool.wait_for_task_completion(int(task_id_value))
	_mesh_jobs.clear()
	if _checkpoint_task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_checkpoint_task_id)
		_checkpoint_task_id = -1
		_checkpoint_job = null


func _process(delta: float) -> void:
	var process_started_usec := Time.get_ticks_usec()
	_process_pending_simulation_save()
	_mesh_uploads_this_frame = 0
	_mesh_dispatches_this_frame = 0
	_last_frame_ms = maxf(delta * 1000.0, 0.0)
	if _frame_time_samples.size() == 512:
		_frame_time_samples[_frame_sample_write_index] = _last_frame_ms
		_frame_sample_write_index = (_frame_sample_write_index + 1) % 512
		_frame_sample_count = mini(_frame_sample_count + 1, 512)
	_peak_frame_ms = maxf(_peak_frame_ms, _last_frame_ms)
	if free_explore_enabled:
		_process_free_exploration(delta)
	_update_focus_key()
	_reconcile_region_window()
	_update_lod_selection()
	if _checkpoint_task_id >= 0 and (global_rebuild_pending or not loading_regions.is_empty()):
		_checkpoint_overlap_observed = true
	_process_async_checkpoint()
	_maybe_schedule_async_checkpoint()
	if terrain_effect_runtime != null and bool(terrain_effect_runtime.get("initialized")):
		var prefetch_result: Dictionary = terrain_effect_runtime.process_prefetch_step(1)
		if not prefetch_result.get("ok", false):
			_terrain_effect_status = "Terrain-object effects unavailable (%s)" % prefetch_result.get("reason", "unknown")
			_record_stream_error("_terrain_effect_prefetch", _terrain_effect_status)
	_process_one_chunk_job()
	object_stream.process_queued_publications()
	var visual_result: Dictionary = object_stream.consume_last_command_visual_result()
	if not visual_result.is_empty():
		if visual_result.get("ok", false):
			_object_state_action_status = "%s committed at world revision %d; visual publication succeeded" % [visual_result.get("operation", "Entity command"), int(visual_result.get("world_revision", -1))]
		else:
			_object_state_action_status = "%s committed at world revision %d, but visual publication failed: %s" % [visual_result.get("operation", "Entity command"), int(visual_result.get("world_revision", -1)), visual_result.get("reason", "unknown")]
	if _placement_target_valid:
		var target_is_published := _is_placement_region_published(_placement_target_region_key)
		if target_is_published != _placement_target_published:
			_placement_target_published = target_is_published
			_update_placement_marker_visual()
	_peak_mesh_uploads_per_frame = maxi(_peak_mesh_uploads_per_frame, _mesh_uploads_this_frame)
	_peak_mesh_dispatches_per_frame = maxi(
		_peak_mesh_dispatches_per_frame, _mesh_dispatches_this_frame
	)
	_last_process_work_ms = float(Time.get_ticks_usec() - process_started_usec) / 1000.0
	_peak_process_work_ms = maxf(_peak_process_work_ms, _last_process_work_ms)
	if _perf_trace_enabled and _last_process_work_ms >= 16.0:
		var effect_pending := 0
		if terrain_effect_runtime != null and bool(terrain_effect_runtime.get("initialized")):
			effect_pending = int(terrain_effect_runtime.get_prefetch_pending_count())
		var object_perf: Dictionary = object_stream.get_performance_snapshot()
		PerformanceTrace.emit("terrain_process_spike", {
			"work_ms": _last_process_work_ms,
			"frame_ms": _last_frame_ms,
			"focus": [focus_region_key.x, focus_region_key.y],
			"active_regions": active_regions.size(),
			"loading_regions": loading_regions.size(),
			"mesh_jobs_in_flight": _mesh_jobs.size(),
			"mesh_uploads_this_frame": _mesh_uploads_this_frame,
			"effect_prefetch_pending": effect_pending,
			"object_publications_pending": int(object_perf.get("pending_region_publication_count", 0)),
			"global_rebuild_pending": global_rebuild_pending,
			"edit_stage": String(_edit_transaction.get("stage_state", "idle")) if not _edit_transaction.is_empty() else "idle",
		})
	_diagnostics_refresh_elapsed += delta
	if int(Input.mouse_mode) != _last_placement_mouse_mode:
		_last_placement_mouse_mode = int(Input.mouse_mode)
		_refresh_placement_target_indicator()
	if _diagnostics_refresh_elapsed >= DIAGNOSTICS_REFRESH_INTERVAL:
		_diagnostics_refresh_elapsed = 0.0
		_update_runtime_diagnostics()
		_update_status()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		_last_pointer_viewport_position = event.position
		_has_pointer_viewport_position = true

	if event is InputEventKey and event.pressed and not event.echo and _event_matches_key(event, KEY_F10):
		_set_free_explore_enabled(not free_explore_enabled)
		return

	if free_explore_enabled and event is InputEventMouseMotion:
		_apply_free_explore_look(event.relative)
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if not free_explore_enabled:
				orbit_dragging = event.pressed
			return
		elif event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var screen_position: Vector2 = _free_explore_screen_center() if free_explore_enabled else event.position
			if event.ctrl_pressed:
				_select_entity_at(screen_position)
			else:
				selected_brush_mode = BrushEditState.Mode.FILL if event.shift_pressed else BrushEditState.Mode.CARVE
				_apply_brush_at(screen_position)
		elif not free_explore_enabled and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_orbit_distance(orbit_offset.length() * 0.9)
		elif not free_explore_enabled and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_orbit_distance(orbit_offset.length() * 1.1)
	elif event is InputEventMouseMotion and orbit_dragging:
		orbit_offset = orbit_offset.rotated(Vector3.UP, -event.relative.x * 0.006)
		orbit_offset.y = clampf(orbit_offset.y - event.relative.y * 0.05, 2.0, 36.0)
		_update_camera()
	elif event is InputEventKey and event.pressed and not event.echo:
		if free_explore_enabled and _is_free_explore_movement_key(event):
			return
		if event.ctrl_pressed and _event_matches_key(event, KEY_Z):
			if event.shift_pressed:
				_handle_entity_history_navigation("ENTITY_REDO")
			else:
				_handle_entity_history_navigation("ENTITY_UNDO")
		elif event.ctrl_pressed and _event_matches_key(event, KEY_Y):
			_handle_entity_history_navigation("ENTITY_REDO")
		elif _event_matches_key(event, KEY_C):
			cave_section_enabled = not cave_section_enabled
			_start_global_rebuild("cave_section")
		elif _event_matches_key(event, KEY_R):
			_start_global_rebuild("regenerate")
		elif _event_matches_key(event, KEY_X):
			var cleared: Dictionary = edit_ledger.clear_for_region(focus_region_key)
			if int(cleared.get("removed_count", 0)) > 0:
				last_brush_result = "Reset focused edits for %s: removed %d command(s); rebuilding %d dependent region(s)" % [
					focus_region_key, cleared["removed_count"], (cleared.get("rebuild_regions", []) as Array).size(),
				]
				_start_global_rebuild("reset")
			else:
				last_brush_result = "Focused reset unavailable for materialized history (%s)" % cleared.get("error", "nothing_to_reset")
		elif _event_matches_key(event, KEY_L):
			lod_enabled = not lod_enabled
			_lod_fallback_chunks.clear()
			_lod_selection_dirty = true
			last_brush_result = "Custom LOD 0/1: %s" % ("ON" if lod_enabled else "OFF; using LOD0 fallback")
		elif _event_matches_key(event, KEY_V):
			object_stream.set_object_visibility(not object_stream.objects_visible)
		elif _event_matches_key(event, KEY_F5):
			_apply_preedit_fixture()
		elif _event_matches_key(event, KEY_P):
			_save_world_to_storage()
		elif _event_matches_key(event, KEY_O):
			_load_world_from_storage()
		elif _event_matches_key(event, KEY_F6):
			_select_next_object()
		elif _event_matches_key(event, KEY_F7):
			_mutate_selected_object()
		elif _event_matches_key(event, KEY_F8):
			_delete_selected_object()
		elif _event_matches_key(event, KEY_F9):
			_restore_selected_object()
		elif _event_matches_key(event, KEY_M):
			_handle_entity_schema_migration()
		elif _event_matches_key(event, KEY_B):
			_place_entity_under_crosshair()
		elif _event_matches_key(event, KEY_A) or _event_matches_key(event, KEY_LEFT):
			_move_focus(Vector3(-FOCUS_MOVE_STEP, 0.0, 0.0))
		elif _event_matches_key(event, KEY_D) or _event_matches_key(event, KEY_RIGHT):
			_move_focus(Vector3(FOCUS_MOVE_STEP, 0.0, 0.0))
		elif _event_matches_key(event, KEY_W) or _event_matches_key(event, KEY_UP):
			_move_focus(Vector3(0.0, 0.0, -FOCUS_MOVE_STEP))
		elif _event_matches_key(event, KEY_S) or _event_matches_key(event, KEY_DOWN):
			_move_focus(Vector3(0.0, 0.0, FOCUS_MOVE_STEP))
		_update_status()
	if not free_explore_enabled and (event is InputEventMouseMotion or event is InputEventMouseButton):
		_refresh_placement_target_indicator(event.position)


func _select_next_object() -> void:
	var ids: Array[String] = object_stream.get_instance_ids()
	if ids.is_empty():
		_selected_object_id = ""
		_object_state_action_status = "Object state: no active object; move near a published region"
		return
	_selected_object_index = posmod(_selected_object_index, ids.size())
	_selected_object_id = ids[_selected_object_index]
	_selected_object_index += 1
	_object_state_action_status = "Selected object %s" % _selected_object_id


func _mutate_selected_object() -> void:
	if _selected_object_id.is_empty():
		_select_next_object()
		if _selected_object_id.is_empty():
			return
	var transform_result := _dispatch_entity_component(_selected_object_id, "core.transform", {
		"schema_version": 1,
		"properties": {"translation_mm": [0, 250, 0], "rotation_mdeg": [0, 0, 12000], "scale_milli": [1100, 1000, 900]},
	})
	if not transform_result.get("ok", false):
		_object_state_action_status = "ENTITY_SET_COMPONENT transform rejected: %s" % transform_result.get("reason", "invalid")
		return
	var appearance_result := _dispatch_entity_component(_selected_object_id, "core.appearance", {
		"schema_version": 1,
		"properties": {"tint_milli": [1000, 650, 350], "label": "owner-state-demo"},
	})
	_object_state_action_status = "ENTITY_SET_COMPONENT transform + appearance committed (world revision %d; visual %s)" % [object_stream.get_command_world_revision(), appearance_result.get("visual_status", "queued")] if appearance_result.get("ok", false) else "Transform committed at world revision %d; appearance command rejected: %s" % [object_stream.get_command_world_revision(), appearance_result.get("reason", "invalid")]


func _delete_selected_object() -> void:
	if _selected_object_id.is_empty():
		_object_state_action_status = "Select an object with F6 first"
		return
	var result := _dispatch_entity_operation("ENTITY_DELETE", _selected_object_id)
	_object_state_action_status = "ENTITY_DELETE committed at world/entity revisions %d/%d; visual %s" % [int(result.get("world_revision", -1)), int(result.get("entity_revision", -1)), result.get("visual_status", "unknown")] if result.get("ok", false) else "ENTITY_DELETE rejected: %s" % result.get("reason", "invalid")


func _restore_selected_object() -> void:
	if _selected_object_id.is_empty():
		_selected_object_id = object_stream.get_latest_deleted_instance_id()
	if _selected_object_id.is_empty():
		_object_state_action_status = "ENTITY_RESTORE rejected: no deleted entity is available"
		return
	var result := _dispatch_entity_operation("ENTITY_RESTORE", _selected_object_id)
	_object_state_action_status = "ENTITY_RESTORE committed at world/entity revisions %d/%d; visual %s" % [int(result.get("world_revision", -1)), int(result.get("entity_revision", -1)), result.get("visual_status", "unknown")] if result.get("ok", false) else "ENTITY_RESTORE rejected: %s" % result.get("reason", "invalid")


func _select_entity_at(screen_position: Vector2) -> void:
	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_direction := camera.project_ray_normal(screen_position)
	var picked: Dictionary = object_stream.find_instance_along_ray(ray_origin, ray_direction)
	if not picked.get("ok", false):
		_object_state_action_status = "Selection missed: %s" % picked.get("reason", "no entity")
		return
	var terrain_sampler := Callable(self, "_sample_world_density")
	if edit_ledger != null and edit_ledger.has_method("get_ray_snapshot"):
		var selection_snapshot: Dictionary = edit_ledger.get_ray_snapshot(
			ray_origin, ray_direction, BrushPicker.MAX_DISTANCE
		)
		if selection_snapshot.get("valid", false):
			var prepared_selection := _prepare_terrain_effect_ray_snapshot(
				selection_snapshot, ray_origin, ray_direction, BrushPicker.MAX_DISTANCE
			)
			if prepared_selection.get("ok", false):
				selection_snapshot = prepared_selection["snapshot"]
				terrain_sampler = func(point: Vector3) -> float:
					return _sample_world_density_from_snapshot(point, selection_snapshot)
	var terrain_hit: Dictionary = BrushPicker.pick_sdf_v1_surface(
		ray_origin, ray_direction, terrain_sampler
	)
	if terrain_hit.get("hit", false):
		var terrain_distance := ray_origin.distance_to(Vector3(terrain_hit.position))
		if float(picked.get("distance", INF)) > terrain_distance + 0.15:
			_object_state_action_status = "Selection blocked by the terrain surface"
			return
	_selected_object_id = String(picked.entity_id)
	var summary: Dictionary = object_stream.get_entity_summary(_selected_object_id)
	_object_state_action_status = "Selected %s (%s; %s)" % [_selected_object_id, summary.get("definition_id", "unknown definition"), "static batch member" if picked.get("batched", false) else "individual representative"]


func _place_entity_under_crosshair() -> void:
	if not object_stream.is_entity_command_ready():
		_object_state_action_status = "Placement blocked: entity save migration required; press M to preflight, then M again to confirm"
		return
	var aim := _placement_aim()
	var screen_position: Vector2 = aim["screen_position"]
	_last_placement_aim_mode = String(aim["mode"])
	var target := _placement_target_at(screen_position)
	_placement_target_dirty = false
	if not target.get("valid", false):
		_placement_target_valid = false
		if is_instance_valid(_placement_target_marker):
			_placement_target_marker.visible = false
		var reason := String(target.get("reason", "no_surface"))
		var reason_text := "no terrain surface at the %s target; aim at a visible surface" % _aim_description(_last_placement_aim_mode) if reason == "no_surface" else "target is outside supported world coordinates"
		_object_state_action_status = "ENTITY_PLACE rejected: %s" % reason_text
		return
	var world_position: Vector3 = target["world_position"]
	var position_mm: Vector3i = target["position_mm"]
	var region_key: Vector2i = target["region_key"]
	if not _is_placement_region_published(region_key):
		_placement_target_valid = true
		_placement_target_published = false
		_placement_target_region_key = region_key
		_placement_target_world_position = world_position
		_update_placement_marker_visual()
		_object_state_action_status = "ENTITY_PLACE rejected: target region %s is not fully published" % region_key
		return
	var definitions: Array[String] = object_stream.get_placeable_definition_ids()
	var definition_id := String(definitions[0]) if not definitions.is_empty() else ""
	if definition_id.is_empty():
		_object_state_action_status = "ENTITY_PLACE rejected: no registered definition is available"
		return
	var command_id := _new_entity_command_id()
	var recipe_seed := int(command_id.substr(0, 8).hex_to_int() % 2147483646) + 1
	var command := _entity_command_base("ENTITY_PLACE", command_id, "")
	command["definition_id"] = definition_id
	command["position_mm"] = [position_mm.x, position_mm.y, position_mm.z]
	command["region_key"] = [region_key.x, region_key.y]
	command["recipe_seed"] = recipe_seed
	command["components"] = {
		"core.transform": {"schema_version": 1, "properties": {"translation_mm": [0, 0, 0], "rotation_mdeg": [0, 0, 0], "scale_milli": [1000, 1000, 1000]}},
		"core.appearance": {"schema_version": 1, "properties": {"tint_milli": [1000, 1000, 1000], "label": ""}},
		"core.logical": {"schema_version": 1, "properties": {"values": {}}},
	}
	if terrain_effect_runtime != null:
		terrain_effect_runtime.invalidate_source_region(region_key)
	var result: Dictionary = object_stream.dispatch_entity_command(command)
	if not result.get("ok", false):
		_object_state_action_status = "ENTITY_PLACE rejected: %s" % result.get("reason", "unknown")
		return
	_placement_target_valid = true
	_placement_target_published = true
	_placement_target_region_key = region_key
	_placement_target_world_position = world_position
	_placement_target_normal = target["normal"]
	_update_placement_marker_visual()
	_selected_object_id = String(result.get("entity_id", ""))
	_schedule_terrain_effect_rebuild(region_key)
	_object_state_action_status = "ENTITY_PLACE committed %s at %s target %s (anchor mm %s; world/entity revisions %d/%d; visual %s)" % [_selected_object_id, _aim_description(_last_placement_aim_mode), region_key, position_mm, int(result.get("world_revision", -1)), int(result.get("entity_revision", -1)), result.get("visual_status", "unknown")]


func _placement_aim() -> Dictionary:
	var viewport := get_viewport()
	var visible_rect := viewport.get_visible_rect()
	var pointer := _last_pointer_viewport_position if _has_pointer_viewport_position else viewport.get_mouse_position()
	return _placement_aim_for_cursor(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, pointer, visible_rect)


func _placement_aim_for_cursor(cursor_visible: bool, pointer: Vector2, visible_rect: Rect2) -> Dictionary:
	if cursor_visible and visible_rect.has_point(pointer):
		return {"mode": "pointer", "screen_position": pointer}
	return {"mode": "center", "screen_position": visible_rect.position + visible_rect.size * 0.5}


func _placement_target_at(screen_position: Vector2) -> Dictionary:
	if not is_instance_valid(camera) or not is_instance_valid(object_stream):
		return {"valid": false, "published": false, "reason": "scene_not_ready"}
	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_direction := camera.project_ray_normal(screen_position)
	var density_sampler := Callable(self, "_sample_world_density")
	if edit_ledger != null and edit_ledger.has_method("get_ray_snapshot"):
		var ray_snapshot: Dictionary = edit_ledger.get_ray_snapshot(
			ray_origin, ray_direction, BrushPicker.MAX_DISTANCE
		)
		if ray_snapshot.get("valid", false):
			var prepared_ray := _prepare_terrain_effect_ray_snapshot(
				ray_snapshot, ray_origin, ray_direction, BrushPicker.MAX_DISTANCE
			)
			if prepared_ray.get("ok", false):
				ray_snapshot = prepared_ray["snapshot"]
				density_sampler = func(point: Vector3) -> float:
					return _sample_world_density_from_snapshot(point, ray_snapshot)
	var picked: Dictionary = BrushPicker.pick_sdf_v1_surface(
		ray_origin, ray_direction, density_sampler
	)
	if not picked.get("hit", false):
		return {"valid": false, "published": false, "reason": "no_surface"}
	var world_position: Vector3 = picked["position"]
	var position_mm := _world_position_to_mm(world_position)
	var mapped: Dictionary = SpatialGrid.world_to_region_local(Vector3(position_mm) / 1000.0)
	if not mapped.get("valid", false):
		return {"valid": false, "published": false, "reason": "unsupported_world_position"}
	var region_key: Vector2i = mapped["region_key"]
	return {
		"valid": true,
		"published": _is_placement_region_published(region_key),
		"world_position": world_position,
		"position_mm": position_mm,
		"region_key": region_key,
		"normal": _estimate_surface_normal_with_sampler(
			world_position, density_sampler
		),
	}


func _is_placement_region_published(region_key: Vector2i) -> bool:
	return active_regions.has(_region_id(region_key)) and object_stream.has_published_region(region_key)


func _world_position_to_mm(world_position: Vector3) -> Vector3i:
	return Vector3i(roundi(world_position.x * 1000.0), roundi(world_position.y * 1000.0), roundi(world_position.z * 1000.0))


func _estimate_surface_normal(world_position: Vector3) -> Vector3:
	return _estimate_surface_normal_with_sampler(
		world_position, Callable(self, "_sample_world_density")
	)


func _estimate_surface_normal_with_sampler(
	world_position: Vector3,
	density_sampler: Callable
) -> Vector3:
	const SAMPLE_RADIUS := 0.025
	var x_gradient := float(density_sampler.call(
		world_position + Vector3.RIGHT * SAMPLE_RADIUS
	)) - float(density_sampler.call(
		world_position - Vector3.RIGHT * SAMPLE_RADIUS
	))
	var y_gradient := float(density_sampler.call(
		world_position + Vector3.UP * SAMPLE_RADIUS
	)) - float(density_sampler.call(
		world_position - Vector3.UP * SAMPLE_RADIUS
	))
	var z_gradient := float(density_sampler.call(
		world_position + Vector3.BACK * SAMPLE_RADIUS
	)) - float(density_sampler.call(
		world_position - Vector3.BACK * SAMPLE_RADIUS
	))
	var gradient := Vector3(x_gradient, y_gradient, z_gradient)
	return gradient.normalized() 		if gradient.is_finite() and gradient.length_squared() > 0.000001 		else Vector3.UP


func _create_placement_target_marker() -> void:
	var marker := MeshInstance3D.new()
	marker.name = "PlacementTargetMarker"
	var sphere := SphereMesh.new()
	sphere.radius = 0.095
	sphere.height = 0.19
	sphere.radial_segments = 12
	sphere.rings = 6
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.2, 0.95, 1.0, 1.0)
	material.emission_enabled = true
	material.emission = Color(0.08, 0.65, 0.9, 1.0)
	material.emission_energy_multiplier = 1.3
	marker.mesh = sphere
	marker.material_override = material
	marker.visible = false
	add_child(marker)
	_placement_target_marker = marker


func _refresh_placement_target_indicator(screen_override: Variant = null) -> void:
	if not is_instance_valid(_placement_target_marker) or not is_inside_tree():
		return
	var aim := _placement_aim()
	if screen_override is Vector2 and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and get_viewport().get_visible_rect().has_point(screen_override):
		aim["screen_position"] = screen_override
		aim["mode"] = "pointer"
	_last_placement_aim_mode = String(aim["mode"])
	var target := _placement_target_at(aim["screen_position"])
	_placement_target_valid = bool(target.get("valid", false))
	_placement_target_published = bool(target.get("published", false))
	_placement_target_dirty = false
	if _placement_target_valid:
		_placement_target_world_position = target["world_position"]
		_placement_target_region_key = target["region_key"]
		_placement_target_normal = target["normal"]
	_update_placement_marker_visual()


func _invalidate_placement_target_after_terrain_change() -> void:
	_placement_target_dirty = true
	_placement_target_invalidation_count += 1
	_placement_target_valid = false
	_placement_target_published = false
	if is_instance_valid(_placement_target_marker):
		_placement_target_marker.visible = false


func _update_placement_marker_visual() -> void:
	if not is_instance_valid(_placement_target_marker):
		return
	_placement_target_marker.visible = _placement_target_valid and not free_explore_enabled
	if not _placement_target_valid:
		return
	_placement_target_marker.global_position = _placement_target_world_position + _placement_target_normal * 0.045
	var material := _placement_target_marker.material_override as StandardMaterial3D
	if material != null:
		var color := Color(0.2, 1.0, 0.45, 1.0) if _placement_target_published else Color(1.0, 0.48, 0.08, 1.0)
		material.albedo_color = color
		material.emission = color


func _aim_description(mode: String) -> String:
	return "visible pointer" if mode == "pointer" else "center aim (cursor hidden or unavailable)"


func _handle_entity_schema_migration() -> void:
	var current_schema := int(object_stream.state_service.snapshot.get("schema_version", 0)) if object_stream.state_service != null else 0
	if current_schema >= EntityStateContract.HISTORY_SNAPSHOT_SCHEMA_VERSION:
		_entity_migration_confirmation_deadline_msec = 0
		if object_stream.is_entity_command_ready():
			_object_state_action_status = "Entity command/history schema is ready (schema 3)"
		else:
			var retry: Dictionary = object_stream.retry_command_migration_region_publications()
			_object_state_action_status = "Entity schema 3 committed; region representations rebuilding (%d queued, %d pending): %s" % [int(retry.get("queued_regions", 0)), int(retry.get("remaining_regions", 0)), retry.get("reason", "retry")]
		return
	var now := Time.get_ticks_msec()
	if _entity_migration_confirmation_deadline_msec > 0 and now <= _entity_migration_confirmation_deadline_msec:
		_entity_migration_confirmation_deadline_msec = 0
		var migration: Dictionary = object_stream.migrate_command_snapshot_explicitly()
		if not migration.get("ok", false):
			_object_state_action_status = "Entity schema migration failed%s: %s" % [" after commit" if migration.get("committed", false) else "", migration.get("reason", "unknown")]
			return
		_object_state_action_status = "Entity/history schema migrated explicitly; generation %d (previous generation %d retained); %d region representation(s) rebuilding; %d older receipt(s) preserved but not undoable; hash %s" % [int(migration.get("generation", -1)), int(migration.get("backup_generation", 0)), int(migration.get("remaining_regions", 0)), int(migration.get("preserved_receipt_count", 0)), String(migration.get("source_payload_sha256", "")).substr(0, 12)]
		return
	var preflight: Dictionary = object_stream.get_command_migration_preflight()
	if not preflight.get("ok", false):
		_object_state_action_status = "Entity schema migration preflight rejected: %s" % preflight.get("reason", "unknown")
		return
	if String(preflight.get("reason", "")) == "already_upgraded":
		_object_state_action_status = "Entity snapshot already uses schema %d; reinitializing command service" % int(preflight.get("source_schema", -1))
		object_stream.migrate_command_snapshot_explicitly()
		return
	_entity_migration_confirmation_deadline_msec = now + 6000
	_object_state_action_status = "History migration preflight passed: schema %d to %d, generation %d, revision %d; %d old receipt(s) preserved, prior commands are not in the new undo history; press M again within 6 s to commit" % [int(preflight.get("source_schema", -1)), int(preflight.get("target_schema", -1)), int(preflight.get("source_generation", 0)), int(preflight.get("revision", -1)), int(preflight.get("preserved_receipt_count", 0))]


func _handle_entity_history_navigation(operation: String) -> void:
	if not object_stream.is_entity_command_ready():
		_object_state_action_status = "%s rejected: history schema migration or resident-region rebuild is pending" % operation
		return
	var command_service: RefCounted = object_stream.get_entity_command_service()
	var summary: Dictionary = command_service.get_history_summary()
	var target: Dictionary = summary.get("undo" if operation == "ENTITY_UNDO" else "redo", {})
	if target.is_empty():
		_object_state_action_status = "%s rejected: no %s operation is available (history %d/%d)" % [operation, "applied" if operation == "ENTITY_UNDO" else "undone", int(summary.get("cursor", 0)), int(summary.get("depth", 0))]
		return
	var entity_id := String(target.get("entity_id", ""))
	var terrain_region := _entity_region_for_terrain_effect(entity_id)
	if terrain_region.get("ok", false) and terrain_effect_runtime != null:
		terrain_effect_runtime.invalidate_source_region(terrain_region["region_key"])
	var command := _entity_command_base(operation, _new_entity_command_id(), entity_id)
	command["history_entry_id"] = String(target.get("history_entry_id", ""))
	var result: Dictionary = object_stream.dispatch_entity_command(command)
	if not result.get("ok", false):
		_object_state_action_status = "%s rejected: %s" % [operation, result.get("reason", "unknown")]
		return
	_selected_object_id = entity_id
	if terrain_region.get("ok", false):
		_schedule_terrain_effect_rebuild(terrain_region["region_key"])
	_object_state_action_status = "%s committed for %s at world/entity revisions %d/%d; history %d/%d; visual %s" % [operation, entity_id, int(result.get("world_revision", -1)), int(result.get("entity_revision", -1)), int(result.get("history_cursor", 0)), int(result.get("history_depth", 0)), result.get("visual_status", "unknown")]


func _dispatch_entity_component(entity_id: String, component_id: String, component: Dictionary) -> Dictionary:
	var terrain_region := _entity_region_for_terrain_effect(entity_id)
	if component_id == EntityStateContract.COMPONENT_TRANSFORM 		and terrain_region.get("ok", false) 		and terrain_effect_runtime != null:
		terrain_effect_runtime.invalidate_source_region(terrain_region["region_key"])
	var command_id := _new_entity_command_id()
	var command := _entity_command_base("ENTITY_SET_COMPONENT", command_id, entity_id)
	command["component_id"] = component_id
	command["component"] = component
	var result: Dictionary = object_stream.dispatch_entity_command(command)
	if result.get("ok", false) 		and component_id == EntityStateContract.COMPONENT_TRANSFORM 		and terrain_region.get("ok", false):
		_schedule_terrain_effect_rebuild(terrain_region["region_key"])
	return result


func _dispatch_entity_operation(operation: String, entity_id: String) -> Dictionary:
	var terrain_region := _entity_region_for_terrain_effect(entity_id)
	if operation in ["ENTITY_DELETE", "ENTITY_RESTORE"] 		and terrain_region.get("ok", false) 		and terrain_effect_runtime != null:
		terrain_effect_runtime.invalidate_source_region(terrain_region["region_key"])
	var result: Dictionary = object_stream.dispatch_entity_command(
		_entity_command_base(operation, _new_entity_command_id(), entity_id)
	)
	if result.get("ok", false) 		and terrain_region.get("ok", false) 		and operation in ["ENTITY_DELETE", "ENTITY_RESTORE"]:
		_schedule_terrain_effect_rebuild(terrain_region["region_key"])
	return result


func _entity_region_for_terrain_effect(entity_id: String) -> Dictionary:
	var command_service: RefCounted = object_stream.get_entity_command_service()
	if command_service == null 		or not bool(command_service.get("initialized")) 		or not command_service.has_method("get_entity_region"):
		return {"ok": false, "reason": "entity_region_unavailable"}
	return command_service.get_entity_region(entity_id)


func _schedule_terrain_effect_rebuild(source_region: Vector2i) -> void:
	if terrain_effect_runtime == null 		or not bool(terrain_effect_runtime.get("initialized")):
		return
	var refreshed: Dictionary = terrain_effect_runtime.refresh_invalidated_source_region(
		source_region
	)
	if not refreshed.get("ok", false):
		_terrain_effect_status = "Terrain-object effects unavailable (%s)" % refreshed.get("reason", "unknown")
		push_error(_terrain_effect_status)
		return
	var targets_value: Variant = refreshed.get("targets", [])
	if typeof(targets_value) != TYPE_ARRAY or targets_value.is_empty():
		return
	# If a global/edit transaction is already rebuilding terrain, its entity
	# revision gate will reject stale jobs and the next snapshots see the freshly
	# reconciled projection. Avoid launching a competing partial transaction.
	if global_rebuild_pending or not _edit_transaction.is_empty():
		return
	var coordinates_by_region: Dictionary = {}
	for target_value in targets_value:
		if typeof(target_value) != TYPE_DICTIONARY:
			continue
		var target: Dictionary = target_value
		var region: Vector2i = target["region_key"]
		var coordinate: Vector2i = target["chunk_coordinate"]
		var region_id := _region_id(region)
		if not active_regions.has(region_id):
			continue
		var coordinates: Array[Vector2i] = []
		var stored_coordinates: Array = coordinates_by_region.get(region_id, [])
		for stored_coordinate in stored_coordinates:
			coordinates.append(Vector2i(stored_coordinate))
		if not coordinates.has(coordinate):
			coordinates.append(coordinate)
		coordinates_by_region[region_id] = coordinates
	if coordinates_by_region.is_empty():
		return
	_begin_operation("terrain_object_effect")
	var region_ids: Array[String] = []
	for region_id in coordinates_by_region:
		region_ids.append(String(region_id))
	region_ids.sort()
	for region_id in region_ids:
		var entry: Dictionary = active_regions[region_id]
		var coordinates: Array[Vector2i] = []
		var stored_coordinates: Array = coordinates_by_region[region_id]
		for stored_coordinate in stored_coordinates:
			coordinates.append(Vector2i(stored_coordinate))
		coordinates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return a.y < b.y or (a.y == b.y and a.x < b.x)
		)
		_begin_region_stage(entry["region_key"], "partial", coordinates)



func _entity_command_base(operation: String, command_id: String, entity_id: String) -> Dictionary:
	var state: Object = object_stream.state_service
	var command := {
		"schema_version": 1,
		"command_id": command_id,
		"operation": operation,
		"origin": {"type": "player", "id": "local.player"},
		"world_id": String(state.get("world_id")),
		"world_seed": int(state.get("world_seed")),
		"generator_version": int(state.get("generator_version")),
		"expected_world_revision": object_stream.get_command_world_revision(),
		"expected_entity_revision": int(state.get_entity_revision(entity_id)) if not entity_id.is_empty() else 0,
	}
	if operation != "ENTITY_PLACE":
		command["entity_id"] = entity_id
	return command


func _new_entity_command_id() -> String:
	var hex := Crypto.new().generate_random_bytes(16).hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]


func _event_matches_key(event: InputEventKey, keycode: int) -> bool:
	return event.keycode == keycode or event.physical_keycode == keycode


func _is_free_explore_movement_key(event: InputEventKey) -> bool:
	return _event_matches_key(event, KEY_W) \
		or _event_matches_key(event, KEY_A) \
		or _event_matches_key(event, KEY_S) \
		or _event_matches_key(event, KEY_D) \
		or _event_matches_key(event, KEY_UP) \
		or _event_matches_key(event, KEY_DOWN) \
		or _event_matches_key(event, KEY_LEFT) \
		or _event_matches_key(event, KEY_RIGHT) \
		or _event_matches_key(event, KEY_SPACE) \
		or _event_matches_key(event, KEY_SHIFT) \
		or _event_matches_key(event, KEY_CTRL)


func _set_free_explore_enabled(enabled: bool) -> void:
	if free_explore_enabled == enabled or not is_instance_valid(camera):
		return
	free_explore_enabled = enabled
	orbit_dragging = false
	_lod_selection_dirty = true
	if enabled:
		_free_explore_previous_mouse_mode = Input.mouse_mode
		_free_explore_ui_was_visible = ui_layer.visible if is_instance_valid(ui_layer) else true
		_free_explore_yaw = camera.rotation.y
		_free_explore_pitch = clampf(camera.rotation.x, -FREE_EXPLORE_MAX_PITCH_RADIANS, FREE_EXPLORE_MAX_PITCH_RADIANS)
		orbit_target = camera.global_position
		if DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if is_instance_valid(ui_layer):
			ui_layer.visible = false
	else:
		if DisplayServer.get_name() != "headless":
			Input.mouse_mode = _free_explore_previous_mouse_mode
		if is_instance_valid(ui_layer):
			ui_layer.visible = _free_explore_ui_was_visible
		var forward := -camera.global_transform.basis.z.normalized()
		var orbit_distance := clampf(orbit_offset.length(), 20.0, 96.0)
		orbit_target = camera.global_position + forward * orbit_distance
		orbit_offset = camera.global_position - orbit_target
		_update_camera()
	_update_placement_marker_visual()
	if is_inside_tree():
		_update_focus_key()
		if is_instance_valid(object_stream):
			_reconcile_region_window()
			if not enabled and edit_ledger != null:
				_update_status()


func _process_free_exploration(delta: float) -> void:
	if not free_explore_enabled or not is_instance_valid(camera):
		return
	var local_input := Vector3.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		local_input.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		local_input.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		local_input.z -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		local_input.z += 1.0
	if Input.is_key_pressed(KEY_SPACE):
		local_input.y += 1.0
	if Input.is_key_pressed(KEY_SHIFT):
		local_input.y -= 1.0
	_apply_free_explore_motion(local_input, delta, Input.is_key_pressed(KEY_CTRL))


func _apply_free_explore_motion(local_input: Vector3, delta: float, boosted: bool = false) -> void:
	if not free_explore_enabled or not is_instance_valid(camera) or delta <= 0.0 or local_input.length_squared() <= 0.0:
		return
	var basis := camera.global_transform.basis
	var forward := -basis.z
	forward.y = 0.0
	if forward.length_squared() <= 0.000001:
		forward = Vector3(-sin(_free_explore_yaw), 0.0, -cos(_free_explore_yaw))
	else:
		forward = forward.normalized()
	var right := basis.x
	right.y = 0.0
	right = right.normalized() if right.length_squared() > 0.000001 else Vector3.RIGHT
	var world_direction := right * local_input.x + Vector3.UP * local_input.y + forward * -local_input.z
	if world_direction.length_squared() <= 0.000001:
		return
	var speed := FREE_EXPLORE_SPEED * (FREE_EXPLORE_BOOST_MULTIPLIER if boosted else 1.0)
	camera.global_position += world_direction.normalized() * speed * delta
	orbit_target = camera.global_position
	_lod_selection_dirty = true


func _apply_free_explore_look(relative: Vector2) -> void:
	if not free_explore_enabled or not is_instance_valid(camera):
		return
	_free_explore_yaw -= relative.x * FREE_EXPLORE_MOUSE_SENSITIVITY
	_free_explore_pitch = clampf(
		_free_explore_pitch - relative.y * FREE_EXPLORE_MOUSE_SENSITIVITY,
		-FREE_EXPLORE_MAX_PITCH_RADIANS,
		FREE_EXPLORE_MAX_PITCH_RADIANS
	)
	camera.rotation = Vector3(_free_explore_pitch, _free_explore_yaw, 0.0)
	_lod_selection_dirty = true


func _free_explore_screen_center() -> Vector2:
	if not is_inside_tree():
		return Vector2.ZERO
	var rect := get_viewport().get_visible_rect()
	return rect.position + rect.size * 0.5


func _move_focus(delta: Vector3) -> void:
	orbit_target += delta
	_update_camera()
	_update_focus_key()
	_reconcile_region_window()


func _update_lod_selection() -> void:
	if not _lod_selection_dirty:
		return
	if global_rebuild_pending or not _edit_transaction.is_empty():
		return
	# Keep old and replacement meshes alive for at most one LOD region transaction.
	# This bounds temporary transition memory while retaining the normal worker and
	# two-ArrayMesh-per-frame publication limits.
	for stage_value in loading_regions.values():
		var pending_stage: Dictionary = stage_value
		if String(pending_stage.get("purpose", "")) == "partial":
			return
	# LOD selection is event-driven. Camera movement, region publication and
	# completed partial transitions mark it dirty; idle frames do no full scan.
	_lod_selection_dirty = false
	var changed_by_region: Dictionary = {}
	for entry_value in active_regions.values():
		var entry: Dictionary = entry_value
		var region_key: Vector2i = entry["region_key"]
		var id := _region_id(region_key)
		if loading_regions.has(id):
			continue
		var changed: Array[Vector2i] = []
		for coordinate in ChunkGrid.all_coordinates():
			var chunk_id: String = ChunkGrid.stable_id(region_key, coordinate)
			var current_lod := int(_published_lod_by_chunk.get(chunk_id, 0))
			var desired_lod := _desired_lod_for_chunk(region_key, coordinate, current_lod)
			if desired_lod != current_lod:
				changed.append(coordinate)
		if not changed.is_empty():
			changed_by_region[id] = {"region_key": region_key, "coordinates": changed}
	if changed_by_region.is_empty():
		return
	_begin_operation("lod_transition")
	var ordered_ids: Array[String] = []
	for id_value in changed_by_region.keys():
		ordered_ids.append(String(id_value))
	ordered_ids.sort()
	var change: Dictionary = changed_by_region[ordered_ids[0]]
	_begin_region_stage(change["region_key"], "partial", change["coordinates"])
	_update_runtime_diagnostics()
	_update_status()


func _is_x_edge(coordinate: Vector2i) -> bool:
	return coordinate.x == 0 or coordinate.x == ChunkGrid.CHUNK_COUNT_X - 1


func _is_z_edge(coordinate: Vector2i) -> bool:
	return coordinate.y == 0 or coordinate.y == ChunkGrid.CHUNK_COUNT_Z - 1


func _uses_shared_corner(coordinate: Vector2i) -> bool:
	return _shared_boundary_runtime_enabled \
		and not cave_section_enabled \
		and _is_x_edge(coordinate) and _is_z_edge(coordinate)


func _uses_shared_x_boundary(coordinate: Vector2i) -> bool:
	return _shared_boundary_runtime_enabled \
		and not cave_section_enabled \
		and _is_x_edge(coordinate) and not _is_z_edge(coordinate)


func _uses_shared_z_boundary(coordinate: Vector2i) -> bool:
	return _shared_boundary_runtime_enabled \
		and not cave_section_enabled \
		and _is_z_edge(coordinate) and not _is_x_edge(coordinate)


func _uses_any_shared_boundary(coordinate: Vector2i) -> bool:
	return _uses_shared_corner(coordinate) \
		or _uses_shared_x_boundary(coordinate) \
		or _uses_shared_z_boundary(coordinate)


func _corner_min_region(region_key: Vector2i, coordinate: Vector2i) -> Vector2i:
	return region_key + Vector2i(
		-1 if coordinate.x == 0 else 0,
		-1 if coordinate.y == 0 else 0
	)


func _corner_owner_for_coordinate(coordinate: Vector2i) -> String:
	return ("minx" if coordinate.x == ChunkGrid.CHUNK_COUNT_X - 1 else "maxx") + "_" \
		+ ("minz" if coordinate.y == ChunkGrid.CHUNK_COUNT_Z - 1 else "maxz")


func _desired_lod_for_chunk(region_key: Vector2i, coordinate: Vector2i, current_lod: int) -> int:
	var chunk_id: String = ChunkGrid.stable_id(region_key, coordinate)
	# Region-edge chunks are the shared-surface collar. LOD transitions begin one
	# chunk inward so the independently selected interior LOD never owns the
	# regional seam.
	if _uses_any_shared_boundary(coordinate):
		return 0
	if not lod_enabled or _lod_fallback_chunks.has(chunk_id):
		return 0
	var center_local: Vector3 = ChunkGrid.origin_for(coordinate) + ChunkGrid.size_for(coordinate) * 0.5
	var center_world: Vector3 = SpatialGrid.region_local_to_world(region_key, center_local)
	var distance := camera.global_position.distance_to(center_world)
	return TerrainLodPolicy.select_lod(distance, current_lod, true)


func _update_focus_key() -> void:
	var mapped: Dictionary = SpatialGrid.world_to_region_local(orbit_target)
	if mapped.get("valid", false):
		focus_region_key = mapped["region_key"]
		world_state = _state_for_region(focus_region_key)
		if (
			is_instance_valid(simulation_runtime)
			and bool(simulation_runtime.get_world_scope_lifecycle_metrics().get("initialized", false))
		):
			var focus_result: Dictionary = simulation_runtime.update_world_scope_focus(
				focus_region_key
			)
			if not focus_result.get("ok", false):
				_simulation_streaming_status = "Simulation focus routing issue: %s" % focus_result.get("reason", "unknown")


func _reconcile_region_window(force: bool = false) -> void:
	var reconcile_started_usec := Time.get_ticks_usec()
	var active_before := active_regions.size()
	var loading_before := loading_regions.size()
	_update_focus_key()
	if not force and focus_region_key == _last_reconciled_focus:
		return
	_last_reconciled_focus = focus_region_key
	var desired := _region_keys_within_radius(focus_region_key, REQUEST_RADIUS)
	var retained := _region_keys_within_radius(focus_region_key, UNLOAD_RADIUS)
	if terrain_effect_runtime != null and bool(terrain_effect_runtime.get("initialized")):
		var effect_window: Dictionary = terrain_effect_runtime.update_resident_target_regions(
			retained
		)
		if not effect_window.get("ok", false):
			_terrain_effect_status = "Terrain-object effects unavailable (%s)" % effect_window.get("reason", "unknown")
			last_stream_error = _terrain_effect_status
			return
	var retained_ids: Dictionary = {}
	for key in retained:
		retained_ids[_region_id(key)] = true
	for id_value in active_regions.keys().duplicate():
		var id: String = id_value
		if not retained_ids.has(id):
			_unload_region(id)

	if global_rebuild_pending:
		_ensure_full_rebuild_targets(desired, retained_ids)
	else:
		for id_value in loading_regions.keys().duplicate():
			var id: String = id_value
			var stage: Dictionary = loading_regions[id]
			var key: Vector2i = stage["region_key"]
			if not retained_ids.has(id) or (stage["purpose"] == "load" and not _contains_region(desired, key)):
				loading_regions.erase(id)
				if not _edit_transaction.is_empty() and (_edit_transaction["target_ids"] as Array).has(id):
					_edit_transaction["target_ids"].erase(id)
		if not _edit_transaction.is_empty() and (_edit_transaction["target_ids"] as Array).is_empty():
			_finish_edit_transaction("accepted; rebuild dependencies left residency and will apply it on load")
		for key in desired:
			var id := _region_id(key)
			if not active_regions.has(id) and not loading_regions.has(id):
				if loading_regions.is_empty():
					_begin_operation("region_stream_load")
				if _edit_transaction_affects_region(key):
					_add_edit_transaction_region(key)
				else:
					_begin_region_stage(key, "load", ChunkGrid.all_coordinates())
		for id_value in loading_regions.keys().duplicate():
			var id: String = id_value
			var stage: Dictionary = loading_regions[id]
			var key: Vector2i = stage["region_key"]
			if stage["purpose"] == "load" and _edit_transaction_affects_region(key):
				_add_edit_transaction_region(key)
	_sync_world_state_index()
	_update_runtime_diagnostics()
	if _perf_trace_enabled:
		PerformanceTrace.emit("terrain_window_reconcile", {
			"duration_usec": Time.get_ticks_usec() - reconcile_started_usec,
			"force": force,
			"focus": [focus_region_key.x, focus_region_key.y],
			"active_before": active_before,
			"active_after": active_regions.size(),
			"loading_before": loading_before,
			"loading_after": loading_regions.size(),
			"mesh_jobs_in_flight": _mesh_jobs.size(),
			"effect_prefetch_pending": int(terrain_effect_runtime.get_prefetch_pending_count()) if terrain_effect_runtime != null and bool(terrain_effect_runtime.get("initialized")) else 0,
		})


func _edit_transaction_affects_region(region_key: Vector2i) -> bool:
	return not _edit_transaction.is_empty() \
		and (_edit_transaction.get("rebuild_regions", []) as Array).has(region_key)


func _add_edit_transaction_region(region_key: Vector2i) -> void:
	if not _edit_transaction_affects_region(region_key):
		return
	var id := _region_id(region_key)
	var already_targeted := false
	for target in _edit_transaction["targets"]:
		if target["id"] == id:
			already_targeted = true
			break
	if not already_targeted:
		_edit_transaction["targets"].append({
			"region_key": region_key,
			"id": id,
			"chunks": ChunkGrid.all_coordinates(),
			"full": true,
		})
	if _edit_transaction.get("stage_state", "") == "failed_pending_retry":
		_edit_transaction["stage_state"] = "staging"
		_edit_transaction["retries"] = 0
		_start_edit_transaction_attempt()
		return
	if not (_edit_transaction["target_ids"] as Array).has(id):
		loading_regions.erase(id)
		_begin_region_stage(region_key, "edit_transaction", ChunkGrid.all_coordinates())
		_edit_transaction["target_ids"].append(id)
		_edit_transaction["rebuild_chunk_count"] += ChunkGrid.CHUNK_COUNT_X * ChunkGrid.CHUNK_COUNT_Z
	_update_runtime_diagnostics()


func _region_keys_within_radius(center: Vector2i, radius: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for z in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			result.append(Vector2i(x, z))
	return result


func _contains_region(keys: Array[Vector2i], target: Vector2i) -> bool:
	return keys.has(target)


func _ensure_full_rebuild_targets(desired: Array[Vector2i], retained_ids: Dictionary) -> void:
	var target_keys: Array[Vector2i] = []
	for key in desired:
		target_keys.append(key)
	for entry in active_regions.values():
		var key: Vector2i = entry["region_key"]
		if retained_ids.has(_region_id(key)) and not target_keys.has(key):
			target_keys.append(key)
	target_keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := maxi(absi(a.x - focus_region_key.x), absi(a.y - focus_region_key.y))
		var db := maxi(absi(b.x - focus_region_key.x), absi(b.y - focus_region_key.y))
		if da == db:
			if a.y == b.y:
				return a.x < b.x
			return a.y < b.y
		return da < db
	)
	var target_ids: Array[String] = []
	for key in target_keys:
		target_ids.append(_region_id(key))
	if target_ids == _full_rebuild_target_ids:
		return
	_full_rebuild_target_ids = target_ids
	loading_regions.clear()
	for key in target_keys:
		_begin_region_stage(key, "full", ChunkGrid.all_coordinates())


func _begin_region_stage(region_key: Vector2i, purpose: String, chunk_coordinates: Array[Vector2i]) -> void:
	var id := _region_id(region_key)
	var state: RefCounted
	if purpose == "full" and not _pending_world_load.is_empty():
		state = WorldState.new(int(_pending_world_load["world_seed"]), region_key, _pending_world_load["ledger"])
	else:
		state = _state_for_region(region_key)
	if state == null:
		state = WorldState.new(world_seed, region_key, edit_ledger)
	var coordinates: Array[Vector2i] = chunk_coordinates.duplicate()
	var token := _next_stage_token
	_next_stage_token += 1
	# Only stages that can replace the region-level terrain publication may
	# invalidate an in-flight object publication. LOD partial stages update
	# existing chunk meshes in place and must not cancel entity visual rebuilds.
	if purpose == "load" or purpose == "full" or not active_regions.has(id):
		object_stream.expect_region_publication(region_key, token)
	var queued_times: Array[int] = []
	var queued_now := Time.get_ticks_usec()
	for _coordinate in coordinates:
		queued_times.append(queued_now)
	var lod_by_coordinate: Dictionary = {}
	for coordinate in coordinates:
		var chunk_id: String = ChunkGrid.stable_id(region_key, coordinate)
		var current_lod := int(_published_lod_by_chunk.get(chunk_id, 0))
		lod_by_coordinate[coordinate] = _desired_lod_for_chunk(region_key, coordinate, current_lod)
	loading_regions[id] = {
		"region_key": region_key,
		"world_state": state,
		"purpose": purpose,
		"chunk_coordinates": coordinates,
		"next_index": 0,
		"stage_token": token,
		"submit_index": 0,
		"pending_count": 0,
		"chunk_queued_usec": queued_times,
		"meshes": {},
		"vertex_count_by_coordinate": {},
		"triangle_count_by_coordinate": {},
		"lod_by_coordinate": lod_by_coordinate,
		"actual_lod_by_coordinate": {},
		"fallback_by_coordinate": {},
		"cave_section_enabled": cave_section_enabled,
		"edit_revision": state.brush_edits.revision,
		"terrain_effect_authority_revision": object_stream.get_command_world_revision(),
		"chunk_enqueued_usec": Time.get_ticks_usec(),
		"retry_count": 0,
	}
	world_states[id] = state
	if region_key == focus_region_key:
		world_state = state
	if _perf_trace_enabled:
		PerformanceTrace.emit("terrain_stage_begin", {
			"region": [region_key.x, region_key.y],
			"purpose": purpose,
			"chunk_count": coordinates.size(),
			"stage_token": token,
			"loading_regions": loading_regions.size(),
			"mesh_jobs_in_flight": _mesh_jobs.size(),
		})


func _process_one_chunk_job() -> void:
	_process_completed_mesh_jobs()
	_dispatch_mesh_jobs()
	if loading_regions.is_empty() and global_rebuild_pending:
		_try_commit_global_rebuild()


func _process_completed_mesh_jobs() -> void:
	var completed_task_ids: Array[int] = []
	for task_id_value in _mesh_jobs.keys():
		var task_id := int(task_id_value)
		if WorkerThreadPool.is_task_completed(task_id):
			completed_task_ids.append(task_id)
	completed_task_ids.sort_custom(func(a: int, b: int) -> bool:
		var record_a: Dictionary = _mesh_jobs[a]
		var record_b: Dictionary = _mesh_jobs[b]
		var stage_a: Dictionary = loading_regions.get(String(record_a.get("stage_id", "")), {})
		var stage_b: Dictionary = loading_regions.get(String(record_b.get("stage_id", "")), {})
		var pa := _stage_priority(String(stage_a.get("purpose", "load")))
		var pb := _stage_priority(String(stage_b.get("purpose", "load")))
		if pa != pb:
			return pa < pb
		var ka: Vector2i = stage_a.get("region_key", Vector2i.ZERO)
		var kb: Vector2i = stage_b.get("region_key", Vector2i.ZERO)
		var da := maxi(absi(ka.x - focus_region_key.x), absi(ka.y - focus_region_key.y))
		var db := maxi(absi(kb.x - focus_region_key.x), absi(kb.y - focus_region_key.y))
		return da < db
	)
	var uploads_this_frame := 0
	var upload_frame_started_usec := Time.get_ticks_usec()
	for task_id in completed_task_ids:
		if uploads_this_frame >= MAX_MESH_UPLOADS_PER_FRAME:
			break
		if uploads_this_frame > 0 \
			and Time.get_ticks_usec() - upload_frame_started_usec >= MESH_UPLOAD_FRAME_BUDGET_USEC:
			break
		WorkerThreadPool.wait_for_task_completion(task_id)
		var record: Dictionary = _mesh_jobs[task_id]
		_mesh_jobs.erase(task_id)
		var job = record["job"]
		var id: String = record["stage_id"]
		if not loading_regions.has(id):
			continue
		var stage: Dictionary = loading_regions[id]
		if int(stage["stage_token"]) != int(record["stage_token"]):
			continue
		var contributes_to_operation := _stage_contributes_to_active_operation(stage)
		if contributes_to_operation:
			_pool_queue_wait_usec_samples.append(maxi(0, int(job.worker_started_usec) - int(record["submitted_usec"])))
		var state: RefCounted = stage["world_state"]
		if state.brush_edits.revision != int(stage["edit_revision"]) \
			or object_stream.get_command_world_revision() \
				!= int(stage.get("terrain_effect_authority_revision", -1)):
			_supersede_region_stage(id)
			continue
		var cpu_result: Dictionary
		var completed_kind := String(record.get("job_kind", "chunk"))
		if completed_kind in ["shared_boundary_x", "shared_boundary_z", "shared_corner_xz"]:
			var shared_result: Dictionary = job.result
			if not shared_result.get("valid", false):
				_fail_region_stage(id, "Shared-surface CPU mesh job failed; previous visible meshes retained")
				continue
			var shared_side := String(record.get("shared_side", ""))
			cpu_result = shared_result.get(shared_side, {})
			var diag := (shared_result.get("diagnostics", {}) as Dictionary).duplicate(true)
			_last_shared_boundary_diagnostics = diag
			if completed_kind == "shared_boundary_x":
				_last_shared_x_boundary_diagnostics = diag
			elif completed_kind == "shared_boundary_z":
				_last_shared_z_boundary_diagnostics = diag
			else:
				_last_shared_corner_diagnostics = diag
			last_mesh_diagnostics["last_shared_boundary_diagnostics"] = _last_shared_boundary_diagnostics
			last_mesh_diagnostics["last_shared_x_boundary_diagnostics"] = _last_shared_x_boundary_diagnostics
			last_mesh_diagnostics["last_shared_z_boundary_diagnostics"] = _last_shared_z_boundary_diagnostics
			last_mesh_diagnostics["last_shared_corner_diagnostics"] = _last_shared_corner_diagnostics
		else:
			cpu_result = job.result
		if not cpu_result.get("valid", false) or not cpu_result.has("positions"):
			_fail_region_stage(id, "Chunk CPU mesh job failed; previous visible meshes retained")
			continue
		var upload_started_usec := Time.get_ticks_usec()
		var result: Dictionary = TerrainMesher.mesh_from_cpu_data(cpu_result)
		var upload_elapsed_usec := Time.get_ticks_usec() - upload_started_usec
		var worker_queue_usec := maxi(0, int(job.worker_started_usec) - int(record["submitted_usec"]))
		var worker_run_usec := maxi(0, int(job.worker_finished_usec) - int(job.worker_started_usec))
		if _perf_trace_enabled and (
			worker_run_usec >= PerformanceTrace.min_usec()
			or upload_elapsed_usec >= PerformanceTrace.min_usec()
			or worker_queue_usec >= PerformanceTrace.min_usec()
		):
			PerformanceTrace.emit("terrain_mesh_job_complete", {
				"region": [(stage["region_key"] as Vector2i).x, (stage["region_key"] as Vector2i).y],
				"chunk": [(record["coordinate"] as Vector2i).x, (record["coordinate"] as Vector2i).y],
				"purpose": String(stage["purpose"]),
				"job_kind": completed_kind,
				"snapshot_usec": int(record.get("snapshot_usec", 0)),
				"worker_queue_usec": worker_queue_usec,
				"worker_run_usec": worker_run_usec,
				"upload_usec": upload_elapsed_usec,
				"job_total_usec": Time.get_ticks_usec() - int(record["submitted_usec"]),
				"mesh_jobs_remaining": _mesh_jobs.size(),
				"completed_ready_count": completed_task_ids.size(),
			})
		if String(stage["purpose"]) == "edit_transaction" and not _edit_transaction.is_empty():
			_edit_transaction["trace_worker_queue_usec_max"] = maxi(int(_edit_transaction.get("trace_worker_queue_usec_max", 0)), worker_queue_usec)
			_edit_transaction["trace_worker_run_usec_max"] = maxi(int(_edit_transaction.get("trace_worker_run_usec_max", 0)), worker_run_usec)
			_edit_transaction["trace_upload_usec_total"] = int(_edit_transaction.get("trace_upload_usec_total", 0)) + upload_elapsed_usec
			_edit_transaction["trace_upload_usec_max"] = maxi(int(_edit_transaction.get("trace_upload_usec_max", 0)), upload_elapsed_usec)
			_edit_trace("job_complete", {
				"sequence_start": int(_edit_transaction.get("operation_sequence_start", -1)),
				"sequence_end": int(_edit_transaction.get("operation_sequence", -1)),
				"revision": int(stage["edit_revision"]),
				"region": str(stage["region_key"]),
				"chunk": str(record["coordinate"]),
				"kind": completed_kind,
				"side": String(record.get("shared_side", "")),
				"snapshot_ms": float(record.get("snapshot_usec", 0)) / 1000.0,
				"worker_queue_ms": float(worker_queue_usec) / 1000.0,
				"worker_run_ms": float(worker_run_usec) / 1000.0,
				"upload_ms": float(upload_elapsed_usec) / 1000.0,
				"job_total_ms": float(Time.get_ticks_usec() - int(record["submitted_usec"])) / 1000.0,
				"candidate_operations": int(record.get("snapshot_candidate_count", -1)),
				"raw_candidate_operations": int(record.get("snapshot_raw_candidate_count", -1)),
				"materialized_tiles": int(record.get("snapshot_tile_count", -1)),
				"sdf_ms": float((result.get("timings_usec", {}) as Dictionary).get("sdf_and_ledger", 0)) / 1000.0,
				"triangulation_ms": float((result.get("timings_usec", {}) as Dictionary).get("triangulation_and_face_normals", 0)) / 1000.0,
				"normals_ms": float((result.get("timings_usec", {}) as Dictionary).get("shared_gradient_normals", 0)) / 1000.0,
				"shared_sampling_ms": float((result.get("timings_usec", {}) as Dictionary).get("shared_sampling", 0)) / 1000.0,
				"shared_polygonize_ms": float((result.get("timings_usec", {}) as Dictionary).get("shared_polygonize", 0)) / 1000.0,
				"shared_deduplicate_ms": float((result.get("timings_usec", {}) as Dictionary).get("shared_deduplicate", 0)) / 1000.0,
				"shared_diagnostics_ms": float((result.get("timings_usec", {}) as Dictionary).get("shared_diagnostics", 0)) / 1000.0,
				"shared_signature_ms": float((result.get("timings_usec", {}) as Dictionary).get("shared_signature", 0)) / 1000.0,
				"shared_partition_ms": float((result.get("timings_usec", {}) as Dictionary).get("shared_partition", 0)) / 1000.0,
				"shared_authority_total_ms": float((result.get("timings_usec", {}) as Dictionary).get("shared_authority_total", 0)) / 1000.0,
				"shared_volume_total_ms": float((result.get("timings_usec", {}) as Dictionary).get("shared_volume_total", 0)) / 1000.0,
				"shared_cell_count": int((result.get("work_counters", {}) as Dictionary).get("cell_count", 0)),
				"shared_mixed_cell_count": int((result.get("work_counters", {}) as Dictionary).get("mixed_cell_count", 0)),
				"shared_uniform_cell_count": int((result.get("work_counters", {}) as Dictionary).get("uniform_cell_count", 0)),
				"shared_tet_call_count": int((result.get("work_counters", {}) as Dictionary).get("tet_call_count", 0)),
				"shared_triangle_candidate_count": int((result.get("work_counters", {}) as Dictionary).get("triangle_candidate_count", 0)),
				"shared_triangle_count": int((result.get("work_counters", {}) as Dictionary).get("triangle_count", 0)),
				"shared_unique_root_count": int((result.get("work_counters", {}) as Dictionary).get("unique_root_count", 0)),
				"shared_sample_count": int((result.get("work_counters", {}) as Dictionary).get("sample_count", 0)),
			})
		if contributes_to_operation:
			_mesh_upload_usec_samples.append(upload_elapsed_usec)
		_last_mesh_upload_ms = float(upload_elapsed_usec) / 1000.0
		_peak_mesh_upload_ms = maxf(_peak_mesh_upload_ms, _last_mesh_upload_ms)
		_mesh_uploads_this_frame += 1
		var cpu_timings: Dictionary = result.get("timings_usec", {})
		var cpu_work_usec := int(cpu_timings.get("sdf_and_ledger", 0)) \
			+ int(cpu_timings.get("triangulation_and_face_normals", 0)) \
			+ int(cpu_timings.get("shared_gradient_normals", 0))
		if contributes_to_operation:
			_operation_total_mesh_work_ms += float(cpu_work_usec + upload_elapsed_usec) / 1000.0
			_add_stage_timings(result.get("timings_usec", {}))
		if not result.get("mesh") is ArrayMesh:
			_fail_region_stage(id, "Chunk main-thread mesh creation failed; previous meshes retained")
			continue
		var coordinate: Vector2i = record["coordinate"]
		stage["meshes"][coordinate] = result["mesh"]
		stage["vertex_count_by_coordinate"][coordinate] = int(result.get("vertex_count", 0))
		stage["triangle_count_by_coordinate"][coordinate] = int(result.get("triangle_count", 0))
		stage["actual_lod_by_coordinate"][coordinate] = int(result.get("lod_level", 0))
		stage["fallback_by_coordinate"][coordinate] = bool(result.get("lod_fallback", false))
		stage["next_index"] = int(stage["next_index"]) + 1
		stage["pending_count"] = maxi(0, int(stage["pending_count"]) - 1)
		stage["sample_count"] = int(stage.get("sample_count", 0)) + int(result["sample_count"])
		stage["triangle_count"] = int(stage.get("triangle_count", 0)) + int(result["triangle_count"])
		var chunk_id: String = ChunkGrid.stable_id(stage["region_key"], coordinate)
		# A retried or superseded staging attempt can finish a chunk before the
		# transaction restarts. Diagnostics represent affected chunk identities,
		# not the number of mesh-job completions.
		if contributes_to_operation:
			if not _operation_chunk_ids.has(chunk_id):
				_operation_chunk_ids.append(chunk_id)
			_operation_sample_count += int(result["sample_count"])
		if stage["purpose"] == "edit_transaction" and not _edit_transaction.is_empty():
			_edit_transaction["mesh_job_count"] = int(_edit_transaction.get("mesh_job_count", 0)) + 1
		loading_regions[id] = stage
		uploads_this_frame += 1
		if int(stage["next_index"]) >= (stage["chunk_coordinates"] as Array).size() \
			and int(stage["submit_index"]) >= (stage["chunk_coordinates"] as Array).size() \
			and int(stage["pending_count"]) == 0:
			_complete_region_stage(id)


func _dispatch_mesh_jobs() -> void:
	var dispatch_started_usec := Time.get_ticks_usec()
	while _mesh_jobs.size() < _mesh_job_limit:
		if _mesh_dispatches_this_frame >= MAX_MESH_JOB_DISPATCHES_PER_FRAME:
			return
		if _mesh_dispatches_this_frame > 0 			and Time.get_ticks_usec() - dispatch_started_usec >= MESH_SNAPSHOT_FRAME_BUDGET_USEC:
			return
		var request := _next_mesh_job_request()
		if request.is_empty():
			return
		var id: String = request["id"]
		var stage: Dictionary = loading_regions[id]
		var state: RefCounted = stage["world_state"]
		if state.brush_edits.revision != int(stage["edit_revision"]) \
			or object_stream.get_command_world_revision() \
				!= int(stage.get("terrain_effect_authority_revision", -1)):
			_supersede_region_stage(id)
			continue
		var inject_edit_failure: bool = debug_fail_next_mesh_stage and String(stage["purpose"]) == "edit_transaction"
		var inject_load_failure: bool = debug_fail_next_load_stage and String(stage["purpose"]) == "load"
		if inject_edit_failure or inject_load_failure:
			debug_fail_next_mesh_stage = false
			debug_fail_next_load_stage = false
			_fail_region_stage(id, "Injected mesh-stage failure; prior meshes retained")
			continue
		var coordinate: Vector2i = request["coordinate"]
		var queue_index: int = int(stage["submit_index"])
		var enqueued_usec := int(stage["chunk_queued_usec"][queue_index])
		var submitted_usec := Time.get_ticks_usec()
		var snapshot_started_usec := Time.get_ticks_usec()
		var snapshot_meta: Dictionary = {}
		if _stage_contributes_to_active_operation(stage):
			_mesh_queue_wait_usec_samples.append(maxi(0, submitted_usec - enqueued_usec))
		var job: RefCounted
		var job_kind := "chunk"
		var shared_side := ""
		if _uses_shared_corner(coordinate):
			var min_region := _corner_min_region(stage["region_key"], coordinate)
			var corner_snapshot: Dictionary = SharedBoundaryAuthority.make_xz_corner_snapshot(
				state.brush_edits, min_region
			)
			var prepared_corner := _prepare_terrain_effect_snapshot(
				corner_snapshot,
				[
					{"region_key": min_region, "chunk_coordinate": Vector2i(ChunkGrid.CHUNK_COUNT_X - 1, ChunkGrid.CHUNK_COUNT_Z - 1)},
					{"region_key": min_region + Vector2i.RIGHT, "chunk_coordinate": Vector2i(0, ChunkGrid.CHUNK_COUNT_Z - 1)},
					{"region_key": min_region + Vector2i(0, 1), "chunk_coordinate": Vector2i(ChunkGrid.CHUNK_COUNT_X - 1, 0)},
					{"region_key": min_region + Vector2i(1, 1), "chunk_coordinate": Vector2i.ZERO},
				]
			)
			if not prepared_corner.get("ok", false):
				if _terrain_effect_snapshot_pending(prepared_corner):
					return
				_fail_region_stage(id, "Terrain-object effect snapshot failed: %s" % prepared_corner.get("reason", "unknown"))
				continue
			corner_snapshot = prepared_corner["snapshot"]
			snapshot_meta = corner_snapshot
			job = SharedCornerMeshJob.new(
				state.world_seed, min_region, corner_snapshot, submitted_usec,
				debug_shared_runtime_diagnostics
			)
			job_kind = "shared_corner_xz"
			shared_side = _corner_owner_for_coordinate(coordinate)
		elif _uses_shared_x_boundary(coordinate):
			var left_region: Vector2i = stage["region_key"] if coordinate.x == ChunkGrid.CHUNK_COUNT_X - 1 \
				else stage["region_key"] - Vector2i.RIGHT
			var pair_snapshot: Dictionary = SharedBoundaryAuthority.make_x_pair_snapshot(
				state.brush_edits, left_region, coordinate.y
			)
			var prepared_pair := _prepare_terrain_effect_snapshot(
				pair_snapshot,
				[
					{"region_key": left_region, "chunk_coordinate": Vector2i(ChunkGrid.CHUNK_COUNT_X - 1, coordinate.y)},
					{"region_key": left_region + Vector2i.RIGHT, "chunk_coordinate": Vector2i(0, coordinate.y)},
				]
			)
			if not prepared_pair.get("ok", false):
				if _terrain_effect_snapshot_pending(prepared_pair):
					return
				_fail_region_stage(id, "Terrain-object effect snapshot failed: %s" % prepared_pair.get("reason", "unknown"))
				continue
			pair_snapshot = prepared_pair["snapshot"]
			snapshot_meta = pair_snapshot
			job = SharedBoundaryMeshJob.new(
				state.world_seed, left_region, coordinate.y, pair_snapshot, submitted_usec,
				debug_shared_runtime_diagnostics
			)
			job_kind = "shared_boundary_x"
			shared_side = "left" if coordinate.x == ChunkGrid.CHUNK_COUNT_X - 1 else "right"
		elif _uses_shared_z_boundary(coordinate):
			var low_region: Vector2i = stage["region_key"] if coordinate.y == ChunkGrid.CHUNK_COUNT_Z - 1 \
				else stage["region_key"] - Vector2i(0, 1)
			var z_snapshot: Dictionary = SharedBoundaryAuthority.make_z_pair_snapshot(
				state.brush_edits, low_region, coordinate.x
			)
			var prepared_z := _prepare_terrain_effect_snapshot(
				z_snapshot,
				[
					{"region_key": low_region, "chunk_coordinate": Vector2i(coordinate.x, ChunkGrid.CHUNK_COUNT_Z - 1)},
					{"region_key": low_region + Vector2i(0, 1), "chunk_coordinate": Vector2i(coordinate.x, 0)},
				]
			)
			if not prepared_z.get("ok", false):
				if _terrain_effect_snapshot_pending(prepared_z):
					return
				_fail_region_stage(id, "Terrain-object effect snapshot failed: %s" % prepared_z.get("reason", "unknown"))
				continue
			z_snapshot = prepared_z["snapshot"]
			snapshot_meta = z_snapshot
			job = SharedZBoundaryMeshJob.new(
				state.world_seed, low_region, coordinate.x, z_snapshot, submitted_usec,
				debug_shared_runtime_diagnostics
			)
			job_kind = "shared_boundary_z"
			shared_side = "low" if coordinate.y == ChunkGrid.CHUNK_COUNT_Z - 1 else "high"
		else:
			var chunk_snapshot: Dictionary = state.brush_edits.get_meshing_snapshot_for_chunk(
				stage["region_key"], coordinate
			)
			var prepared_chunk := _prepare_terrain_effect_snapshot(
				chunk_snapshot,
				[{"region_key": stage["region_key"], "chunk_coordinate": coordinate}]
			)
			if not prepared_chunk.get("ok", false):
				if _terrain_effect_snapshot_pending(prepared_chunk):
					return
				_fail_region_stage(id, "Terrain-object effect snapshot failed: %s" % prepared_chunk.get("reason", "unknown"))
				continue
			chunk_snapshot = prepared_chunk["snapshot"]
			snapshot_meta = chunk_snapshot
			job = TerrainMeshJob.new(
				state.world_seed, stage["region_key"], coordinate,
				stage["cave_section_enabled"],
				chunk_snapshot,
				submitted_usec,
				int(stage.get("lod_by_coordinate", {}).get(coordinate, 0))
			)
		var snapshot_elapsed_usec := Time.get_ticks_usec() - snapshot_started_usec
		if _perf_trace_enabled and snapshot_elapsed_usec >= PerformanceTrace.min_usec():
			PerformanceTrace.emit("terrain_mesh_snapshot", {
				"duration_usec": snapshot_elapsed_usec,
				"region": [(stage["region_key"] as Vector2i).x, (stage["region_key"] as Vector2i).y],
				"chunk": [coordinate.x, coordinate.y],
				"purpose": String(stage["purpose"]),
				"job_kind": job_kind,
				"queue_wait_usec": maxi(0, submitted_usec - enqueued_usec),
				"effect_frame_count": int(snapshot_meta.get("terrain_effect_frame_count", 0)),
				"candidate_operations": int(snapshot_meta.get("candidate_operation_count", -1)),
				"materialized_tiles": (snapshot_meta.get("materialized_tiles", []) as Array).size(),
				"mesh_jobs_in_flight": _mesh_jobs.size(),
				"dispatches_this_frame": _mesh_dispatches_this_frame + 1,
				"dispatch_budget": MAX_MESH_JOB_DISPATCHES_PER_FRAME,
			})
		if String(stage["purpose"]) == "edit_transaction" and not _edit_transaction.is_empty():
			_edit_transaction["trace_snapshot_usec_total"] = int(_edit_transaction.get("trace_snapshot_usec_total", 0)) + snapshot_elapsed_usec
			_edit_transaction["trace_snapshot_usec_max"] = maxi(int(_edit_transaction.get("trace_snapshot_usec_max", 0)), snapshot_elapsed_usec)
		var high_priority: bool = String(stage["purpose"]) in ["edit_transaction", "partial"]
		var task_label := "P1.0C terrain chunk"
		if job_kind == "shared_boundary_x":
			task_label = "shared boundary X"
		elif job_kind == "shared_boundary_z":
			task_label = "shared boundary Z"
		elif job_kind == "shared_corner_xz":
			task_label = "shared corner XZ"
		var task_id := WorkerThreadPool.add_task(
			Callable(job, "run"), high_priority, task_label
		)
		if task_id < 0:
			_fail_region_stage(id, "Worker pool rejected a mesh job; previous visible meshes retained")
			continue
		stage["submit_index"] = int(stage["submit_index"]) + 1
		stage["pending_count"] = int(stage["pending_count"]) + 1
		loading_regions[id] = stage
		_mesh_dispatches_this_frame += 1
		_mesh_jobs[task_id] = {
			"job": job,
			"stage_id": id,
			"stage_token": stage["stage_token"],
			"coordinate": coordinate,
			"submitted_usec": submitted_usec,
			"job_kind": job_kind,
			"shared_side": shared_side,
			"snapshot_usec": snapshot_elapsed_usec,
			"snapshot_candidate_count": int(snapshot_meta.get("candidate_operation_count", -1)),
			"snapshot_raw_candidate_count": int(snapshot_meta.get("raw_candidate_operation_count", snapshot_meta.get("candidate_operation_count", -1))),
			"snapshot_tile_count": (snapshot_meta.get("materialized_tiles", []) as Array).size(),
		}
		_peak_mesh_jobs_in_flight = maxi(_peak_mesh_jobs_in_flight, _mesh_jobs.size())
		if String(stage["purpose"]) == "edit_transaction":
			_edit_trace("job_dispatch", {
				"sequence_start": int(_edit_transaction.get("operation_sequence_start", -1)),
				"sequence_end": int(_edit_transaction.get("operation_sequence", -1)),
				"revision": int(stage["edit_revision"]),
				"region": str(stage["region_key"]),
				"chunk": str(coordinate),
				"kind": job_kind,
				"side": shared_side,
				"snapshot_ms": float(snapshot_elapsed_usec) / 1000.0,
				"stage_queue_ms": float(submitted_usec - enqueued_usec) / 1000.0,
				"candidate_operations": int(snapshot_meta.get("candidate_operation_count", -1)),
				"raw_candidate_operations": int(snapshot_meta.get("raw_candidate_operation_count", snapshot_meta.get("candidate_operation_count", -1))),
				"materialized_tiles": (snapshot_meta.get("materialized_tiles", []) as Array).size(),
			})


func _prepare_terrain_effect_snapshot(
	base_snapshot: Dictionary,
	targets: Array
) -> Dictionary:
	if terrain_effect_runtime == null or not bool(terrain_effect_runtime.get("initialized")):
		return {"ok": false, "reason": "terrain_effect_runtime_unavailable"}
	var prepared: Dictionary = terrain_effect_runtime.prepare_targets_snapshot(
		base_snapshot, targets
	)
	if prepared.get("ok", false):
		_terrain_effect_status = "Terrain-object effects active (%d frame(s), %d resident scope(s))" % [
			int(prepared.get("effect_count", 0)),
			int(terrain_effect_runtime.get_loaded_scope_count()),
		]
	elif prepared.get("pending", false):
		_terrain_effect_status = "Terrain-object effects prefetching (%d scope(s) pending)" % int(
			prepared.get("prefetch_pending_count", prepared.get("missing_scope_count", 0))
		)
	else:
		_terrain_effect_status = "Terrain-object effects unavailable (%s)" % prepared.get("reason", "unknown")
	return prepared


func _terrain_effect_snapshot_pending(result: Dictionary) -> bool:
	return not result.get("ok", false) and bool(result.get("pending", false))


func _next_mesh_job_request() -> Dictionary:
	var candidates: Array[String] = []
	for key_value in loading_regions.keys():
		candidates.append(String(key_value))
	candidates.sort_custom(func(a: String, b: String) -> bool:
		var stage_a: Dictionary = loading_regions[a]
		var stage_b: Dictionary = loading_regions[b]
		var pa := _stage_priority(String(stage_a["purpose"]))
		var pb := _stage_priority(String(stage_b["purpose"]))
		if pa != pb:
			return pa < pb
		var ka: Vector2i = stage_a["region_key"]
		var kb: Vector2i = stage_b["region_key"]
		var da := maxi(absi(ka.x - focus_region_key.x), absi(ka.y - focus_region_key.y))
		var db := maxi(absi(kb.x - focus_region_key.x), absi(kb.y - focus_region_key.y))
		if da == db:
			return ka.y < kb.y if ka.y != kb.y else ka.x < kb.x
		return da < db
	)
	for id in candidates:
		var stage: Dictionary = loading_regions[id]
		var submit_index: int = int(stage.get("submit_index", 0))
		var coordinates: Array[Vector2i] = stage["chunk_coordinates"]
		if submit_index < coordinates.size():
			return {"id": id, "coordinate": coordinates[submit_index], "index": submit_index}
	return {}


func _stage_priority(purpose: String) -> int:
	if purpose == "edit_transaction":
		return 0
	if purpose == "partial":
		return 1
	if purpose == "full":
		return 2
	return 3


func _complete_region_stage(id: String) -> void:
	if not loading_regions.has(id):
		return
	var stage: Dictionary = loading_regions[id]
	if int(stage["next_index"]) < (stage["chunk_coordinates"] as Array).size():
		return
	if not _stage_lod_selection_is_current(stage):
		_supersede_region_stage(id)
		return
	if global_rebuild_pending or stage["purpose"] == "full":
		_try_commit_global_rebuild()
		return
	if stage["purpose"] == "edit_transaction":
		_try_commit_edit_transaction()
		return
	loading_regions.erase(id)
	if stage["purpose"] == "partial":
		if _publish_partial_stage(id, stage):
			_clear_stream_error(id)
	else:
		_publish_region(
			stage["region_key"],
			stage["world_state"],
			stage["meshes"],
			stage.get("actual_lod_by_coordinate", {}),
			stage.get("fallback_by_coordinate", {}),
			int(stage["stage_token"]),
			stage.get("vertex_count_by_coordinate", {}),
			stage.get("triangle_count_by_coordinate", {})
		)
		_streamed_region_loads += 1
		_stage_retry_counts.erase(id)
		_clear_stream_error(id)
		if _operation_name == "initial_load" and loading_regions.is_empty():
			print("TERRAIN_STREAM_WINDOW_READY: focus=%s active_regions=%d active_chunks=%d queued_chunks=0 peak_queue=%d peak_mesh_upload_ms=%.3f" % [
				focus_region_key, active_regions.size(), chunk_nodes.size(), _peak_queue_depth, _peak_mesh_upload_ms,
			])
	_sync_world_state_index()
	_record_completed_operation(stage)
	_update_runtime_diagnostics()


func _publish_partial_stage(id: String, stage: Dictionary) -> bool:
	if not active_regions.has(id):
		return false
	var entry: Dictionary = active_regions[id]
	var region_nodes: Dictionary = entry["chunk_nodes"]
	for coordinate in stage["chunk_coordinates"]:
		var chunk_id: String = ChunkGrid.stable_id(stage["region_key"], coordinate)
		if not region_nodes.has(chunk_id) or not stage["meshes"].has(coordinate):
			_fail_region_stage(id, "Partial remesh was incomplete; old visible meshes retained")
			return false
	for coordinate in stage["chunk_coordinates"]:
		var chunk_id: String = ChunkGrid.stable_id(stage["region_key"], coordinate)
		var node: MeshInstance3D = region_nodes[chunk_id]
		_replace_node_mesh(
			node,
			stage["meshes"][coordinate],
			int(stage.get("vertex_count_by_coordinate", {}).get(coordinate, -1)),
			int(stage.get("triangle_count_by_coordinate", {}).get(coordinate, -1))
		)
		_set_chunk_lod_state(chunk_id, node, int(stage.get("actual_lod_by_coordinate", {}).get(coordinate, 0)), bool(stage.get("fallback_by_coordinate", {}).get(coordinate, false)))
	_record_completed_operation(stage)
	_lod_selection_dirty = true
	if stage["region_key"] == focus_region_key:
		_invalidate_placement_target_after_terrain_change()
	_update_runtime_diagnostics()
	return true


func _try_commit_global_rebuild() -> void:
	if not global_rebuild_pending:
		return
	for id in _full_rebuild_target_ids:
		if not loading_regions.has(id):
			return
		var stage: Dictionary = loading_regions[id]
		if int(stage["next_index"]) < (stage["chunk_coordinates"] as Array).size():
			return
		if not _stage_lod_selection_is_current(stage):
			_supersede_region_stage(id)
			return
	var all_stages: Array[Dictionary] = []
	for id in _full_rebuild_target_ids:
		all_stages.append(loading_regions[id])
	if not _pending_world_load.is_empty():
		var pending_load: Dictionary = _pending_world_load.duplicate(true)
		world_seed = int(pending_load["world_seed"])
		edit_ledger = pending_load["ledger"]
		_persistence_blocked = false
		_checkpoint_generation = int(pending_load["generation"]) if _scalable_runtime_enabled else _checkpoint_generation
		_persistence_status = "Loaded generation %d (%d ordered edit(s))" % [
			int(pending_load["generation"]), edit_ledger.get_edit_count(),
		]
		if not _apply_pending_simulation_candidate(pending_load):
			_persistence_blocked = true
			_persistence_status += "; simulation restore blocked"
		_pending_world_load = {}
	global_rebuild_pending = false
	global_rebuild_reason = ""
	_global_rebuild_retry_count = 0
	for id in _full_rebuild_target_ids:
		_clear_stream_error(id)
	_full_rebuild_target_ids.clear()
	loading_regions.clear()
	_edit_transaction = {}
	var publish_started_usec := Time.get_ticks_usec()
	for stage in all_stages:
		_publish_region(
			stage["region_key"],
			stage["world_state"],
			stage["meshes"],
			stage.get("actual_lod_by_coordinate", {}),
			stage.get("fallback_by_coordinate", {}),
			int(stage["stage_token"]),
			stage.get("vertex_count_by_coordinate", {}),
			stage.get("triangle_count_by_coordinate", {})
		)
	_mesh_publish_usec_samples.append(Time.get_ticks_usec() - publish_started_usec)
	_rendered_cave_section_enabled = cave_section_enabled
	_streamed_region_loads += all_stages.size()
	_sync_world_state_index()
	_record_completed_operation({
		"region_key": focus_region_key,
		"world_state": world_state,
		"purpose": "full",
		"sample_count": _operation_sample_count,
		"triangle_count": 0,
	})
	_update_runtime_diagnostics()


func _publish_region(
	region_key: Vector2i,
	state: RefCounted,
	meshes: Dictionary,
	actual_lods: Dictionary = {},
	fallback_lods: Dictionary = {},
	publication_token: int = -1,
	vertex_counts: Dictionary = {},
	triangle_counts: Dictionary = {}
) -> void:
	var publish_started_usec := Time.get_ticks_usec()
	var id := _region_id(region_key)
	var region_nodes: Dictionary = {}
	var region_origin: Vector3 = SpatialGrid.region_origin_world(region_key)
	var created_node_count := 0
	var reused_node_count := 0
	var released_node_count := 0
	var chunk_commit_started_usec := Time.get_ticks_usec()
	var node_resolve_usec := 0
	var transform_usec := 0
	var mesh_replace_usec := 0
	var metadata_usec := 0
	var lod_state_usec := 0
	var index_commit_usec := 0
	var slowest_mesh_replace_usec := 0
	var slowest_node_resolve_usec := 0
	for coordinate in ChunkGrid.all_coordinates():
		if not meshes.has(coordinate):
			continue
		var chunk_id: String = state.chunk_id(coordinate)
		var node_resolve_started_usec := Time.get_ticks_usec()
		var node: MeshInstance3D
		if active_regions.has(id) and active_regions[id]["chunk_nodes"].has(chunk_id):
			node = active_regions[id]["chunk_nodes"][chunk_id]
			reused_node_count += 1
		else:
			node = _create_chunk_node(region_key, coordinate, chunk_id)
			created_node_count += 1
		var node_resolve_elapsed_usec := Time.get_ticks_usec() - node_resolve_started_usec
		node_resolve_usec += node_resolve_elapsed_usec
		slowest_node_resolve_usec = maxi(slowest_node_resolve_usec, node_resolve_elapsed_usec)

		var transform_started_usec := Time.get_ticks_usec()
		node.position = region_origin + ChunkGrid.origin_for(coordinate)
		transform_usec += Time.get_ticks_usec() - transform_started_usec

		var mesh_replace_started_usec := Time.get_ticks_usec()
		_replace_node_mesh(
			node,
			meshes[coordinate],
			int(vertex_counts.get(coordinate, -1)),
			int(triangle_counts.get(coordinate, -1))
		)
		var mesh_replace_elapsed_usec := Time.get_ticks_usec() - mesh_replace_started_usec
		mesh_replace_usec += mesh_replace_elapsed_usec
		slowest_mesh_replace_usec = maxi(slowest_mesh_replace_usec, mesh_replace_elapsed_usec)

		var metadata_started_usec := Time.get_ticks_usec()
		node.visible = true
		node.set_meta("stable_chunk_id", chunk_id)
		node.set_meta("region_key", region_key)
		node.set_meta("chunk_coordinate", coordinate)
		metadata_usec += Time.get_ticks_usec() - metadata_started_usec

		var lod_started_usec := Time.get_ticks_usec()
		_set_chunk_lod_state(
			chunk_id,
			node,
			int(actual_lods.get(coordinate, 0)),
			bool(fallback_lods.get(coordinate, false))
		)
		lod_state_usec += Time.get_ticks_usec() - lod_started_usec

		var index_started_usec := Time.get_ticks_usec()
		region_nodes[chunk_id] = node
		chunk_nodes[chunk_id] = node
		index_commit_usec += Time.get_ticks_usec() - index_started_usec
	var chunk_commit_usec := Time.get_ticks_usec() - chunk_commit_started_usec

	var stale_release_started_usec := Time.get_ticks_usec()
	var previous: Dictionary = active_regions.get(id, {})
	for old_id in previous.get("chunk_nodes", {}):
		if not region_nodes.has(old_id):
			released_node_count += 1
			_release_chunk_node(old_id, previous["chunk_nodes"][old_id])
	var stale_release_usec := Time.get_ticks_usec() - stale_release_started_usec

	var registry_started_usec := Time.get_ticks_usec()
	active_regions[id] = {"region_key": region_key, "world_state": state, "chunk_nodes": region_nodes}
	world_states[id] = state
	_lod_selection_dirty = true
	var registry_commit_usec := Time.get_ticks_usec() - registry_started_usec

	if (
		is_instance_valid(simulation_runtime)
		and bool(simulation_runtime.get_world_scope_lifecycle_metrics().get("initialized", false))
	):
		var simulation_publication: Dictionary = simulation_runtime.publish_world_region_scope(
			region_key, 0
		)
		if not simulation_publication.get("ok", false):
			_simulation_streaming_status = "Simulation publication issue: %s" % simulation_publication.get("reason", "unknown")

	var object_enqueue_started_usec := Time.get_ticks_usec()
	var object_publication: Dictionary = object_stream.enqueue_region_publication(
		region_key, state, publication_token
	)
	var object_enqueue_usec := Time.get_ticks_usec() - object_enqueue_started_usec

	var object_status_started_usec := Time.get_ticks_usec()
	if (
		not object_publication.get("ok", false)
		and object_publication.get("reason") != "stale_object_region_publication"
	):
		_procedural_object_status = "Procedural object issue: %s" % object_stream.get_error_summary()
	else:
		var object_error: String = object_stream.get_error_summary()
		_procedural_object_status = (
			"Procedural objects queued"
			if object_error.is_empty()
			else "Procedural object issue: %s" % object_error
		)
	var object_status_usec := Time.get_ticks_usec() - object_status_started_usec

	var focus_refresh_usec := 0
	var placement_invalidate_usec := 0
	var focused_region := region_key == focus_region_key
	if focused_region:
		world_state = state
		var placement_invalidate_started_usec := Time.get_ticks_usec()
		_invalidate_placement_target_after_terrain_change()
		placement_invalidate_usec = Time.get_ticks_usec() - placement_invalidate_started_usec

	var publish_duration_usec := Time.get_ticks_usec() - publish_started_usec
	var measured_top_level_usec := (
		chunk_commit_usec
		+ stale_release_usec
		+ registry_commit_usec
		+ object_enqueue_usec
		+ object_status_usec
		+ placement_invalidate_usec
	)
	var chunk_measured_usec := (
		node_resolve_usec
		+ transform_usec
		+ mesh_replace_usec
		+ metadata_usec
		+ lod_state_usec
		+ index_commit_usec
	)
	_last_region_publish_profile = {
		"region": [region_key.x, region_key.y],
		"focused_region": focused_region,
		"duration_usec": publish_duration_usec,
		"mesh_count": meshes.size(),
		"created_node_count": created_node_count,
		"reused_node_count": reused_node_count,
		"released_node_count": released_node_count,
		"placement_target_dirty_after_publish": _placement_target_dirty,
		"placement_target_invalidation_count": _placement_target_invalidation_count,
		"timings_usec": {
			"chunk_commit": chunk_commit_usec,
			"stale_release": stale_release_usec,
			"registry_commit": registry_commit_usec,
			"object_enqueue": object_enqueue_usec,
			"object_status": object_status_usec,
			"focus_refresh": focus_refresh_usec,
			"placement_invalidate": placement_invalidate_usec,
			"top_level_unaccounted": maxi(0, publish_duration_usec - measured_top_level_usec),
		},
		"chunk_timings_usec": {
			"node_resolve": node_resolve_usec,
			"transform": transform_usec,
			"mesh_replace": mesh_replace_usec,
			"metadata": metadata_usec,
			"lod_state": lod_state_usec,
			"index_commit": index_commit_usec,
			"chunk_unaccounted": maxi(0, chunk_commit_usec - chunk_measured_usec),
			"slowest_mesh_replace": slowest_mesh_replace_usec,
			"slowest_node_resolve": slowest_node_resolve_usec,
		},
	}
	if _perf_trace_enabled and publish_duration_usec >= PerformanceTrace.min_usec():
		PerformanceTrace.emit("terrain_region_publish_detail", _last_region_publish_profile)
		PerformanceTrace.emit("terrain_region_publish", {
			"duration_usec": publish_duration_usec,
			"region": [region_key.x, region_key.y],
			"mesh_count": meshes.size(),
			"active_region_count": active_regions.size(),
			"active_chunk_count": chunk_nodes.size(),
			"object_publication_pending": int(
				object_stream.get_performance_snapshot().get(
					"pending_region_publication_count", 0
				)
			),
		})

func _create_chunk_node(region_key: Vector2i, coordinate: Vector2i, chunk_id: String) -> MeshInstance3D:
	if region_key == Vector2i.ZERO and coordinate == Vector2i.ZERO:
		return terrain_mesh_template
	var node := MeshInstance3D.new()
	node.name = "Region_%d_%d_Chunk_%d_%d" % [region_key.x, region_key.y, coordinate.x, coordinate.y]
	node.material_override = terrain_mesh_template.material_override
	terrain_chunks_root.add_child(node)
	return node


func _release_chunk_node(chunk_id: String, node: MeshInstance3D) -> void:
	chunk_nodes.erase(chunk_id)
	_published_lod_by_chunk.erase(chunk_id)
	_lod_fallback_chunks.erase(chunk_id)
	_replace_node_mesh(node, null)
	if node == terrain_mesh_template:
		node.visible = false
		return
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.free()


func _replace_node_mesh(
	node: MeshInstance3D,
	replacement: Mesh,
	replacement_vertex_count: int = -1,
	replacement_triangle_count: int = -1
) -> void:
	var previous := node.mesh
	var previous_triangle_count := int(node.get_meta("mesh_triangle_count", -1))
	var previous_vertex_count := int(node.get_meta("mesh_vertex_count", -1))
	if previous_triangle_count < 0:
		previous_triangle_count = _mesh_triangle_count(previous)
	if previous_vertex_count < 0:
		previous_vertex_count = _mesh_vertex_count(previous)
	var next_triangle_count := replacement_triangle_count
	var next_vertex_count := replacement_vertex_count
	if next_triangle_count < 0:
		next_triangle_count = _mesh_triangle_count(replacement)
	if next_vertex_count < 0:
		next_vertex_count = _mesh_vertex_count(replacement)
	_active_triangle_count -= previous_triangle_count
	_active_vertex_count -= previous_vertex_count
	node.mesh = replacement
	_active_triangle_count += next_triangle_count
	_active_vertex_count += next_vertex_count
	node.set_meta("mesh_triangle_count", next_triangle_count)
	node.set_meta("mesh_vertex_count", next_vertex_count)


func _set_chunk_lod_state(chunk_id: String, node: MeshInstance3D, lod_level: int, did_fallback: bool) -> void:
	var actual_lod := clampi(lod_level, 0, 1)
	_published_lod_by_chunk[chunk_id] = actual_lod
	node.set_meta("lod_level", actual_lod)
	if did_fallback:
		_lod_fallback_chunks[chunk_id] = true
	else:
		_lod_fallback_chunks.erase(chunk_id)


func _stage_lod_selection_is_current(stage: Dictionary) -> bool:
	var lods: Dictionary = stage.get("lod_by_coordinate", {})
	for coordinate in stage.get("chunk_coordinates", []):
		var chunk_id: String = ChunkGrid.stable_id(stage["region_key"], coordinate)
		var current_lod := int(_published_lod_by_chunk.get(chunk_id, 0))
		if int(lods.get(coordinate, 0)) != _desired_lod_for_chunk(stage["region_key"], coordinate, current_lod):
			return false
	return true


func _mesh_triangle_count(mesh: Mesh) -> int:
	if mesh == null or mesh.get_surface_count() == 0:
		return 0
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	return vertices.size() / 3


func _mesh_vertex_count(mesh: Mesh) -> int:
	if mesh == null or mesh.get_surface_count() == 0:
		return 0
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	return vertices.size()


func _unload_region(id: String) -> void:
	if not active_regions.has(id):
		return
	var entry: Dictionary = active_regions[id]
	if (
		is_instance_valid(simulation_runtime)
		and bool(simulation_runtime.get_world_scope_lifecycle_metrics().get("initialized", false))
	):
		var simulation_unload: Dictionary = simulation_runtime.unload_world_region_scope(
			entry["region_key"]
		)
		if not simulation_unload.get("ok", false):
			_simulation_streaming_status = "Simulation unload issue: %s" % simulation_unload.get("reason", "unknown")
	object_stream.unload_region(entry["region_key"])
	if _edit_transaction.has("target_ids") and (_edit_transaction["target_ids"] as Array).has(id):
		_edit_transaction["target_ids"].erase(id)
		loading_regions.erase(id)
	for chunk_id in entry["chunk_nodes"]:
		_release_chunk_node(chunk_id, entry["chunk_nodes"][chunk_id])
	active_regions.erase(id)
	world_states.erase(id)
	_streamed_region_unloads += 1


func _supersede_region_stage(id: String) -> void:
	if not loading_regions.has(id):
		return
	var stale_stage: Dictionary = loading_regions[id]
	loading_regions.erase(id)
	_superseded_stage_total += 1
	var region_key: Vector2i = stale_stage["region_key"]
	var purpose: String = stale_stage["purpose"]
	if not _edit_transaction.is_empty() \
		and int(_edit_transaction.get("revision", -1)) == edit_ledger.revision \
		and (_edit_transaction.get("target_ids", []) as Array).has(id):
		_start_edit_transaction_attempt()
	elif global_rebuild_pending:
		# Every full-rebuild snapshot is revision-pinned. Replace the complete staged
		# set together so no mixture of revisions can be published.
		loading_regions.clear()
		_full_rebuild_target_ids.clear()
		var desired := _region_keys_within_radius(focus_region_key, REQUEST_RADIUS)
		var retained: Dictionary = {}
		for key in _region_keys_within_radius(focus_region_key, UNLOAD_RADIUS):
			retained[_region_id(key)] = true
		_ensure_full_rebuild_targets(desired, retained)
	elif purpose == "load":
		var desired := _region_keys_within_radius(focus_region_key, REQUEST_RADIUS)
		if not active_regions.has(id) and _contains_region(desired, region_key):
			_begin_region_stage(region_key, "load", ChunkGrid.all_coordinates())
	elif purpose == "partial":
		if active_regions.has(id):
			_begin_region_stage(region_key, "partial", stale_stage["chunk_coordinates"])
	_sync_world_state_index()
	_update_runtime_diagnostics()
	_update_status()


func _record_stream_error(id: String, message: String) -> void:
	var error_key := id if id != "" else "_global"
	_stream_errors_by_region[error_key] = message
	last_stream_error = message


func _clear_stream_error(id: String) -> void:
	_stream_errors_by_region.erase(id)
	if _stream_errors_by_region.is_empty():
		last_stream_error = ""
	else:
		var keys: Array = _stream_errors_by_region.keys()
		keys.sort()
		last_stream_error = String(_stream_errors_by_region[keys[-1]])


func _fail_region_stage(id: String, message: String) -> void:
	_record_stream_error(id, message)
	var failed_stage: Dictionary = loading_regions.get(id, {})
	loading_regions.erase(id)
	if not _edit_transaction.is_empty() and (_edit_transaction["target_ids"] as Array).has(id):
		_retry_edit_transaction(message)
		_sync_world_state_index()
		_update_runtime_diagnostics()
		_update_status()
		return
	if global_rebuild_pending:
		_global_rebuild_retry_count += 1
		if _global_rebuild_retry_count <= MAX_STAGE_RETRIES:
			last_stream_error = "%s; full rebuild retry %d/%d" % [message, _global_rebuild_retry_count, MAX_STAGE_RETRIES]
			_stream_errors_by_region[id if id != "" else "_global"] = last_stream_error
			loading_regions.clear()
			for target_id in _full_rebuild_target_ids:
				_begin_region_stage(_region_key_from_id(target_id), "full", ChunkGrid.all_coordinates())
		else:
			loading_regions.clear()
			global_rebuild_pending = false
			global_rebuild_reason = ""
			_full_rebuild_target_ids.clear()
			if not _pending_world_load.is_empty():
				_pending_world_load = {}
				_persistence_status = "World load rebuild failed; previous world and meshes retained"
			cave_section_enabled = _rendered_cave_section_enabled
			last_mesh_diagnostics["operation"] = "failed_pending_retry"
			last_brush_result = "%s; visible mesh set retained, press R to retry" % message
	elif id != "" and not active_regions.has(id) and failed_stage.get("purpose", "") == "load":
		var retries := int(_stage_retry_counts.get(id, 0)) + 1
		_stage_retry_counts[id] = retries
		_mesh_stage_retry_total += 1
		var key: Vector2i = failed_stage.get("region_key", Vector2i.ZERO)
		if retries <= MAX_STAGE_RETRIES and _contains_region(_region_keys_within_radius(focus_region_key, REQUEST_RADIUS), key):
			_begin_region_stage(key, "load", ChunkGrid.all_coordinates())
		else:
			last_stream_error = "%s; load retry limit reached, move focus away and back or press R" % message
			_stream_errors_by_region[id] = last_stream_error
	_sync_world_state_index()
	_update_runtime_diagnostics()
	_update_status()


func _record_completed_operation(stage: Dictionary) -> void:
	var queue_waits := _queue_wait_percentiles_ms()
	last_mesh_diagnostics = {
		"operation": _operation_name,
		"focus_region_key": focus_region_key,
		"active_region_count": active_regions.size(),
		"preview_region_count": active_regions.size(),
		"active_chunk_count": chunk_nodes.size(),
		"remeshed_chunk_count": _operation_chunk_ids.size(),
		"remeshed_chunk_ids": _operation_chunk_ids.duplicate(),
		"sample_count": _operation_sample_count,
		"triangle_count": _active_triangle_count,
		"total_triangle_count": _active_triangle_count,
		"mesh_vertex_attribute_bytes_estimate": _get_mesh_attribute_bytes_estimate(),
		"elapsed_ms": float(Time.get_ticks_usec() - _operation_started_usec) / 1000.0 if _operation_started_usec > 0 else 0.0,
		"total_mesh_work_ms": _operation_total_mesh_work_ms,
		"mesh_queue_wait_p50_ms": queue_waits.x,
		"mesh_queue_wait_p95_ms": queue_waits.y,
		"mesh_queue_wait_total_ms": _sum_usec(_mesh_queue_wait_usec_samples) / 1000.0,
		"worker_queue_wait_p50_ms": _percentile_usec(_pool_queue_wait_usec_samples, 0.50),
		"worker_queue_wait_p95_ms": _percentile_usec(_pool_queue_wait_usec_samples, 0.95),
		"array_mesh_upload_p50_ms": _percentile_usec(_mesh_upload_usec_samples, 0.50),
		"mesh_publish_p95_ms": _percentile_usec(_mesh_publish_usec_samples, 0.95),
		"stage_timings_ms": _stage_timings_ms(),
		"peak_mesh_upload_ms": _peak_mesh_upload_ms,
		"max_active_region_count": _peak_active_region_count,
		"max_queue_depth": _peak_queue_depth,
		"operation_region_key": stage.get("region_key", focus_region_key),
		"global_edit_count": edit_ledger.get_edit_count(),
		"peak_mesh_jobs_in_flight": _peak_mesh_jobs_in_flight,
		"global_edit_last_sequence": edit_ledger.get_last_sequence(),
		"global_edit_revision": edit_ledger.revision,
		"last_support_region_count": _last_edit_support_region_count,
		"last_rebuild_region_count": _last_edit_rebuild_region_count,
		"last_rebuild_chunk_count": _last_edit_rebuild_chunk_count,
		"last_dirty_mesh_job_count": _last_edit_mesh_jobs,
		"edit_stage_state": "idle" if _edit_transaction.is_empty() else _edit_transaction.get("stage_state", "staging"),
		"last_edit_rejection": _last_edit_rejection,
		"last_shared_boundary_diagnostics": _last_shared_boundary_diagnostics.duplicate(true),
		"last_shared_x_boundary_diagnostics": _last_shared_x_boundary_diagnostics.duplicate(true),
		"last_shared_z_boundary_diagnostics": _last_shared_z_boundary_diagnostics.duplicate(true),
		"last_shared_corner_diagnostics": _last_shared_corner_diagnostics.duplicate(true),
	}


func _start_global_rebuild(operation_name: String) -> void:
	if operation_name != "load_world":
		_pending_world_load = {}
	_begin_operation(operation_name)
	_global_rebuild_retry_count = 0
	_edit_transaction = {}
	global_rebuild_pending = true
	global_rebuild_reason = operation_name
	loading_regions.clear()
	_full_rebuild_target_ids.clear()
	var desired := _region_keys_within_radius(focus_region_key, REQUEST_RADIUS)
	var targets: Array[Vector2i] = []
	for entry in active_regions.values():
		var key: Vector2i = entry["region_key"]
		if not targets.has(key):
			targets.append(key)
	for key in desired:
		if not targets.has(key):
			targets.append(key)
	targets.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := maxi(absi(a.x - focus_region_key.x), absi(a.y - focus_region_key.y))
		var db := maxi(absi(b.x - focus_region_key.x), absi(b.y - focus_region_key.y))
		if da == db:
			if a.y == b.y:
				return a.x < b.x
			return a.y < b.y
		return da < db
	)
	for key in targets:
		var id := _region_id(key)
		_full_rebuild_target_ids.append(id)
		_begin_region_stage(key, "full", ChunkGrid.all_coordinates())
	_sync_world_state_index()
	_update_runtime_diagnostics()


func _schedule_edit_transaction(operation: Dictionary) -> void:
	var operations: Array[Dictionary] = [operation]
	_schedule_edit_transaction_batch(operations)


func _schedule_edit_transaction_batch(operations: Array[Dictionary]) -> void:
	if operations.is_empty():
		return
	var schedule_started_usec := Time.get_ticks_usec()
	_begin_operation("global_brush_edit")
	var support_regions_by_id: Dictionary = {}
	var rebuild_regions_by_id: Dictionary = {}
	var target_builders: Dictionary = {}
	_last_edit_rejection = ""
	for operation in operations:
		for support_region_value in operation["support_regions"]:
			var support_region: Vector2i = support_region_value
			support_regions_by_id[_region_id(support_region)] = support_region
		for rebuild_region_value in operation["rebuild_regions"]:
			var region_key: Vector2i = rebuild_region_value
			var id := _region_id(region_key)
			rebuild_regions_by_id[id] = region_key
			if not active_regions.has(id) and not loading_regions.has(id):
				continue
			var local_center := Vector3(
				(operation["center_world"] as Vector3).x - float(region_key.x) * SpatialGrid.REGION_SIZE_X,
				(operation["center_world"] as Vector3).y,
				(operation["center_world"] as Vector3).z - float(region_key.y) * SpatialGrid.REGION_SIZE_Z
			)
			var needs_full_stage := not active_regions.has(id)
			var chunks: Array[Vector2i] = ChunkGrid.all_coordinates() if needs_full_stage else ChunkGrid.affected_chunks_for_sphere(
				local_center, float(operation["radius"])
			)
			if chunks.is_empty():
				continue
			if not target_builders.has(id):
				target_builders[id] = {
					"region_key": region_key,
					"id": id,
					"full": needs_full_stage,
					"chunk_set": {},
				}
			var builder: Dictionary = target_builders[id]
			if needs_full_stage:
				builder["full"] = true
				builder["chunk_set"] = {}
				for coordinate in ChunkGrid.all_coordinates():
					(builder["chunk_set"] as Dictionary)[coordinate] = true
			elif not bool(builder["full"]):
				for coordinate in chunks:
					(builder["chunk_set"] as Dictionary)[coordinate] = true
			target_builders[id] = builder

	var target_ids_ordered: Array[String] = []
	for id_value in target_builders.keys():
		target_ids_ordered.append(String(id_value))
	target_ids_ordered.sort()
	var targets: Array[Dictionary] = []
	_last_edit_rebuild_chunk_count = 0
	for id in target_ids_ordered:
		var builder: Dictionary = target_builders[id]
		var chunks: Array[Vector2i] = []
		for coordinate in ChunkGrid.all_coordinates():
			if (builder["chunk_set"] as Dictionary).has(coordinate):
				chunks.append(coordinate)
		if chunks.is_empty():
			continue
		targets.append({
			"region_key": builder["region_key"],
			"id": id,
			"chunks": chunks,
			"full": bool(builder["full"]),
		})
		_last_edit_rebuild_chunk_count += chunks.size()

	var rebuild_region_ids: Array[String] = []
	for id_value in rebuild_regions_by_id.keys():
		rebuild_region_ids.append(String(id_value))
	rebuild_region_ids.sort()
	var rebuild_regions: Array[Vector2i] = []
	for id in rebuild_region_ids:
		rebuild_regions.append(rebuild_regions_by_id[id])

	_last_edit_support_region_count = support_regions_by_id.size()
	_last_edit_rebuild_region_count = rebuild_regions.size()
	if targets.is_empty():
		_edit_transaction = {}
		last_brush_result += "; no rebuild-dependent region is resident, future loads will replay it"
		_record_completed_operation({"region_key": focus_region_key, "purpose": "global_brush_edit"})
		_flush_buffered_brush_requests()
		return

	var first_sequence := int(operations[0]["sequence"])
	var last_sequence := int(operations[-1]["sequence"])
	_edit_transaction = {
		"revision": edit_ledger.revision,
		"operation_sequence": last_sequence,
		"operation_sequence_start": first_sequence,
		"operation_count": operations.size(),
		"rebuild_regions": rebuild_regions,
		"target_ids": [],
		"targets": targets,
		"retries": 0,
		"stage_state": "staging",
		"support_region_count": support_regions_by_id.size(),
		"rebuild_region_count": rebuild_regions.size(),
		"rebuild_chunk_count": 0,
		"mesh_job_count": 0,
		"trace_started_usec": schedule_started_usec,
		"trace_snapshot_usec_total": 0,
		"trace_snapshot_usec_max": 0,
		"trace_worker_queue_usec_max": 0,
		"trace_worker_run_usec_max": 0,
		"trace_upload_usec_total": 0,
		"trace_upload_usec_max": 0,
	}
	_edit_trace("schedule", {
		"sequence_start": first_sequence,
		"sequence_end": last_sequence,
		"revision": int(edit_ledger.revision),
		"operation_count": operations.size(),
		"target_regions": targets.size(),
		"rebuild_regions": rebuild_regions.size(),
		"rebuild_chunks": _last_edit_rebuild_chunk_count,
		"schedule_ms": float(Time.get_ticks_usec() - schedule_started_usec) / 1000.0,
	})
	_start_edit_transaction_attempt()
	_update_runtime_diagnostics()


func _start_edit_transaction_attempt() -> void:
	if _edit_transaction.is_empty():
		return
	var target_ids: Array[String] = []
	for target in _edit_transaction["targets"]:
		var id: String = target["id"]
		if not active_regions.has(id) and not loading_regions.has(id):
			continue
		var region_key: Vector2i = target["region_key"]
		var chunks: Array[Vector2i] = target["chunks"]
		if not active_regions.has(id):
			chunks = ChunkGrid.all_coordinates()
		loading_regions.erase(id)
		_begin_region_stage(region_key, "edit_transaction", chunks)
		target_ids.append(id)
	_edit_transaction["target_ids"] = target_ids
	_edit_transaction["stage_state"] = "staging"
	_edit_transaction["rebuild_chunk_count"] = 0
	_edit_transaction["mesh_job_count"] = 0
	for target in _edit_transaction["targets"]:
		if target_ids.has(target["id"]):
			_edit_transaction["rebuild_chunk_count"] += target["chunks"].size()
	if target_ids.is_empty():
		_finish_edit_transaction("accepted; unloaded rebuild dependencies will apply it on load")


func _try_commit_edit_transaction() -> void:
	if _edit_transaction.is_empty() or int(_edit_transaction["revision"]) != edit_ledger.revision:
		return
	var target_ids: Array[String] = _edit_transaction["target_ids"]
	for id in target_ids:
		if not loading_regions.has(id):
			return
		var stage: Dictionary = loading_regions[id]
		if stage["purpose"] != "edit_transaction" \
			or int(stage["edit_revision"]) != edit_ledger.revision \
			or int(stage["next_index"]) < (stage["chunk_coordinates"] as Array).size():
			return
		if not _stage_lod_selection_is_current(stage):
			_supersede_region_stage(id)
			return
		for coordinate in stage["chunk_coordinates"]:
			if not stage["meshes"].has(coordinate):
				_fail_region_stage(id, "Edit transaction mesh set is incomplete; previous meshes retained")
				return
		if active_regions.has(id):
			var nodes: Dictionary = active_regions[id]["chunk_nodes"]
			for coordinate in stage["chunk_coordinates"]:
				if not nodes.has(ChunkGrid.stable_id(stage["region_key"], coordinate)):
					_fail_region_stage(id, "Edit transaction lost a visible chunk target; previous meshes retained")
					return
	# All targets and meshes validate before the first visible assignment.
	_edit_transaction["stage_state"] = "committing"
	var publish_started_usec := Time.get_ticks_usec()
	for id in target_ids:
		var stage: Dictionary = loading_regions[id]
		if active_regions.has(id):
			var nodes: Dictionary = active_regions[id]["chunk_nodes"]
			for coordinate in stage["chunk_coordinates"]:
				var chunk_id: String = ChunkGrid.stable_id(stage["region_key"], coordinate)
				_replace_node_mesh(
					nodes[chunk_id],
					stage["meshes"][coordinate],
					int(stage.get("vertex_count_by_coordinate", {}).get(coordinate, -1)),
					int(stage.get("triangle_count_by_coordinate", {}).get(coordinate, -1))
				)
				_set_chunk_lod_state(chunk_id, nodes[chunk_id], int(stage.get("actual_lod_by_coordinate", {}).get(coordinate, 0)), bool(stage.get("fallback_by_coordinate", {}).get(coordinate, false)))
		else:
			_publish_region(
				stage["region_key"],
				stage["world_state"],
				stage["meshes"],
				stage.get("actual_lod_by_coordinate", {}),
				stage.get("fallback_by_coordinate", {}),
				int(stage["stage_token"]),
				stage.get("vertex_count_by_coordinate", {}),
				stage.get("triangle_count_by_coordinate", {})
			)
		loading_regions.erase(id)
	_mesh_publish_usec_samples.append(Time.get_ticks_usec() - publish_started_usec)
	var committed_sequence: int = _edit_transaction["operation_sequence"]
	var committed_sequence_start := int(_edit_transaction.get("operation_sequence_start", committed_sequence))
	var committed_operation_count := int(_edit_transaction.get("operation_count", 1))
	var committed_regions: int = target_ids.size()
	for id in target_ids:
		_clear_stream_error(id)
	_last_edit_mesh_jobs = int(_edit_transaction.get("mesh_job_count", 0))
	var trace_transaction_usec := Time.get_ticks_usec() - int(_edit_transaction.get("trace_started_usec", Time.get_ticks_usec()))
	var trace_summary := {
		"sequence_start": committed_sequence_start,
		"sequence_end": committed_sequence,
		"revision": int(_edit_transaction.get("revision", -1)),
		"operation_count": committed_operation_count,
		"resident_regions": committed_regions,
		"mesh_jobs": _last_edit_mesh_jobs,
		"transaction_ms": float(trace_transaction_usec) / 1000.0,
		"snapshot_total_ms": float(_edit_transaction.get("trace_snapshot_usec_total", 0)) / 1000.0,
		"snapshot_max_ms": float(_edit_transaction.get("trace_snapshot_usec_max", 0)) / 1000.0,
		"worker_queue_max_ms": float(_edit_transaction.get("trace_worker_queue_usec_max", 0)) / 1000.0,
		"worker_run_max_ms": float(_edit_transaction.get("trace_worker_run_usec_max", 0)) / 1000.0,
		"upload_total_ms": float(_edit_transaction.get("trace_upload_usec_total", 0)) / 1000.0,
		"upload_max_ms": float(_edit_transaction.get("trace_upload_usec_max", 0)) / 1000.0,
		"publish_ms": float(Time.get_ticks_usec() - publish_started_usec) / 1000.0,
	}
	_edit_trace("commit", trace_summary)
	_edit_transaction = {}
	if committed_operation_count > 1:
		last_brush_result = "Global edits #%d-#%d coalesced mesh commit complete across %d resident region(s)" % [
			committed_sequence_start, committed_sequence, committed_regions,
		]
	else:
		last_brush_result = "Global edit #%d mesh commit complete across %d resident region(s)" % [committed_sequence, committed_regions]
	_record_completed_operation({"region_key": focus_region_key, "purpose": "global_brush_edit"})
	_sync_world_state_index()
	_update_runtime_diagnostics()
	_flush_buffered_brush_requests()


func _finish_edit_transaction(message: String) -> void:
	if _edit_transaction.is_empty():
		return
	var sequence: int = _edit_transaction["operation_sequence"]
	_edit_transaction = {}
	last_brush_result = "Global edit #%d %s" % [sequence, message]
	_record_completed_operation({"region_key": focus_region_key, "purpose": "global_brush_edit"})
	_sync_world_state_index()
	_update_runtime_diagnostics()
	_flush_buffered_brush_requests()


func _retry_edit_transaction(failure_message: String) -> void:
	if _edit_transaction.is_empty():
		return
	_edit_transaction["retries"] = int(_edit_transaction["retries"]) + 1
	_mesh_stage_retry_total += 1
	if int(_edit_transaction["retries"]) <= MAX_STAGE_RETRIES:
		last_stream_error = "%s; retry %d/%d" % [failure_message, _edit_transaction["retries"], MAX_STAGE_RETRIES]
		for id in _edit_transaction["target_ids"]:
			_stream_errors_by_region[id] = last_stream_error
		_start_edit_transaction_attempt()
		return
	var exhausted_target_ids: Array = (_edit_transaction["target_ids"] as Array).duplicate()
	for id_value in exhausted_target_ids:
		var id: String = id_value
		if loading_regions.has(id) and loading_regions[id]["purpose"] == "edit_transaction":
			loading_regions.erase(id)
	_edit_transaction["stage_state"] = "failed_pending_retry"
	_edit_transaction["target_ids"] = []
	last_stream_error = "%s; accepted edit retained, press R to retry mesh build" % failure_message
	for id_value in exhausted_target_ids:
		_stream_errors_by_region[String(id_value)] = last_stream_error
	last_brush_result = "Accepted edit remains in the global ledger; visible meshes retained until retry succeeds"
	_update_runtime_diagnostics()


func _begin_operation(operation_name: String) -> void:
	_operation_name = operation_name
	_operation_chunk_ids.clear()
	_operation_sample_count = 0
	_operation_total_mesh_work_ms = 0.0
	_operation_stage_timings_usec.clear()
	_mesh_queue_wait_usec_samples.clear()
	_pool_queue_wait_usec_samples.clear()
	_mesh_upload_usec_samples.clear()
	_mesh_publish_usec_samples.clear()
	_operation_started_usec = Time.get_ticks_usec()


func _stage_contributes_to_active_operation(stage: Dictionary) -> bool:
	var purpose := String(stage.get("purpose", ""))
	match _operation_name:
		"global_brush_edit":
			return purpose == "edit_transaction"
		"lod_transition":
			return purpose == "partial"
		"initial_load", "region_stream_load":
			return purpose == "load"
		_:
			return purpose == "full"


func _add_stage_timings(timings_usec: Dictionary) -> void:
	for key in timings_usec:
		_operation_stage_timings_usec[key] = int(_operation_stage_timings_usec.get(key, 0)) + int(timings_usec[key])


func _stage_timings_ms() -> Dictionary:
	var result: Dictionary = {}
	for key in _operation_stage_timings_usec:
		result[key] = float(_operation_stage_timings_usec[key]) / 1000.0
	return result


func _queue_wait_percentiles_ms() -> Vector2:
	if _mesh_queue_wait_usec_samples.is_empty():
		return Vector2.ZERO
	var samples := _mesh_queue_wait_usec_samples.duplicate()
	samples.sort()
	return Vector2(
		float(samples[maxi(0, ceili(float(samples.size()) * 0.50) - 1)]) / 1000.0,
		float(samples[maxi(0, ceili(float(samples.size()) * 0.95) - 1)]) / 1000.0
	)


func _percentile_usec(samples: Array[int], fraction: float) -> float:
	if samples.is_empty():
		return 0.0
	var sorted_samples := samples.duplicate()
	sorted_samples.sort()
	var index := clampi(ceili(float(sorted_samples.size()) * fraction) - 1, 0, sorted_samples.size() - 1)
	return float(sorted_samples[index]) / 1000.0


func _sum_usec(samples: Array[int]) -> int:
	var total := 0
	for sample in samples:
		total += sample
	return total


func _sync_world_state_index() -> void:
	world_states.clear()
	for id_value in active_regions:
		var id: String = id_value
		world_states[id] = active_regions[id]["world_state"]
	for id_value in loading_regions:
		var id: String = id_value
		world_states[id] = loading_regions[id]["world_state"]
	world_state = _state_for_region(focus_region_key)


func _state_for_region(region_key: Vector2i) -> RefCounted:
	var id := _region_id(region_key)
	if active_regions.has(id):
		return active_regions[id]["world_state"]
	if loading_regions.has(id):
		return loading_regions[id]["world_state"]
	if not _pending_world_load.is_empty():
		return WorldState.new(int(_pending_world_load["world_seed"]), region_key, _pending_world_load["ledger"])
	return WorldState.new(world_seed, region_key, edit_ledger)


func _prepare_terrain_effect_ray_snapshot(
	base_snapshot: Dictionary,
	ray_origin: Vector3,
	ray_direction: Vector3,
	max_distance: float
) -> Dictionary:
	if terrain_effect_runtime == null or not bool(terrain_effect_runtime.get("initialized")):
		return {"ok": false, "reason": "terrain_effect_runtime_unavailable"}
	if not ray_origin.is_finite() or not ray_direction.is_finite() 		or ray_direction.length_squared() <= 0.000001 		or not is_finite(max_distance) or max_distance <= 0.0:
		return {"ok": false, "reason": "terrain_effect_ray_invalid"}
	var direction := ray_direction.normalized()
	var targets_by_id: Dictionary = {}
	var step := 1.5
	var distance := 0.0
	while distance <= max_distance and targets_by_id.size() < 64:
		var point := ray_origin + direction * distance
		var mapped: Dictionary = SpatialGrid.world_to_region_local(point)
		if mapped.get("valid", false):
			var region_key: Vector2i = mapped["region_key"]
			if active_regions.has(_region_id(region_key)) 				or loading_regions.has(_region_id(region_key)):
				var coordinate := _chunk_coordinate_for_local(
					mapped["local_position"]
				)
				var target_id := ChunkGrid.stable_id(region_key, coordinate)
				targets_by_id[target_id] = {
					"region_key": region_key,
					"chunk_coordinate": coordinate,
				}
		distance += step
	if targets_by_id.is_empty():
		return {"ok": false, "reason": "terrain_effect_ray_has_no_resident_targets"}
	var ids: Array[String] = []
	for target_id in targets_by_id:
		ids.append(String(target_id))
	ids.sort()
	var targets: Array[Dictionary] = []
	for target_id in ids:
		targets.append(targets_by_id[target_id])
	return _prepare_terrain_effect_snapshot(base_snapshot, targets)


func _chunk_coordinate_for_local(local_position: Vector3) -> Vector2i:
	var chunk_width := float(ChunkGrid.CELLS_PER_CHUNK_X) * ChunkGrid.SAMPLE_STEP
	var chunk_depth := float(ChunkGrid.CELLS_PER_CHUNK_Z) * ChunkGrid.SAMPLE_STEP
	return Vector2i(
		clampi(floori(local_position.x / chunk_width), 0, ChunkGrid.CHUNK_COUNT_X - 1),
		clampi(floori(local_position.z / chunk_depth), 0, ChunkGrid.CHUNK_COUNT_Z - 1)
	)


func _sample_world_density(world_position: Vector3) -> float:
	var mapped: Dictionary = SpatialGrid.world_to_region_local(world_position)
	if not mapped.get("valid", false):
		return -INF
	var key: Vector2i = mapped["region_key"]
	var state := _state_for_region(key)
	return state.sample_density(mapped["local_position"], cave_section_enabled)


func _sample_world_density_from_snapshot(world_position: Vector3, snapshot: Dictionary) -> float:
	var mapped: Dictionary = SpatialGrid.world_to_region_local(world_position)
	if not mapped.get("valid", false):
		return -INF
	return BrushEditState.sample_density_snapshot(
		world_seed, mapped["region_key"], mapped["local_position"], cave_section_enabled, snapshot
	)


func _edit_trace(event: String, payload: Dictionary = {}) -> void:
	if not _edit_trace_enabled:
		return
	var record := payload.duplicate(true)
	record["event"] = event
	record["t_usec"] = Time.get_ticks_usec()
	print("EDIT_TRACE " + JSON.stringify(record))


func _apply_brush_at(screen_position: Vector2) -> void:
	if global_rebuild_pending or not active_regions.has(_region_id(focus_region_key)):
		last_brush_result = "Focused region is not ready for edits; no edit added"
		_update_status()
		return
	var pick_total_started_usec := Time.get_ticks_usec()
	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_direction := camera.project_ray_normal(screen_position)
	var focused_state: RefCounted = _state_for_region(focus_region_key)
	var snapshot_started_usec := Time.get_ticks_usec()
	var pick_snapshot: Dictionary = focused_state.brush_edits.get_ray_snapshot(
		ray_origin, ray_direction, BrushPicker.MAX_DISTANCE
	)
	var prepared_pick := _prepare_terrain_effect_ray_snapshot(
		pick_snapshot, ray_origin, ray_direction, BrushPicker.MAX_DISTANCE
	)
	if not prepared_pick.get("ok", false):
		last_brush_result = "Terrain-object effect pick snapshot unavailable (%s); no edit added" % prepared_pick.get("reason", "unknown")
		_update_status()
		return
	pick_snapshot = prepared_pick["snapshot"]
	_last_brush_pick_snapshot_elapsed_usec = Time.get_ticks_usec() - snapshot_started_usec
	_last_brush_pick_candidate_count = int(pick_snapshot.get("candidate_operation_count", 0))
	_last_brush_pick_sample_count = 0
	var density_sampler := func(point: Vector3) -> float:
		_last_brush_pick_sample_count += 1
		return _sample_world_density_from_snapshot(point, pick_snapshot)
	var pick_started_usec := Time.get_ticks_usec()
	var pick: Dictionary = BrushPicker.pick_sdf_v1_surface(ray_origin, ray_direction, density_sampler)
	_last_brush_pick_elapsed_usec = Time.get_ticks_usec() - pick_started_usec
	_last_brush_pick_total_elapsed_usec = Time.get_ticks_usec() - pick_total_started_usec
	_last_brush_pick_hit = bool(pick.get("hit", false))
	_last_brush_pick_position = pick.get("position", Vector3.ZERO)
	_brush_pick_serial += 1
	_edit_trace("pick", {
		"pick_serial": _brush_pick_serial,
		"snapshot_ms": float(_last_brush_pick_snapshot_elapsed_usec) / 1000.0,
		"march_ms": float(_last_brush_pick_elapsed_usec) / 1000.0,
		"total_ms": float(_last_brush_pick_total_elapsed_usec) / 1000.0,
		"candidate_operations": _last_brush_pick_candidate_count,
		"samples": _last_brush_pick_sample_count,
		"hit": _last_brush_pick_hit,
	})
	if not pick.get("hit", false):
		last_brush_result = "No terrain surface hit; no edit added"
		_update_status()
		return
	var world_hit: Vector3 = pick["position"]
	var mapped: Dictionary = SpatialGrid.world_to_region_local(world_hit)
	if not mapped.get("valid", false):
		last_brush_result = "Invalid world position; no edit added"
		_update_status()
		return
	_accept_brush_at_world(world_hit)


func _accept_brush_at_world(world_hit: Vector3) -> bool:
	var accept_started_usec := Time.get_ticks_usec()
	_edit_trace_serial += 1
	var trace_serial := _edit_trace_serial
	if global_rebuild_pending:
		last_brush_result = "Global mesh publication is busy; no edit added"
		_update_status()
		return false
	if not world_hit.is_finite():
		last_brush_result = "Edit rejected (non-finite hit); terrain unchanged"
		_update_status()
		return false
	if not _edit_transaction.is_empty():
		if _buffered_brush_requests.size() >= MAX_BUFFERED_BRUSH_REQUESTS:
			last_brush_result = "Edit input buffer is full; no edit added"
			_update_status()
			return false
		_buffered_brush_requests.append({
			"mode": selected_brush_mode,
			"center_world": world_hit,
			"radius": BRUSH_RADIUS,
			"buffered_usec": Time.get_ticks_usec(),
			"trace_serial": trace_serial,
		})
		_edit_trace("buffered_input", {
			"trace_serial": trace_serial,
			"active_revision": int(_edit_transaction.get("revision", edit_ledger.revision)),
			"pending_count": _buffered_brush_requests.size(),
			"accept_ms": float(Time.get_ticks_usec() - accept_started_usec) / 1000.0,
		})
		var buffered_mode := "FILL" if selected_brush_mode == BrushEditState.Mode.FILL else "CARVE"
		last_brush_result = "%s buffered while revision %d publishes; %d pending edit(s)" % [
			buffered_mode,
			int(_edit_transaction.get("revision", edit_ledger.revision)),
			_buffered_brush_requests.size(),
		]
		_update_status()
		return true
	var ledger_started_usec := Time.get_ticks_usec()
	if not edit_ledger.add_sphere(selected_brush_mode, world_hit, BRUSH_RADIUS):
		_last_edit_rejection = edit_ledger.last_rejection_reason
		last_brush_result = "Edit rejected (%s); terrain unchanged" % _last_edit_rejection
		_update_status()
		return false
	var ledger_elapsed_usec := Time.get_ticks_usec() - ledger_started_usec
	var operation: Dictionary = edit_ledger.get_last_operation_snapshot()
	_edit_trace("ledger_accept", {
		"trace_serial": trace_serial,
		"sequence": int(operation["sequence"]),
		"revision": int(edit_ledger.revision),
		"ledger_ms": float(ledger_elapsed_usec) / 1000.0,
		"accept_to_ledger_ms": float(Time.get_ticks_usec() - accept_started_usec) / 1000.0,
		"tail_operations": int(edit_ledger.get_tail_edit_count()) if edit_ledger.has_method("get_tail_edit_count") else -1,
		"support_regions": (operation["support_regions"] as Array).size(),
		"dependency_regions": (operation["dependency_regions"] as Array).size(),
		"rebuild_regions": (operation["rebuild_regions"] as Array).size(),
	})
	_last_edit_rejection = ""
	var mode_name := "FILL" if selected_brush_mode == BrushEditState.Mode.FILL else "CARVE"
	last_brush_result = "%s #%d accepted globally at %s; %d support + %d dependent rebuild region(s)" % [
		mode_name,
		operation["sequence"],
		world_hit,
		(operation["support_regions"] as Array).size(),
		(operation["dependency_regions"] as Array).size(),
	]
	_schedule_edit_transaction(operation)
	_update_status()
	return true


func _flush_buffered_brush_requests() -> void:
	if _buffered_brush_requests.is_empty() or not _edit_transaction.is_empty() or global_rebuild_pending:
		return
	var requests: Array[Dictionary] = _buffered_brush_requests.duplicate(true)
	_buffered_brush_requests.clear()
	var operations: Array[Dictionary] = []
	var rejected := 0
	var batch_ledger_started_usec := Time.get_ticks_usec()
	var oldest_buffered_usec := 0
	for request in requests:
		var buffered_usec := int(request.get("buffered_usec", 0))
		if buffered_usec > 0 and (oldest_buffered_usec == 0 or buffered_usec < oldest_buffered_usec):
			oldest_buffered_usec = buffered_usec
		var mode := int(request["mode"])
		var center: Vector3 = request["center_world"]
		var radius := float(request["radius"])
		if edit_ledger.add_sphere(mode, center, radius):
			operations.append(edit_ledger.get_last_operation_snapshot())
		else:
			rejected += 1
	var batch_ledger_usec := Time.get_ticks_usec() - batch_ledger_started_usec
	if operations.is_empty():
		last_brush_result = "Buffered edit batch rejected; %d request(s) unchanged" % rejected
		_update_status()
		return
	var first_sequence := int(operations[0]["sequence"])
	var last_sequence := int(operations[-1]["sequence"])
	last_brush_result = "Coalesced %d buffered edit(s) into revisions #%d-#%d%s" % [
		operations.size(),
		first_sequence,
		last_sequence,
		"" if rejected == 0 else "; %d rejected" % rejected,
	]
	_edit_trace("buffer_flush", {
		"operation_count": operations.size(),
		"rejected": rejected,
		"ledger_ms": float(batch_ledger_usec) / 1000.0,
		"oldest_buffer_wait_ms": float(Time.get_ticks_usec() - oldest_buffered_usec) / 1000.0 if oldest_buffered_usec > 0 else 0.0,
		"sequence_start": first_sequence,
		"sequence_end": last_sequence,
	})
	_schedule_edit_transaction_batch(operations)
	_update_status()


func _region_id(region_key: Vector2i) -> String:
	return "%d,%d" % [region_key.x, region_key.y]


func _region_key_from_id(region_id: String) -> Vector2i:
	var parts := region_id.split(",")
	if parts.size() != 2:
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))


func _update_camera() -> void:
	_lod_selection_dirty = true
	camera.position = orbit_target + orbit_offset
	camera.look_at(orbit_target, Vector3.UP)
	if is_instance_valid(_placement_target_marker):
		_refresh_placement_target_indicator()


func _set_orbit_distance(distance: float) -> void:
	orbit_offset = orbit_offset.normalized() * clampf(distance, 20.0, 96.0)
	_update_camera()


func _get_total_triangle_count() -> int:
	return _active_triangle_count


func _get_mesh_attribute_bytes_estimate() -> int:
	return _active_vertex_count * 24


func _frame_time_percentiles() -> Vector3:
	if _frame_sample_count == 0:
		return Vector3.ZERO
	var sorted: Array[float] = []
	for index in range(_frame_sample_count):
		sorted.append(_frame_time_samples[index])
	sorted.sort()
	return Vector3(
		sorted[maxi(0, ceili(float(sorted.size()) * 0.50) - 1)],
		sorted[maxi(0, ceili(float(sorted.size()) * 0.95) - 1)],
		sorted[maxi(0, ceili(float(sorted.size()) * 0.99) - 1)]
	)


func _queued_chunk_count() -> int:
	var total := 0
	for stage_value in loading_regions.values():
		var stage: Dictionary = stage_value
		total += (stage["chunk_coordinates"] as Array).size() - int(stage["next_index"])
	return total


func _queued_mesh_job_count() -> int:
	return _queued_chunk_count()


func _update_runtime_diagnostics() -> void:
	_peak_active_region_count = maxi(_peak_active_region_count, active_regions.size())
	_peak_queue_depth = maxi(_peak_queue_depth, _queued_chunk_count())
	_peak_mesh_job_queue_depth = maxi(_peak_mesh_job_queue_depth, _queued_mesh_job_count())
	if last_mesh_diagnostics.is_empty():
		last_mesh_diagnostics = {}
	last_mesh_diagnostics["active_region_count"] = active_regions.size()
	last_mesh_diagnostics["preview_region_count"] = active_regions.size()
	last_mesh_diagnostics["active_chunk_count"] = chunk_nodes.size()
	var lod0_count := 0
	var lod1_count := 0
	for lod_value in _published_lod_by_chunk.values():
		if int(lod_value) == 1:
			lod1_count += 1
		else:
			lod0_count += 1
	last_mesh_diagnostics["lod_enabled"] = lod_enabled
	last_mesh_diagnostics["lod0_chunk_count"] = lod0_count
	last_mesh_diagnostics["lod1_chunk_count"] = lod1_count
	last_mesh_diagnostics["lod_fallback_chunk_count"] = _lod_fallback_chunks.size()
	last_mesh_diagnostics["requested_region_count"] = (REQUEST_RADIUS * 2 + 1) * (REQUEST_RADIUS * 2 + 1)
	last_mesh_diagnostics["loading_region_count"] = loading_regions.size()
	last_mesh_diagnostics["queued_chunk_count"] = _queued_chunk_count()
	last_mesh_diagnostics["queued_mesh_job_count"] = _queued_mesh_job_count()
	last_mesh_diagnostics["peak_active_region_count"] = _peak_active_region_count
	last_mesh_diagnostics["peak_queue_depth"] = _peak_queue_depth
	last_mesh_diagnostics["peak_mesh_job_queue_depth"] = _peak_mesh_job_queue_depth
	last_mesh_diagnostics["last_mesh_upload_ms"] = _last_mesh_upload_ms
	last_mesh_diagnostics["peak_mesh_upload_ms"] = _peak_mesh_upload_ms
	last_mesh_diagnostics["last_process_work_ms"] = _last_process_work_ms
	last_mesh_diagnostics["peak_process_work_ms"] = _peak_process_work_ms
	last_mesh_diagnostics["last_frame_ms"] = _last_frame_ms
	last_mesh_diagnostics["peak_frame_ms"] = _peak_frame_ms
	last_mesh_diagnostics["streamed_region_loads"] = _streamed_region_loads
	last_mesh_diagnostics["streamed_region_unloads"] = _streamed_region_unloads
	last_mesh_diagnostics["global_rebuild_pending"] = global_rebuild_pending
	last_mesh_diagnostics["max_active_region_count"] = MAX_ACTIVE_REGIONS
	last_mesh_diagnostics["max_mesh_uploads_per_frame"] = MAX_MESH_UPLOADS_PER_FRAME
	last_mesh_diagnostics["mesh_upload_frame_budget_usec"] = MESH_UPLOAD_FRAME_BUDGET_USEC
	last_mesh_diagnostics["max_mesh_job_dispatches_per_frame"] = MAX_MESH_JOB_DISPATCHES_PER_FRAME
	last_mesh_diagnostics["mesh_snapshot_frame_budget_usec"] = MESH_SNAPSHOT_FRAME_BUDGET_USEC
	last_mesh_diagnostics["mesh_job_limit"] = _mesh_job_limit
	last_mesh_diagnostics["peak_mesh_uploads_per_frame"] = _peak_mesh_uploads_per_frame
	last_mesh_diagnostics["peak_mesh_dispatches_per_frame"] = _peak_mesh_dispatches_per_frame
	last_mesh_diagnostics["mesh_jobs_in_flight"] = _mesh_jobs.size()
	last_mesh_diagnostics["peak_mesh_jobs_in_flight"] = _peak_mesh_jobs_in_flight
	last_mesh_diagnostics["last_brush_pick_elapsed_ms"] = float(_last_brush_pick_elapsed_usec) / 1000.0
	last_mesh_diagnostics["last_brush_pick_snapshot_elapsed_ms"] = float(_last_brush_pick_snapshot_elapsed_usec) / 1000.0
	last_mesh_diagnostics["last_brush_pick_total_elapsed_ms"] = float(_last_brush_pick_total_elapsed_usec) / 1000.0
	last_mesh_diagnostics["last_brush_pick_sample_count"] = _last_brush_pick_sample_count
	last_mesh_diagnostics["last_brush_pick_hit"] = _last_brush_pick_hit
	last_mesh_diagnostics["last_brush_pick_position"] = _last_brush_pick_position
	last_mesh_diagnostics["last_brush_pick_candidate_count"] = _last_brush_pick_candidate_count
	last_mesh_diagnostics["brush_pick_serial"] = _brush_pick_serial
	last_mesh_diagnostics["global_edit_count"] = edit_ledger.get_edit_count()
	last_mesh_diagnostics["global_edit_limit"] = BrushEditState.MAX_OPERATION_COUNT
	last_mesh_diagnostics["global_edit_last_sequence"] = edit_ledger.get_last_sequence()
	last_mesh_diagnostics["global_edit_revision"] = edit_ledger.revision
	last_mesh_diagnostics["last_support_region_count"] = _last_edit_support_region_count
	last_mesh_diagnostics["last_rebuild_region_count"] = _last_edit_rebuild_region_count
	last_mesh_diagnostics["last_rebuild_chunk_count"] = _last_edit_rebuild_chunk_count
	last_mesh_diagnostics["last_dirty_mesh_job_count"] = _last_edit_mesh_jobs
	last_mesh_diagnostics["edit_stage_state"] = "idle" if _edit_transaction.is_empty() else _edit_transaction.get("stage_state", "staging")
	last_mesh_diagnostics["last_edit_rejection"] = _last_edit_rejection
	last_mesh_diagnostics["mesh_stage_retry_total"] = _mesh_stage_retry_total
	last_mesh_diagnostics["superseded_stage_total"] = _superseded_stage_total
	last_mesh_diagnostics["resident_region_count"] = active_regions.size()
	last_mesh_diagnostics["queued_region_count"] = loading_regions.size()
	var frame_percentiles := _frame_time_percentiles()
	last_mesh_diagnostics["frame_time_p50_ms"] = frame_percentiles.x
	last_mesh_diagnostics["frame_time_p95_ms"] = frame_percentiles.y
	last_mesh_diagnostics["frame_time_p99_ms"] = frame_percentiles.z


func _configure_preedit_arguments() -> void:
	var env_path := OS.get_environment("SANDBOX_PREEDIT_PATH")
	if not env_path.is_empty():
		_preedit_path = env_path
	var env_count := OS.get_environment("SANDBOX_PREEDIT_COUNT")
	if env_count.is_valid_int():
		_preedit_count = clampi(int(env_count), 1, 20000)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--preedit-path="):
			_preedit_path = argument.trim_prefix("--preedit-path=")
		elif argument.begins_with("--preedit-count="):
			var raw := argument.trim_prefix("--preedit-count=")
			if raw.is_valid_int():
				_preedit_count = clampi(int(raw), 1, 20000)
	if not _preedit_path.is_empty():
		_preedit_status = "F5: inject edits from %s" % _preedit_path
	else:
		_preedit_status = "F5: inject %d deterministic edits around focus" % _preedit_count


func _maybe_schedule_async_checkpoint() -> void:
	if not _scalable_runtime_enabled or _checkpoint_task_id >= 0 \
		or _persistence_blocked or not _pending_world_load.is_empty():
		return
	if edit_ledger != null and edit_ledger.needs_checkpoint(ScalableSdfState.CHECKPOINT_TAIL_TARGET):
		_start_async_checkpoint(false)


func _start_async_checkpoint(manual: bool) -> bool:
	if not _scalable_runtime_enabled or _persistence_blocked:
		_checkpoint_status = "checkpoint unavailable"
		return false
	if _checkpoint_task_id >= 0:
		_checkpoint_status = "checkpoint already running"
		return false
	if edit_ledger == null or int(edit_ledger.get_tail_edit_count()) <= 0:
		_checkpoint_status = "materialized state already current"
		if manual:
			_persistence_status = "No uncheckpointed edits; materialized generation %d is current" % _checkpoint_generation
		return true
	var snapshot: Dictionary = edit_ledger.make_async_checkpoint_snapshot()
	if not snapshot.get("valid", false):
		_checkpoint_status = "checkpoint snapshot failed"
		return false
	var now := Time.get_ticks_usec()
	var job := AsyncCheckpointJob.new(
		world_save_store.get_world_directory(), snapshot, now
	)
	var task_id := WorkerThreadPool.add_task(
		Callable(job, "run"), false, "terrain async checkpoint"
	)
	if task_id < 0:
		_checkpoint_status = "worker pool rejected checkpoint"
		return false
	_checkpoint_job = job
	_checkpoint_task_id = task_id
	_checkpoint_started_usec = now
	_checkpoint_overlap_observed = false
	_checkpoint_status = "checkpoint running: %d frozen tail edit(s)" % (snapshot.get("tail_operations", []) as Array).size()
	if manual:
		_persistence_status = "Async materialized checkpoint queued; gameplay remains active"
	return true


func _process_async_checkpoint() -> void:
	if _checkpoint_task_id < 0 or not WorkerThreadPool.is_task_completed(_checkpoint_task_id):
		return
	WorkerThreadPool.wait_for_task_completion(_checkpoint_task_id)
	var job := _checkpoint_job
	var result: Dictionary = job.result if job != null else {}
	_checkpoint_task_id = -1
	_checkpoint_job = null
	if not result.get("valid", false):
		_checkpoint_status = "checkpoint failed: %s" % result.get("reason", "unknown")
		_persistence_status = _checkpoint_status
		return
	var checkpoint_snapshot: Dictionary = result.get("checkpoint_snapshot", {})
	var checkpoint_store: RefCounted = result.get("store")
	var head: Dictionary = result.get("head", {})
	if checkpoint_store == null or not edit_ledger.commit_async_checkpoint(
		checkpoint_snapshot, checkpoint_store, head
	):
		_checkpoint_status = "checkpoint main-thread commit rejected: %s" % edit_ledger.last_storage_error
		_persistence_status = _checkpoint_status
		return
	world_save_store = checkpoint_store
	_checkpoint_generation = int(head.get("generation", _checkpoint_generation))
	_checkpoint_last_worker_ms = float(result.get("worker_usec", 0)) / 1000.0
	_checkpoint_status = "checkpoint gen %d committed in %.1f ms; archived %d, live tail %d" % [
		_checkpoint_generation,
		_checkpoint_last_worker_ms,
		int(edit_ledger.get_archived_edit_count()),
		int(edit_ledger.get_tail_edit_count()),
	]
	_persistence_status = _checkpoint_status
	if not _save_simulation_state(_checkpoint_generation):
		_persistence_status += "; " + _simulation_persistence_status


func _apply_preedit_fixture() -> void:
	if not _scalable_runtime_enabled:
		last_brush_result = "Pre-edit fixture requires the scalable materialized runtime"
		return
	if global_rebuild_pending or not _edit_transaction.is_empty() or not loading_regions.is_empty():
		last_brush_result = "Wait for current terrain staging to finish before injecting pre-edits"
		return
	var specs_result := _load_preedit_specs(_preedit_path) if not _preedit_path.is_empty() \
		else {"ok": true, "operations": _build_deterministic_preedit_specs(_preedit_count)}
	if not specs_result.get("ok", false):
		last_brush_result = "Pre-edit input rejected: %s" % specs_result.get("reason", "invalid")
		return
	var operations: Array = specs_result.get("operations", [])
	var accepted := 0
	var started := Time.get_ticks_usec()
	for spec_value in operations:
		if typeof(spec_value) != TYPE_DICTIONARY:
			continue
		var spec: Dictionary = spec_value
		if not edit_ledger.add_sphere(
			int(spec.get("mode", BrushEditState.Mode.CARVE)),
			spec.get("center", Vector3.INF),
			float(spec.get("radius", BRUSH_RADIUS))
		):
			last_brush_result = "Pre-edit #%d rejected: %s" % [accepted, edit_ledger.last_rejection_reason]
			break
		accepted += 1
	if accepted <= 0:
		return
	var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0
	_preedit_status = "Injected %d pre-edits in %.1f ms; checkpoint will compact in background" % [accepted, elapsed_ms]
	last_brush_result = _preedit_status
	_start_global_rebuild("preedit_fixture")
	_start_async_checkpoint(false)


func _build_deterministic_preedit_specs(count: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var origin := SpatialGrid.region_origin_world(focus_region_key)
	for index in range(count):
		# Four-region fixture: general edits plus deliberate X, Z and X/Z-corner
		# crossings. This is the default owner-facing stress pattern.
		var lane := index % 4
		var x := 1.0 + float((index * 37) % 120) * 0.25
		var z := 1.0 + float((index * 19) % 88) * 0.25
		var y := 0.75 + float((index * 11) % 17) * 0.20
		if lane == 1:
			x = 15.25 + float(index % 7) * 0.25
		elif lane == 2:
			z = 11.25 + float(index % 7) * 0.25
		elif lane == 3:
			x = 15.25 + float(index % 7) * 0.25
			z = 11.25 + float((index * 3) % 7) * 0.25
		result.append({
			"mode": BrushEditState.Mode.CARVE if index % 3 == 0 else BrushEditState.Mode.FILL,
			"center": origin + Vector3(x, y, z),
			"radius": 0.55 + float(index % 5) * 0.12,
		})
	return result


func _load_preedit_specs(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {"ok": false, "reason": "file_not_found"}
	var text_value := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text_value)
	var rows: Variant = parsed
	if typeof(parsed) == TYPE_DICTIONARY:
		rows = (parsed as Dictionary).get("operations", null)
	if typeof(rows) != TYPE_ARRAY:
		return {"ok": false, "reason": "expected_array_or_operations_array"}
	var result: Array[Dictionary] = []
	for row_value in rows:
		if typeof(row_value) != TYPE_DICTIONARY:
			return {"ok": false, "reason": "operation_not_object"}
		var row: Dictionary = row_value
		var center_value: Variant = row.get("center", row.get("center_world", null))
		if typeof(center_value) != TYPE_ARRAY or (center_value as Array).size() != 3:
			return {"ok": false, "reason": "center_requires_xyz_array"}
		var center_array: Array = center_value
		var mode_value: Variant = row.get("mode", "CARVE")
		var mode := BrushEditState.Mode.CARVE
		if typeof(mode_value) == TYPE_STRING:
			mode = BrushEditState.Mode.FILL if String(mode_value).to_upper() == "FILL" else BrushEditState.Mode.CARVE
		elif typeof(mode_value) == TYPE_INT:
			mode = int(mode_value)
		result.append({
			"mode": mode,
			"center": Vector3(float(center_array[0]), float(center_array[1]), float(center_array[2])),
			"radius": float(row.get("radius", BRUSH_RADIUS)),
		})
	return {"ok": true, "operations": result}


func _build_ledger_from_payload(payload: Dictionary) -> Dictionary:
	var seed_value: Variant = payload.get("world_seed", null)
	var generator_value: Variant = payload.get("generator_version", null)
	if typeof(seed_value) != TYPE_INT or typeof(generator_value) != TYPE_INT \
		or int(generator_value) != Field.GENERATOR_VERSION:
		return {"ok": false, "reason": "world_identity_or_generator_invalid"}
	var ledger: RefCounted = BrushEditState.new(int(seed_value), int(generator_value))
	var snapshot := {
		"world_seed": int(seed_value),
		"generator_version": int(generator_value),
		"revision": int(payload.get("ledger_revision", -1)),
		"next_sequence": int(payload.get("next_sequence", -1)),
	}
	if payload.has("storage_reference"):
		snapshot["storage_reference"] = payload["storage_reference"]
	else:
		snapshot["operations"] = payload.get("operations", null)
	if not ledger.restore_persistence_snapshot(snapshot):
		return {"ok": false, "reason": ledger.last_restore_rejection_reason}
	return {"ok": true, "world_seed": int(seed_value), "ledger": ledger}


func _loaded_world_message(load_result: Dictionary) -> String:
	if load_result.get("recovered_temporary", false):
		return "Recovered complete interrupted save generation %d" % int(load_result.get("generation", 0))
	if int(load_result.get("ignored_invalid_candidates", 0)) > 0:
		return "Loaded valid generation %d; ignored %d invalid candidate(s)" % [
			int(load_result.get("generation", 0)), int(load_result["ignored_invalid_candidates"]),
		]
	return "Loaded terrain schema v2 generation %d (%d indexed segment(s))" % [int(load_result.get("generation", 0)), int(load_result.get("segment_count", 0))]


func _save_world_to_storage() -> bool:
	if _persistence_blocked:
		_persistence_status = "Save blocked until the invalid/incompatible existing world is handled"
		_update_status()
		return false
	if _scalable_runtime_enabled:
		var queued := _start_async_checkpoint(true)
		if queued and _checkpoint_task_id < 0:
			if not _save_simulation_state(_checkpoint_generation):
				_persistence_status += "; " + _simulation_persistence_status
				_update_status()
				return false
		_update_status()
		return queued
	if global_rebuild_pending or not _edit_transaction.is_empty():
		_persistence_status = "Save waits for coherent terrain publication to finish"
		_update_status()
		return false
	var saved: Dictionary = world_save_store.save_ledger(world_id, edit_ledger)
	if not saved.get("ok", false):
		_persistence_status = "Save failed (%s); previous generations retained" % saved.get("reason", "unknown")
		_update_status()
		return false
	var terrain_generation := int(saved["generation"])
	_persistence_status = "Saved generation %d (%d ordered edit(s), revision %d)" % [
		terrain_generation, int(saved["operation_count"]), int(saved["revision"]),
	]
	if not _save_simulation_state(terrain_generation):
		_persistence_status += "; " + _simulation_persistence_status
		_update_status()
		return false
	_update_status()
	return true


func _load_world_from_storage() -> bool:
	if global_rebuild_pending or not _edit_transaction.is_empty():
		_persistence_status = "Load waits for the current mesh transaction to finish"
		_update_status()
		return false
	if _scalable_runtime_enabled:
		if _checkpoint_task_id >= 0:
			_persistence_status = "Load waits for the async checkpoint to finish"
			_update_status()
			return false
		var loaded: Dictionary = world_save_store.load_world(world_id)
		if not loaded.get("ok", false):
			_persistence_status = "Load rejected (%s); current world is unchanged" % loaded.get("reason", "invalid")
			_update_status()
			return false
		if not loaded.get("found", false):
			_persistence_status = "No materialized world exists; current world is unchanged"
			_update_status()
			return false
		var candidate: RefCounted = loaded["state"]
		var terrain_generation := int(loaded["generation"])
		var simulation_candidate := _read_simulation_candidate(
			int(candidate.world_seed), terrain_generation
		)
		if not simulation_candidate.get("ok", false):
			_persistence_status = "Load rejected: simulation sidecar %s; current world is unchanged" % simulation_candidate.get("reason", "invalid")
			_update_status()
			return false
		_pending_world_load = {
			"world_seed": int(candidate.world_seed),
			"ledger": candidate,
			"generation": terrain_generation,
			"simulation_found": bool(simulation_candidate.get("found", false)),
			"simulation_generation": int(simulation_candidate.get("generation", 0)),
			"simulation_snapshot": simulation_candidate.get("snapshot", {}),
		}
		_checkpoint_generation = terrain_generation
		_persistence_status = "Loading materialized generation %d; old meshes remain until coherent publication" % _checkpoint_generation
		_start_global_rebuild("load_world")
		_update_status()
		return true
	var loaded: Dictionary = world_save_store.load_world(world_id)
	if not loaded.get("ok", false):
		_persistence_status = "Load rejected (%s); current world is unchanged" % loaded.get("reason", "invalid")
		_update_status()
		return false
	if not loaded.get("found", false):
		_persistence_status = "No saved local world exists; current world is unchanged"
		_update_status()
		return false
	var candidate: Dictionary = _build_ledger_from_payload(loaded.get("payload", {}))
	if not candidate.get("ok", false):
		_persistence_status = "Load rejected (%s); current world is unchanged" % candidate.get("reason", "invalid")
		_update_status()
		return false
	var terrain_generation := int(loaded["generation"])
	var simulation_candidate := _read_simulation_candidate(
		int(candidate["world_seed"]), terrain_generation
	)
	if not simulation_candidate.get("ok", false):
		_persistence_status = "Load rejected: simulation sidecar %s; current world is unchanged" % simulation_candidate.get("reason", "invalid")
		_update_status()
		return false
	_pending_world_load = {
		"world_seed": int(candidate["world_seed"]),
		"ledger": candidate["ledger"],
		"generation": terrain_generation,
		"simulation_found": bool(simulation_candidate.get("found", false)),
		"simulation_generation": int(simulation_candidate.get("generation", 0)),
		"simulation_snapshot": simulation_candidate.get("snapshot", {}),
	}
	_persistence_status = "Loading generation %d; old meshes remain until the complete set is ready" % terrain_generation
	_start_global_rebuild("load_world")
	_update_status()
	return true


func _update_status() -> void:
	if free_explore_enabled:
		if is_instance_valid(status_label):
			status_label.text = ""
		return
	var state := _state_for_region(focus_region_key)
	var seed: int = state.world_seed if state != null else world_seed
	var generator_version: int = state.generator_version if state != null else Field.GENERATOR_VERSION
	var selected_mode_name := "FILL" if selected_brush_mode == BrushEditState.Mode.FILL else "CARVE"
	var queue_depth := _queued_chunk_count()
	var transaction_state := "idle" if _edit_transaction.is_empty() else String(_edit_transaction.get("stage_state", "staging"))
	if not _buffered_brush_requests.is_empty():
		transaction_state += " + %d buffered" % _buffered_brush_requests.size()
	var aim_text := "visible pointer" if _last_placement_aim_mode == "pointer" else "center aim (cursor hidden/unavailable)"
	var target_text := "none" if not _placement_target_valid else "%s at %s (%s)" % [aim_text, _placement_target_region_key, "published" if _placement_target_published else "waiting for publication"]
	var status := "P1.1C custom LOD 0/1 + P1.0C global SDF edits  |  seed %d  |  generator v%d\nFocus region: %s  |  resident/active: %d/%d  |  queued regions: %d  |  queued chunks/jobs: %d/%d\nWASD/arrows: move focus    Right-drag: orbit    Wheel: zoom    Left: carve    Shift+left: fill    F10: free explore\nC: cave section    R: rebuild    X: focused reset    L: LOD    F5: pre-edits    P/O: checkpoint/load\nCtrl+left: select object    B: place at visible pointer; hidden cursor uses center aim    F6: cycle    F7: transform + appearance    F8: delete    F9: restore baseline\nPlacement target: %s\nUndo anchor: entity origin/base center coincides with the terrain hit; no slope conforming\nCtrl+Z: Undo entity command    Ctrl+Y / Ctrl+Shift+Z: Redo entity command\nM twice within 6 s: explicit schema-3 history migration (preflight then commit); no automatic migration\nLocal world: %s\nSelected: %s    Global edits: %d/%d  |  seq/rev: %d/%d  |  Radius: %.2f\nLast edit: %d support / %d rebuild regions, %d chunks, %d uploads  |  commit: %s\nLOD chunks 0/1: %d/%d    Worker jobs: %d/%d  |  max uploads/frame: %d  |  last/peak upload: %.1f/%.1f ms  |  peak frame: %.1f ms\n" % [
		seed,
		generator_version,
		focus_region_key,
		active_regions.size(),
		MAX_ACTIVE_REGIONS,
		loading_regions.size(),
		queue_depth,
		_queued_mesh_job_count(),
		target_text,
		_persistence_status,
		selected_mode_name,
		edit_ledger.get_edit_count(),
		ScalableSdfState.MAX_SAFE_SEQUENCE if _scalable_runtime_enabled else BrushEditState.MAX_OPERATION_COUNT,
		edit_ledger.get_last_sequence(),
		edit_ledger.revision,
		BRUSH_RADIUS,
		_last_edit_support_region_count,
		_last_edit_rebuild_region_count,
		_last_edit_rebuild_chunk_count,
		_last_edit_mesh_jobs,
		transaction_state,
		int(last_mesh_diagnostics.get("lod0_chunk_count", 0)),
		int(last_mesh_diagnostics.get("lod1_chunk_count", 0)),
		_mesh_jobs.size(),
		_mesh_job_limit,
		MAX_MESH_UPLOADS_PER_FRAME,
		_last_mesh_upload_ms,
		_peak_mesh_upload_ms,
		_peak_frame_ms,
	]
	status += "Runtime timing: last op %s %.1f ms | frame p50/p95/p99 %.1f/%.1f/%.1f ms | process peak %.1f ms\n" % [
		String(last_mesh_diagnostics.get("operation", _operation_name)),
		float(last_mesh_diagnostics.get("elapsed_ms", 0.0)),
		float(last_mesh_diagnostics.get("frame_time_p50_ms", 0.0)),
		float(last_mesh_diagnostics.get("frame_time_p95_ms", 0.0)),
		float(last_mesh_diagnostics.get("frame_time_p99_ms", 0.0)),
		_peak_process_work_ms,
	]
	if is_instance_valid(simulation_runtime):
		var simulation_metrics: Dictionary = simulation_runtime.get_world_scope_lifecycle_metrics()
		if bool(simulation_metrics.get("initialized", false)):
			status += "P4 simulation: resident/peak %d/%d | registrations/revisits %d/%d | route obs %d | due queued/deferred %d/%d | %s\n" % [
				int(simulation_metrics.get("resident_count", 0)),
				int(simulation_metrics.get("peak_resident_scopes", 0)),
				int(simulation_metrics.get("registrations_total", 0)),
				int(simulation_metrics.get("revisits_total", 0)),
				int(simulation_metrics.get("route_observations_total", 0)),
				int(simulation_metrics.get("due_updates_queued_total", 0)),
				int(simulation_metrics.get("due_updates_deferred_total", 0)),
				_simulation_streaming_status,
			]
	if global_rebuild_pending:
		status += "Rebuilding visible set: %d regions staged\n" % loading_regions.size()
	if cave_section_enabled:
		status += "Global cave section: ON (world Z=6)\n"
	var definition_ids: Array[String] = object_stream.get_definition_ids()
	status += "Procedural objects: %d visible in %d regions | definitions: %s | V: toggle objects\n" % [
		object_stream.get_visible_instance_count(),
		object_stream.get_active_region_count(),
	", ".join(definition_ids),
	]
	var population_metrics: Dictionary = object_stream.get_performance_snapshot()
	status += "Static population: %d declarative rules | %d batched instances | %d pending region(s) | peak region generation %.2f ms\n" % [
		object_stream.get_population_rule_ids().size(),
		int(population_metrics.get("batched_instance_count", 0)),
		int(population_metrics.get("pending_region_publication_count", 0)),
		float(population_metrics.get("peak_generation_usec", 0)) / 1000.0,
	]
	if terrain_effect_runtime != null and bool(terrain_effect_runtime.get("initialized")):
		var effect_perf: Dictionary = terrain_effect_runtime.get_performance_snapshot()
		var projection_perf: Dictionary = effect_perf.get("projection", {})
		status += "Effect runtime: prep avg/peak %.2f/%.2f ms | prefetch pending/peak %.0f/%.2f ms | resident/protected %d/%d | reconcile/evict %d/%d | lookup scopes/frames %d/%d\n" % [
			float(effect_perf.get("prepare_average_usec", 0.0)) / 1000.0,
			float(effect_perf.get("prepare_peak_usec", 0)) / 1000.0,
			float(effect_perf.get("prefetch_pending_count", 0)),
			float(effect_perf.get("prefetch_peak_usec", 0)) / 1000.0,
			int(effect_perf.get("resident_scope_count", 0)),
			int(effect_perf.get("protected_scope_count", 0)),
			int(effect_perf.get("scope_reconcile_count", 0)),
			int(effect_perf.get("scope_eviction_count", 0)),
			int(projection_perf.get("lookup_scope_index_examined_count", 0)),
			int(projection_perf.get("lookup_frame_count", 0)),
		]
	var state_schema := int(object_stream.state_service.snapshot.get("schema_version", 0)) if object_stream.state_service != null else 0
	var command_readiness := "READY" if object_stream.is_entity_command_ready() else ("REBUILDING resident regions" if state_schema >= EntityStateContract.HISTORY_SNAPSHOT_SCHEMA_VERSION else "LOCKED until explicit history migration")
	status += "Entity state schema %d | world revision %d | command dispatcher %s\n" % [state_schema, object_stream.get_instance_state_revision(), command_readiness]
	var entity_command_service: RefCounted = object_stream.get_entity_command_service()
	if entity_command_service != null and bool(entity_command_service.get("initialized")):
		var history: Dictionary = entity_command_service.get_history_summary()
		var undo_entry: Dictionary = history.get("undo", {})
		var redo_entry: Dictionary = history.get("redo", {})
		status += "History depth/cursor %d/%d | Undo: %s | Redo: %s | Ctrl+Z undo, Ctrl+Y/Ctrl+Shift+Z redo (F9 remains baseline restore)\n" % [int(history.get("depth", 0)), int(history.get("cursor", 0)), String(undo_entry.get("operation", "none")), String(redo_entry.get("operation", "none"))]
	if not _selected_object_id.is_empty():
		var selected_summary: Dictionary = object_stream.get_entity_summary(_selected_object_id)
		if selected_summary.get("ok", false):
			status += "Entity: %s | %s | %s | world/entity rev %d/%d | %s\n" % [
				_selected_object_id,
				selected_summary.get("definition_id", "unknown"),
				"explicitly placed" if String(selected_summary.get("identity_kind", "")) == "placed_explicit_v1" else "procedural identity",
				int(selected_summary.get("world_revision", 0)),
				int(selected_summary.get("entity_revision", 0)),
				"logically deleted" if bool(selected_summary.get("deleted", false)) else "active",
			]
	var command_metrics: Dictionary = object_stream.get_last_entity_command_metrics()
	if not command_metrics.is_empty():
		status += "Last command timings us: validate %d, inverse %d, candidate/history validate %d/%d, persist %d, reconstruct %d, visual queue/wait/publish %d/%d/%d, total/published %d/%d\n" % [
			int(command_metrics.get("command_validation_usec", 0)),
			int(command_metrics.get("inverse_preparation_usec", 0)),
			int(command_metrics.get("candidate_validation_usec", 0)),
			int(command_metrics.get("history_validation_usec", 0)),
			int(command_metrics.get("persistence_usec", 0)),
			int(command_metrics.get("regional_reconstruction_usec", 0)),
			int(command_metrics.get("visual_queue_usec", 0)),
			int(command_metrics.get("visual_queue_wait_usec", 0)),
			int(command_metrics.get("visual_publication_usec", 0)),
			int(command_metrics.get("command_total_usec", 0)),
			int(command_metrics.get("command_total_to_visual_publish_usec", 0)),
		]
	status += _object_state_action_status + "\n"
	status += _procedural_object_status + "\n"
	var package_discovery_summary := object_stream.get_package_discovery_summary()
	if not package_discovery_summary.is_empty():
		status += package_discovery_summary + "\n"
	if _scalable_runtime_enabled:
		status += "Materialized SDF: archived %d | hot tail %d | generation %d | %s | shared X/Z/corner collar %s\n" % [
			int(edit_ledger.get_archived_edit_count()),
			int(edit_ledger.get_tail_edit_count()),
			_checkpoint_generation,
			_checkpoint_status,
			"ON" if _shared_boundary_runtime_enabled and not cave_section_enabled else "fallback",
		]
		status += _preedit_status + "\n"
	if last_stream_error != "":
		status += "STREAM ERROR: " + last_stream_error + "\n"
	status += last_brush_result
	status_label.text = status
