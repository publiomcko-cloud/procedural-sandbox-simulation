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
const EnvironmentClimateDomainScript := preload("res://scripts/simulation/environment_climate_domain.gd")
const EnvironmentHydrologyDomainScript := preload("res://scripts/simulation/environment_hydrology_domain.gd")
const EnvironmentSurfaceCacheJobScript := preload("res://scripts/simulation/environment_surface_cache_job.gd")
const DM16BenchmarkProbe := preload("res://scripts/diagnostics/dm16_benchmark_probe.gd")
const DM19ColdAttribution := preload("res://scripts/diagnostics/dm19_cold_attribution.gd")
const DM18CanonicalCache := preload("res://scripts/terrain/dm18_canonical_region_cache.gd")
const DM12SnapshotBatch := preload("res://scripts/terrain/dm12_surface_snapshot_batch.gd")
const EnvironmentVisualScript := preload("res://scripts/simulation/environment_visual_presentation.gd")
const EnvironmentStartupLocation := preload("res://scripts/simulation/environment_startup_location.gd")
const SimulationRuntimeStoreScript := preload("res://scripts/simulation/simulation_runtime_store.gd")
const SimulationRuntimeScript := preload("res://scripts/simulation/simulation_runtime.gd")
const PerformanceTrace := preload("res://scripts/diagnostics/performance_trace.gd")
const StreamBudgetPolicy := preload("res://scripts/terrain/terrain_stream_budget_policy.gd")
const StreamDispatchSelector := preload("res://scripts/terrain/terrain_stream_dispatch_selector.gd")
const StreamLookaheadPolicy := preload("res://scripts/terrain/terrain_stream_lookahead_policy.gd")
const DM9PrefetchPolicy := preload("res://scripts/terrain/dm9_canonical_prefetch_policy.gd")
const DM9VisualBudget := preload("res://scripts/terrain/dm9_visual_worker_budget_policy.gd")
const CoarsePreviewJob := preload("res://scripts/terrain/terrain_coarse_preview_job.gd")
const CoarsePreviewPolicy := preload("res://scripts/terrain/terrain_coarse_preview_policy.gd")
const ProgressiveLoadPolicy := preload("res://scripts/terrain/terrain_stream_progressive_load_policy.gd")
const DM3Policy := preload("res://scripts/experiments/b4_region_stream_policy.gd")
const DM3VisualJob := preload("res://scripts/experiments/b4_region_visual_job.gd")
const DM5DecorJob := preload("res://scripts/experiments/b4_low_detail_decor_job.gd")
const DM7RockJob := preload("res://scripts/experiments/b4_high_detail_rock_job.gd")
const DM7StaticBatch := preload("res://scripts/objects/procedural_object_static_batch.gd")

const BRUSH_RADIUS := 1.25
const REQUEST_RADIUS := 1
const UNLOAD_RADIUS := 2
const MAX_ACTIVE_REGIONS := 25
const MIN_MESH_JOBS_IN_FLIGHT := 4
const MAX_MESH_JOBS_IN_FLIGHT_HARD := 8
const MAX_MESH_JOB_DISPATCHES_PER_FRAME := 1
const MESH_SNAPSHOT_FRAME_BUDGET_USEC := 3500
const MAX_MESH_UPLOADS_PER_FRAME := 4
const MAX_COARSE_PREVIEW_JOBS := 1
const MAX_PROGRESSIVE_CHUNK_PUBLISHES_PER_FRAME := 2
const PROGRESSIVE_PUBLISH_BUDGET_USEC := 2200
const MESH_UPLOAD_FRAME_BUDGET_USEC := 3500
const STREAM_BUDGET_TRACE_INTERVAL_USEC := 1_000_000
const MAX_SURFACE_CACHE_JOBS_IN_FLIGHT := 2
const MAX_SURFACE_CACHE_DISPATCHES_PER_FRAME := 1
const SURFACE_CACHE_RETRY_BASE_USEC := 250_000
const SURFACE_CACHE_RETRY_MAX_USEC := 8_000_000
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

# Opt-in CI-only deterministic route: no keyboard events, no world mutations.
const STREAM_BENCH_START := Vector3(88.0, 8.0, 162.0)
const STREAM_BENCH_STEP_SEC := 1.0 / 60.0
const STREAM_BENCH_DEFAULT_FRAMES := 1200

@onready var terrain_chunks_root: Node3D = $TerrainChunks
@onready var terrain_mesh_template: MeshInstance3D = $TerrainChunks/Terrain
@onready var camera: Camera3D = $Camera3D
@onready var ui_layer: CanvasLayer = $CanvasLayer
@onready var status_label: Label = $CanvasLayer/Status
@onready var object_stream: ProceduralObjectStream = $ProceduralObjects
@onready var simulation_runtime: Node = $SimulationRuntime

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
var _material_content_domain: RefCounted
var _climate_content_domain: RefCounted
var _environment_visual
var _startup_location_status := ""
var _start_ocean_probe_enabled := false
var _start_ocean_probe_elapsed := 0.0
var _start_ocean_probe_samples := 0
var _simulation_material_profile_id := ""
var _simulation_climate_profile_id := ""
var _surface_cache_pending: Dictionary = {}
var _surface_cache_jobs: Dictionary = {}
var _surface_cache_job_by_region: Dictionary = {}
var _surface_cache_retry_after_usec: Dictionary = {}
var _surface_cache_retry_counts: Dictionary = {}
var _surface_cache_repair_cursor := 0
var _surface_cache_visual_install_failures_total := 0
var _surface_cache_last_effect_revision := -1
var _surface_cache_dispatches_this_frame := 0
var _surface_cache_publications_total := 0
var _surface_cache_stale_discards_total := 0
var _surface_cache_snapshot_failures_total := 0
var _surface_cache_worker_failures_total := 0
var _simulation_streaming_status := "Simulation streaming unavailable"
var _simulation_persistence_status := "Simulation state not loaded"
var _simulation_persistence_blocked := false
var _simulation_store: RefCounted
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
# The default streaming path remains unchanged; adaptive is opt-in for A/B.
var _stream_profile := "baseline"
# DM2 visual-only experimental mesher. The authoritative field and saves stay SDF.
var _experimental_mesh_backend := "sdf"
# DM3-only derived 11x11 region visual shell; never added to active_regions.
var _dm3_shell_nodes: Dictionary = {}
var _dm3_shell_jobs: Dictionary = {}
var _dm3_shell_pending: Dictionary = {}
var _dm3_shell_retry_after_usec: Dictionary = {}
var _dm3_shell_order: Array[Vector2i] = []
var _dm3_retired_region_nodes: Dictionary = {}
var _dm3_last_scan_usec := 0
var _dm3_shell_seed := -1
var _dm3_shell_built := 0
var _dm3_shell_evicted := 0
var _dm3_shell_lod_promoted := 0
var _dm4_high_complete_focus := Vector2i(2147483647, 2147483647)
var _dm4_high_complete_receipts := 0
var _dm8_high_receipt_signature := ""
var _dm8_rock_receipt_signature := ""
var _dm8_radial_scan_count := 0
var _dm8_radial_scan_total_usec := 0
var _dm8_radial_scan_max_usec := 0
var _dm8_gap_first_requested_usec: Dictionary = {}
var _dm8_gap_sample_count := 0
# DM5 derived LOW decorators are independent of authoritative object/hydro scope.
var _dm5_decor_jobs: Dictionary = {}
var _dm5_decor_pending: Dictionary = {}
var _dm5_decor_nodes: Dictionary = {}
var _dm5_decor_retry_after_usec: Dictionary = {}
var _dm5_rock_mesh: SphereMesh
var _dm5_rock_material: StandardMaterial3D
var _dm5_water_material: StandardMaterial3D
var _dm5_cache_hits := 0
var _dm5_decor_published := 0
var _dm5_decor_evictions := 0
var _dm5_shell_regenerations := 0
var _dm6_retained_high_reused_total := 0
var _dm6_low_preview_prevented_total := 0
var _dm6_ttl_evicted_total := 0
var _dm6_last_memory_warning_usec := 0
var _dm6_outer_high_visible_count := 0
var _dm6_retained_high_visibility_repairs := 0
# DM7: exact HIGH mod-rock batch at terrain radius minus two (6 - 2 = 4).
# LOW water and all terrain high/cache behavior are deliberately unchanged.
const DM7_ROCK_HIGH_RADIUS := 4
const DM7_MAX_ROCK_JOBS_IN_FLIGHT := 1
var _dm7_rock_jobs: Dictionary = {}
var _dm7_rock_pending: Dictionary = {}
var _dm7_rock_retry_after_usec: Dictionary = {}
var _dm7_high_rock_publications := 0
var _dm7_high_rock_mesh_bytes := 0
var _dm7_rock_visible_count := 0
var _dm7_rock_high_completion_focus := Vector2i(2147483647, 2147483647)
var _dm7_rock_high_completion_receipts := 0
var _stream_budget_state: Dictionary = {"dispatch_limit": 1}
var _stream_window_started_usec := 0
var _stream_window_frames := 0
var _stream_window_boost_frames := 0
var _stream_window_frame_ms_sum := 0.0
var _stream_window_frame_ms_peak := 0.0
var _stream_window_frames_over_20_ms := 0
var _stream_window_frames_over_33_ms := 0
var _stream_window_work_over_16_ms := 0
var _stream_window_work_ms_sum := 0.0
var _stream_window_work_ms_peak := 0.0
var _stream_window_dispatches := 0
var _stream_window_uploads := 0
var _stream_window_stage_usec: Dictionary = {}
# DM12 opt-in main-thread frame attribution. Per-frame timings are never
# computed/printed during ordinary gameplay unless explicitly enabled.
var _dm12_trace_enabled := false
# DM16: isolated benchmark-only in-memory receipts work even when
# SANDBOX_PERF_TRACE=0. Neither mode prints inside the _process loop.
var _dm16_probe: RefCounted
var _dm16_light_stage := false
# DM18: opt-in revision-gated complete canonical mesh reuse.
var _dm18_cache: RefCounted = DM18CanonicalCache.new()
var _dm18_cache_enabled := false
var _dm18_diagnostic_enabled := false
var _dm18_focus_missing_visual_high := 0
var _dm18_focus_missing_cached := 0
var _dm18_focus_missing_total := 0
var _dm18_cache_restores := 0
var _dm18_restore_total_usec := 0
var _dm18_restore_max_usec := 0
var _dm18_cold_load_total_usec := 0
var _dm18_cold_loads := 0
var _dm18_hot_load_total_usec := 0
var _dm18_hot_loads := 0
var _dm18_job_times: Dictionary = {
	"jobs": 0, "snapshot_usec": 0, "worker_queue_usec": 0,
	"worker_run_usec": 0, "upload_usec": 0, "stale_jobs": 0
}
# DM19: profiling only, allocated exclusively for benchmark when explicitly enabled.
var _dm19_cold_profile: RefCounted

var _dm12_surface_slice := false
var _dm14_lazy_route_enabled := false
var _dm12_surface_prepare: Dictionary = {}
var _dm12_frame_id := 0
var _dm12_frame_stage_usec: Dictionary = {}
var _dm12_previous_stage_usec: Dictionary = {}
var _dm12_previous_receipt: Dictionary = {}
var _dm12_previous_process_usec := 0
var _dm12_publish_region_count := 0
var _dm12_publish_region_usec := 0
var _dm12_publish_region_max_usec := 0
var _dm12_visual_publish_count := 0
var _dm12_visual_publish_usec := 0
var _dm12_coarse_publish_count := 0
var _dm12_canonical_mesh_uploaded := 0
var _dm12_progressive_publish_count := 0
var _dm12_last_visual_publish_usec := 0
var _dm12_spike_trace_count := 0
var _dm12_spike_trace_limit := 600
var _stream_window_dispatch_blockers: Dictionary = {}
var _stream_window_skipped_load_stages := 0
var _stream_window_skipped_then_dispatched := 0
var _stream_window_skip_budget_exhausted := 0
var _last_f10_speed_mps := 0.0
var _stream_bench_route := ""
var _stream_bench_frames_goal := STREAM_BENCH_DEFAULT_FRAMES
var _stream_bench_warmup_remaining := 0
var _stream_bench_warmup_frames := 0
var _stream_bench_frames_done := 0
var _stream_bench_started_usec := 0
var _stream_bench_distance_m := 0.0
# DM17: opt-in wall-clock motion; never used by ordinary gameplay or DM16 baseline.
var _dm17_wallclock_route := false
var _dm17_previous_motion_usec := 0
var _dm17_motion_elapsed_sec := 0.0
var _stream_bench_reported := false
var _lookahead_stage_targets: Array[Vector2i] = []
var _lookahead_stage_signature := ""
var _last_reconciled_lookahead_signature := ""
var _dm9_prefetch_enabled := false
var _dm9_stages_started := 0
var _dm9_stages_ready := 0
var _dm9_stages_promoted := 0
var _dm9_stages_discarded := 0
var _dm9_ready_hits := 0
var _dm9_visual_worker_limit := 1
var _dm9_visual_worker_effective_limit := 1
var _dm9_visual_adaptive := false
var _dm9_fast_b4 := false
var _dm11_visual_dedicated := false
var _dm11_next_visual_task_id := -1
var _dm9_shell_started_total := 0
var _dm9_shell_completed_total := 0
var _lookahead_stage_begin_total := 0
var _stream_window_lookahead_stages := 0
var _stream_window_f10_frames := 0
var _stream_window_f10_focus_missing_frames := 0
var _stream_window_f10_region_gaps := 0
var _stream_window_f10_speed_peak_mps := 0.0
var _stream_window_f10_distance_m := 0.0
var _stream_window_f10_perceived_region_gaps := 0
var _stream_window_f10_coarse_covered_regions := 0
var _stream_window_f10_perceived_focus_missing_frames := 0
var _coarse_preview_jobs: Dictionary = {}
var _coarse_preview_nodes: Dictionary = {}
var _coarse_preview_attempts: Dictionary = {}
# E7: provisional visible nodes ONLY. Region/object/simulation authority remains
# exclusively at the original 16-chunk _publish_region commit.
var _progressive_chunk_nodes: Dictionary = {}
var _progressive_chunk_published_total := 0
var _progressive_chunk_revoked_total := 0
var _stream_window_progressive_published := 0
var _stream_window_coarse_published := 0
var _stream_window_coarse_replaced := 0
var _stream_window_coarse_discarded := 0
var _stream_window_coarse_worker_usec := 0
var _stream_window_coarse_publish_usec := 0

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
	if OS.get_environment("SANDBOX_DM19_COLD_DIAGNOSTIC") == "1" \
	and OS.get_environment("SANDBOX_STREAM_BENCHMARK") == "1":
		_dm19_cold_profile = DM19ColdAttribution.new()
	_dm18_cache_enabled = OS.get_environment("SANDBOX_DM18_CANONICAL_CACHE") == "1" \
		and OS.get_environment("SANDBOX_TERRAIN_BACKEND").strip_edges().to_lower() == "b4"
	_dm18_diagnostic_enabled = OS.get_environment("SANDBOX_DM18_DIAGNOSTIC") == "1" \
		and OS.get_environment("SANDBOX_STREAM_BENCHMARK") == "1"
	if OS.get_environment("SANDBOX_STREAM_BENCHMARK") == "1" \
	and OS.get_environment("SANDBOX_DM16_BENCH_METRICS") == "1":
		_dm16_probe = DM16BenchmarkProbe.new()
		_dm16_light_stage = not _perf_trace_enabled and \
			OS.get_environment("SANDBOX_DM16_LIGHT_STAGES") == "1"
	var requested_mesh_backend := OS.get_environment("SANDBOX_TERRAIN_BACKEND").strip_edges().to_lower()
	if requested_mesh_backend == "b4":
		_experimental_mesh_backend = "b4"
	elif requested_mesh_backend not in ["", "sdf"]:
		push_warning("DM2 unknown backend; using canonical SDF")
	print("DM2_TERRAIN_BACKEND=%s requested=%s" % [_experimental_mesh_backend, requested_mesh_backend])
	if _perf_trace_enabled:
		PerformanceTrace.emit("dm2_terrain_backend", {
			"backend": _experimental_mesh_backend,
			"requested": requested_mesh_backend,
			"authority": "sdf_unmodified",
			"lod_policy": "lod0_only" if _experimental_mesh_backend == "b4" else "canonical",
		})
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
	var stream_profile_env := OS.get_environment("SANDBOX_STREAM_PROFILE")
	var stream_profile_args := OS.get_cmdline_user_args()
	_stream_profile = StreamBudgetPolicy.resolve_profile(
		stream_profile_env, stream_profile_args
	)
	_dm9_prefetch_enabled = _dm3_enabled() and OS.get_environment("SANDBOX_DM9_PREFETCH") == "1"
	if _dm9_prefetch_enabled:
		print("DM9_CANONICAL_PREFETCH: enabled=1 hold_until_core=1 protected_radius=2 revision_gated=1")
	if _dm3_enabled() and OS.get_environment("SANDBOX_DM9_VISUAL_WORKERS").is_valid_int():
		_dm9_visual_worker_limit = clampi(int(OS.get_environment("SANDBOX_DM9_VISUAL_WORKERS")), 1, DM9VisualBudget.MAX_WORKERS)
	_dm9_visual_adaptive = _dm3_enabled() and OS.get_environment("SANDBOX_DM9_VISUAL_ADAPTIVE") == "1"
	_dm9_fast_b4 = _dm3_enabled() and OS.get_environment("SANDBOX_DM9_FAST_B4") == "1"
	_dm12_trace_enabled = _perf_trace_enabled and OS.get_environment("SANDBOX_DM12_FRAME_TRACE") == "1"
	if _dm12_trace_enabled:
		print("DM12_FRAME_TRACE: enabled=1 per_frame_stage=1 previous_frame_delta=1 publication_correlation=1")
	_dm12_surface_slice = _dm3_enabled() and OS.get_environment("SANDBOX_DM12_SURFACE_SLICE") == "1"
	_dm14_lazy_route_enabled = OS.get_environment("SANDBOX_DM14_LAZY_ROUTES") == "1"
	if _dm12_surface_slice:
		print("DM12_SURFACE_SLICE: enabled=1 immutable_snapshot_chunk_batch=3 revision_gated=1")
	_dm11_visual_dedicated = _dm3_enabled() and OS.get_environment("SANDBOX_DM11_VISUAL_LANE") == "1"
	if _dm11_visual_dedicated:
		print("DM11_VISUAL_LANE: isolated_native_threads=1 priority=low canonical_worker_pool_unchanged=1")
	if _dm9_fast_b4:
		print("DM9_FAST_B4: enabled=1 pristine_visual_only=1 authoritative_backend_unchanged=1")
	if _dm9_visual_adaptive:
		print("DM9_VISUAL_ADAPTIVE: enabled=1 max_workers=%d core_missing_or_loading=1 moving_limit=1 idle_max=4" % _dm9_visual_worker_limit)
	if _dm9_visual_worker_limit > 1:
		print("DM9_VISUAL_WORKERS: limit=%d old_limit=1 visual_only=1" % _dm9_visual_worker_limit)
	if _dm3_enabled():
		print("DM6_REGION_STREAM: radius=6 high_all=1 b4_sample_step=0.5 retention_radius=10 retention_seconds=20 eviction=ttl_only no_low_downgrade=1")
		print("DM7_ROCK_STREAM: high_radius=4 terrain_high_radius=6 low_water_unchanged=1 mod_geometry_exact=1 visual_only=1")
		print("DM8_RADIAL_STREAM: terrain_m=130 rock_m=90 retain_m=210 player_world_xz=1 diagonal_coverage_preserved=1 retention_seconds=20")
		if _perf_trace_enabled:
			PerformanceTrace.emit("dm4_region_stream_mode", {
				"radius_regions": DM3Policy.ACTIVE_RADIUS,
				"high_through_regions": DM3Policy.ACTIVE_RADIUS,
				"low_from_regions": -1,
				"backend": "b4",
				"mesh_step_m": 0.5,
				"priority": "strict_distance_then_forward",
				"retention_radius_regions": 10,
				"retention_seconds": 20,
				"authority_window_unchanged": true,
			})
	var stream_profile_requested := stream_profile_env.strip_edges().to_lower()
	for argument in stream_profile_args:
		if argument.begins_with("--stream-profile="):
			stream_profile_requested = argument.trim_prefix("--stream-profile=").strip_edges().to_lower()
	if stream_profile_requested not in ["", "baseline", "adaptive", "adaptive-skip", "adaptive-skip-lookahead", "adaptive-skip-coarse", "adaptive-skip-progressive"]:
		push_warning("Unknown stream profile; using baseline")
	if _perf_trace_enabled:
		PerformanceTrace.emit("terrain_stream_profile", {
			"profile": _stream_profile,
			"requested_profile": stream_profile_requested,
			"profile_mismatch": stream_profile_requested != "" and stream_profile_requested != _stream_profile,
			"mesh_dispatch_baseline": MAX_MESH_JOB_DISPATCHES_PER_FRAME,
			"mesh_dispatch_adaptive_max": StreamBudgetPolicy.ADAPTIVE_DISPATCHES,
			"f10_lookahead_seconds": StreamLookaheadPolicy.LOOKAHEAD_SECONDS if _stream_profile == "adaptive-skip-lookahead" else 0.0,
			"mesh_jobs_in_flight_limit": _mesh_job_limit,
			"mesh_upload_limit": MAX_MESH_UPLOADS_PER_FRAME,
			"dm9_prefetch_enabled": _dm9_prefetch_enabled,
			"dm9_visual_worker_limit": _dm9_visual_worker_limit,
			"dm9_visual_adaptive": _dm9_visual_adaptive,
			"dm9_fast_b4": _dm9_fast_b4,
			"dm11_visual_dedicated": _dm11_visual_dedicated,
			"dm12_surface_slice": _dm12_surface_slice,
			"dm11_canonical_fast_b4": OS.get_environment("SANDBOX_DM11_CANONICAL_FAST_B4") == "1",
			"snapshot_budget_usec": MESH_SNAPSHOT_FRAME_BUDGET_USEC,
			"upload_budget_usec": MESH_UPLOAD_FRAME_BUDGET_USEC,
		})
	# Deterministic benchmark mode is inert without the dedicated CI opt-in.
	if OS.get_environment("SANDBOX_STREAM_BENCHMARK") == "1":
		_dm17_wallclock_route = OS.get_environment("SANDBOX_DM17_WALLCLOCK_ROUTE") == "1"
		for argument in stream_profile_args:
			if argument.begins_with("--stream-benchmark-route="):
				_stream_bench_route = argument.trim_prefix("--stream-benchmark-route=").strip_edges().to_lower()
			elif argument.begins_with("--stream-benchmark-frames="):
				_stream_bench_frames_goal = int(argument.trim_prefix("--stream-benchmark-frames="))
			elif argument.begins_with("--stream-benchmark-warmup-frames="):
				_stream_bench_warmup_frames = int(
					argument.trim_prefix("--stream-benchmark-warmup-frames=")
				)
				_stream_bench_warmup_remaining = _stream_bench_warmup_frames
		if not _stream_bench_route.is_empty():
			if _stream_bench_route not in ["idle", "straight-18", "straight-54", "outback-18", "outback-54"] \
			or _stream_bench_frames_goal < 120 or _stream_bench_frames_goal > 18000 \
			or _stream_bench_warmup_frames < 0 or _stream_bench_warmup_frames > 12000:
				push_error("P5_STREAM_BENCH_INVALID_ROUTE_OR_FRAMES")
				get_tree().quit(2)
				return
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

	_apply_startup_location()
	_material_content_domain = MaterialEnvironmentDomainScript.new()
	_climate_content_domain = EnvironmentClimateDomainScript.new()
	var material_handlers: Array[RefCounted] = [
		_material_content_domain.create_content_handler(),
		_climate_content_domain.create_content_handler(),
	]
	# The playable scene opts into the bundled climate preset. Generic P4
	# consumers keep their historical first-party-only discovery contract.
	var playable_roots: Array[String] = object_package_roots_override.duplicate()
	if playable_roots.is_empty():
		var mod_root := ProjectSettings.globalize_path("user://mods")
		var root_created := DirAccess.make_dir_recursive_absolute(mod_root)
		if root_created == OK or root_created == ERR_ALREADY_EXISTS:
			playable_roots = [
				"res://mods/first-party",
				"res://mods/environment-presets",
				"user://mods",
			]
	var object_initialization: Dictionary = object_stream.initialize(
		world_seed,
		world_id,
		playable_roots,
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
	_environment_visual = EnvironmentVisualScript.new()
	_environment_visual.name = "EnvironmentVisuals"
	add_child(_environment_visual)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--p5-water-debug="):
			var diagnostic_mode := argument.trim_prefix("--p5-water-debug=")
			if _environment_visual.set_water_debug_mode(diagnostic_mode):
				print("P5_WATER_DEBUG_MODE: %s" % diagnostic_mode)
			else:
				push_warning("P5_WATER_DEBUG_INVALID: %s (normal mode retained)" % diagnostic_mode)
	if not _simulation_persistence_blocked:
		_configure_simulation_streaming()
	_configure_environment_visual()
	_create_placement_target_marker()
	terrain_mesh_template.mesh = null
	terrain_mesh_template.visible = false
	_begin_operation("initial_load")
	_update_camera()
	if not _stream_bench_route.is_empty():
		# Pinned world-space camera start, direction and seed. No input capture.
		Engine.max_fps = 60
		camera.global_position = STREAM_BENCH_START
		camera.rotation = Vector3(-0.2, 0.0, 0.0)
		orbit_target = camera.global_position
		free_explore_enabled = true
		_free_explore_yaw = 0.0
		_free_explore_pitch = -0.2
		_stream_bench_started_usec = Time.get_ticks_usec()
		print("P5_STREAM_BENCH_START: " + JSON.stringify({
			"route": _stream_bench_route,
			"frames": _stream_bench_frames_goal,
			"profile": _stream_profile,
			"seed": world_seed,
			"start": [STREAM_BENCH_START.x, STREAM_BENCH_START.y, STREAM_BENCH_START.z],
		}))
	_reconcile_region_window(true)
	_update_status()


func _apply_startup_location() -> void:
	var selection: Dictionary = EnvironmentStartupLocation.select_from_args(
		OS.get_cmdline_user_args(), world_seed
	)
	if not selection.get("ok", false):
		_startup_location_status = "START_LOCATION_INVALID: %s (default focus retained)" % selection.get("reason", "unknown")
		push_warning(_startup_location_status)
		print(_startup_location_status)
		return
	if String(selection.get("mode", "default")) == "default":
		return
	orbit_target = selection["target"]
	var start_region: Vector2i = selection["region"]
	_startup_location_status = (
		"P5_START_LOCATION: mode=%s region=(%d,%d) world_target=(%.2f,%.2f,%.2f) "
		+ "base_sdf_ocean_cells=%d seed=%d"
	) % [
		String(selection["mode"]), start_region.x, start_region.y,
		orbit_target.x, orbit_target.y, orbit_target.z,
		int(selection.get("candidate_water_cells", -1)), world_seed
	]
	print(_startup_location_status)
	if String(selection["mode"]) == "ocean":
		_start_ocean_probe_enabled = true
		print("P5_START_WATER_NOTE: base SDF eligibility only; live water requires hydrology binding and current terrain cache")


func _probe_start_ocean_visual(delta: float) -> void:
	if _start_ocean_probe_samples >= 30:
		_start_ocean_probe_enabled = false
		return
	_start_ocean_probe_elapsed += maxf(0.0, delta)
	if _start_ocean_probe_elapsed < 2.0:
		return
	_start_ocean_probe_elapsed = 0.0
	_start_ocean_probe_samples += 1
	var profile_count := -1
	if is_instance_valid(object_stream) and object_stream.registry != null:
		profile_count = object_stream.registry.get_content_record_ids(
			EnvironmentClimateDomainScript.PROFILE_TYPE
		).size()
	var climate_enabled := false
	var hydrology_enabled := false
	var environmental_state: Dictionary = {}
	var surface_cache: Dictionary = {}
	var scope_id := _surface_cache_scope_id(focus_region_key)
	if is_instance_valid(simulation_runtime) and simulation_runtime.initialized:
		climate_enabled = simulation_runtime.has_environment_climate()
		hydrology_enabled = simulation_runtime.has_environment_hydrology()
		environmental_state = simulation_runtime.get_environment_scope(scope_id)
		surface_cache = simulation_runtime.get_environment_surface_cache(scope_id)
	var ocean_cells := 0
	var kinds: PackedByteArray = environmental_state.get("reservoir_kind", PackedByteArray())
	for kind in kinds:
		if int(kind) == 2:
			ocean_cells += 1
	var visible_triangles := 0
	if is_instance_valid(_environment_visual):
		var water_node := _environment_visual.get_node_or_null(
			"Water_%d_%d" % [focus_region_key.x, focus_region_key.y]
		) as MeshInstance3D
		if water_node != null and water_node.visible and water_node.mesh != null:
			visible_triangles = water_node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() / 3
	var ready := ocean_cells > 0 and visible_triangles > 0
	var metrics: Dictionary = _environment_visual.get_visual_metrics() if is_instance_valid(_environment_visual) else {}
	var status_label_text := "P5_WATER_READY" if ready else "P5_WATER_DIAG"
	print("%s: region=%s candidate=%s profiles=%d climate=%s hydrology=%s scope=%s cache=%s ocean_cells=%d visible_triangles=%d debug=%s halo_cells=%d ocean_sdf_tiles=%d ocean_seam_edges=%d refined_quads=%d state_revision=%d status=%s" % [
		status_label_text,
		str(focus_region_key),
		str(_startup_location_status),
		profile_count,
		str(climate_enabled),
		str(hydrology_enabled),
		str(not environmental_state.is_empty()),
		str(not surface_cache.is_empty()),
		ocean_cells,
		visible_triangles,
		String(metrics.get("water_debug_mode", "normal")),
		int(metrics.get("visible_coastal_halo_cells", 0)),
		int(metrics.get("visible_ocean_sdf_tiles", 0)),
		int(metrics.get("visible_ocean_seam_edges", 0)),
		int(metrics.get("visible_refined_coast_quads", 0)),
		int(environmental_state.get("state_revision", -1)),
		_simulation_streaming_status,
	])
	if ready:
		_start_ocean_probe_enabled = false


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

	var validator: Node = SimulationRuntimeScript.new()
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
	if content_validation.get("ok", false):
		content_validation = validator.validate_environment_climate_content(
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
	if content_validation.get("ok", false):
		content_validation = simulation_runtime.validate_environment_climate_content(
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
	_simulation_climate_profile_id = ""
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

		var climate_profile_ids: Array[String] = object_stream.registry.get_content_record_ids(
			EnvironmentClimateDomainScript.PROFILE_TYPE
		)
		if climate_profile_ids.size() == 1:
			var climate_profile_id := String(climate_profile_ids[0])
			var climate_config: Dictionary = simulation_runtime.configure_environment_climate(
				object_stream.registry, climate_profile_id
			)
			if climate_config.get("ok", false):
				_simulation_climate_profile_id = climate_profile_id
				var runoff_config: Dictionary = simulation_runtime.configure_environment_runoff(
					object_stream.registry, climate_profile_id
				)
				if runoff_config.get("ok", false):
					var hydrology_config: Dictionary = simulation_runtime.configure_environment_hydrology(
						world_seed, Field.GENERATOR_VERSION
					)
					if not hydrology_config.get("ok", false):
						_simulation_streaming_status = "World hydrology unavailable (%s)" % hydrology_config.get("reason", "unknown")
				else:
					_simulation_streaming_status = "Runoff simulation unavailable (%s)" % runoff_config.get("reason", "unknown")
			else:
				_simulation_streaming_status = "Climate simulation unavailable (%s)" % climate_config.get("reason", "unknown")
		elif climate_profile_ids.size() > 1:
			_simulation_streaming_status = "Climate simulation awaiting explicit profile selection (%d profiles)" % climate_profile_ids.size()

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
	_configure_environment_visual()


func _configure_environment_visual() -> void:
	if not is_instance_valid(_environment_visual):
		return
	var profile: Dictionary = {}
	var sha := ""
	if (
		is_instance_valid(simulation_runtime)
		and simulation_runtime.has_environment_climate()
		and object_stream.registry != null
		and not _simulation_climate_profile_id.is_empty()
	):
		profile = object_stream.registry.get_content_record(
			EnvironmentClimateDomainScript.PROFILE_TYPE, _simulation_climate_profile_id
		)
		var pin: Dictionary = simulation_runtime.environment_climate_domain.get_bound_profile_pin(
			_simulation_climate_profile_id
		)
		sha = String(pin.get("profile_sha256", ""))
	_environment_visual.configure_environment(simulation_runtime, profile, sha)


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
	# Dedicated visual threads are reference-counted and must be joined before
	# releasing their job objects. Legacy WorkerThreadPool visual jobs also
	# finish before scene teardown; no callbacks access a freed world.
	for id_value in _dm3_shell_jobs.keys().duplicate():
		var id := int(id_value)
		var record: Dictionary = _dm3_shell_jobs[id]
		var native_thread: Thread = record.get("thread", null)
		if native_thread != null:
			native_thread.wait_to_finish()
		else:
			WorkerThreadPool.wait_for_task_completion(id)
	_dm3_shell_jobs.clear()
	_dm3_shell_pending.clear()
	for task_id_value in _coarse_preview_jobs.keys().duplicate():
		WorkerThreadPool.wait_for_task_completion(int(task_id_value))
	_coarse_preview_jobs.clear()
	if _checkpoint_task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_checkpoint_task_id)
		_checkpoint_task_id = -1
		_checkpoint_job = null


## Once/second aggregation avoids introducing a per-frame logging bottleneck.
## Stage timing is passive in baseline and adaptive runs.
func _stream_dispatch_blocked(reason: String) -> void:
	if _dm19_cold_profile != null:
		_dm19_cold_profile.blocked(reason)
	if not _perf_trace_enabled:
		return
	_stream_window_dispatch_blockers[reason] = int(_stream_window_dispatch_blockers.get(reason, 0)) + 1


func _stream_stage_measure(stage: String, started_usec: int) -> void:
	if not _perf_trace_enabled and not _dm16_light_stage:
		return
	var elapsed := maxi(0, Time.get_ticks_usec() - started_usec)
	if _perf_trace_enabled:
		_stream_window_stage_usec[stage] = int(_stream_window_stage_usec.get(stage, 0)) + elapsed
		if _dm12_trace_enabled:
			_dm12_frame_stage_usec[stage] = int(_dm12_frame_stage_usec.get(stage, 0)) + elapsed
	if _dm16_light_stage and _dm16_probe != null:
		_dm16_probe.record_stage(stage, elapsed)



func _dm12_stage(stage: String, started_usec: int) -> void:
	if not _dm12_trace_enabled:
		return
	_dm12_frame_stage_usec[stage] = int(
		_dm12_frame_stage_usec.get(stage, 0)
	) + maxi(0, Time.get_ticks_usec() - started_usec)


func _dm12_emit_frame_if_spike(started_usec: int) -> void:
	if not _dm12_trace_enabled:
		return
	var finished_usec := Time.get_ticks_usec()
	var process_usec := maxi(0, finished_usec - started_usec)
	var delta_spike := _last_frame_ms >= 33.0
	var work_spike := process_usec >= 14_000
	if (delta_spike or work_spike) and _dm12_spike_trace_count < _dm12_spike_trace_limit:
		_dm12_spike_trace_count += 1
		var accounted_usec := 0
		for stage_name_value in _dm12_frame_stage_usec.keys():
			var stage_name := String(stage_name_value)
			# mesh_* stages are nested inside mesh_dispatch_and_upload.
			if stage_name.begins_with("mesh_") and stage_name != "mesh_dispatch_and_upload":
				continue
			accounted_usec += int(_dm12_frame_stage_usec[stage_name])
		PerformanceTrace.emit("dm12_frame_attribution", {
			"frame_id": _dm12_frame_id,
			"delta_previous_frame_ms": _last_frame_ms,
			"current_process_usec": process_usec,
			"prior_process_usec": _dm12_previous_process_usec,
			"stages_usec": _dm12_frame_stage_usec.duplicate(),
			"prior_stages_usec": _dm12_previous_stage_usec.duplicate(),
			"prior_publication_counts": _dm12_previous_receipt.duplicate(),
			"stage_sum_usec": accounted_usec,
			"unaccounted_current_usec": maxi(0, process_usec - accounted_usec),
			"canonical_regions_committed": _dm12_publish_region_count,
			"canonical_publish_total_usec": _dm12_publish_region_usec,
			"canonical_publish_max_usec": _dm12_publish_region_max_usec,
			"canonical_chunk_uploads": _dm12_canonical_mesh_uploaded,
			"progressive_chunks_published": _dm12_progressive_publish_count,
			"visual_high_regions_published": _dm12_visual_publish_count,
			"visual_high_publish_total_usec": _dm12_visual_publish_usec,
			"coarse_previews_published": _dm12_coarse_publish_count,
			"mesh_jobs_in_flight": _mesh_jobs.size(),
			"visual_jobs_in_flight": _dm3_shell_jobs.size(),
			"loading_regions": loading_regions.size(),
			"active_regions": active_regions.size(),
			"focus": [focus_region_key.x, focus_region_key.y],
			"speed_mps": _last_f10_speed_mps,
			"trace_emitted": _dm12_spike_trace_count,
			"delta_is_previous_frame": true,
			"current_process_wall_only": true,
		})
	_dm12_previous_stage_usec = _dm12_frame_stage_usec.duplicate()
	_dm12_previous_process_usec = process_usec
	_dm12_previous_receipt = {
		"canonical_regions_committed": _dm12_publish_region_count,
		"canonical_publish_total_usec": _dm12_publish_region_usec,
		"canonical_chunk_uploads": _dm12_canonical_mesh_uploaded,
		"progressive_chunks_published": _dm12_progressive_publish_count,
		"visual_high_regions_published": _dm12_visual_publish_count,
		"visual_high_publish_total_usec": _dm12_visual_publish_usec,
		"coarse_previews_published": _dm12_coarse_publish_count,
	}


func _stream_finish_frame() -> void:
	if not _perf_trace_enabled:
		return
	var now := Time.get_ticks_usec()
	if _stream_window_started_usec == 0:
		_stream_window_started_usec = now
	_stream_window_frames += 1
	_stream_window_frame_ms_sum += _last_frame_ms
	_stream_window_work_ms_sum += _last_process_work_ms
	_stream_window_frame_ms_peak = maxf(_stream_window_frame_ms_peak, _last_frame_ms)
	_stream_window_work_ms_peak = maxf(_stream_window_work_ms_peak, _last_process_work_ms)
	if _last_frame_ms > 20.0:
		_stream_window_frames_over_20_ms += 1
	if _last_frame_ms > 33.0:
		_stream_window_frames_over_33_ms += 1
	if _last_process_work_ms > 16.0:
		_stream_window_work_over_16_ms += 1
	_stream_window_dispatches += _mesh_dispatches_this_frame
	_stream_window_uploads += _mesh_uploads_this_frame
	if free_explore_enabled and _last_f10_speed_mps > 0.01:
		_stream_window_f10_frames += 1
		_stream_window_f10_speed_peak_mps = maxf(
			_stream_window_f10_speed_peak_mps, _last_f10_speed_mps
		)
		_stream_window_f10_distance_m += _last_f10_speed_mps * maxf(0.0, _last_frame_ms) / 1000.0
		if not active_regions.has(_region_id(focus_region_key)):
			_stream_window_f10_focus_missing_frames += 1
			if not _coarse_preview_nodes.has(_region_id(focus_region_key)):
				_stream_window_f10_perceived_focus_missing_frames += 1
		for region in _region_keys_within_radius(focus_region_key, REQUEST_RADIUS):
			if not active_regions.has(_region_id(region)):
				_stream_window_f10_region_gaps += 1
				if _coarse_preview_nodes.has(_region_id(region)):
					_stream_window_f10_coarse_covered_regions += 1
				else:
					_stream_window_f10_perceived_region_gaps += 1
	if int(_stream_budget_state.get("dispatch_limit", 1)) > 1:
		_stream_window_boost_frames += 1
	if now - _stream_window_started_usec < STREAM_BUDGET_TRACE_INTERVAL_USEC:
		return
	var effect_pending := 0
	if terrain_effect_runtime != null and bool(terrain_effect_runtime.get("initialized")):
		effect_pending = int(terrain_effect_runtime.get_prefetch_pending_count())
	PerformanceTrace.emit("terrain_stream_budget_window", {
		"profile": _stream_profile,
		"frame_count": _stream_window_frames,
		"boosted_frames": _stream_window_boost_frames,
		"frame_mean_ms": _stream_window_frame_ms_sum / maxf(1.0, float(_stream_window_frames)),
		"frame_peak_ms": _stream_window_frame_ms_peak,
		"frames_over_20_ms": _stream_window_frames_over_20_ms,
		"frames_over_33_ms": _stream_window_frames_over_33_ms,
		"process_frames_over_16_ms": _stream_window_work_over_16_ms,
		"process_mean_ms": _stream_window_work_ms_sum / maxf(1.0, float(_stream_window_frames)),
		"process_peak_ms": _stream_window_work_ms_peak,
		"mesh_dispatches": _stream_window_dispatches,
		"mesh_uploads": _stream_window_uploads,
		"mesh_jobs_in_flight": _mesh_jobs.size(),
		"loading_regions": loading_regions.size(),
		"effect_prefetch_pending": effect_pending,
		"dm9_prefetch_enabled": _dm9_prefetch_enabled,
		"dm9_speculative_stages": _dm9_count_speculative(false),
		"dm9_ready_stages": _dm9_count_speculative(true),
		"dm9_visual_worker_limit": _dm9_visual_worker_limit,
		"dm9_visual_worker_effective_limit": _dm9_visual_worker_effective_limit,
		"dm9_visual_adaptive": _dm9_visual_adaptive,
		"dm9_fast_b4": _dm9_fast_b4,
		"dm11_visual_dedicated": _dm11_visual_dedicated,
		"dm12_surface_slice": _dm12_surface_slice,
		"dm11_canonical_fast_b4": OS.get_environment("SANDBOX_DM11_CANONICAL_FAST_B4") == "1",
		"dm9_visual_workers_in_flight": _dm3_shell_jobs.size(),
		"dm9_visual_started_total": _dm9_shell_started_total,
		"dm9_visual_completed_total": _dm9_shell_completed_total,
		"dm9_prefetch_started_total": _dm9_stages_started,
		"dm9_prefetch_ready_total": _dm9_stages_ready,
		"dm9_prefetch_promoted_total": _dm9_stages_promoted,
		"dm9_prefetch_hit_total": _dm9_ready_hits,
		"dm9_prefetch_discarded_total": _dm9_stages_discarded,
		"surface_jobs_in_flight": _surface_cache_jobs.size(),
		"mesh_limit": int(_stream_budget_state.get("dispatch_limit", 1)),
		"reason": String(_stream_budget_state.get("reason", "baseline")),
		"stage_work_usec": _stream_window_stage_usec.duplicate(true),
		"mesh_dispatch_blockers": _stream_window_dispatch_blockers.duplicate(true),
		"effect_pending_load_skips": _stream_window_skipped_load_stages,
		"successful_dispatch_after_skip": _stream_window_skipped_then_dispatched,
		"skip_time_budget_exhausted": _stream_window_skip_budget_exhausted,
		"f10_movement_frames": _stream_window_f10_frames,
		"f10_focus_missing_frames": _stream_window_f10_focus_missing_frames,
		"f10_missing_regions_in_window_total": _stream_window_f10_region_gaps,
		"f10_perceived_missing_regions_total": _stream_window_f10_perceived_region_gaps,
		"f10_coarse_covered_region_samples": _stream_window_f10_coarse_covered_regions,
		"f10_perceived_focus_missing_frames": _stream_window_f10_perceived_focus_missing_frames,
		"f10_peak_speed_mps": _stream_window_f10_speed_peak_mps,
		"f10_distance_m": _stream_window_f10_distance_m,
		"f10_predictive_stages_started": _stream_window_lookahead_stages,
		"coarse_preview_published": _stream_window_coarse_published,
		"coarse_preview_replaced": _stream_window_coarse_replaced,
		"coarse_preview_discarded": _stream_window_coarse_discarded,
		"coarse_preview_visible": _coarse_preview_nodes.size(),
		"coarse_preview_jobs_in_flight": _coarse_preview_jobs.size(),
		"progressive_chunks_visible": _progressive_visible_chunk_count(),
		"progressive_chunks_published": _stream_window_progressive_published,
		"coarse_preview_worker_usec": _stream_window_coarse_worker_usec,
		"coarse_preview_publish_usec": _stream_window_coarse_publish_usec,
	})
	_stream_window_started_usec = now
	_stream_window_frames = 0
	_stream_window_boost_frames = 0
	_stream_window_frame_ms_sum = 0.0
	_stream_window_frame_ms_peak = 0.0
	_stream_window_frames_over_20_ms = 0
	_stream_window_frames_over_33_ms = 0
	_stream_window_work_over_16_ms = 0
	_stream_window_work_ms_sum = 0.0
	_stream_window_work_ms_peak = 0.0
	_stream_window_dispatches = 0
	_stream_window_uploads = 0
	_stream_window_stage_usec.clear()
	_stream_window_dispatch_blockers.clear()
	_stream_window_skipped_load_stages = 0
	_stream_window_skipped_then_dispatched = 0
	_stream_window_skip_budget_exhausted = 0
	_stream_window_f10_frames = 0
	_stream_window_f10_focus_missing_frames = 0
	_stream_window_f10_region_gaps = 0
	_stream_window_f10_perceived_region_gaps = 0
	_stream_window_f10_coarse_covered_regions = 0
	_stream_window_f10_perceived_focus_missing_frames = 0
	_stream_window_f10_speed_peak_mps = 0.0
	_stream_window_f10_distance_m = 0.0
	_stream_window_lookahead_stages = 0
	_stream_window_coarse_published = 0
	_stream_window_progressive_published = 0
	_stream_window_coarse_replaced = 0
	_stream_window_coarse_discarded = 0
	_stream_window_coarse_worker_usec = 0
	_stream_window_coarse_publish_usec = 0


func _process(delta: float) -> void:
	var process_started_usec := Time.get_ticks_usec()
	if _dm12_trace_enabled:
		_dm12_frame_id += 1
		_dm12_frame_stage_usec.clear()
		_dm12_publish_region_count = 0
		_dm12_publish_region_usec = 0
		_dm12_publish_region_max_usec = 0
		_dm12_visual_publish_count = 0
		_dm12_visual_publish_usec = 0
		_dm12_coarse_publish_count = 0
		_dm12_canonical_mesh_uploaded = 0
		_dm12_progressive_publish_count = 0
	_process_pending_simulation_save()
	_mesh_uploads_this_frame = 0
	_mesh_dispatches_this_frame = 0
	_surface_cache_dispatches_this_frame = 0
	_last_frame_ms = maxf(delta * 1000.0, 0.0)
	var previous_dispatch_limit := int(_stream_budget_state.get("dispatch_limit", 1))
	_stream_budget_state = StreamBudgetPolicy.next(
		_stream_budget_state, _last_frame_ms, _last_process_work_ms,
		_stream_profile in ["adaptive", "adaptive-skip", "adaptive-skip-lookahead", "adaptive-skip-coarse", "adaptive-skip-progressive"]
	)
	if _perf_trace_enabled and int(_stream_budget_state["dispatch_limit"]) != previous_dispatch_limit:
		PerformanceTrace.emit("terrain_stream_budget_transition", {
			"profile": _stream_profile,
			"previous_limit": previous_dispatch_limit,
			"new_limit": int(_stream_budget_state["dispatch_limit"]),
			"reason": String(_stream_budget_state["reason"]),
			"frame_ms": _last_frame_ms,
			"previous_process_ms": _last_process_work_ms,
			"cooldown_frames": int(_stream_budget_state["cooldown_frames"]),
		})
	if _frame_time_samples.size() == 512:
		_frame_time_samples[_frame_sample_write_index] = _last_frame_ms
		_frame_sample_write_index = (_frame_sample_write_index + 1) % 512
		_frame_sample_count = mini(_frame_sample_count + 1, 512)
	_peak_frame_ms = maxf(_peak_frame_ms, _last_frame_ms)
	var camera_before_motion := camera.global_position
	if free_explore_enabled:
		_process_free_exploration(delta)
	var f10_motion := camera.global_position - camera_before_motion
	f10_motion.y = 0.0
	_last_f10_speed_mps = (
		f10_motion.length() / maxf(delta, 0.000001)
		if free_explore_enabled else 0.0
	)
	var stream_preflight_started_usec := Time.get_ticks_usec()
	_dm12_stage("pre_stream", process_started_usec)
	_update_focus_key()
	# R3's speculative stage strip is derived entirely from the F10 camera.
	# It is never authoritative, never extends beyond the existing retained 5x5
	# terrain window, and remains lower-priority than the visible 3x3.
	var mapped_ahead: Dictionary = {}
	if (_stream_profile == "adaptive-skip-lookahead" or _dm9_prefetch_enabled) \
	and free_explore_enabled and _last_f10_speed_mps > 0.01:
		var velocity := f10_motion / maxf(delta, 0.000001)
		var horizon_seconds := DM9PrefetchPolicy.HORIZON_SECONDS if _dm9_prefetch_enabled else StreamLookaheadPolicy.LOOKAHEAD_SECONDS
		var ahead_position := camera.global_position + velocity * horizon_seconds
		mapped_ahead = SpatialGrid.world_to_region_local(ahead_position)
		if _dm9_prefetch_enabled:
			_lookahead_stage_targets = DM9PrefetchPolicy.targets(focus_region_key, camera.global_position, velocity)
		elif mapped_ahead.get("valid", false):
			_lookahead_stage_targets = StreamLookaheadPolicy.forward_stage_targets(
				focus_region_key, mapped_ahead["region_key"]
			)
		_lookahead_stage_signature = str(_lookahead_stage_targets)
	elif not free_explore_enabled or _last_f10_speed_mps <= 0.01 or (_stream_profile != "adaptive-skip-lookahead" and not _dm9_prefetch_enabled):
		_lookahead_stage_targets.clear()
		_lookahead_stage_signature = ""
	_reconcile_region_window()
	# Effect projection prefetch reuses the same protected 9x9 source halo and
	# respects urgent prerequisites queued by visible mesh work.
	if not mapped_ahead.is_empty() and mapped_ahead.get("valid", false) \
	and terrain_effect_runtime != null \
	and bool(terrain_effect_runtime.get("initialized")):
		terrain_effect_runtime.prioritize_prefetch_for_motion(
			focus_region_key, mapped_ahead["region_key"]
		)
	_stream_stage_measure("focus_window_lookahead", stream_preflight_started_usec)
	stream_preflight_started_usec = Time.get_ticks_usec()
	_update_lod_selection()
	_stream_stage_measure("lod_selection", stream_preflight_started_usec)
	if _checkpoint_task_id >= 0 and (global_rebuild_pending or not loading_regions.is_empty()):
		_checkpoint_overlap_observed = true
	_process_async_checkpoint()
	_maybe_schedule_async_checkpoint()
	var stream_stage_started_usec := Time.get_ticks_usec()
	if _dm14_lazy_route_enabled and terrain_effect_runtime != null \
	and bool(terrain_effect_runtime.get("initialized")):
		var cleanup_result: Dictionary = terrain_effect_runtime.process_route_cleanup_step(24, 1200)
		if not cleanup_result.get("ok", false):
			_record_stream_error("_dm14_effect_route_cleanup",
				String(cleanup_result.get("reason", "unknown")))
	_stream_stage_measure("effect_route_cleanup", stream_stage_started_usec)
	stream_stage_started_usec = Time.get_ticks_usec()
	if terrain_effect_runtime != null and bool(terrain_effect_runtime.get("initialized")):
		var prefetch_result: Dictionary = terrain_effect_runtime.process_prefetch_step(1)
		if not prefetch_result.get("ok", false):
			_terrain_effect_status = "Terrain-object effects unavailable (%s)" % prefetch_result.get("reason", "unknown")
			_record_stream_error("_terrain_effect_prefetch", _terrain_effect_status)
	_stream_stage_measure("effect_prefetch", stream_stage_started_usec)
	stream_stage_started_usec = Time.get_ticks_usec()
	_process_one_chunk_job()
	_stream_stage_measure("mesh_dispatch_and_upload", stream_stage_started_usec)
	stream_stage_started_usec = Time.get_ticks_usec()
	if _stream_profile in ["adaptive-skip-coarse", "adaptive-skip-progressive"]:
		_process_coarse_previews()
	_stream_stage_measure("coarse_preview", stream_stage_started_usec)
	stream_stage_started_usec = Time.get_ticks_usec()
	if _dm3_enabled():
		_dm3_process_shells()
	_stream_stage_measure("dm3_visual_shell", stream_stage_started_usec)
	stream_stage_started_usec = Time.get_ticks_usec()
	object_stream.process_queued_publications()
	_stream_stage_measure("object_publication", stream_stage_started_usec)
	stream_stage_started_usec = Time.get_ticks_usec()
	_process_surface_cache_jobs()
	_stream_stage_measure("sdf_cache", stream_stage_started_usec)
	stream_stage_started_usec = Time.get_ticks_usec()
	if is_instance_valid(_environment_visual):
		_environment_visual.process_visual_frame(delta, camera.global_position, focus_region_key)
	_stream_stage_measure("water_visual", stream_stage_started_usec)
	if _start_ocean_probe_enabled:
		_probe_start_ocean_visual(delta)
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
	var dm12_finalize_started_usec := Time.get_ticks_usec()
	_stream_finish_frame()
	_dm12_stage("frame_accounting", dm12_finalize_started_usec)
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
		var dm12_diagnostics_started_usec := Time.get_ticks_usec()
		_update_runtime_diagnostics()
		_update_status()
		_dm12_stage("diagnostics", dm12_diagnostics_started_usec)
	_dm12_emit_frame_if_spike(process_started_usec)
	if _dm19_cold_profile != null and _stream_bench_frames_done >= 1 \
	and _stream_bench_warmup_remaining == 0 and not _stream_bench_reported:
		var dm19_focus_id := _region_id(focus_region_key)
		_dm19_cold_profile.sample_frame(
			dm19_focus_id, active_regions.has(dm19_focus_id),
			loading_regions.get(dm19_focus_id, {}),
			int(_stream_budget_state.get("dispatch_limit", 1)),
			_mesh_jobs.size(), _mesh_job_limit
		)
	if _dm18_diagnostic_enabled and _stream_bench_frames_done >= 1 \
	and _stream_bench_warmup_remaining == 0 and not _stream_bench_reported:
		var focus_id := _region_id(focus_region_key)
		if not active_regions.has(focus_id):
			_dm18_focus_missing_total += 1
			if _dm5_has_cached_high(focus_id):
				_dm18_focus_missing_visual_high += 1
			if _dm18_cache.has_region(focus_id):
				_dm18_focus_missing_cached += 1
	if _dm16_probe != null and _stream_bench_frames_done >= 1 \
	and _stream_bench_frames_done <= _stream_bench_frames_goal \
	and _stream_bench_warmup_remaining == 0 \
	and not _stream_bench_reported:
		_dm16_probe.record_frame(
			_last_frame_ms, Time.get_ticks_usec() - process_started_usec,
			not active_regions.has(_region_id(focus_region_key)) if _stream_bench_route != "idle" else false,
			_dm8_high_receipt_signature != "",
			float(Time.get_ticks_usec() - _stream_bench_started_usec) / 1000.0
		)


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
				_invalidate_surface_cache_regions(cleared.get("rebuild_regions", []))
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
	if not enabled:
		_lookahead_stage_targets.clear()
		_lookahead_stage_signature = ""
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
	if not _stream_bench_route.is_empty():
		# The optional prewarm is a separate stationary interval preceding
		# the deterministic route. It primes IN-PROCESS B4 HIGH residency
		# rather than incorrectly testing an empty cold cache.
		if _stream_bench_warmup_remaining > 0:
			_stream_bench_warmup_remaining -= 1
			if _stream_bench_warmup_remaining == 0:
				print("DM5_BENCH_WARMUP_COMPLETE: " + JSON.stringify({
					"frames": _stream_bench_warmup_frames,
					"focus": [focus_region_key.x, focus_region_key.y],
					"high_shells": _dm3_shell_nodes.size(),
					"retired_full_regions": _dm3_retired_region_nodes.size(),
				}))
			return
		if _stream_bench_frames_done >= _stream_bench_frames_goal:
			if not _stream_bench_reported:
				_stream_bench_reported = true
				# Include the final, otherwise lost sub-second telemetry window.
				# _stream_finish_frame() executes later in this same _process call.
				if _perf_trace_enabled:
					_stream_window_started_usec = Time.get_ticks_usec() - STREAM_BUDGET_TRACE_INTERVAL_USEC
				# Dedicated GPU lane requires proof of a real Windows display and
				# at least one rendered frame, not simply a successful CPU scene.
				var display_name := DisplayServer.get_name()
				var drawn_frames := Engine.get_frames_drawn()
				var adapter_name := RenderingServer.get_video_adapter_name()
				print("P5_STREAM_BENCH_DISPLAY: " + JSON.stringify({
					"display": display_name,
					"drawn_frames": drawn_frames,
					"adapter": adapter_name,
					"screens": DisplayServer.get_screen_count(),
				}))
				var capture_path := OS.get_environment("SANDBOX_STREAM_BENCH_SCREENSHOT")
				if not capture_path.is_empty():
					if display_name.to_lower() != "windows" or drawn_frames < 20:
						push_error("P5_STREAM_BENCH_GUI_NOT_INTERACTIVE")
						get_tree().quit(3)
						return
					var image: Image = get_viewport().get_texture().get_image()
					if image == null or image.is_empty():
						push_error("P5_STREAM_BENCH_CAPTURE_EMPTY")
						get_tree().quit(3)
						return
					var png_error := image.save_png(capture_path)
					if png_error != OK:
						push_error("P5_STREAM_BENCH_CAPTURE_FAILED: %d" % png_error)
						get_tree().quit(3)
						return
					print("P5_STREAM_BENCH_SCREENSHOT: " + JSON.stringify({
						"width": image.get_width(),
						"height": image.get_height(),
						"path": capture_path,
					}))
				if _dm16_probe != null:
					print("DM16_BENCH_SUMMARY: " + JSON.stringify(
						_dm16_probe.summary(
							_stream_bench_route, _stream_profile, world_seed,
							_stream_bench_frames_goal, _perf_trace_enabled,
							_dm16_light_stage, _dm9_shell_completed_total,
							_dm3_shell_nodes.size(), active_regions.size(),
							int(object_stream.get_command_world_revision())
						)
					))
				print("P5_STREAM_BENCH_COMPLETE: " + JSON.stringify({
					"route": _stream_bench_route,
					"profile": _stream_profile,
					"seed": world_seed,
					"frames": _stream_bench_frames_done,
					"warmup_frames": _stream_bench_warmup_frames,
					"distance_m": snappedf(_stream_bench_distance_m, 0.001),
					"wallclock_route": _dm17_wallclock_route,
					"dm17_sparse_block": OS.get_environment("SANDBOX_DM17_SPARSE_BLOCK") == "1",
					"dm17_shared_lattice": OS.get_environment("SANDBOX_DM17_SHARED_LATTICE") == "1",
					"dm18_cache_enabled": _dm18_cache_enabled,
					"dm18_diagnostic_enabled": _dm18_diagnostic_enabled,
					"dm19_cold_diagnostic_enabled": _dm19_cold_profile != null,
					"dm19_cold": _dm19_cold_profile.summary() if _dm19_cold_profile != null else {},
					"dm18_cache": _dm18_cache.stats() if _dm18_cache_enabled else {},
					"dm18": {
						"focus_missing_total": _dm18_focus_missing_total,
						"focus_missing_visual_high": _dm18_focus_missing_visual_high,
						"focus_missing_cached_mesh": _dm18_focus_missing_cached,
						"cache_restores": _dm18_cache_restores,
						"restore_total_ms": float(_dm18_restore_total_usec) / 1000.0,
						"restore_max_ms": float(_dm18_restore_max_usec) / 1000.0,
						"new_loads": _dm18_cold_loads,
						"new_loads_total_ms": float(_dm18_cold_load_total_usec) / 1000.0,
						"cached_loads": _dm18_hot_loads,
						"cached_loads_total_ms": float(_dm18_hot_load_total_usec) / 1000.0,
						"canonical_jobs": _dm18_job_times.duplicate()
					},
					"wallclock_motion_seconds": snappedf(_dm17_motion_elapsed_sec, 0.000001),
					"final_x_mm": roundi(camera.global_position.x * 1000.0),
					"final_z_mm": roundi(camera.global_position.z * 1000.0),
					"elapsed_wall_ms": (Time.get_ticks_usec() - _stream_bench_started_usec) / 1000.0,
					"active_regions": active_regions.size(),
				}))
				get_tree().quit(0)
			return
		var local_input := Vector3.ZERO
		var motion_step_sec := STREAM_BENCH_STEP_SEC
		if _dm17_wallclock_route:
			var now_usec := Time.get_ticks_usec()
			# The first measured frame starts the wall clock without inventing a 1/60s step.
			motion_step_sec = maxf(0.0, float(now_usec - _dm17_previous_motion_usec) / 1000000.0) \
				if _dm17_previous_motion_usec > 0 else 0.0
			_dm17_previous_motion_usec = now_usec
			_dm17_motion_elapsed_sec += motion_step_sec
		if _stream_bench_route != "idle":
			local_input.x = -1.0 if _stream_bench_route.begins_with("outback") \
				and (_dm17_motion_elapsed_sec >= float(_stream_bench_frames_goal) * STREAM_BENCH_STEP_SEC * 0.5 \
				if _dm17_wallclock_route else _stream_bench_frames_done >= _stream_bench_frames_goal / 2) else 1.0
			_stream_bench_distance_m += (54.0 if _stream_bench_route.ends_with("54") else 18.0) * motion_step_sec
		_apply_free_explore_motion(local_input, motion_step_sec, _stream_bench_route.ends_with("54"))
		_stream_bench_frames_done += 1
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
		and _experimental_mesh_backend != "b4" \
		and not cave_section_enabled \
		and _is_x_edge(coordinate) and _is_z_edge(coordinate)


func _uses_shared_x_boundary(coordinate: Vector2i) -> bool:
	return _shared_boundary_runtime_enabled \
		and _experimental_mesh_backend != "b4" \
		and not cave_section_enabled \
		and _is_x_edge(coordinate) and not _is_z_edge(coordinate)


func _uses_shared_z_boundary(coordinate: Vector2i) -> bool:
	return _shared_boundary_runtime_enabled \
		and _experimental_mesh_backend != "b4" \
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
	# The experimental mesher has no stitched multi-LOD support.
	if _experimental_mesh_backend == "b4":
		return 0
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


func _dm9_count_speculative(only_ready: bool) -> int:
	var count := 0
	for value in loading_regions.values():
		var stage: Dictionary = value
		if bool(stage.get("dm9_speculative", false)) and (not only_ready or bool(stage.get("dm9_ready", false))):
			count += 1
	return count


func _dm9_revision_valid(stage: Dictionary) -> bool:
	var state: RefCounted = stage["world_state"]
	return DM9PrefetchPolicy.valid_revision(
		int(stage.get("dm9_stage_seed", -1)), world_seed,
		int(stage["edit_revision"]), int(state.brush_edits.revision),
		int(stage["terrain_effect_authority_revision"]), int(object_stream.get_command_world_revision()),
		bool(stage["cave_section_enabled"]), cave_section_enabled
	)


func _dm9_trace_stage(action: String, stage: Dictionary) -> void:
	if not _perf_trace_enabled:
		return
	var key: Vector2i = stage["region_key"]
	PerformanceTrace.emit("dm9_prefetch_stage", {
		"action": action,
		"region": [key.x, key.y],
		"focus": [focus_region_key.x, focus_region_key.y],
		"stage_token": int(stage["stage_token"]),
		"ready": bool(stage.get("dm9_ready", false)),
		"completed_chunks": int(stage.get("next_index", 0)),
		"total_chunks": (stage["chunk_coordinates"] as Array).size(),
		"elapsed_usec": maxi(0, Time.get_ticks_usec() - int(stage["chunk_enqueued_usec"])),
		"mesh_jobs_in_flight": _mesh_jobs.size(),
	})


func _dm9_promote_stage(id: String) -> void:
	if not loading_regions.has(id):
		return
	var stage: Dictionary = loading_regions[id]
	if not bool(stage.get("dm9_speculative", false)):
		return
	if not _dm9_revision_valid(stage) or not _stage_lod_selection_is_current(stage) \
	or global_rebuild_pending or not _edit_transaction.is_empty():
		_dm9_stages_discarded += 1
		_dm9_trace_stage("stale", stage)
		_supersede_region_stage(id)
		return
	stage["dm9_speculative"] = false
	stage["dm9_promoted"] = true
	stage["dm9_promoted_usec"] = Time.get_ticks_usec()
	loading_regions[id] = stage
	world_states[id] = stage["world_state"]
	object_stream.expect_region_publication(stage["region_key"], int(stage["stage_token"]))
	_dm9_stages_promoted += 1
	_dm9_trace_stage("promote", stage)
	if bool(stage.get("dm9_ready", false)):
		_dm9_ready_hits += 1
		_complete_region_stage(id)


func _reconcile_region_window(force: bool = false) -> void:
	var reconcile_started_usec := Time.get_ticks_usec()
	var active_before := active_regions.size()
	var loading_before := loading_regions.size()
	_update_focus_key()
	var source_window_changed := force or focus_region_key != _last_reconciled_focus
	if not source_window_changed \
	and _last_reconciled_lookahead_signature == _lookahead_stage_signature:
		return
	_last_reconciled_focus = focus_region_key
	_last_reconciled_lookahead_signature = _lookahead_stage_signature
	var desired := _region_keys_within_radius(focus_region_key, REQUEST_RADIUS)
	var retained := _region_keys_within_radius(focus_region_key, UNLOAD_RADIUS)
	if (_stream_profile == "adaptive-skip-lookahead" or _dm9_prefetch_enabled) and free_explore_enabled \
	and not global_rebuild_pending and _edit_transaction.is_empty():
		for ahead_region in _lookahead_stage_targets:
			if _contains_region(retained, ahead_region) \
			and not _contains_region(desired, ahead_region):
				desired.append(ahead_region)
	# A changed predictive strip does not change the retained 5x5 or
	# protected 9x9 source footprint. Reordering stages must not reissue
	# an expensive full object-source window reconciliation each time F10
	# crosses its lookahead horizon.
	if source_window_changed \
	and terrain_effect_runtime != null \
	and bool(terrain_effect_runtime.get("initialized")):
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
				if bool(stage.get("dm9_speculative", false)):
					_dm9_stages_discarded += 1
					_dm9_trace_stage("discard", stage)
				_discard_progressive_chunks(id, "left_window")
				if _dm19_cold_profile != null:
					_dm19_cold_profile.cancel(id, "left_window")
				loading_regions.erase(id)
				if not _edit_transaction.is_empty() and (_edit_transaction["target_ids"] as Array).has(id):
					_edit_transaction["target_ids"].erase(id)
		if not _edit_transaction.is_empty() and (_edit_transaction["target_ids"] as Array).is_empty():
			_finish_edit_transaction("accepted; rebuild dependencies left residency and will apply it on load")
		var core_desired := _region_keys_within_radius(focus_region_key, REQUEST_RADIUS)
		for key in desired:
			var id := _region_id(key)
			var speculative := _dm9_prefetch_enabled and not _contains_region(core_desired, key)
			if loading_regions.has(id) and not speculative and bool(loading_regions[id].get("dm9_speculative", false)):
				_dm9_promote_stage(id)
			if not active_regions.has(id) and not loading_regions.has(id):
				if loading_regions.is_empty() and not speculative:
					_begin_operation("region_stream_load")
				if _edit_transaction_affects_region(key):
					_add_edit_transaction_region(key)
				else:
					_begin_region_stage(key, "load", ChunkGrid.all_coordinates(), speculative)
					if speculative:
						_dm9_stages_started += 1
						_dm9_trace_stage("begin", loading_regions[id])
					if _stream_profile == "adaptive-skip-lookahead" \
					and _contains_region(_lookahead_stage_targets, key) \
					and not _contains_region(
						_region_keys_within_radius(focus_region_key, REQUEST_RADIUS), key
					):
						_lookahead_stage_begin_total += 1
						_stream_window_lookahead_stages += 1
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
			"f10_predictive_stage_targets": _lookahead_stage_targets.size() if _stream_profile == "adaptive-skip-lookahead" else 0,
			"f10_predictive_stage_begins_total": _lookahead_stage_begin_total,
			"dm9_prefetch_enabled": _dm9_prefetch_enabled,
			"dm9_speculative_stages": _dm9_count_speculative(false),
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
		_discard_progressive_chunks(id, "edit_transaction_started")
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
	_discard_all_progressive_chunks("full_rebuild_targets")
	loading_regions.clear()
	for key in target_keys:
		_begin_region_stage(key, "full", ChunkGrid.all_coordinates())


## Capture completed 16-chunk canonical mesh assets, never the world authority.
func _dm18_identity_for_state(state: RefCounted) -> Dictionary:
	if state == null or state.brush_edits == null:
		return {}
	return DM18CanonicalCache.identity(
		int(state.world_seed), int(state.generator_version),
		int(state.brush_edits.get_instance_id()), int(state.brush_edits.revision),
		int(object_stream.get_command_world_revision()), cave_section_enabled,
		_experimental_mesh_backend
	)


func _dm18_capture_completed_region(id: String, entry: Dictionary) -> void:
	if not _dm18_cache_enabled or global_rebuild_pending or not _edit_transaction.is_empty():
		return
	var state: RefCounted = entry.get("world_state")
	var identity_token: Dictionary = entry.get("dm18_identity_at_publish", {})
	if loading_regions.has(id) or identity_token.is_empty() \
		or not DM18CanonicalCache.same_identity(identity_token, _dm18_identity_for_state(state)):
		return
		return
	var meshes := {}
	var lods := {}
	var fallback := {}
	var vertices := {}
	var triangles := {}
	var nodes: Dictionary = entry.get("chunk_nodes", {})
	var region: Vector2i = entry["region_key"]
	for coordinate in ChunkGrid.all_coordinates():
		var chunk_id := ChunkGrid.stable_id(region, coordinate)
		if not nodes.has(chunk_id):
			return
		var node: MeshInstance3D = nodes[chunk_id]
		if not is_instance_valid(node) or node.mesh == null:
			return
		meshes[coordinate] = node.mesh
		lods[coordinate] = int(_published_lod_by_chunk.get(chunk_id, 0))
		fallback[coordinate] = bool(_lod_fallback_chunks.get(chunk_id, false))
		vertices[coordinate] = int(node.get_meta("mesh_vertex_count", 0))
		triangles[coordinate] = int(node.get_meta("mesh_triangle_count", 0))
	_dm18_cache.remember(id, region, identity_token, meshes, lods, fallback, vertices, triangles)


## Stage the exact cached meshes; still call standard publication of object and
## simulation scopes, using fresh ledger state and new revision-gated token.
func _dm18_commit_cached_region_step() -> void:
	if not _dm18_cache_enabled or global_rebuild_pending or not _edit_transaction.is_empty():
		return
	if _last_frame_ms >= 33.0 or _last_process_work_ms >= 18.0:
		return
	var candidates: Array[String] = []
	for id_value in loading_regions.keys():
		var id: String = id_value
		if bool(loading_regions[id].get("dm18_cache_ready", false)):
			candidates.append(id)
	if candidates.is_empty():
		return
	candidates.sort_custom(func(a: String, b: String) -> bool:
		var ka: Vector2i = loading_regions[a]["region_key"]
		var kb: Vector2i = loading_regions[b]["region_key"]
		var da := maxi(absi(ka.x - focus_region_key.x), absi(ka.y - focus_region_key.y))
		var db := maxi(absi(kb.x - focus_region_key.x), absi(kb.y - focus_region_key.y))
		return da < db if da != db else a < b
	)
	var id := candidates[0]
	if not loading_regions.has(id):
		return
	var stage: Dictionary = loading_regions[id]
	var state: RefCounted = stage["world_state"]
	if not _dm18_cache.is_reusable(id, _dm18_identity_for_state(state)) \
		or int(stage["edit_revision"]) != int(state.brush_edits.revision) \
		or int(stage["terrain_effect_authority_revision"]) \
			!= int(object_stream.get_command_world_revision()):
		_dm18_cache.erase(id)
		_supersede_region_stage(id)
		return
	var started := Time.get_ticks_usec()
	_complete_region_stage(id)
	var elapsed := Time.get_ticks_usec() - started
	_dm18_cache_restores += 1
	_dm18_restore_total_usec += elapsed
	_dm18_restore_max_usec = maxi(_dm18_restore_max_usec, elapsed)


func _begin_region_stage(region_key: Vector2i, purpose: String, chunk_coordinates: Array[Vector2i], dm9_speculative: bool = false) -> void:
	var id := _region_id(region_key)
	if purpose == "load" and _dm3_enabled() and _dm5_has_cached_high(id):
		_dm5_cache_hits += 1
		_dm6_retained_high_reused_total += 1
		if _perf_trace_enabled:
			PerformanceTrace.emit("dm5_retained_high_revisit", {
				"region": [region_key.x, region_key.y],
				"cached": "shell" if _dm3_shell_nodes.has(id) else "retired_full",
				"cache_hits": _dm5_cache_hits,
				"superseded_by_low": false,
			})
	_discard_progressive_chunks(id, "stage_replaced")
	_clear_coarse_preview(id)
	var state: RefCounted
	if purpose == "full" and not _pending_world_load.is_empty():
		state = WorldState.new(int(_pending_world_load["world_seed"]), region_key, _pending_world_load["ledger"])
	else:
		state = _state_for_region(region_key)
	if state == null:
		state = WorldState.new(world_seed, region_key, edit_ledger)
	var coordinates: Array[Vector2i] = chunk_coordinates.duplicate()
	if purpose == "load" and _stream_profile == "adaptive-skip-progressive":
		coordinates = ProgressiveLoadPolicy.interior_first(
			coordinates, ChunkGrid.CHUNK_COUNT_X, ChunkGrid.CHUNK_COUNT_Z
		)
	var token := _next_stage_token
	_next_stage_token += 1
	# Only stages that can replace the region-level terrain publication may
	# invalidate an in-flight object publication. LOD partial stages update
	# existing chunk meshes in place and must not cancel entity visual rebuilds.
	if not dm9_speculative and (purpose == "load" or purpose == "full" or not active_regions.has(id)):
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
		"dm9_speculative": dm9_speculative,
		"dm9_ready": false,
		"dm9_promoted": false,
		"dm9_stage_seed": int(state.world_seed),
	}
	if not dm9_speculative:
		world_states[id] = state
	# Only complete LOAD stages may restore the previous 16 canonical meshes.
	if _dm18_cache_enabled and purpose == "load" and not dm9_speculative \
		and not global_rebuild_pending and _edit_transaction.is_empty() \
		and coordinates.size() == ChunkGrid.all_coordinates().size():
		var reused: Dictionary = _dm18_cache.lookup(id, _dm18_identity_for_state(state))
		if not reused.is_empty():
			var cached_stage: Dictionary = loading_regions[id]
			cached_stage["meshes"] = reused["meshes"]
			cached_stage["actual_lod_by_coordinate"] = reused["lods"]
			cached_stage["fallback_by_coordinate"] = reused["fallback"]
			cached_stage["vertex_count_by_coordinate"] = reused["vertex_counts"]
			cached_stage["triangle_count_by_coordinate"] = reused["triangle_counts"]
			cached_stage["next_index"] = coordinates.size()
			cached_stage["submit_index"] = coordinates.size()
			cached_stage["pending_count"] = 0
			cached_stage["dm18_cache_ready"] = true
			loading_regions[id] = cached_stage
	if _dm19_cold_profile != null:
		_dm19_cold_profile.begin(
			id, purpose, Time.get_ticks_usec(),
			bool(loading_regions[id].get("dm18_cache_ready", false)),
			maxi(absi(region_key.x - focus_region_key.x),
				absi(region_key.y - focus_region_key.y))
		)
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
			"dm9_speculative": dm9_speculative,
		})


func _surface_cache_scope_id(region_key: Vector2i) -> String:
	return "region:%d,%d" % [region_key.x, region_key.y]


func _queue_surface_cache_region(region_key: Vector2i) -> void:
	if not is_instance_valid(simulation_runtime) or not simulation_runtime.initialized:
		return
	var id := _region_id(region_key)
	if not active_regions.has(id):
		return
	var state: RefCounted = active_regions[id]["world_state"]
	if state == null or state.brush_edits == null:
		return
	var terrain_revision := int(state.brush_edits.revision)
	var terrain_cache_scope_id := int(state.brush_edits.get_instance_id())
	var terrain_effect_revision := int(object_stream.get_command_world_revision())
	var scope_id := _surface_cache_scope_id(region_key)
	var expectation: Dictionary = simulation_runtime.expect_environment_surface_cache(
		scope_id,
		region_key,
		int(state.world_seed),
		int(state.generator_version),
		terrain_revision,
		terrain_cache_scope_id,
		terrain_effect_revision
	)
	if not expectation.get("ok", false):
		return
	var cached: Dictionary = simulation_runtime.get_environment_surface_cache(scope_id)
	if (
		not cached.is_empty()
		and int(cached.get("terrain_revision", -1)) == terrain_revision
		and int(cached.get("terrain_cache_scope_id", -1)) == terrain_cache_scope_id
		and int(cached.get("terrain_effect_revision", -1)) == terrain_effect_revision
		and (
			not simulation_runtime.has_environment_hydrology()
			or not is_instance_valid(_environment_visual)
			or _environment_visual.has_region_shoreline_samples(region_key, cached)
		)
	):
		_surface_cache_pending.erase(id)
		_surface_cache_retry_after_usec.erase(id)
		_surface_cache_retry_counts.erase(id)
		return
	var previous_pending: Dictionary = _surface_cache_pending.get(id, {})
	if not previous_pending.is_empty() and (
		int(previous_pending.get("terrain_revision", -1)) != terrain_revision
		or int(previous_pending.get("terrain_cache_scope_id", -1)) != terrain_cache_scope_id
		or int(previous_pending.get("terrain_effect_revision", -1)) != terrain_effect_revision
	):
		_surface_cache_retry_after_usec.erase(id)
		_surface_cache_retry_counts.erase(id)
	if is_instance_valid(_environment_visual):
		_environment_visual.invalidate_region_shoreline_samples(region_key)
	_surface_cache_pending[id] = {
		"region_key": region_key,
		"scope_id": scope_id,
		"world_seed": int(state.world_seed),
		"generator_version": int(state.generator_version),
		"terrain_revision": terrain_revision,
		"terrain_cache_scope_id": terrain_cache_scope_id,
		"terrain_effect_revision": terrain_effect_revision,
	}


func _invalidate_surface_cache_regions(regions: Array) -> void:
	for region_value in regions:
		if typeof(region_value) != TYPE_VECTOR2I:
			continue
		_queue_surface_cache_region(region_value)


func _sync_surface_cache_effect_revision() -> void:
	var current_revision := int(object_stream.get_command_world_revision())
	if _surface_cache_last_effect_revision < 0:
		_surface_cache_last_effect_revision = current_revision
		return
	if current_revision == _surface_cache_last_effect_revision:
		return
	_surface_cache_last_effect_revision = current_revision
	var ids: Array[String] = []
	for id_value in active_regions.keys():
		ids.append(String(id_value))
	ids.sort()
	for id in ids:
		var entry: Dictionary = active_regions[id]
		_queue_surface_cache_region(entry["region_key"])


## Retry transient failures without dropping publication obligations or
## dispatching infinitely in one frame. New terrain revisions reset cooldown.
func _schedule_surface_cache_retry(region_key: Vector2i, reason: String) -> void:
	var id := _region_id(region_key)
	if not active_regions.has(id):
		return
	_queue_surface_cache_region(region_key)
	if not _surface_cache_pending.has(id):
		return
	var attempt := int(_surface_cache_retry_counts.get(id, 0)) + 1
	_surface_cache_retry_counts[id] = attempt
	var shift := mini(attempt - 1, 5)
	var delay := mini(SURFACE_CACHE_RETRY_MAX_USEC, SURFACE_CACHE_RETRY_BASE_USEC * (1 << shift))
	_surface_cache_retry_after_usec[id] = Time.get_ticks_usec() + delay
	if _perf_trace_enabled:
		PerformanceTrace.emit("p5_surface_cache_retry_scheduled", {
			"region": [region_key.x, region_key.y],
			"reason": reason, "attempt": attempt,
			"delay_usec": delay,
		})


## Lightweight self-heal for lost/failed visualization delivery after revisit.
## Checks one active region/frame, even if the canonical cache is missing,
## and never changes the canonical SDF authority.
func _repair_missing_surface_cache_visual() -> void:
	if not is_instance_valid(_environment_visual) or not simulation_runtime.has_environment_hydrology():
		return
	var ids: Array = active_regions.keys()
	if ids.is_empty():
		_surface_cache_repair_cursor = 0
		return
	ids.sort()
	var id := String(ids[_surface_cache_repair_cursor % ids.size()])
	_surface_cache_repair_cursor = (_surface_cache_repair_cursor + 1) % ids.size()
	if _surface_cache_pending.has(id) or _surface_cache_job_by_region.has(id):
		return
	var region_key: Vector2i = active_regions[id]["region_key"]
	var surface: Dictionary = simulation_runtime.get_environment_surface_cache(
		_surface_cache_scope_id(region_key)
	)
	if surface.is_empty() or not _environment_visual.has_region_shoreline_samples(region_key, surface):
		_queue_surface_cache_region(region_key)
		if _perf_trace_enabled and _surface_cache_pending.has(id):
			PerformanceTrace.emit("p5_surface_cache_repair_queued", {
				"region": [region_key.x, region_key.y],
				"terrain_revision": int(surface.get("terrain_revision", -1)),
			})


func _process_surface_cache_jobs() -> void:
	if not is_instance_valid(simulation_runtime) or not simulation_runtime.initialized:
		return
	_sync_surface_cache_effect_revision()
	_repair_missing_surface_cache_visual()

	var completed: Array[int] = []
	for task_id_value in _surface_cache_jobs.keys():
		var task_id := int(task_id_value)
		if WorkerThreadPool.is_task_completed(task_id):
			completed.append(task_id)
	completed.sort()
	for task_id in completed:
		WorkerThreadPool.wait_for_task_completion(task_id)
		if not _surface_cache_jobs.has(task_id):
			continue
		var job_record: Dictionary = _surface_cache_jobs[task_id]
		_surface_cache_jobs.erase(task_id)
		var id := String(job_record["region_id"])
		if int(_surface_cache_job_by_region.get(id, -1)) == task_id:
			_surface_cache_job_by_region.erase(id)
		var job = job_record["job"]
		if not active_regions.has(id):
			_surface_cache_stale_discards_total += 1
			continue
		var state: RefCounted = active_regions[id]["world_state"]
		if (
			int(state.brush_edits.revision) != int(job.terrain_revision)
			or int(state.brush_edits.get_instance_id()) != int(job.terrain_cache_scope_id)
			or int(object_stream.get_command_world_revision()) != int(job.terrain_effect_revision)
		):
			_surface_cache_stale_discards_total += 1
			_queue_surface_cache_region(job.region_key)
			continue
		var built: Dictionary = job.result
		if not built.get("valid", false) or typeof(built.get("record")) != TYPE_DICTIONARY:
			_surface_cache_worker_failures_total += 1
			_schedule_surface_cache_retry(job.region_key, "worker:" + String(built.get("reason", "invalid_record")))
			continue
		var publication: Dictionary = simulation_runtime.publish_environment_surface_cache(
			built["record"]
		)
		if not publication.get("ok", false):
			if String(publication.get("reason", "")).contains("stale"):
				_surface_cache_stale_discards_total += 1
				_queue_surface_cache_region(job.region_key)
			else:
				_surface_cache_worker_failures_total += 1
				_schedule_surface_cache_retry(job.region_key, "publication:" + String(publication.get("reason", "rejected")))
			continue
		_surface_cache_publications_total += 1
		var install_ok := true
		if is_instance_valid(_environment_visual) and simulation_runtime.has_environment_hydrology():
			install_ok = bool(_environment_visual.install_region_shoreline_samples(
				job.region_key, built["record"], built.get("visual_shoreline", {})
			))
		if not install_ok:
			_surface_cache_visual_install_failures_total += 1
			var visual_result: Dictionary = built.get("visual_shoreline", {})
			_schedule_surface_cache_retry(job.region_key,
				"shoreline_install:" + String(visual_result.get("reason", "rejected")))
			continue
		_surface_cache_retry_after_usec.erase(id)
		_surface_cache_retry_counts.erase(id)
		var pending_token: Dictionary = _surface_cache_pending.get(id, {})
		if (
			int(pending_token.get("terrain_revision", -1)) == int(job.terrain_revision)
			and int(pending_token.get("terrain_cache_scope_id", -1))
				== int(job.terrain_cache_scope_id)
			and int(pending_token.get("terrain_effect_revision", -1))
				== int(job.terrain_effect_revision)
		):
			_surface_cache_pending.erase(id)
		if _perf_trace_enabled:
			PerformanceTrace.emit_duration(
				"environment_surface_cache_job",
				int(job.worker_started_usec),
				{
					"region": [job.region_key.x, job.region_key.y],
					"terrain_revision": int(job.terrain_revision),
					"terrain_effect_revision": int(job.terrain_effect_revision),
					"worker_usec": maxi(
						0, int(job.worker_finished_usec) - int(job.worker_started_usec)
					),
					"queue_usec": maxi(
						0, int(job.worker_started_usec) - int(job.queued_usec)
					),
					"diagnostics": built.get("diagnostics", {}),
				},
				true
			)

	while (
		_surface_cache_jobs.size() < MAX_SURFACE_CACHE_JOBS_IN_FLIGHT
		and _surface_cache_dispatches_this_frame < MAX_SURFACE_CACHE_DISPATCHES_PER_FRAME
	):
		var candidates: Array[String] = []
		for id_value in _surface_cache_pending.keys():
			var id := String(id_value)
			if (
				active_regions.has(id)
				and not _surface_cache_job_by_region.has(id)
				and Time.get_ticks_usec() >= int(_surface_cache_retry_after_usec.get(id, 0))
			):
				candidates.append(id)
		if candidates.is_empty():
			break
		candidates.sort_custom(func(a: String, b: String) -> bool:
			var a_key: Vector2i = active_regions[a]["region_key"]
			var b_key: Vector2i = active_regions[b]["region_key"]
			var a_distance := maxi(
				absi(a_key.x - focus_region_key.x),
				absi(a_key.y - focus_region_key.y)
			)
			var b_distance := maxi(
				absi(b_key.x - focus_region_key.x),
				absi(b_key.y - focus_region_key.y)
			)
			if a_distance != b_distance:
				return a_distance < b_distance
			return a_key.y < b_key.y if a_key.y != b_key.y else a_key.x < b_key.x
		)
		var dispatched := _dm12_prepare_surface_cache_job(candidates[0]) if _dm12_surface_slice \
			else _dispatch_surface_cache_job(candidates[0])
		if dispatched.get("ok", false):
			_surface_cache_dispatches_this_frame += 1
			continue
		if dispatched.get("pending", false):
			break
		_surface_cache_snapshot_failures_total += 1
		var rejected_id := candidates[0]
		var rejected_region: Vector2i = active_regions[rejected_id]["region_key"]
		_schedule_surface_cache_retry(rejected_region,
			"snapshot:" + String(dispatched.get("reason", "rejected")))



## DM12 optional spill of the 16 immutable per-chunk SDF snapshots over
## multiple _process frames. All original effect validation, revision gates,
## worker construction and publication remain in _dispatch_surface_cache_job.
func _dm12_prepare_surface_cache_job(id: String) -> Dictionary:
	if not active_regions.has(id) or not _surface_cache_pending.has(id):
		_dm12_surface_prepare.clear()
		return {"ok": false, "reason": "surface_snapshot_batch_no_pending_region"}
	var token: Dictionary = _surface_cache_pending[id]
	var state: RefCounted = active_regions[id]["world_state"]
	if int(state.brush_edits.revision) != int(token["terrain_revision"]) \
		or int(state.brush_edits.get_instance_id()) != int(token["terrain_cache_scope_id"]) \
		or int(object_stream.get_command_world_revision()) != int(token["terrain_effect_revision"]):
		_dm12_surface_prepare.clear()
		_queue_surface_cache_region(token["region_key"])
		return {"ok": false, "pending": true, "reason": "surface_snapshot_batch_superseded"}
	if _dm12_surface_prepare.get("id", "") != id \
		or _dm12_surface_prepare.get("token", {}) != token:
		_dm12_surface_prepare = {
			"id": id,
			"token": token.duplicate(true),
			"batch": DM12SnapshotBatch.new(
				token["region_key"],
				int(token["terrain_revision"]),
				int(token["terrain_cache_scope_id"])
			)
		}
	var batch: RefCounted = _dm12_surface_prepare["batch"]
	var step: Dictionary = batch.capture(state.brush_edits, 3, 2_500)
	if not step.get("ok", false):
		_dm12_surface_prepare.clear()
		if String(step.get("reason", "")).contains("revision"):
			_queue_surface_cache_region(token["region_key"])
			return {"ok": false, "pending": true, "reason": String(step.get("reason", ""))}
		return step
	if _dm12_trace_enabled:
		PerformanceTrace.emit("dm12_surface_snapshot_step", {
			"region": [token["region_key"].x, token["region_key"].y],
			"captured": int(step["captured"]),
			"processed": int(step["processed"]),
			"step_usec": int(step["elapsed_usec"]),
			"complete": bool(step["complete"])
		})
	if not bool(step["complete"]):
		return {"ok": false, "pending": true, "reason": "surface_snapshot_batch_incomplete"}
	var inputs: Dictionary = batch.prepared_inputs()
	if inputs.is_empty():
		_dm12_surface_prepare.clear()
		return {"ok": false, "reason": "surface_snapshot_batch_incomplete_inputs"}
	var dispatched := _dispatch_surface_cache_job(id, inputs)
	if dispatched.get("ok", false):
		if _perf_trace_enabled:
			PerformanceTrace.emit("dm12_surface_snapshot_complete", {
				"region": [token["region_key"].x, token["region_key"].y],
				"capture_calls": int(inputs.get("capture_calls", 0)),
				"capture_total_usec": int(inputs.get("capture_total_usec", 0)),
				"chunk_count": (inputs["base_snapshots"] as Dictionary).size()
			})
	if dispatched.get("ok", false) or not bool(dispatched.get("pending", false)):
		_dm12_surface_prepare.clear()
	return dispatched

func _dispatch_surface_cache_job(id: String, sliced_inputs: Dictionary = {}) -> Dictionary:
	if not active_regions.has(id) or not _surface_cache_pending.has(id):
		return {"ok": false, "reason": "surface_cache_region_not_pending"}
	var token: Dictionary = _surface_cache_pending[id]
	var region_key: Vector2i = token["region_key"]
	var state: RefCounted = active_regions[id]["world_state"]
	if (
		int(state.brush_edits.revision) != int(token["terrain_revision"])
		or int(state.brush_edits.get_instance_id()) != int(token["terrain_cache_scope_id"])
		or int(object_stream.get_command_world_revision())
			!= int(token["terrain_effect_revision"])
	):
		_queue_surface_cache_region(region_key)
		return {"ok": false, "pending": true, "reason": "surface_cache_token_changed"}

	var snapshot_started_usec := Time.get_ticks_usec()
	var base_snapshots: Dictionary = {}
	var effect_targets: Array[Dictionary] = []
	var anchor_snapshot: Dictionary = {}
	if not sliced_inputs.is_empty():
		base_snapshots = sliced_inputs["base_snapshots"]
		effect_targets = sliced_inputs["effect_targets"]
		anchor_snapshot = sliced_inputs["anchor_snapshot"]
	if sliced_inputs.is_empty():
		for coordinate in ChunkGrid.all_coordinates():
			var base_snapshot: Dictionary = state.brush_edits.get_meshing_snapshot_for_chunk(
				region_key, coordinate
			)
			if not base_snapshot.get("valid", false):
				return {
					"ok": false,
					"reason": String(base_snapshot.get("storage_error", "surface_cache_snapshot_invalid")),
				}
			if (
				int(base_snapshot.get("revision", -1)) != int(token["terrain_revision"])
				or int(base_snapshot.get("cache_scope_id", -1))
					!= int(token["terrain_cache_scope_id"])
			):
				return {"ok": false, "pending": true, "reason": "surface_cache_snapshot_stale"}
			base_snapshots[coordinate] = base_snapshot
			effect_targets.append({
				"region_key": region_key,
				"chunk_coordinate": coordinate,
			})
			if anchor_snapshot.is_empty():
				anchor_snapshot = base_snapshot
	elif base_snapshots.size() != ChunkGrid.all_coordinates().size() \
		or effect_targets.size() != base_snapshots.size() or anchor_snapshot.is_empty():
		return {"ok": false, "reason": "surface_snapshot_batch_invalid_inputs"}

	var prepared_region := _prepare_terrain_effect_snapshot(
		anchor_snapshot, effect_targets
	)
	if not prepared_region.get("ok", false):
		if _terrain_effect_snapshot_pending(prepared_region):
			return {
				"ok": false,
				"pending": true,
				"reason": "surface_cache_effect_snapshot_pending",
			}
		return {
			"ok": false,
			"reason": String(
				prepared_region.get("reason", "surface_cache_effect_snapshot_invalid")
			),
		}
	var prepared_snapshot: Dictionary = prepared_region["snapshot"]
	var chunk_snapshots: Dictionary = {}
	for coordinate in ChunkGrid.all_coordinates():
		var snapshot: Dictionary = (base_snapshots[coordinate] as Dictionary).duplicate(true)
		snapshot["terrain_object_effect_frames"] = (
			prepared_snapshot.get("terrain_object_effect_frames", []) as Array
		).duplicate(true)
		snapshot["terrain_effect_snapshot_sha256"] = String(
			prepared_snapshot.get("terrain_effect_snapshot_sha256", "")
		)
		snapshot["terrain_effect_authority_revision"] = int(
			prepared_snapshot.get("terrain_effect_authority_revision", -1)
		)
		snapshot["terrain_effect_frame_count"] = int(
			prepared_snapshot.get("terrain_effect_frame_count", 0)
		)
		chunk_snapshots[coordinate] = snapshot

	if (
		int(state.brush_edits.revision) != int(token["terrain_revision"])
		or int(object_stream.get_command_world_revision())
			!= int(token["terrain_effect_revision"])
	):
		_queue_surface_cache_region(region_key)
		return {"ok": false, "pending": true, "reason": "surface_cache_snapshot_superseded"}

	var queued_usec := Time.get_ticks_usec()
	var job := EnvironmentSurfaceCacheJobScript.new(
		String(token["scope_id"]),
		int(token["world_seed"]),
		int(token["generator_version"]),
		region_key,
		int(token["terrain_revision"]),
		int(token["terrain_cache_scope_id"]),
		int(token["terrain_effect_revision"]),
		chunk_snapshots,
		queued_usec
	)
	job.build_visual_shoreline = (
		is_instance_valid(_environment_visual)
		and simulation_runtime.has_environment_hydrology()
	)
	if job.build_visual_shoreline:
		var refine_levels := PackedInt64Array()
		# Ocean can become bound only AFTER this surface-cache job has
		# published. Include its deterministic level before the first tick.
		if (region_key.y + 1) * 6 > EnvironmentHydrologyDomainScript.OCEAN_START_GLOBAL_CELL_Z:
			refine_levels.append(EnvironmentHydrologyDomainScript.OCEAN_LEVEL_MM)
		var live_environment: Dictionary = simulation_runtime.get_environment_scope(String(token["scope_id"]))
		var kinds: PackedByteArray = live_environment.get("reservoir_kind", PackedByteArray())
		var levels: PackedInt64Array = live_environment.get("reservoir_level_mm", PackedInt64Array())
		if kinds.size() == levels.size():
			for i in range(kinds.size()):
				if int(kinds[i]) == 1 and not refine_levels.has(int(levels[i])):
					refine_levels.append(int(levels[i]))
				if refine_levels.size() >= 12:
					break
		job.visual_refine_levels_mm = refine_levels
	var task_id := WorkerThreadPool.add_task(
		Callable(job, "run"), false, "environment SDF surface cache"
	)
	if task_id < 0:
		return {"ok": false, "reason": "surface_cache_worker_rejected"}
	_surface_cache_jobs[task_id] = {
		"job": job,
		"region_id": id,
		"snapshot_usec": Time.get_ticks_usec() - snapshot_started_usec,
	}
	_surface_cache_job_by_region[id] = task_id
	if _perf_trace_enabled:
		var snapshot_usec := Time.get_ticks_usec() - snapshot_started_usec
		if snapshot_usec >= PerformanceTrace.min_usec():
			PerformanceTrace.emit("environment_surface_cache_snapshot", {
				"duration_usec": snapshot_usec,
				"region": [region_key.x, region_key.y],
				"terrain_revision": int(token["terrain_revision"]),
				"terrain_effect_revision": int(token["terrain_effect_revision"]),
				"chunk_snapshot_count": chunk_snapshots.size(),
				"jobs_in_flight": _surface_cache_jobs.size(),
			})
	return {"ok": true, "reason": "ok", "task_id": task_id}


## E2 derived coarse-first preview: always separate from terrain authority.
func _coarse_preview_record_current(id: String, record: Dictionary) -> bool:
	if _dm3_enabled() and _dm5_has_cached_high(id):
		return false
	if _stream_profile not in ["adaptive-skip-coarse", "adaptive-skip-progressive"] or not loading_regions.has(id):
		return false
	var stage: Dictionary = loading_regions[id]
	var state: RefCounted = stage["world_state"]
	return CoarsePreviewPolicy.revision_matches(
		stage, record, world_seed, int(state.generator_version),
		int(state.brush_edits.revision),
		int(object_stream.get_command_world_revision()),
		focus_region_key, active_regions.has(id), global_rebuild_pending,
		not _edit_transaction.is_empty(), int(state.brush_edits.get_edit_count()) > 0,
		cave_section_enabled
	)


func _clear_coarse_preview(id: String, reason: String = "stale") -> bool:
	if not _coarse_preview_nodes.has(id):
		return false
	var entry: Dictionary = _coarse_preview_nodes[id]
	_coarse_preview_nodes.erase(id)
	var node: MeshInstance3D = entry.get("node", null)
	if is_instance_valid(node):
		node.visible = false
		node.queue_free()
	for tile_node_value in (entry.get("chunk_nodes", {}) as Dictionary).values():
		var tile_node: MeshInstance3D = tile_node_value
		if is_instance_valid(tile_node):
			tile_node.visible = false
			tile_node.queue_free()
	if reason != "definitive":
		_stream_window_coarse_discarded += 1
		if _perf_trace_enabled:
			var key: Vector2i = entry.get("region_key", Vector2i.ZERO)
			PerformanceTrace.emit("terrain_region_coarse_discarded", {
				"region": [key.x, key.y],
				"stage_token": int(entry.get("stage_token", -1)),
				"reason": reason,
			})
	return true


func _process_coarse_previews() -> void:
	# Revocation must also work while definitive effects are still pending.
	for id_value in _coarse_preview_attempts.keys().duplicate():
		var id: String = id_value
		if not loading_regions.has(id) or int(loading_regions[id]["stage_token"]) != int(_coarse_preview_attempts[id]):
			_coarse_preview_attempts.erase(id)
	for id_value in _coarse_preview_nodes.keys().duplicate():
		var id: String = id_value
		var entry: Dictionary = _coarse_preview_nodes[id]
		if not _coarse_preview_record_current(id, entry):
			_clear_coarse_preview(id, "revision_or_residency_changed")
	var completed: Array[int] = []
	for task_id_value in _coarse_preview_jobs.keys():
		var task_id := int(task_id_value)
		if WorkerThreadPool.is_task_completed(task_id):
			completed.append(task_id)
	completed.sort()
	# Bounded to one main-thread upload per frame, with a spike veto.
	if not completed.is_empty() and _last_frame_ms < 20.0:
		var task_id := completed[0]
		WorkerThreadPool.wait_for_task_completion(task_id)
		var record: Dictionary = _coarse_preview_jobs[task_id]
		_coarse_preview_jobs.erase(task_id)
		var id: String = record["stage_id"]
		var job: RefCounted = record["job"]
		var cpu: Dictionary = job.get("result")
		_stream_window_coarse_worker_usec += int(cpu.get("worker_usec", 0))
		if cpu.get("valid", false) and _coarse_preview_record_current(id, record):
			var started_usec := Time.get_ticks_usec()
			var mesh: ArrayMesh = CoarsePreviewJob.mesh_from_cpu_data(cpu)
			if mesh.get_surface_count() > 0:
				var node: MeshInstance3D = null
				var preview_chunk_nodes: Dictionary = {}
				if _stream_profile == "adaptive-skip-progressive":
					var patches: Dictionary = cpu.get("chunk_patches", {})
					var already_visible: Dictionary = _progressive_chunk_nodes.get(id, {}).get("nodes", {})
					for coordinate in ChunkGrid.all_coordinates():
						var patch: Dictionary = patches.get(coordinate, {})
						var tile_mesh: ArrayMesh = CoarsePreviewJob.mesh_from_cpu_data(patch)
						if tile_mesh.get_surface_count() == 0:
							continue
						var patch_node := MeshInstance3D.new()
						patch_node.name = "E7Coarse_%s_%d_%d" % [id, coordinate.x, coordinate.y]
						patch_node.mesh = tile_mesh
						patch_node.material_override = terrain_mesh_template.material_override
						patch_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
						patch_node.position = SpatialGrid.region_origin_world(record["region_key"])
						patch_node.visible = not already_visible.has(ChunkGrid.stable_id(record["region_key"], coordinate))
						terrain_chunks_root.add_child(patch_node)
						preview_chunk_nodes[coordinate] = patch_node
				else:
					node = MeshInstance3D.new()
					node.name = "E2Coarse_%s" % id.replace(":", "_").replace(",", "_")
					node.mesh = mesh
					node.material_override = terrain_mesh_template.material_override
					node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					node.position = SpatialGrid.region_origin_world(record["region_key"])
					terrain_chunks_root.add_child(node)
				_coarse_preview_nodes[id] = {
					"node": node,
					"chunk_nodes": preview_chunk_nodes,
					"region_key": record["region_key"],
					"stage_token": int(record["stage_token"]),
					"seed": int(record["seed"]),
					"generator_version": int(record["generator_version"]),
					"edit_revision": int(record["edit_revision"]),
					"effect_revision": int(record["effect_revision"]),
				}
				var publish_usec := Time.get_ticks_usec() - started_usec
				_stream_window_coarse_publish_usec += publish_usec
				_stream_window_coarse_published += 1
				if _dm12_trace_enabled:
					_dm12_coarse_publish_count += 1
				if _perf_trace_enabled:
					var stage: Dictionary = loading_regions[id]
					var key: Vector2i = record["region_key"]
					PerformanceTrace.emit("terrain_region_coarse_visible", {
						"region": [key.x, key.y],
						"stage_token": int(record["stage_token"]),
						"edit_revision": int(record["edit_revision"]),
						"effect_revision": int(record["effect_revision"]),
						"queue_to_coarse_usec": Time.get_ticks_usec() - int(stage["chunk_enqueued_usec"]),
						"worker_usec": int(cpu.get("worker_usec", 0)),
						"publish_usec": publish_usec,
						"triangle_count": int(cpu.get("triangle_count", 0)),
						"preview_patch_count": preview_chunk_nodes.size(),
						"source": "derived_preview_not_authority",
					})
	if _coarse_preview_jobs.size() >= MAX_COARSE_PREVIEW_JOBS or _last_frame_ms >= 20.0 	or _last_process_work_ms >= 10.5:
		return
	_submit_coarse_preview_job()


func _submit_coarse_preview_job() -> void:
	var candidates: Array[String] = []
	for id_value in loading_regions.keys():
		var id: String = id_value
		if _coarse_preview_attempts.has(id) or _coarse_preview_nodes.has(id):
			continue
		var stage: Dictionary = loading_regions[id]
		var state: RefCounted = stage["world_state"]
		if _dm3_enabled() and _dm5_has_cached_high(id):
			# Revisit cache is already B4 HIGH; never schedule an E7 LOW
			# approximation that would replace or overlap it.
			_dm6_low_preview_prevented_total += 1
			continue
		if not CoarsePreviewPolicy.eligible_stage(
			_stream_profile, stage, active_regions.has(id), global_rebuild_pending,
			not _edit_transaction.is_empty(), int(state.brush_edits.get_edit_count()) > 0,
			cave_section_enabled
		):
			continue
		var key: Vector2i = stage["region_key"]
		if maxi(absi(key.x - focus_region_key.x), absi(key.y - focus_region_key.y)) <= 1:
			candidates.append(id)
	candidates.sort_custom(func(a: String, b: String) -> bool:
		var ka: Vector2i = loading_regions[a]["region_key"]
		var kb: Vector2i = loading_regions[b]["region_key"]
		var da := maxi(absi(ka.x - focus_region_key.x), absi(ka.y - focus_region_key.y))
		var db := maxi(absi(kb.x - focus_region_key.x), absi(kb.y - focus_region_key.y))
		if da != db:
			return da < db
		return ka.y < kb.y if ka.y != kb.y else ka.x < kb.x
	)
	if candidates.is_empty():
		return
	var id := candidates[0]
	var stage: Dictionary = loading_regions[id]
	var state: RefCounted = stage["world_state"]
	var job := CoarsePreviewJob.new(
		int(state.world_seed), stage["region_key"], int(stage["stage_token"]),
		int(stage["edit_revision"]), int(stage["terrain_effect_authority_revision"]),
		int(state.generator_version),
		_stream_profile == "adaptive-skip-progressive"
	)
	var task_id := WorkerThreadPool.add_task(
		Callable(job, "run"), false, "E2 derived coarse preview"
	)
	if task_id < 0:
		return
	_coarse_preview_attempts[id] = int(stage["stage_token"])
	_coarse_preview_jobs[task_id] = {
		"stage_id": id,
		"region_key": stage["region_key"],
		"stage_token": int(stage["stage_token"]),
		"seed": int(state.world_seed),
		"generator_version": int(state.generator_version),
		"edit_revision": int(stage["edit_revision"]),
		"effect_revision": int(stage["terrain_effect_authority_revision"]),
		"job": job,
	}


## E7 provisional chunk nodes are never registered in active_regions:
## partial meshes stay visually present but do not activate simulation,
## placement, object publication, world lifecycle, or authoritative commits.
func _progressive_stage_current(id: String) -> bool:
	if _stream_profile != "adaptive-skip-progressive" or not loading_regions.has(id):
		return false
	var stage: Dictionary = loading_regions[id]
	var state: RefCounted = stage["world_state"]
	return ProgressiveLoadPolicy.eligible(
		stage, active_regions.has(id), global_rebuild_pending,
		not _edit_transaction.is_empty(),
		int(state.brush_edits.get_edit_count()) > 0,
		cave_section_enabled
	) and ProgressiveLoadPolicy.current(
		stage, int(stage["stage_token"]), int(state.brush_edits.revision),
		int(object_stream.get_command_world_revision())
	)


func _progressive_visible_chunk_count() -> int:
	var total := 0
	for entry_value in _progressive_chunk_nodes.values():
		total += (entry_value.get("nodes", {}) as Dictionary).size()
	return total


func _discard_progressive_chunks(id: String, reason: String = "revoked") -> void:
	if not _progressive_chunk_nodes.has(id):
		return
	var record: Dictionary = _progressive_chunk_nodes[id]
	_progressive_chunk_nodes.erase(id)
	var nodes: Dictionary = record.get("nodes", {})
	for chunk_id_value in nodes.keys():
		var chunk_id: String = chunk_id_value
		var node: MeshInstance3D = nodes[chunk_id]
		if is_instance_valid(node):
			_release_chunk_node(chunk_id, node)
	_progressive_chunk_revoked_total += nodes.size()
	if _perf_trace_enabled:
		var region: Vector2i = record.get("region_key", Vector2i.ZERO)
		PerformanceTrace.emit("terrain_progressive_chunks_revoked", {
			"region": [region.x, region.y],
			"stage_token": int(record.get("stage_token", -1)),
			"count": nodes.size(),
			"reason": reason,
			"authoritative_region_committed": false,
		})


func _discard_all_progressive_chunks(reason: String) -> void:
	for id_value in _progressive_chunk_nodes.keys().duplicate():
		_discard_progressive_chunks(String(id_value), reason)


func _prune_progressive_chunks() -> void:
	for id_value in _progressive_chunk_nodes.keys().duplicate():
		var id: String = id_value
		var entry: Dictionary = _progressive_chunk_nodes[id]
		if not _progressive_stage_current(id) or int(entry["stage_token"]) != int(loading_regions[id]["stage_token"]):
			_discard_progressive_chunks(id, "stale_revision_or_stage")


func _hide_coarse_patch_for_definitive_chunk(id: String, coordinate: Vector2i) -> void:
	if not _coarse_preview_nodes.has(id):
		return
	var patches: Dictionary = _coarse_preview_nodes[id].get("chunk_nodes", {})
	if patches.has(coordinate):
		var node: MeshInstance3D = patches[coordinate]
		if is_instance_valid(node):
			node.visible = false


func _process_progressive_chunk_publications() -> void:
	if _stream_profile != "adaptive-skip-progressive" \
	or _last_frame_ms >= 20.0 or _last_process_work_ms >= 10.5:
		return
	var started_usec := Time.get_ticks_usec()
	var staged_ids: Array[String] = []
	for id_value in loading_regions.keys():
		var id: String = id_value
		if bool(loading_regions[id_value].get("dm9_speculative", false)):
			continue
		if _progressive_stage_current(id):
			staged_ids.append(id)
	staged_ids.sort_custom(func(a: String, b: String) -> bool:
		var ka: Vector2i = loading_regions[a]["region_key"]
		var kb: Vector2i = loading_regions[b]["region_key"]
		var da := maxi(absi(ka.x - focus_region_key.x), absi(ka.y - focus_region_key.y))
		var db := maxi(absi(kb.x - focus_region_key.x), absi(kb.y - focus_region_key.y))
		if da != db:
			return da < db
		return ka.y < kb.y if ka.y != kb.y else ka.x < kb.x
	)
	var published := 0
	for id in staged_ids:
		if published >= MAX_PROGRESSIVE_CHUNK_PUBLISHES_PER_FRAME:
			break
		if Time.get_ticks_usec() - started_usec >= PROGRESSIVE_PUBLISH_BUDGET_USEC:
			break
		var stage: Dictionary = loading_regions[id]
		if not _stage_lod_selection_is_current(stage):
			_supersede_region_stage(id)
			continue
		var region_key: Vector2i = stage["region_key"]
		for coordinate in stage["chunk_coordinates"]:
			if published >= MAX_PROGRESSIVE_CHUNK_PUBLISHES_PER_FRAME \
			or Time.get_ticks_usec() - started_usec >= PROGRESSIVE_PUBLISH_BUDGET_USEC:
				break
			if not ProgressiveLoadPolicy.valid_chunk_publication(
				stage, coordinate, active_regions.has(id), global_rebuild_pending,
				not _edit_transaction.is_empty(),
				int((stage["world_state"] as RefCounted).brush_edits.get_edit_count()) > 0,
				cave_section_enabled,
				int((stage["world_state"] as RefCounted).brush_edits.revision),
				int(object_stream.get_command_world_revision())
			):
				continue
			var chunk_id := ChunkGrid.stable_id(region_key, coordinate)
			var existing: Dictionary = _progressive_chunk_nodes.get(id, {}).get("nodes", {})
			if existing.has(chunk_id):
				continue
			var mesh: Mesh = stage["meshes"][coordinate]
			var dm5_keep_high := _dm3_enabled() and _dm5_has_cached_high(id)
			if _dm3_enabled() and not dm5_keep_high:
				_dm3_drop_shell(id)
				_dm3_drop_retired(id)
			var node := _create_chunk_node(region_key, coordinate, chunk_id)
			node.position = SpatialGrid.region_origin_world(region_key) + ChunkGrid.origin_for(coordinate)
			_replace_node_mesh(
				node, mesh,
				int(stage.get("vertex_count_by_coordinate", {}).get(coordinate, -1)),
				int(stage.get("triangle_count_by_coordinate", {}).get(coordinate, -1))
			)
			# Preserve already-loaded HIGH geometry while the new
			# authoritative chunks stage. Provisional B4 meshes are invisible
			# until the atomic 16-chunk commit, never replaced by E7 LOW.
			node.visible = not dm5_keep_high
			node.set_meta("stable_chunk_id", chunk_id)
			node.set_meta("region_key", region_key)
			node.set_meta("chunk_coordinate", coordinate)
			_set_chunk_lod_state(
				chunk_id, node,
				int(stage.get("actual_lod_by_coordinate", {}).get(coordinate, 0)),
				bool(stage.get("fallback_by_coordinate", {}).get(coordinate, false))
			)
			chunk_nodes[chunk_id] = node
			if not _progressive_chunk_nodes.has(id):
				_progressive_chunk_nodes[id] = {
					"region_key": region_key,
					"stage_token": int(stage["stage_token"]),
					"nodes": {},
				}
			(_progressive_chunk_nodes[id]["nodes"] as Dictionary)[chunk_id] = node
			_hide_coarse_patch_for_definitive_chunk(id, coordinate)
			_progressive_chunk_published_total += 1
			_stream_window_progressive_published += 1
			if _dm12_trace_enabled:
				_dm12_progressive_publish_count += 1
			published += 1
			if _perf_trace_enabled:
				PerformanceTrace.emit("terrain_chunk_progressive_visible", {
					"region": [region_key.x, region_key.y],
					"chunk": [coordinate.x, coordinate.y],
					"stage_token": int(stage["stage_token"]),
					"edit_revision": int(stage["edit_revision"]),
					"effect_revision": int(stage["terrain_effect_authority_revision"]),
					"elapsed_usec": maxi(0, Time.get_ticks_usec() - int(stage["chunk_enqueued_usec"])),
					"progressive_visible_in_region": (_progressive_chunk_nodes[id]["nodes"] as Dictionary).size(),
					"focus_region": [focus_region_key.x, focus_region_key.y],
					"focused": region_key == focus_region_key,
					"has_authoritative_region_commit": active_regions.has(id),
					"coarse_patch_hidden": true,
				})


func _process_one_chunk_job() -> void:
	_dm18_commit_cached_region_step()
	var started_usec := Time.get_ticks_usec()
	_prune_progressive_chunks()
	_dm12_stage("mesh_prune", started_usec)
	started_usec = Time.get_ticks_usec()
	_process_progressive_chunk_publications()
	_dm12_stage("mesh_progressive", started_usec)
	started_usec = Time.get_ticks_usec()
	_process_completed_mesh_jobs()
	_dm12_stage("mesh_completed", started_usec)
	started_usec = Time.get_ticks_usec()
	_dispatch_mesh_jobs()
	_dm12_stage("mesh_dispatch", started_usec)
	if loading_regions.is_empty() and global_rebuild_pending:
		started_usec = Time.get_ticks_usec()
		_try_commit_global_rebuild()
		_dm12_stage("mesh_global_commit", started_usec)


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
			if _dm18_diagnostic_enabled:
				_dm18_job_times["stale_jobs"] += 1
			if _dm19_cold_profile != null:
				_dm19_cold_profile.stale_job()
			continue
		var stage: Dictionary = loading_regions[id]
		if int(stage["stage_token"]) != int(record["stage_token"]):
			if _dm18_diagnostic_enabled:
				_dm18_job_times["stale_jobs"] += 1
			if _dm19_cold_profile != null:
				_dm19_cold_profile.stale_job()
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
		if _dm18_diagnostic_enabled:
			_dm18_job_times["jobs"] += 1
			_dm18_job_times["snapshot_usec"] += int(record.get("snapshot_usec", 0))
			_dm18_job_times["worker_queue_usec"] += worker_queue_usec
			_dm18_job_times["worker_run_usec"] += worker_run_usec
			_dm18_job_times["upload_usec"] += upload_elapsed_usec
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
				"terrain_backend": String(cpu_result.get("backend", "sdf")),
				"dm11_canonical_fast_b4": bool(cpu_result.get("dm11_canonical_fast_b4", false)),
				"dm11_fast_sdf_cache": bool(cpu_result.get("dm11_fast_sdf_cache", false)),
				"dm11_canonical_sample_usec": int(cpu_result.get("dm11_canonical_sample_usec", 0)),
				"dm11_canonical_cell_usec": int(cpu_result.get("dm11_canonical_cell_usec", 0)),
				"dm11_canonical_uniform_cells": int(cpu_result.get("dm11_canonical_uniform_cells", 0)),
				"dm11_surface_mesh_usec": int((cpu_result.get("timings_usec", {}) as Dictionary).get("b4_surface_nets_usec", 0)),
				"snapshot_usec": int(record.get("snapshot_usec", 0)),
				"worker_queue_usec": worker_queue_usec,
				"worker_run_usec": worker_run_usec,
				"upload_usec": upload_elapsed_usec,
				"job_total_usec": Time.get_ticks_usec() - int(record["submitted_usec"]),
				"mesh_jobs_remaining": _mesh_jobs.size(),
				"completed_ready_count": completed_task_ids.size(),
				"dm9_speculative": bool(stage.get("dm9_speculative", false)),
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
		if _dm12_trace_enabled:
			_dm12_canonical_mesh_uploaded += 1
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
		if _dm19_cold_profile != null:
			_dm19_cold_profile.completed_job(
				id, Time.get_ticks_usec(),
				worker_queue_usec, worker_run_usec, upload_elapsed_usec
			)
		uploads_this_frame += 1
		if int(stage["next_index"]) >= (stage["chunk_coordinates"] as Array).size() \
			and int(stage["submit_index"]) >= (stage["chunk_coordinates"] as Array).size() \
			and int(stage["pending_count"]) == 0:
			_complete_region_stage(id)


func _dispatch_mesh_jobs() -> void:
	var dispatch_started_usec := Time.get_ticks_usec()
	# A blocked LOAD stage may be skipped for this invocation only. The
	# selector never advances its chunk index, so exact order within each
	# region and all revision/transaction checks remain unchanged.
	var skipped_ids: Dictionary = {}
	var successful_after_skip := false
	while _mesh_jobs.size() < _mesh_job_limit:
		if _mesh_dispatches_this_frame >= int(_stream_budget_state.get("dispatch_limit", 1)):
			_stream_dispatch_blocked("dispatch_cap")
			return
		var elapsed_usec := Time.get_ticks_usec() - dispatch_started_usec
		if (_mesh_dispatches_this_frame > 0 or not skipped_ids.is_empty()) \
		and elapsed_usec >= MESH_SNAPSHOT_FRAME_BUDGET_USEC:
			_stream_dispatch_blocked("snapshot_time_budget")
			if not skipped_ids.is_empty():
				_stream_window_skip_budget_exhausted += 1
			return
		var request := _next_mesh_job_request(skipped_ids)
		if request.is_empty():
			_stream_dispatch_blocked("no_eligible_stage_after_skips" if not skipped_ids.is_empty() else "no_eligible_stage")
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
					_stream_dispatch_blocked("effect_pending_corner")
					if StreamDispatchSelector.can_skip_pending(
						_stream_profile, String(stage["purpose"]),
						skipped_ids.size(), Time.get_ticks_usec() - dispatch_started_usec,
						MESH_SNAPSHOT_FRAME_BUDGET_USEC,
						_last_frame_ms < StreamBudgetPolicy.SPIKE_FRAME_MS
						and _last_process_work_ms < StreamBudgetPolicy.SPIKE_PROCESS_MS
						and String(_stream_budget_state.get("reason", "baseline")) not in ["frame_spike", "cooldown"]
					):
						skipped_ids[id] = true
						_stream_window_skipped_load_stages += 1
						continue
					_stream_dispatch_blocked("effect_skip_not_allowed_or_budget")
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
					_stream_dispatch_blocked("effect_pending_x_boundary")
					if StreamDispatchSelector.can_skip_pending(
						_stream_profile, String(stage["purpose"]),
						skipped_ids.size(), Time.get_ticks_usec() - dispatch_started_usec,
						MESH_SNAPSHOT_FRAME_BUDGET_USEC,
						_last_frame_ms < StreamBudgetPolicy.SPIKE_FRAME_MS
						and _last_process_work_ms < StreamBudgetPolicy.SPIKE_PROCESS_MS
						and String(_stream_budget_state.get("reason", "baseline")) not in ["frame_spike", "cooldown"]
					):
						skipped_ids[id] = true
						_stream_window_skipped_load_stages += 1
						continue
					_stream_dispatch_blocked("effect_skip_not_allowed_or_budget")
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
					_stream_dispatch_blocked("effect_pending_z_boundary")
					if StreamDispatchSelector.can_skip_pending(
						_stream_profile, String(stage["purpose"]),
						skipped_ids.size(), Time.get_ticks_usec() - dispatch_started_usec,
						MESH_SNAPSHOT_FRAME_BUDGET_USEC,
						_last_frame_ms < StreamBudgetPolicy.SPIKE_FRAME_MS
						and _last_process_work_ms < StreamBudgetPolicy.SPIKE_PROCESS_MS
						and String(_stream_budget_state.get("reason", "baseline")) not in ["frame_spike", "cooldown"]
					):
						skipped_ids[id] = true
						_stream_window_skipped_load_stages += 1
						continue
					_stream_dispatch_blocked("effect_skip_not_allowed_or_budget")
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
					_stream_dispatch_blocked("effect_pending_chunk")
					if StreamDispatchSelector.can_skip_pending(
						_stream_profile, String(stage["purpose"]),
						skipped_ids.size(), Time.get_ticks_usec() - dispatch_started_usec,
						MESH_SNAPSHOT_FRAME_BUDGET_USEC,
						_last_frame_ms < StreamBudgetPolicy.SPIKE_FRAME_MS
						and _last_process_work_ms < StreamBudgetPolicy.SPIKE_PROCESS_MS
						and String(_stream_budget_state.get("reason", "baseline")) not in ["frame_spike", "cooldown"]
					):
						skipped_ids[id] = true
						_stream_window_skipped_load_stages += 1
						continue
					_stream_dispatch_blocked("effect_skip_not_allowed_or_budget")
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
				int(stage.get("lod_by_coordinate", {}).get(coordinate, 0)),
				_experimental_mesh_backend == "b4"
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
				"dispatch_budget": int(_stream_budget_state.get("dispatch_limit", 1)),
				"dm9_speculative": bool(stage.get("dm9_speculative", false)),
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
		if not skipped_ids.is_empty() and not successful_after_skip:
			successful_after_skip = true
			_stream_window_skipped_then_dispatched += 1
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
		if _dm19_cold_profile != null:
			_dm19_cold_profile.submit(id, Time.get_ticks_usec(), snapshot_elapsed_usec)
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
	if _mesh_jobs.size() >= _mesh_job_limit:
		_stream_dispatch_blocked("worker_capacity")


func _prepare_terrain_effect_snapshot(
	base_snapshot: Dictionary,
	targets: Array
) -> Dictionary:
	if terrain_effect_runtime == null or not bool(terrain_effect_runtime.get("initialized")):
		return {"ok": false, "reason": "terrain_effect_runtime_unavailable"}
	var dm19_effect_started := Time.get_ticks_usec() if _dm19_cold_profile != null else 0
	var prepared: Dictionary = terrain_effect_runtime.prepare_targets_snapshot(
		base_snapshot, targets
	)
	if _dm19_cold_profile != null:
		_dm19_cold_profile.effect_result(
			prepared, Time.get_ticks_usec() - dm19_effect_started, targets.size()
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


func _next_mesh_job_request(excluded: Dictionary = {}) -> Dictionary:
	var selected := StreamDispatchSelector.next(loading_regions, excluded, focus_region_key)
	if not _dm3_enabled() or selected.is_empty():
		return selected
	var selected_stage: Dictionary = loading_regions[selected["id"]]
	if String(selected_stage.get("purpose", "")) != "load":
		return selected
	var best := selected
	var best_rank := 2147483647
	var forward := _dm3_forward()
	for id_value in loading_regions.keys():
		var id: String = id_value
		if excluded.has(id):
			continue
		var stage: Dictionary = loading_regions[id]
		if String(stage.get("purpose", "")) != "load":
			continue
		var index := int(stage.get("submit_index", 0))
		if index >= (stage["chunk_coordinates"] as Array).size():
			continue
		var priority := DM3Policy.rank(
			stage["region_key"], focus_region_key, forward, camera.global_position
		)
		if _dm9_prefetch_enabled and bool(stage.get("dm9_speculative", false)):
			priority += 100000000
		if priority < best_rank or (priority == best_rank and id < String(best.get("id", "~"))):
			best_rank = priority
			best = {
				"id": id, "coordinate": stage["chunk_coordinates"][index],
				"index": index,
			}
	return best


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
	if not _stage_lod_selection_is_current(stage) or (bool(stage.get("dm9_promoted", false)) and not _dm9_revision_valid(stage)):
		_supersede_region_stage(id)
		return
	if bool(stage.get("dm9_speculative", false)):
		if not bool(stage.get("dm9_ready", false)):
			stage["dm9_ready"] = true
			loading_regions[id] = stage
			_dm9_stages_ready += 1
			_dm9_trace_stage("ready", stage)
		return
	if global_rebuild_pending or stage["purpose"] == "full":
		_try_commit_global_rebuild()
		return
	if stage["purpose"] == "edit_transaction":
		_try_commit_edit_transaction()
		return
	loading_regions.erase(id)
	if _dm19_cold_profile != null and String(stage["purpose"]) == "load":
		_dm19_cold_profile.published(id, Time.get_ticks_usec())
	if _dm18_diagnostic_enabled and String(stage["purpose"]) == "load":
		var wall_usec := maxi(0, Time.get_ticks_usec() - int(stage.get("chunk_enqueued_usec", 0)))
		if bool(stage.get("dm18_cache_ready", false)):
			_dm18_hot_loads += 1
			_dm18_hot_load_total_usec += wall_usec
		else:
			_dm18_cold_loads += 1
			_dm18_cold_load_total_usec += wall_usec
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
		if _perf_trace_enabled:
			PerformanceTrace.emit("terrain_region_load_complete", {
				"region": [(stage["region_key"] as Vector2i).x, (stage["region_key"] as Vector2i).y],
				"purpose": String(stage["purpose"]),
				"stage_token": int(stage["stage_token"]),
				"elapsed_usec": maxi(0, Time.get_ticks_usec() - int(stage.get("chunk_enqueued_usec", 0))),
				"chunk_count": (stage["chunk_coordinates"] as Array).size(),
				"profile": _stream_profile,
				"dm9_promoted": bool(stage.get("dm9_promoted", false)),
				"dm9_promoted_wait_usec": maxi(0, Time.get_ticks_usec() - int(stage.get("dm9_promoted_usec", Time.get_ticks_usec()))) if bool(stage.get("dm9_promoted", false)) else 0,
				"dm9_prefetch_age_usec": maxi(0, Time.get_ticks_usec() - int(stage.get("chunk_enqueued_usec", 0))) if bool(stage.get("dm9_promoted", false)) else 0,
				"publish_usec": int(_last_region_publish_profile.get("duration_usec", 0)),
			})
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
	# Partial replacement may mix prior and new revision states by design.
	# Never claim this as a fully reusable 16-chunk cache snapshot.
	entry["dm18_identity_at_publish"] = {}
	active_regions[id] = entry
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
	if _dm3_enabled():
		_dm3_drop_shell(id)
		_dm3_drop_retired(id)
		# DM7: derived HIGH rocks stay visible until the real object renderer
		# publishes, which may lag behind this 16-chunk terrain commit.
	var region_nodes: Dictionary = {}
	var early_record: Dictionary = _progressive_chunk_nodes.get(id, {})
	var early_nodes: Dictionary = early_record.get("nodes", {}) if int(early_record.get("stage_token", -1)) == publication_token else {}
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
		elif early_nodes.has(chunk_id):
			node = early_nodes[chunk_id]
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
		# A mesh already visible with the exact stage token needs no second
		# GPU replacement; final commit only adopts the provisional node.
		if not early_nodes.has(chunk_id) or node.mesh != meshes[coordinate]:
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
	# Only the definitive 16-chunk commit replaces the derived overlay.
	if _clear_coarse_preview(id, "definitive"):
		_stream_window_coarse_replaced += 1
		if _perf_trace_enabled:
			PerformanceTrace.emit("terrain_region_coarse_replaced", {
				"region": [region_key.x, region_key.y],
				"stage_token": publication_token,
				"definitive_chunk_count": meshes.size(),
			})

	var stale_release_started_usec := Time.get_ticks_usec()
	var previous: Dictionary = active_regions.get(id, {})
	for old_id in previous.get("chunk_nodes", {}):
		if not region_nodes.has(old_id):
			released_node_count += 1
			_release_chunk_node(old_id, previous["chunk_nodes"][old_id])
	var stale_release_usec := Time.get_ticks_usec() - stale_release_started_usec

	var registry_started_usec := Time.get_ticks_usec()
	active_regions[id] = {
		"region_key": region_key, "world_state": state,
		"chunk_nodes": region_nodes,
		"dm18_identity_at_publish": _dm18_identity_for_state(state) if _dm18_cache_enabled else {}
	}
	# Visibility was non-authoritative; remove the provisional bookkeeping
	# only after all 16 nodes have been adopted by the committed region.
	_progressive_chunk_nodes.erase(id)
	if is_instance_valid(_environment_visual):
		_environment_visual.register_region(region_key)
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
		else:
			_queue_surface_cache_region(region_key)

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
	if _dm12_trace_enabled:
		_dm12_publish_region_count += 1
		_dm12_publish_region_usec += publish_duration_usec
		_dm12_publish_region_max_usec = maxi(_dm12_publish_region_max_usec, publish_duration_usec)
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



## DM5 cache is actual resident HIGH GPU mesh, never a fresh LOW proxy.
func _dm5_has_cached_high(id: String) -> bool:
	if _dm3_shell_nodes.has(id):
		var node: MeshInstance3D = _dm3_shell_nodes[id].get("node", null)
		return is_instance_valid(node) and node.mesh != null and node.visible
	if _dm3_retired_region_nodes.has(id):
		for value in _dm3_retired_region_nodes[id].get("nodes", []):
			var node: MeshInstance3D = value
			if is_instance_valid(node) and node.visible and node.mesh != null:
				return true
	return false


func _dm5_drop_decor(id: String, reason: String = "pruned") -> void:
	if not _dm5_decor_nodes.has(id):
		return
	var record: Dictionary = _dm5_decor_nodes[id]
	_dm5_decor_nodes.erase(id)
	if bool(record.get("rock_high", false)):
		_dm7_rock_visible_count = maxi(0, _dm7_rock_visible_count - 1)
		_dm7_high_rock_mesh_bytes = maxi(
			0, _dm7_high_rock_mesh_bytes - int(record.get("rock_high_bytes", 0))
		)
	var root: Node3D = record.get("root", null)
	if is_instance_valid(root):
		root.visible = false
		root.queue_free()
	_dm5_decor_evictions += 1
	if _perf_trace_enabled:
		PerformanceTrace.emit("dm5_low_decor_evicted", {
			"region": String(id),
			"reason": reason,
			"cache_regions_remaining": _dm5_decor_nodes.size(),
		})


func _dm5_build_decor_mesh(cpu: Dictionary, key: Vector2i) -> Dictionary:
	var root := Node3D.new()
	root.name = "DM5LowDetail_%d_%d" % [key.x, key.y]
	root.position = SpatialGrid.region_origin_world(key)
	root.set_meta("dm5_visual_only", true)
	var rock_count := 0
	var rock_data: Array = cpu.get("rocks", [])
	if not rock_data.is_empty():
		if _dm5_rock_mesh == null:
			_dm5_rock_mesh = SphereMesh.new()
			_dm5_rock_mesh.radius = 1.0
			_dm5_rock_mesh.height = 2.0
			_dm5_rock_mesh.radial_segments = 6
			_dm5_rock_mesh.rings = 3
			_dm5_rock_material = StandardMaterial3D.new()
			_dm5_rock_material.albedo_color = Color(0.38, 0.39, 0.37)
			_dm5_rock_material.roughness = 0.94
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _dm5_rock_mesh
		mm.instance_count = rock_data.size()
		for i in range(rock_data.size()):
			var rock: Dictionary = rock_data[i]
			var basis := Basis(Vector3.UP, float(rock["yaw"]))
			basis = basis.scaled_local(rock["scale"])
			mm.set_instance_transform(i, Transform3D(basis, rock["position"]))
		var rocks := MultiMeshInstance3D.new()
		rocks.name = "LowRocks"
		rocks.multimesh = mm
		rocks.material_override = _dm5_rock_material
		root.add_child(rocks)
		rock_count = rock_data.size()
	var water_positions: PackedVector3Array = cpu.get(
		"water_positions", PackedVector3Array()
	)
	var water_colors: PackedColorArray = cpu.get(
		"water_colors", PackedColorArray()
	)
	if not water_positions.is_empty() and water_positions.size() == water_colors.size():
		if _dm5_water_material == null:
			_dm5_water_material = StandardMaterial3D.new()
			_dm5_water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_dm5_water_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_dm5_water_material.cull_mode = BaseMaterial3D.CULL_DISABLED
			_dm5_water_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
			_dm5_water_material.vertex_color_use_as_albedo = true
			_dm5_water_material.albedo_color = Color.WHITE
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = water_positions
		arrays[Mesh.ARRAY_COLOR] = water_colors
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var water := MeshInstance3D.new()
		water.name = "LowWater"
		water.mesh = mesh
		water.material_override = _dm5_water_material
		water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(water)
	terrain_chunks_root.add_child(root)
	return {
		"root": root, "rocks": rock_count,
		"water_triangles": water_positions.size() / 3,
		"rock_high": false, "rock_high_count": 0,
		"rock_high_vertices": 0, "rock_high_bytes": 0,
	}


func _dm5_process_decor(now: int) -> void:
	# Keep derived rocks while the canonical terrain is already active but
	# its separately queued object renderer has not published yet.
	for id_value in _dm5_decor_nodes.keys().duplicate():
		var id: String = id_value
		var record: Dictionary = _dm5_decor_nodes[id]
		var key: Vector2i = record["region_key"]
		if active_regions.has(id):
			if is_instance_valid(object_stream) and object_stream.has_published_region(key):
				_dm5_drop_decor(id, "canonical_objects_ready")
		elif not _dm5_has_cached_high(id):
			_dm5_drop_decor(id, "terrain_cache_expired")
	if _last_frame_ms < 40.0 and _last_process_work_ms < 22.0:
		for task_id_value in _dm5_decor_jobs.keys().duplicate():
			var task_id := int(task_id_value)
			if not WorkerThreadPool.is_task_completed(task_id):
				continue
			WorkerThreadPool.wait_for_task_completion(task_id)
			var record: Dictionary = _dm5_decor_jobs[task_id]
			_dm5_decor_jobs.erase(task_id)
			var id: String = record["id"]
			_dm5_decor_pending.erase(id)
			var cpu: Dictionary = (record["job"] as RefCounted).result
			var key: Vector2i = record["region_key"]
			if int(record["seed"]) != world_seed or String(record["world_id"]) != world_id \
					or (active_regions.has(id) and object_stream.has_published_region(key)) \
					or (not active_regions.has(id) and not _dm5_has_cached_high(id)):
				break
			if not bool(cpu.get("valid", false)):
				_dm5_decor_retry_after_usec[id] = now + 5_000_000
				break
			_dm5_drop_decor(id, "replacement")
			var visuals := _dm5_build_decor_mesh(cpu, key)
			visuals["region_key"] = key
			visuals["seed"] = world_seed
			visuals["world_id"] = world_id
			visuals["rock_status"] = cpu.get("rock_status", "")
			_dm5_decor_nodes[id] = visuals
			_dm5_decor_published += 1
			if _perf_trace_enabled:
				PerformanceTrace.emit("dm5_low_decor_visible", {
					"region": [key.x, key.y],
					"rocks": int(cpu.get("rock_count", 0)),
					"rock_status": String(cpu.get("rock_status", "")),
					"ocean_triangles": int(cpu.get("ocean_triangles", 0)),
					"river_triangles": int(cpu.get("river_triangles", 0)),
					"source": "mod_registry_and_hydrology_v1_preview",
					"visual_only": true,
				})
			break
	if _dm5_decor_jobs.size() >= 1 or _last_frame_ms >= 40.0 \
			or _last_process_work_ms >= 22.0 or global_rebuild_pending \
			or not is_instance_valid(object_stream):
		return
	if not bool(object_stream.get("initialized")):
		return
	var registry: ContentDefinitionRegistry = object_stream.registry
	if registry == null:
		return
	# A region already HIGH-retained at radius 7..10 must KEEP its
	# LOW rock/water representation, even after leaving the radius-6
	# generation queue. On first retirement it must be eligible to acquire
	# those visuals without forcing a new terrain or mod source scope.
	var decor_targets: Array[Vector2i] = _dm3_shell_order.duplicate()
	for record_value in _dm3_retired_region_nodes.values():
		var record: Dictionary = record_value
		var key: Vector2i = record["region_key"]
		if not decor_targets.has(key):
			decor_targets.append(key)
	for record_value in _dm3_shell_nodes.values():
		var record: Dictionary = record_value
		var key: Vector2i = record["region_key"]
		if not decor_targets.has(key):
			decor_targets.append(key)
	for key in decor_targets:
		var id := _region_id(key)
		if active_regions.has(id) or not _dm5_has_cached_high(id) \
				or _dm5_decor_nodes.has(id) or _dm5_decor_pending.has(id):
			continue
		if now < int(_dm5_decor_retry_after_usec.get(id, 0)):
			continue
		var job := DM5DecorJob.new(world_seed, world_id, key, registry)
		var task_id := WorkerThreadPool.add_task(
			Callable(job, "run"), false, "DM5 LOW rock and water visuals"
		)
		if task_id < 0:
			return
		_dm5_decor_pending[id] = true
		_dm5_decor_jobs[task_id] = {
			"id": id, "region_key": key, "seed": world_seed,
			"world_id": world_id, "job": job,
		}
		break


## DM7: one fully batched HIGH rock mesh per region. The native mod
## generation and geological mesh algorithms run on a worker; only GPU
## resource publication and LOW->HIGH atomic visibility change run here.
## Water is unchanged LOW, and this visual is never interactive/authoritative.
func _dm7_commit_high_rocks(id: String, key: Vector2i, cpu: Dictionary) -> bool:
	if not _dm5_decor_nodes.has(id):
		return false
	var record: Dictionary = _dm5_decor_nodes[id]
	if bool(record.get("rock_high", false)):
		return true
	var root: Node3D = record.get("root", null)
	if not is_instance_valid(root) or not bool(cpu.get("ok", false)):
		return false
	var vertices: PackedVector3Array = cpu.get("positions", PackedVector3Array())
	var normals: PackedVector3Array = cpu.get("normals", PackedVector3Array())
	if vertices.size() != normals.size() or vertices.size() % 3 != 0:
		return false
	var new_node: MeshInstance3D = null
	if not vertices.is_empty():
		var result: Dictionary = DM7StaticBatch.commit(cpu)
		if not result.get("ok", false) or not result.get("mesh", null) is ArrayMesh:
			return false
		new_node = MeshInstance3D.new()
		new_node.name = "HIGH_ModRocks"
		new_node.mesh = result["mesh"]
		new_node.material_override = _dm5_rock_material
		new_node.set_meta("dm7_visual_only", true)
		root.add_child(new_node)
	# Install HIGH before hiding LOW; never display an empty-frame gap.
	var low_node: Node3D = root.get_node_or_null("LowRocks")
	if is_instance_valid(low_node):
		low_node.visible = false
	record["rock_high"] = true
	record["rock_high_count"] = int(cpu.get("rock_count", 0))
	record["rock_high_vertices"] = vertices.size()
	record["rock_high_bytes"] = vertices.size() * 24
	record["rock_high_node"] = new_node
	_dm5_decor_nodes[id] = record
	_dm7_high_rock_publications += 1
	_dm7_rock_visible_count += 1
	_dm7_high_rock_mesh_bytes += int(record["rock_high_bytes"])
	if _perf_trace_enabled:
		PerformanceTrace.emit("dm7_rock_high_visible", {
			"region": [key.x, key.y],
			"rocks": int(cpu.get("rock_count", 0)),
			"vertices": vertices.size(),
			"triangles": int(cpu.get("triangle_count", 0)),
			"mesh_cpu_payload_bytes": int(record["rock_high_bytes"]),
			"worker_usec": int(cpu.get("worker_usec", 0)),
			"geometry_usec": int(cpu.get("geometry_usec", 0)),
			"rock_high_radius": DM7_ROCK_HIGH_RADIUS,
			"terrain_high_radius": DM3Policy.ACTIVE_RADIUS,
			"visual_only": true,
			"matches_canonical_pristine_geometry": true,
		})
	return true


func _dm7_rock_high_receipt_if_complete() -> void:
	# The radial target set changes as the player moves WITHIN one
	# region; completion must be keyed by the actual target set, not focus.
	var player_position: Vector3 = orbit_target
	var target_ids: Array[String] = []
	for key in _dm3_shell_order:
		if not DM3Policy.within_rock_high(key, player_position):
			continue
		target_ids.append(_region_id(key))
		var id := _region_id(key)
		if active_regions.has(id) and object_stream.has_published_region(key):
			continue
		if not _dm5_decor_nodes.has(id) \
				or not bool(_dm5_decor_nodes[id].get("rock_high", false)):
			return
	# Canonical regions with zero generated rocks may not emit a geometry
	# prewarm publication. Their terrain is still authoritative and HIGH;
	# exterior radial targets require derived HIGH rock geometry.
	var canonical_rock_publications := 0
	for z in range(focus_region_key.y - 1, focus_region_key.y + 2):
		for x in range(focus_region_key.x - 1, focus_region_key.x + 2):
			var key := Vector2i(x, z)
			if not active_regions.has(_region_id(key)):
				return
			if object_stream.has_published_region(key):
				canonical_rock_publications += 1
	target_ids.sort()
	var signature := "%d:%d:%d" % [
		focus_region_key.x, focus_region_key.y, hash(target_ids)
	]
	if _dm8_rock_receipt_signature == signature:
		return
	_dm8_rock_receipt_signature = signature
	_dm7_rock_high_completion_focus = focus_region_key
	_dm7_rock_high_completion_receipts += 1
	var receipt := {
		"focus": [focus_region_key.x, focus_region_key.y],
		"radius": DM7_ROCK_HIGH_RADIUS,
		"terrain_high_radius": DM3Policy.ACTIVE_RADIUS,
		"region_count": target_ids.size() + 9,
		"outer_region_count": target_ids.size(),
		"radial_radius_m": DM3Policy.radial_radius_m(DM7_ROCK_HIGH_RADIUS),
		"player_xz_m": [player_position.x, player_position.z],
		"canonical_core_count": 9,
		"canonical_object_published_regions": canonical_rock_publications,
		"rock_high_resident_regions": _dm7_rock_visible_count,
		"geometry": "procedural_rock_shape_descriptor",
		"visual_only": true,
		"receipt": _dm7_rock_high_completion_receipts,
	}
	print("DM8_ROCK_HIGH_RADIAL_COMPLETE: " + JSON.stringify(receipt))
	if _perf_trace_enabled:
		PerformanceTrace.emit("dm8_rock_high_radial_complete", receipt)


func _dm7_process_high_rocks(now: int) -> void:
	# Completed jobs are accepted only while their same-seed/world visual
	# exists; stale work never promotes an evicted or canonical region.
	if _last_frame_ms < 40.0 and _last_process_work_ms < 22.0:
		for task_id_value in _dm7_rock_jobs.keys().duplicate():
			var task_id := int(task_id_value)
			if not WorkerThreadPool.is_task_completed(task_id):
				continue
			WorkerThreadPool.wait_for_task_completion(task_id)
			var record: Dictionary = _dm7_rock_jobs[task_id]
			_dm7_rock_jobs.erase(task_id)
			var id: String = record["id"]
			_dm7_rock_pending.erase(id)
			var key: Vector2i = record["region_key"]
			if int(record["seed"]) != world_seed \
					or String(record["world_id"]) != world_id \
					or not _dm5_decor_nodes.has(id) \
					or (active_regions.has(id) and object_stream.has_published_region(key)):
				break
			var cpu: Dictionary = (record["job"] as RefCounted).result
			if not _dm7_commit_high_rocks(id, key, cpu):
				_dm7_rock_retry_after_usec[id] = now + 5_000_000
				if _perf_trace_enabled:
					PerformanceTrace.emit("dm7_rock_high_failed", {
						"region": [key.x, key.y],
						"reason": String(cpu.get("reason", "commit_failed")),
					})
			break
	_dm7_rock_high_receipt_if_complete()
	if _dm7_rock_jobs.size() >= DM7_MAX_ROCK_JOBS_IN_FLIGHT \
			or _last_frame_ms >= 40.0 or _last_process_work_ms >= 22.0 \
			or global_rebuild_pending or cave_section_enabled \
			or not is_instance_valid(object_stream) \
			or not bool(object_stream.get("initialized")):
		return
	var registry: ContentDefinitionRegistry = object_stream.registry
	if registry == null:
		return
	# The terrain's queue is strictly nearest and camera-facing first.
	# Build each FULL geological rock mesh by radius 4, not only at 1..2.
	for key in _dm3_shell_order:
		if not DM3Policy.within_rock_high(key, orbit_target):
			continue
		var id := _region_id(key)
		if active_regions.has(id) or not _dm5_decor_nodes.has(id) \
				or _dm7_rock_pending.has(id) \
				or bool(_dm5_decor_nodes[id].get("rock_high", false)):
			continue
		if not _dm5_has_cached_high(id):
			continue
		if now < int(_dm7_rock_retry_after_usec.get(id, 0)):
			continue
		var job := DM7RockJob.new(world_seed, world_id, key, registry)
		var task_id := WorkerThreadPool.add_task(
			Callable(job, "run"), false, "DM7 exact HIGH rock preview"
		)
		if task_id < 0:
			return
		_dm7_rock_pending[id] = true
		_dm7_rock_jobs[task_id] = {
			"id": id, "region_key": key, "seed": world_seed,
			"world_id": world_id, "job": job,
		}
		break


## DM3 region-space preview only. Do not expand authoritative world states,
## simulation scopes, mod effects, persistence or the 81-source projection cap.
func _dm3_enabled() -> bool:
	return _experimental_mesh_backend == "b4" \
		and _stream_profile == "adaptive-skip-progressive"


func _dm3_forward() -> Vector3:
	var forward: Vector3 = -camera.global_transform.basis.z
	forward.y = 0.0
	return forward.normalized() if forward.length_squared() > 0.00001 else Vector3.FORWARD


func _dm3_drop_shell(id: String, reason: String = "replaced") -> void:
	if not _dm3_shell_nodes.has(id):
		return
	var record: Dictionary = _dm3_shell_nodes[id]
	_dm3_shell_nodes.erase(id)
	var node: MeshInstance3D = record["node"]
	if is_instance_valid(node):
		node.visible = false
		node.queue_free()
	_dm3_shell_evicted += 1
	if reason == "expired":
		_dm6_ttl_evicted_total += 1
	if _perf_trace_enabled and reason == "expired":
		PerformanceTrace.emit("dm6_high_expired", {
			"region": [record["region_key"].x, record["region_key"].y],
			"source": "shell", "reason": reason,
		})


func _dm3_drop_retired(id: String, reason: String = "replaced") -> void:
	if not _dm3_retired_region_nodes.has(id):
		return
	var record: Dictionary = _dm3_retired_region_nodes[id]
	_dm3_retired_region_nodes.erase(id)
	for node_value in record["nodes"]:
		var node: MeshInstance3D = node_value
		if is_instance_valid(node):
			node.visible = false
			node.queue_free()
	if reason == "expired":
		_dm6_ttl_evicted_total += 1
	if _perf_trace_enabled and reason == "expired":
		PerformanceTrace.emit("dm6_high_expired", {
			"region": [record["region_key"].x, record["region_key"].y],
			"source": "retired", "reason": reason,
		})


func _dm3_retire_region_nodes(id: String, entry: Dictionary) -> void:
	_dm3_drop_shell(id)
	_dm3_drop_retired(id)
	var visuals: Array[MeshInstance3D] = []
	for chunk_id_value in entry["chunk_nodes"].keys():
		var chunk_id: String = chunk_id_value
		var node: MeshInstance3D = entry["chunk_nodes"][chunk_id]
		if not is_instance_valid(node):
			continue
		# The (0,0) scene template is permanent, so clone only its
		# already-built mesh resource into a transient cached visual before
		# releasing the template. Otherwise the return path has a chunk hole.
		if node == terrain_mesh_template:
			var clone := MeshInstance3D.new()
			clone.name = "DM5RetainedTemplate_%s" % id.replace(",", "_")
			clone.mesh = node.mesh
			clone.position = node.position
			clone.material_override = node.material_override
			terrain_chunks_root.add_child(clone)
			visuals.append(clone)
			_release_chunk_node(chunk_id, node)
			continue
		var triangles := int(node.get_meta("mesh_triangle_count", -1))
		var vertices := int(node.get_meta("mesh_vertex_count", -1))
		if triangles < 0:
			triangles = _mesh_triangle_count(node.mesh)
		if vertices < 0:
			vertices = _mesh_vertex_count(node.mesh)
		_active_triangle_count -= triangles
		_active_vertex_count -= vertices
		chunk_nodes.erase(chunk_id)
		_published_lod_by_chunk.erase(chunk_id)
		_lod_fallback_chunks.erase(chunk_id)
		node.set_meta("dm3_visual_only", true)
		visuals.append(node)
	if not visuals.is_empty():
		_dm3_retired_region_nodes[id] = {
			"region_key": entry["region_key"],
			"nodes": visuals,
			"last_near_usec": Time.get_ticks_usec(),
			"seed": world_seed,
		}


func _dm3_prune_shells(now: int) -> void:
	var focus: Vector2i = focus_region_key
	_dm6_outer_high_visible_count = 0
	for id_value in _dm3_shell_nodes.keys().duplicate():
		var id: String = id_value
		var record: Dictionary = _dm3_shell_nodes[id]
		var in_retention := DM3Policy.within_retention(
			record["region_key"], orbit_target
		)
		if active_regions.has(id) or int(record["seed"]) != world_seed:
			_dm3_drop_shell(id, "authoritative_or_seed_change")
			continue
		if not DM3Policy.keep_radial(
				int(record["last_near_usec"]), now,
				record["region_key"], orbit_target):
			_dm3_drop_shell(id, "expired")
			continue
		if in_retention:
			record["last_near_usec"] = now
			_dm3_shell_nodes[id] = record
		if not DM3Policy.within_high(record["region_key"], orbit_target):
			var retained_node: MeshInstance3D = record.get("node", null)
			if is_instance_valid(retained_node) and retained_node.mesh != null:
				if not retained_node.visible:
					retained_node.visible = true
					_dm6_retained_high_visibility_repairs += 1
				_dm6_outer_high_visible_count += 1
	for id_value in _dm3_retired_region_nodes.keys().duplicate():
		var id: String = id_value
		var record: Dictionary = _dm3_retired_region_nodes[id]
		var in_retention := DM3Policy.within_retention(
			record["region_key"], orbit_target
		)
		# Uniform B4 HIGH throughout the view. Keep retired meshes while
		# a new HIGH shell is generated, preventing motion-created holes.
		if active_regions.has(id) or int(record["seed"]) != world_seed:
			_dm3_drop_retired(id, "authoritative_or_seed_change")
			continue
		if not DM3Policy.keep_radial(
				int(record["last_near_usec"]), now,
				record["region_key"], orbit_target):
			_dm3_drop_retired(id, "expired")
			continue
		if in_retention:
			record["last_near_usec"] = now
			_dm3_retired_region_nodes[id] = record
		if not DM3Policy.within_high(record["region_key"], orbit_target):
			for node_value in record["nodes"]:
				var retained_node: MeshInstance3D = node_value
				if is_instance_valid(retained_node) and retained_node.mesh != null:
					if not retained_node.visible:
						retained_node.visible = true
						_dm6_retained_high_visibility_repairs += 1
			_dm6_outer_high_visible_count += 1
	# DM6: strict retention means hard-cap-based eviction is forbidden. The
	# old 48/512 caps caused reloading and visible HIGH->LOW flashes when
	# returning through the radius-10 history. Retain GPU meshes through
	# the full TTL. Budget excess is observable, not an eviction reason.
	if (_dm3_retired_region_nodes.size() > DM3Policy.MAX_DETAILED_VISUAL_REGIONS
			or _dm3_shell_nodes.size() > DM3Policy.MAX_SHELL_REGIONS) \
			and now - _dm6_last_memory_warning_usec > 5_000_000:
		_dm6_last_memory_warning_usec = now
		if _perf_trace_enabled:
			PerformanceTrace.emit("dm6_retention_capacity_warning", {
				"high_shell_count": _dm3_shell_nodes.size(),
				"retired_high_count": _dm3_retired_region_nodes.size(),
				"warning_only": true,
				"forced_high_evictions": 0,
			})
	var dm7_rocks_retained_outer := 0
	for decor_value in _dm5_decor_nodes.values():
		var decor: Dictionary = decor_value
		if bool(decor.get("rock_high", false)) \
				and not active_regions.has(_region_id(decor["region_key"])) \
				and not DM3Policy.within_rock_high(
					decor["region_key"], orbit_target):
			dm7_rocks_retained_outer += 1
	if _perf_trace_enabled:
		PerformanceTrace.emit("dm4_region_b4_high_window", {
			"dm7_rocks_high_retained_beyond_radius4": dm7_rocks_retained_outer,
			"dm5_cache_hits": _dm5_cache_hits,
			"dm6_retained_high_reused_total": _dm6_retained_high_reused_total,
			"dm7_rock_high_radius": DM7_ROCK_HIGH_RADIUS,
			"dm8_rock_high_radius_m": DM3Policy.radial_radius_m(DM7_ROCK_HIGH_RADIUS),
			"dm8_terrain_high_radius_m": DM3Policy.radial_radius_m(DM3Policy.ACTIVE_RADIUS),
			"dm8_retain_radius_m": DM3Policy.radial_radius_m(DM3Policy.RETAIN_RADIUS),
			"dm8_player_xz_m": [orbit_target.x, orbit_target.z],
			"dm8_high_radius_new_vs_old_region_count": _dm3_shell_order.size() + 9 - 169,
			"dm8_radial_targets": _dm3_shell_order.size(),
			"dm8_radial_scan_count": _dm8_radial_scan_count,
			"dm8_radial_scan_avg_usec": int(
				float(_dm8_radial_scan_total_usec) / float(maxi(1, _dm8_radial_scan_count))
			),
			"dm8_radial_scan_max_usec": _dm8_radial_scan_max_usec,
			"dm7_rock_high_resident_regions": _dm7_rock_visible_count,
			"dm7_rock_high_mesh_payload_bytes": _dm7_high_rock_mesh_bytes,
			"dm7_rock_high_published_total": _dm7_high_rock_publications,
			"dm6_low_preview_prevented_total": _dm6_low_preview_prevented_total,
			"dm6_ttl_evicted_total": _dm6_ttl_evicted_total,
			"dm6_high_visible_beyond_active_radius": _dm6_outer_high_visible_count,
			"dm6_visibility_repairs_total": _dm6_retained_high_visibility_repairs,
			"dm5_decor_regions": _dm5_decor_nodes.size(),
			"dm5_decor_published": _dm5_decor_published,
			"dm5_decor_evictions": _dm5_decor_evictions,
			"focus": [focus.x, focus.y],
			"shell_regions": _dm3_shell_nodes.size(),
			"retired_detail_regions": _dm3_retired_region_nodes.size(),
			"jobs_in_flight": _dm3_shell_jobs.size(),
			"built": _dm3_shell_built,
			"evicted": _dm3_shell_evicted,
			"lod_promoted": _dm3_shell_lod_promoted,
			"high_resolution_regions": _dm3_shell_nodes.size(),
			"pending_or_active_jobs": _dm3_shell_pending.size(),
			"active_radius": DM3Policy.ACTIVE_RADIUS,
			"fine_radius": DM3Policy.FINE_RADIUS,
			"retain_radius": DM3Policy.RETAIN_RADIUS,
			"retention_seconds": 20,
		})



## DM8 instrumentation: outstanding visual region gaps and their ages.
## Sample at the existing 200ms region reconciliation cadence. It never
## issues extra jobs or changes priority; the next phase can use the
## evidence to target the actual worker/snapshot/commit bottleneck.
func _dm8_sample_gap_pressure(now: int) -> void:
	if not _perf_trace_enabled:
		return
	var terrain_ready := 0
	var rock_targets := 0
	var rock_ready := 0
	var forward := _dm3_forward()
	var first_gap_distance_m := INF
	var front_gap_count := 0
	var new_requests := 0
	var gap_ages_ms: Array[int] = []
	var currently_requested: Dictionary = {}
	for key in _dm3_shell_order:
		var id := _region_id(key)
		currently_requested[id] = true
		var ready := active_regions.has(id) or _dm5_has_cached_high(id)
		var distance_m := DM3Policy.world_distance_m(key, orbit_target)
		if ready:
			terrain_ready += 1
			_dm8_gap_first_requested_usec.erase(id)
		else:
			first_gap_distance_m = minf(first_gap_distance_m, distance_m)
			if not _dm8_gap_first_requested_usec.has(id):
				_dm8_gap_first_requested_usec[id] = now
				new_requests += 1
			gap_ages_ms.append(int(
				maxi(0, now - int(_dm8_gap_first_requested_usec[id])) / 1000
			))
			var direction := DM3Policy.center_world(key) - Vector2(
				orbit_target.x, orbit_target.z
			)
			var facing := Vector2(forward.x, forward.z)
			if direction.length_squared() > 0.000001 and facing.length_squared() > 0.000001:
				if direction.normalized().dot(facing.normalized()) > 0.5:
					front_gap_count += 1
		if DM3Policy.within_rock_high(key, orbit_target):
			rock_targets += 1
			if active_regions.has(id) and object_stream.has_published_region(key):
				rock_ready += 1
			elif _dm5_decor_nodes.has(id) and bool(
					_dm5_decor_nodes[id].get("rock_high", false)):
				rock_ready += 1
	for id_value in _dm8_gap_first_requested_usec.keys().duplicate():
		if not currently_requested.has(id_value):
			_dm8_gap_first_requested_usec.erase(id_value)
	gap_ages_ms.sort()
	_dm8_gap_sample_count += 1
	var gap_p95_ms := 0
	if not gap_ages_ms.is_empty():
		var index := mini(
			gap_ages_ms.size() - 1, ceili(0.95 * float(gap_ages_ms.size())) - 1
		)
		gap_p95_ms = gap_ages_ms[index]
	PerformanceTrace.emit("dm8_radial_gap_sample", {
		"focus": [focus_region_key.x, focus_region_key.y],
		"player_xz_m": [orbit_target.x, orbit_target.z],
		"terrain_required_outer": _dm3_shell_order.size(),
		"terrain_ready_outer": terrain_ready,
		"terrain_gap_outer": _dm3_shell_order.size() - terrain_ready,
		"terrain_gap_nearest_m": first_gap_distance_m if is_finite(first_gap_distance_m) else -1.0,
		"terrain_gap_front_cone": front_gap_count,
		"terrain_gap_age_p95_ms": gap_p95_ms,
		"terrain_gap_new_since_last_scan": new_requests,
		"rock_required_outer": rock_targets,
		"rock_ready_outer": rock_ready,
		"rock_gap_outer": rock_targets - rock_ready,
		"terrain_high_worker_jobs": _dm3_shell_jobs.size(),
		"terrain_high_pending_regions": _dm3_shell_pending.size(),
		"rock_high_worker_jobs": _dm7_rock_jobs.size(),
		"rock_high_pending_regions": _dm7_rock_pending.size(),
		"low_decor_worker_jobs": _dm5_decor_jobs.size(),
		"canonical_loading_regions": loading_regions.size(),
		"canonical_mesh_jobs": _mesh_jobs.size(),
		"sample": _dm8_gap_sample_count,
	})


## Completion requires EVERY region in the actual-player radius-130m disc to have a
## HIGH B4 visual (or a fully committed canonical B4 region), not merely
## a submitted worker or an approximate coarse preview. Emit once/focus.
func _dm4_emit_full_high_receipt_if_ready() -> void:
	if not _dm3_enabled():
		return
	var shell_targets := _dm3_shell_order
	var target_ids: Array[String] = []
	for key in shell_targets:
		target_ids.append(_region_id(key))
	target_ids.sort()
	var signature := "%d:%d:%d" % [
		focus_region_key.x, focus_region_key.y, hash(target_ids)
	]
	if _dm8_high_receipt_signature == signature:
		return
	var high_shell_count := 0
	var canonical_count := 0
	for region in shell_targets:
		var id := _region_id(region)
		if active_regions.has(id):
			canonical_count += 1
			continue
		if _dm3_retired_region_nodes.has(id):
			canonical_count += 1
			continue
		if not _dm3_shell_nodes.has(id):
			return
		var shell: Dictionary = _dm3_shell_nodes[id]
		if int(shell.get("lod", 1)) != 0 or not is_instance_valid(shell.get("node", null)):
			return
		high_shell_count += 1
	# The central 3x3 must have its definitive region mesh published.
	for z in range(focus_region_key.y - 1, focus_region_key.y + 2):
		for x in range(focus_region_key.x - 1, focus_region_key.x + 2):
			if not active_regions.has(_region_id(Vector2i(x, z))):
				return
	_dm4_high_complete_focus = focus_region_key
	_dm8_high_receipt_signature = signature
	_dm4_high_complete_receipts += 1
	var receipt := {
		"focus": [focus_region_key.x, focus_region_key.y],
		"requested_region_count": shell_targets.size() + 9,
		"radial_radius_m": DM3Policy.radial_radius_m(DM3Policy.ACTIVE_RADIUS),
		"player_xz_m": [orbit_target.x, orbit_target.z],
		"reference_center_region_count": DM3Policy.expected_region_count(),
		"high_shell_regions": high_shell_count,
		"retired_detail_regions": canonical_count,
		"canonical_core_regions": 9,
		"mesh_step_m": 0.5,
		"backend": "b4",
		"visual_only_outside_authority": true,
		"receipt_number": _dm4_high_complete_receipts,
	}
	print("DM8_HIGH_RADIAL_COMPLETE: " + JSON.stringify(receipt))
	if _perf_trace_enabled:
		PerformanceTrace.emit("dm8_high_radial_complete", receipt)


func _dm9_visual_limit_for_frame() -> int:
	if not _dm9_visual_adaptive:
		return _dm9_visual_worker_limit
	var core_ready := true
	for key in _region_keys_within_radius(focus_region_key, REQUEST_RADIUS):
		if not active_regions.has(_region_id(key)):
			core_ready = false
			break
	return DM9VisualBudget.effective_limit(
		_dm9_visual_worker_limit,
		core_ready,
		loading_regions.size(),
		_mesh_jobs.size(),
		_last_f10_speed_mps,
		_last_frame_ms,
		_last_process_work_ms
	)


func _dm3_process_shells() -> void:
	if not _dm3_enabled():
		return
	var now := Time.get_ticks_usec()
	_dm9_visual_worker_effective_limit = _dm9_visual_limit_for_frame()
	# Retired meshes must not survive a world seed switch.
	if _dm3_shell_seed != world_seed:
		for id_value in _dm3_shell_nodes.keys().duplicate():
			_dm3_drop_shell(String(id_value))
		for id_value in _dm3_retired_region_nodes.keys().duplicate():
			_dm3_drop_retired(String(id_value))
		_dm3_shell_seed = world_seed
		_dm3_shell_order.clear()
		_dm3_last_scan_usec = 0
	# One mesh upload/frame. All workers are CPU-only, detached and pure.
	if _last_frame_ms < 40.0:
		for task_id_value in _dm3_shell_jobs.keys().duplicate():
			var task_id := int(task_id_value)
			var record: Dictionary = _dm3_shell_jobs[task_id]
			var native_thread: Thread = record.get("thread", null)
			if native_thread != null:
				if native_thread.is_alive():
					continue
				native_thread.wait_to_finish()
			else:
				if not WorkerThreadPool.is_task_completed(task_id):
					continue
				WorkerThreadPool.wait_for_task_completion(task_id)
			_dm3_shell_jobs.erase(task_id)
			var id: String = record["id"]
			_dm3_shell_pending.erase(id)
			var key: Vector2i = record["region_key"]
			var dist := DM3Policy.distance(focus_region_key, key)
			var dist_m := DM3Policy.world_distance_m(key, orbit_target)
			var level := DM3Policy.lod_for_distance(dist)
			var job: RefCounted = record["job"]
			var cpu: Dictionary = job.get("result")
			var dm9_shell_queue_usec := maxi(0, int(job.get("started_usec")) - int(record.get("submitted_usec", now)))
			var dm9_shell_run_usec := maxi(0, int(job.get("finished_usec")) - int(job.get("started_usec")))
			if int(record["seed"]) != world_seed \
			or dist < 2 or not DM3Policy.within_high(key, orbit_target) \
			or level != int(record["lod"]) \
			or active_regions.has(id) or loading_regions.has(id) \
			or global_rebuild_pending or cave_section_enabled:
				break
			if not cpu.get("valid", false) or int(cpu.get("triangle_count", 0)) == 0 \
					or String(cpu.get("backend", "")) != "b4" \
					or not is_equal_approx(float(cpu.get("sample_step", 0.0)), 0.5):
				_dm3_shell_retry_after_usec[id] = now + 5_000_000
				break
			var dm9_shell_publish_started_usec := Time.get_ticks_usec()
			var mesh: ArrayMesh = CoarsePreviewJob.mesh_from_cpu_data(cpu)
			if mesh.get_surface_count() == 0:
				_dm3_shell_retry_after_usec[id] = now + 5_000_000
				break
			var node: MeshInstance3D
			var previous_lod := -1
			if _dm3_shell_nodes.has(id):
				var current: Dictionary = _dm3_shell_nodes[id]
				node = current["node"]
				previous_lod = int(current["lod"])
			else:
				node = MeshInstance3D.new()
				node.name = "DM3VisualRegion_%d_%d" % [key.x, key.y]
				node.material_override = terrain_mesh_template.material_override
				node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				node.position = SpatialGrid.region_origin_world(key)
				terrain_chunks_root.add_child(node)
			node.mesh = mesh
			node.visible = true
			# There must never be a concurrent E7 LOW preview on the same
			# screen position after the true B4 HIGH resource is published.
			_clear_coarse_preview(id, "dm6_high_replaces_low")
			node.set_meta("dm3_visual_only", true)
			node.set_meta("dm3_preview_lod", level)
			_dm3_shell_nodes[id] = {
				"node": node,
				"region_key": key,
				"lod": level,
				"seed": world_seed,
				"last_near_usec": now,
			}
			# Decorators can now be generated once for this true B4 HIGH
			# region; never resample rocks/water from E7 low preview.
			_dm3_drop_retired(id)
			if previous_lod == 1 and level == 0:
				_dm3_shell_lod_promoted += 1
			_dm3_shell_built += 1
			_dm9_shell_completed_total += 1
			if _dm12_trace_enabled:
				_dm12_visual_publish_count += 1
				_dm12_visual_publish_usec += Time.get_ticks_usec() - dm9_shell_publish_started_usec
			if _perf_trace_enabled:
				PerformanceTrace.emit("dm9_visual_shell_complete", {
					"region": [key.x, key.y],
					"worker_queue_usec": dm9_shell_queue_usec,
					"worker_run_usec": dm9_shell_run_usec,
					"field_generate_usec": int(cpu.get("field_generate_usec", 0)),
					"precompute_usec": int(cpu.get("precompute_usec", 0)),
					"lattice_usec": int(cpu.get("lattice_usec", 0)),
					"cell_rebuild_usec": int(cpu.get("cell_rebuild_usec", 0)),
					"uniform_cells_skipped": int(cpu.get("uniform_cells_skipped", 0)),
					"chunk_build_usec": int(cpu.get("chunk_build_usec", 0)),
					"chunk_combine_usec": int(cpu.get("chunk_combine_usec", 0)),
					"fast_pristine": bool(cpu.get("fast_pristine", false)),
					"surface_mesh_usec": int(cpu.get("surface_mesh_usec", 0)),
					"main_thread_publish_usec": Time.get_ticks_usec() - dm9_shell_publish_started_usec,
					"in_flight": _dm3_shell_jobs.size(),
					"worker_limit": _dm9_visual_worker_limit,
					"worker_effective_limit": _dm9_visual_worker_effective_limit,
					"adaptive": _dm9_visual_adaptive,
					"dm11_visual_lane": "native_low" if native_thread != null else "worker_pool",
					"dm11_thread_id": int(job.get("worker_thread_id")),
				})
			if _perf_trace_enabled:
				PerformanceTrace.emit("dm4_region_b4_high_visible", {
					"region": [key.x, key.y],
					"lod": level,
					"backend": "b4",
					"sample_step_m": float(cpu.get("sample_step", 0.0)),
					"distance_regions": dist,
					"distance_player_m": dist_m,
					"triangle_count": int(cpu.get("triangle_count", 0)),
					"worker_usec": int(cpu.get("worker_usec", 0)),
					"retained": previous_lod >= 0,
					"visual_only": true,
				})
			break
	if now - _dm3_last_scan_usec >= DM3Policy.RESCAN_USEC or _dm3_shell_order.is_empty():
		_dm3_last_scan_usec = now
		var radial_scan_started := Time.get_ticks_usec()
		_dm3_shell_order = DM3Policy.desired_regions(
			focus_region_key, _dm3_forward(), orbit_target
		)
		var scan_usec := Time.get_ticks_usec() - radial_scan_started
		_dm8_radial_scan_count += 1
		_dm8_radial_scan_total_usec += scan_usec
		_dm8_radial_scan_max_usec = maxi(_dm8_radial_scan_max_usec, scan_usec)
		_dm3_prune_shells(now)
		_dm5_process_decor(now)
		_dm7_process_high_rocks(now)
		_dm8_sample_gap_pressure(now)
		_dm4_emit_full_high_receipt_if_ready()
	# Prioritize authoritative SDF/B4 jobs over the derived circular halo.
	# DM9 can submit up to four CPU-only derived HIGH jobs, but only while idle and canonical-ready.
	# One main-thread upload/frame remains enforced above; sorted queue remains stable.
	if _last_frame_ms >= 40.0 or _last_process_work_ms >= 22.0 \
			or _dm3_shell_jobs.size() >= _dm9_visual_worker_effective_limit \
			or global_rebuild_pending or cave_section_enabled:
		return
	for key in _dm3_shell_order:
		if _dm3_shell_jobs.size() >= _dm9_visual_worker_effective_limit:
			break
		var id := _region_id(key)
		if active_regions.has(id) or loading_regions.has(id):
			continue
		var dist := DM3Policy.distance(focus_region_key, key)
		if dist < 2 or not DM3Policy.within_high(key, orbit_target):
			continue
		if _dm3_retired_region_nodes.has(id) and DM3Policy.within_high(
				key, orbit_target):
			continue
		var desired_lod := DM3Policy.lod_for_distance(dist)
		if _dm3_shell_nodes.has(id) \
			and int(_dm3_shell_nodes[id]["lod"]) == desired_lod:
			continue
		if _dm3_shell_pending.has(id):
			continue
		if now < int(_dm3_shell_retry_after_usec.get(id, 0)):
			continue
		var job := DM3VisualJob.new(world_seed, key, desired_lod, _dm9_fast_b4)
		var task_id := -1
		var native_thread: Thread = null
		if _dm11_visual_dedicated:
			native_thread = Thread.new()
			var started := native_thread.start(Callable(job, "run"), Thread.PRIORITY_LOW)
			if started != OK:
				push_warning("DM11_VISUAL_LANE: Thread.start failed; no job was submitted (%d)" % started)
				return
			task_id = _dm11_next_visual_task_id
			_dm11_next_visual_task_id -= 1
		else:
			task_id = WorkerThreadPool.add_task(
				Callable(job, "run"), false, "DM3 derived region halo"
			)
			if task_id < 0:
				return
		_dm3_shell_pending[id] = desired_lod
		_dm3_shell_jobs[task_id] = {
			"id": id,
			"region_key": key,
			"lod": desired_lod,
			"seed": world_seed,
			"job": job,
			"thread": native_thread,
			"submitted_usec": Time.get_ticks_usec(),
		}
		_dm9_shell_started_total += 1
		if _dm9_visual_worker_limit <= 1:
			break


func _unload_region(id: String) -> void:
	_discard_progressive_chunks(id, "unload")
	if not active_regions.has(id):
		return
	var entry: Dictionary = active_regions[id]
	if is_instance_valid(_environment_visual):
		_environment_visual.unregister_region(entry["region_key"])
	_surface_cache_pending.erase(id)
	_surface_cache_retry_after_usec.erase(id)
	_surface_cache_retry_counts.erase(id)
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
	_dm18_capture_completed_region(id, entry)
	if _edit_transaction.has("target_ids") and (_edit_transaction["target_ids"] as Array).has(id):
		_edit_transaction["target_ids"].erase(id)
		loading_regions.erase(id)
	if _dm3_enabled() and not global_rebuild_pending:
		_dm3_retire_region_nodes(id, entry)
	else:
		for chunk_id in entry["chunk_nodes"]:
			_release_chunk_node(chunk_id, entry["chunk_nodes"][chunk_id])
	active_regions.erase(id)
	world_states.erase(id)
	_streamed_region_unloads += 1


func _supersede_region_stage(id: String) -> void:
	_discard_progressive_chunks(id, "superseded")
	_clear_coarse_preview(id, "superseded")
	if not loading_regions.has(id):
		return
	var stale_stage: Dictionary = loading_regions[id]
	if _dm19_cold_profile != null:
		_dm19_cold_profile.cancel(id, "superseded")
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
	_discard_progressive_chunks(id, "stage_failed")
	_clear_coarse_preview(id, "stage_failed")
	_record_stream_error(id, message)
	var failed_stage: Dictionary = loading_regions.get(id, {})
	if _dm19_cold_profile != null:
		_dm19_cold_profile.cancel(id, "failed")
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
	if _dm18_cache_enabled:
		_dm18_cache.clear()
	_discard_all_progressive_chunks("global_rebuild")
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
	_discard_all_progressive_chunks("edit_command")
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
			_queue_surface_cache_region(region_key)
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
		_discard_progressive_chunks(id, "edit_transaction_restart")
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
		if not bool(loading_regions[id].get("dm9_speculative", false)):
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
	last_mesh_diagnostics["stream_profile"] = _stream_profile
	last_mesh_diagnostics["stream_dispatch_budget"] = int(_stream_budget_state.get("dispatch_limit", 1))
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
	_queue_simulation_save(_checkpoint_generation)
	_process_pending_simulation_save()
	if _pending_simulation_save_terrain_generation >= 0:
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
			_queue_simulation_save(_checkpoint_generation)
			_process_pending_simulation_save()
			if _pending_simulation_save_terrain_generation >= 0:
				_persistence_status += "; " + _simulation_persistence_status
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
	_queue_simulation_save(terrain_generation)
	_process_pending_simulation_save()
	if _pending_simulation_save_terrain_generation >= 0:
		_persistence_status += "; " + _simulation_persistence_status
	_update_status()
	return true


func _load_world_from_storage() -> bool:
	if _pending_simulation_save_terrain_generation >= 0:
		_persistence_status = "Load waits for the pending simulation snapshot to commit"
		_update_status()
		return false
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
	status += "DM2 terrain mesher: %s | experimental B4: visual-only, SDF simulation/save unchanged\n" % _experimental_mesh_backend
	if _dm3_enabled():
		status += "DM6: 6-region B4 HIGH / retain 10 and 20s grace | visible %d + retired %d\n" % [
			_dm3_shell_nodes.size(), _dm3_retired_region_nodes.size()
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
			status += "P4 persistence: generation %d | terrain generation %d | pending %d | %s\n" % [
				_simulation_storage_generation,
				_checkpoint_generation,
				_pending_simulation_save_terrain_generation,
				_simulation_persistence_status,
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
