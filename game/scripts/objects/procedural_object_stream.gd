class_name ProceduralObjectStream
extends Node3D

## Owns only transient visual representatives for published terrain regions.
## Deterministic instance records are built by ProceduralObjectWorld.
const Loader := preload("res://scripts/modding/declarative_mod_loader.gd")
const RegistryScript := preload("res://scripts/modding/content_definition_registry.gd")
const ObjectWorld := preload("res://scripts/objects/procedural_object_world.gd")
const RegionGenerationJob := preload("res://scripts/objects/procedural_object_region_generation_job.gd")
const RockMeshAdapter := preload("res://scripts/objects/procedural_rock_mesh_adapter.gd")
const StaticBatchBuilder := preload("res://scripts/objects/procedural_object_static_batch.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const FIELD := preload("res://scripts/terrain/sdf_world.gd")
const StateServiceScript := preload("res://scripts/objects/procedural_object_state_service.gd")
const StateContract := preload("res://scripts/objects/procedural_object_state_contract.gd")
const EntityCommandServiceScript := preload("res://scripts/entities/entity_command_service.gd")
const TerrainEffectProjectionService := preload("res://scripts/terrain/terrain_object_effect_projection_service.gd")
const MAX_RESIDENT_REGIONS := 25
const MAX_PENDING_REGION_PUBLICATIONS := 25
const MAX_REGION_PUBLICATIONS_PER_FRAME := 1
const MAX_REGION_GENERATION_JOBS_IN_FLIGHT := 2
const MAX_CACHED_GEOMETRY_VARIANTS := 32

var registry: ContentDefinitionRegistry
var world_seed := 0
var world_id := ""
var initialized := false
var initialization_error := ""
var objects_visible := true
var _regions: Dictionary = {} # region id -> {root, instances, world_seed}
var _region_errors: Dictionary = {}
var _definition_ids: Array[String] = []
var _mod_count := 0
var _rock_material: StandardMaterial3D
var state_service: RefCounted
var entity_command_service: RefCounted
var terrain_effect_projection_service: RefCounted
var _terrain_effect_dirty_chunk_ids: Array[String] = []
var state_directory_override := ""
var _package_discovery_report: Dictionary = {}
var _expected_publication_tokens: Dictionary = {}
var _published_publication_tokens: Dictionary = {}
var _population_rule_ids: Array[String] = []
var _terrain_interaction_rule_ids: Array[String] = []
var _pending_region_publications: Dictionary = {}
var _pending_publication_order: Array[String] = []
var _region_generation_jobs: Dictionary = {} # worker task id -> {job, id, request, cancelled}
var _region_generation_task_by_id: Dictionary = {}
var _next_region_publication_serial := 1
var _geometry_mesh_cache: Dictionary = {}
var _geometry_mesh_cache_order: Array[String] = []
var _last_region_metrics: Dictionary = {}
var _peak_region_generation_usec := 0
var _peak_mesh_build_usec := 0
var _peak_batch_build_usec := 0
var _peak_publications_per_process_tick := 0
var _publications_last_process_tick := 0
var _total_published_instance_count := 0
var _command_visual_pending: Dictionary = {}
var _command_migration_sync_regions: Dictionary = {}
var _last_command_visual_result: Dictionary = {}
var _last_entity_command_metrics: Dictionary = {}
var _last_reconstruction_usec := 0
var debug_fail_next_visual_publication := false
var _debug_fail_visual_request_serial := -1


func initialize(seed_value: int, world_identifier: String, package_roots: Array[String] = [], object_state_directory: String = "") -> Dictionary:
	_clear_region_nodes()
	initialized = false
	registry = null
	terrain_effect_projection_service = null
	_terrain_effect_dirty_chunk_ids.clear()
	_definition_ids.clear()
	world_seed = seed_value
	world_id = world_identifier
	_expected_publication_tokens.clear()
	_published_publication_tokens.clear()
	_pending_region_publications.clear()
	_pending_publication_order.clear()
	_next_region_publication_serial = 1
	_debug_fail_visual_request_serial = -1
	_command_visual_pending.clear()
	_command_migration_sync_regions.clear()
	_last_command_visual_result.clear()
	_geometry_mesh_cache.clear()
	_geometry_mesh_cache_order.clear()
	_population_rule_ids.clear()
	_terrain_interaction_rule_ids.clear()
	_package_discovery_report.clear()
	_terrain_effect_dirty_chunk_ids.clear()
	terrain_effect_projection_service = null
	var roots: Array[String] = []
	for package_root in package_roots:
		roots.append(package_root)
	var discovery: Dictionary = {}
	if roots.is_empty():
		roots = _configured_package_roots()
		if roots.is_empty():
			var root_error := initialization_error if not initialization_error.is_empty() else "user_mod_directory_unavailable"
			return _fail_initialize(root_error)
		discovery = _discover_configured_packages(roots)
	else:
		var optional_roots := _configured_optional_roots(roots)
		discovery = Loader.discover_and_validate(roots, optional_roots)
	var candidate: ContentDefinitionRegistry = RegistryScript.new()
	_package_discovery_report = discovery.duplicate(true)
	if not discovery.get("ok", false):
		return _fail_initialize("package_discovery_failed:%s" % discovery.get("reason", "unknown"))
	var registration: Dictionary = candidate.register_discovered(discovery)
	if not registration.get("ok", false):
		return _fail_initialize("package_registration_failed:%s" % registration.get("reason", "unknown"))
	state_directory_override = object_state_directory
	var state_load := _initialize_state_service(world_seed)
	if not state_load.get("ok", false):
		return _fail_initialize("object_state_unavailable:%s" % state_load.get("reason", "invalid"))
	registry = candidate
	_initialize_entity_command_service()
	var effect_projection_directory := _terrain_effect_projection_directory(world_seed)
	var projection_candidate: RefCounted = TerrainEffectProjectionService.new()
	var projection_initialized: Dictionary = projection_candidate.initialize(
		world_id, world_seed, FIELD.GENERATOR_VERSION, effect_projection_directory
	)
	if not projection_initialized.get("ok", false):
		return _fail_initialize(
			"terrain_effect_projection_unavailable:%s" % projection_initialized.get("reason", "invalid")
		)
	terrain_effect_projection_service = projection_candidate
	_mod_count = int(registration.get("mod_count", 0))
	_definition_ids = candidate.get_definition_ids()
	_population_rule_ids = candidate.get_population_rule_ids()
	_terrain_interaction_rule_ids = candidate.get_terrain_interaction_rule_ids()
	_rock_material = StandardMaterial3D.new()
	_rock_material.albedo_color = Color(0.38, 0.39, 0.37, 1.0)
	_rock_material.roughness = 0.94
	initialized = true
	initialization_error = ""
	return {
		"ok": true,
		"reason": "ok",
		"mod_count": _mod_count,
		"definition_ids": _definition_ids.duplicate(),
		"population_rule_ids": _population_rule_ids.duplicate(),
		"terrain_interaction_rule_ids": _terrain_interaction_rule_ids.duplicate(),
		"accepted_package_count": int(discovery.get("accepted_package_count", _mod_count)),
		"optional_directory_ignored_count": int(discovery.get("optional_directory_ignored_count", 0)),
		"discovery_diagnostics": discovery.get("diagnostics", []).duplicate(true),
	}


func expect_region_publication(region_key: Vector2i, publication_token: int) -> void:
	var id := _region_id(region_key)
	if publication_token > int(_expected_publication_tokens.get(id, -1)):
		_expected_publication_tokens[id] = publication_token
		if _region_generation_task_by_id.has(id):
			var task_id := int(_region_generation_task_by_id[id])
			if _region_generation_jobs.has(task_id):
				var record: Dictionary = _region_generation_jobs[task_id]
				var request: Dictionary = record.get("request", {})
				if int(request.get("publication_token", -1)) != publication_token:
					record["cancelled"] = true
					_region_generation_jobs[task_id] = record
		if _pending_region_publications.has(id) and int(_pending_region_publications[id].get("publication_token", -1)) != publication_token:
			_pending_region_publications.erase(id)
			_pending_publication_order.erase(id)


func enqueue_region_publication(region_key: Vector2i, state: RefCounted, publication_token: int = -1, force_rebuild: bool = false) -> Dictionary:
	var id := _region_id(region_key)
	if not initialized:
		return _record_region_failure(id, "object_stream_not_initialized")
	if state == null or state.get("region_key") != region_key:
		return _record_region_failure(id, "region_world_identity_mismatch")
	if _expected_publication_tokens.has(id) and publication_token != int(_expected_publication_tokens[id]):
		return _failure("stale_object_region_publication")
	var request_serial := _next_region_publication_serial
	_next_region_publication_serial += 1
	var request := {
		"region_key": region_key,
		"world_state": state,
		"publication_token": publication_token,
		"force_rebuild": force_rebuild,
		"request_serial": request_serial,
	}
	if _pending_region_publications.has(id):
		# Latest state wins. Any older worker for this same region is now
		# superseded; its immutable CPU result may finish but must not publish.
		_mark_region_generation_cancelled(id)
		_pending_region_publications[id] = request
		return {
			"ok": true,
			"reason": "queued_replaced",
			"queue_depth": _pending_region_publications.size(),
			"request_serial": request_serial,
		}
	if _pending_region_publications.size() >= MAX_PENDING_REGION_PUBLICATIONS:
		return _record_region_failure(id, "object_publication_queue_full")
	_mark_region_generation_cancelled(id)
	_pending_region_publications[id] = request
	_pending_publication_order.append(id)
	_region_errors.erase(id)
	return {
		"ok": true,
		"reason": "queued",
		"queue_depth": _pending_region_publications.size(),
		"request_serial": request_serial,
	}


func process_queued_publications() -> int:
	_publications_last_process_tick = 0
	# Unit-level callers that are not in a SceneTree retain the deterministic
	# synchronous contract. Runtime publication uses worker generation.
	if not is_inside_tree():
		while _publications_last_process_tick < MAX_REGION_PUBLICATIONS_PER_FRAME and not _pending_publication_order.is_empty():
			var id: String = _pending_publication_order.pop_front()
			if not _pending_region_publications.has(id):
				continue
			var request: Dictionary = _pending_region_publications[id]
			_pending_region_publications.erase(id)
			var result := publish_region(
				request["region_key"], request["world_state"],
				bool(request.get("force_rebuild", false)), int(request["publication_token"]),
				{}, int(request.get("request_serial", -1))
			)
			_publications_last_process_tick += 1
			_finish_queued_publication(id, result, int(request.get("request_serial", -1)))
	else:
		_process_completed_region_generation_jobs()
		_dispatch_region_generation_jobs()
	_peak_publications_per_process_tick = maxi(_peak_publications_per_process_tick, _publications_last_process_tick)
	return _publications_last_process_tick


func _dispatch_region_generation_jobs() -> void:
	# Examine each currently queued region at most once. Requests for a region
	# that already has a worker in flight stay queued instead of being orphaned.
	var remaining_attempts := _pending_publication_order.size()
	while _region_generation_jobs.size() < MAX_REGION_GENERATION_JOBS_IN_FLIGHT \
		and not _pending_publication_order.is_empty() and remaining_attempts > 0:
		remaining_attempts -= 1
		var id: String = _pending_publication_order.pop_front()
		if _region_generation_task_by_id.has(id):
			_pending_publication_order.append(id)
			continue
		if not _pending_region_publications.has(id):
			continue
		var request: Dictionary = _pending_region_publications[id]
		_pending_region_publications.erase(id)
		var state: RefCounted = request["world_state"]
		var job := RegionGenerationJob.new(int(state.get("world_seed")), world_id, request["region_key"], registry)
		var task_id := WorkerThreadPool.add_task(Callable(job, "run"), false, "procedural object region generation")
		if task_id < 0:
			_finish_queued_publication(
				id,
				_record_region_failure(id, "object_generation_worker_rejected"),
				int(request.get("request_serial", -1))
			)
			continue
		_region_generation_jobs[task_id] = {
			"job": job,
			"id": id,
			"request": request,
			"cancelled": false,
			"submitted_usec": Time.get_ticks_usec(),
		}
		_region_generation_task_by_id[id] = task_id


func _process_completed_region_generation_jobs() -> void:
	var completed: Array[int] = []
	for task_id_value in _region_generation_jobs.keys():
		var task_id := int(task_id_value)
		if WorkerThreadPool.is_task_completed(task_id):
			completed.append(task_id)
	completed.sort()
	for task_id in completed:
		if _publications_last_process_tick >= MAX_REGION_PUBLICATIONS_PER_FRAME:
			break
		WorkerThreadPool.wait_for_task_completion(task_id)
		var record: Dictionary = _region_generation_jobs[task_id]
		_region_generation_jobs.erase(task_id)
		var id := String(record["id"])
		_region_generation_task_by_id.erase(id)
		if bool(record.get("cancelled", false)):
			continue
		var request: Dictionary = record["request"]
		var publication_token := int(request.get("publication_token", -1))
		if _expected_publication_tokens.has(id) and publication_token != int(_expected_publication_tokens[id]):
			continue
		var job = record["job"]
		var generated: Dictionary = job.result
		var result: Dictionary
		if not generated.get("ok", false):
			result = _record_region_failure(id, String(generated.get("reason", "object_generation_failed")))
		else:
			result = publish_region(
				request["region_key"], request["world_state"],
				bool(request.get("force_rebuild", false)), publication_token, generated,
				int(request.get("request_serial", -1))
			)
		_publications_last_process_tick += 1
		_finish_queued_publication(id, result, int(request.get("request_serial", -1)))


func _finish_queued_publication(id: String, result: Dictionary, request_serial: int = -1) -> void:
	if not result.get("ok", false) and result.get("reason", "") != "stale_object_region_publication":
		_region_errors[id] = String(result.get("reason", "object_region_publication_failed"))
	if _command_visual_pending.has(id):
		var pending_visual: Dictionary = _command_visual_pending[id]
		# An older same-region worker can finish after a newer command has queued
		# its own visual rebuild. Only the exact request may resolve that command.
		if int(pending_visual.get("request_serial", -2)) == request_serial:
			var visual_publication_usec := int(_last_region_metrics.get("publication_usec", 0))
			var visual_queue_wait_usec := maxi(0, int(Time.get_ticks_usec() - int(pending_visual.get("queued_usec", Time.get_ticks_usec())) - visual_publication_usec))
			var visual_elapsed_usec := Time.get_ticks_usec() - int(pending_visual.get("command_started_usec", Time.get_ticks_usec()))
			var visual_timings: Dictionary = _last_entity_command_metrics.duplicate(true)
			visual_timings["visual_queue_wait_usec"] = visual_queue_wait_usec
			visual_timings["visual_publication_usec"] = visual_publication_usec
			visual_timings["command_total_to_visual_publish_usec"] = visual_elapsed_usec
			_last_entity_command_metrics = visual_timings
			_last_command_visual_result = {
				"entity_id": String(pending_visual.get("entity_id", "")),
				"operation": String(pending_visual.get("operation", "")),
				"world_revision": int(pending_visual.get("world_revision", -1)),
				"ok": bool(result.get("ok", false)),
				"reason": String(result.get("reason", "publication_failed")),
				"timings_usec": visual_timings,
			}
			_command_visual_pending.erase(id)
	if _command_migration_sync_regions.has(id) and result.get("ok", false):
		_command_migration_sync_regions.erase(id)


func publish_region(
	region_key: Vector2i,
	state: RefCounted,
	force_rebuild: bool = false,
	publication_token: int = -1,
	generated_base: Dictionary = {},
	request_serial: int = -1
) -> Dictionary:
	var publication_started_usec := Time.get_ticks_usec()
	var id := _region_id(region_key)
	if _expected_publication_tokens.has(id) and publication_token != int(_expected_publication_tokens[id]):
		return _failure("stale_object_region_publication")
	if publication_token >= 0 and publication_token < int(_published_publication_tokens.get(id, -1)):
		return _failure("stale_object_region_publication")
	if not initialized:
		return _record_region_failure(id, "object_stream_not_initialized")
	if state == null or state.get("region_key") != region_key:
		return _record_region_failure(id, "region_world_identity_mismatch")
	var region_world_seed: int = int(state.get("world_seed"))
	if region_world_seed != world_seed:
		# A stream can never present object nodes from two world-seed domains at once.
		# The terrain stream owns cancellation/requeue of its corresponding regions.
		_clear_region_nodes()
		var state_load := _initialize_state_service(region_world_seed)
		if not state_load.get("ok", false):
			return _record_region_failure(id, "object_state_unavailable:%s" % state_load.get("reason", "invalid"))
		world_seed = region_world_seed
		_initialize_entity_command_service()
		var effect_projection_directory := _terrain_effect_projection_directory(world_seed)
		var projection_candidate: RefCounted = TerrainEffectProjectionService.new()
		var projection_initialized: Dictionary = projection_candidate.initialize(
			world_id, world_seed, FIELD.GENERATOR_VERSION, effect_projection_directory
		)
		if not projection_initialized.get("ok", false):
			return _record_region_failure(
				id,
				"terrain_effect_projection_unavailable:%s" % projection_initialized.get("reason", "invalid")
			)
		terrain_effect_projection_service = projection_candidate
	if not _regions.has(id) and _regions.size() >= MAX_RESIDENT_REGIONS:
		return _record_region_failure(id, "object_resident_region_budget_exceeded")
	if not force_rebuild and _regions.has(id) and int(_regions[id]["world_seed"]) == region_world_seed and _regions[id].get("world_state") == state:
		if publication_token >= 0:
			_published_publication_tokens[id] = publication_token
		return {"ok": true, "reason": "already_published", "instance_count": _regions[id]["instances"].size()}
	var base_instances: Array[Dictionary] = []
	var generation_usec := 0
	var generation_worker_usec := int(generated_base.get("worker_usec", 0))
	var main_thread_reconstruction_usec := 0
	var candidate_cell_count := 0
	var surface_anchor_count := 0
	if entity_command_service != null and bool(entity_command_service.get("initialized")):
		var reconstruction: Dictionary
		if generated_base.is_empty():
			reconstruction = entity_command_service.reconstruct_region(region_key)
		else:
			reconstruction = entity_command_service.reconstruct_region_from_generated(region_key, generated_base)
		if not reconstruction.get("ok", false):
			return _record_region_failure(id, String(reconstruction.get("reason", "entity_region_reconstruction_failed")))
		base_instances = entity_command_service.get_region_base_instances(region_key)
		_last_reconstruction_usec = int(reconstruction.get("reconstruction_usec", 0))
		generation_usec = int(reconstruction.get("generation_usec", _last_reconstruction_usec))
		main_thread_reconstruction_usec = int(reconstruction.get("main_thread_reconstruction_usec", 0))
		candidate_cell_count = int(reconstruction.get("candidate_cell_count", 0))
		surface_anchor_count = int(reconstruction.get("surface_anchor_count", 0))
	else:
		var generated: Dictionary = generated_base
		if generated.is_empty():
			generated = ObjectWorld.build_region_instances(region_world_seed, world_id, region_key, registry)
		if not generated.get("ok", false):
			return _record_region_failure(id, String(generated.get("reason", "object_generation_failed")))
		base_instances = generated["instances"]
		generation_usec = int(generated.get("timings_usec", {}).get("total", 0))
		_last_reconstruction_usec = generation_usec
		candidate_cell_count = int(generated.get("candidate_cell_count", 0))
		surface_anchor_count = int(generated.get("surface_anchor_count", 0))
	# Terrain interaction is independent from the optional command/history
	# migration. Resolve the same authoritative object state in both the legacy
	# and command-enabled paths, then project it once.
	if terrain_effect_projection_service != null and state_service != null:
		var active_effect_instances: Array[Dictionary] = []
		var source_revisions: Dictionary = {}
		for base_instance_value in base_instances:
			var base_instance_for_effect: Dictionary = base_instance_value
			var resolved_for_effect: Dictionary = state_service.resolve_instance(
				base_instance_for_effect
			)
			if not resolved_for_effect.get("ok", false):
				return _record_region_failure(
					id,
					"terrain_effect_state_resolution_failed:%s" % resolved_for_effect.get("reason", "unknown")
				)
			if bool(resolved_for_effect.get("deleted", false)):
				continue
			var resolved_instance: Dictionary = resolved_for_effect["instance"]
			active_effect_instances.append(resolved_instance.duplicate(true))
			var resolved_id := String(resolved_instance.get("instance_id", ""))
			# The live terrain projection uses the authoritative world revision as
			# its source epoch. It is monotonic across schema 1/2/3 migrations,
			# unlike per-entity revisions which are introduced by later schemas and
			# can therefore appear to move backwards at the migration boundary.
			# Entity revisions remain the command-concurrency token; the projection
			# needs a cross-schema monotonic version for derived overlay recovery.
			source_revisions[resolved_id] = int(state_service.get_revision())
		var effect_reconcile: Dictionary = terrain_effect_projection_service.reconcile_scope(
			region_key,
			int(state_service.get_revision()),
			active_effect_instances,
			source_revisions
		)
		if not effect_reconcile.get("ok", false):
			return _record_region_failure(
				id,
				"terrain_effect_reconcile_failed:%s" % effect_reconcile.get("reason", "unknown")
			)
		for chunk_id_value in effect_reconcile.get("affected_chunk_ids", []):
			var dirty_chunk_id := String(chunk_id_value)
			if not _terrain_effect_dirty_chunk_ids.has(dirty_chunk_id):
				_terrain_effect_dirty_chunk_ids.append(dirty_chunk_id)
		_terrain_effect_dirty_chunk_ids.sort()

	var pending_nodes: Array[Node3D] = []
	var instances: Array[Dictionary] = []
	var batch_items: Array[Dictionary] = []
	var geometry_cpu_by_instance: Dictionary = generated_base.get("geometry_cpu_by_instance", {})
	var geometry_cpu_worker_usec := int(generated_base.get("geometry_cpu_usec", 0))
	var mesh_build_started_usec := Time.get_ticks_usec()
	for base_instance in base_instances:
		var resolved: Dictionary = state_service.resolve_instance(base_instance)
		if not resolved.get("ok", false):
			for pending_node in pending_nodes:
				pending_node.free()
			return _record_region_failure(id, String(resolved.get("reason", "object_state_resolution_failed")))
		if resolved.get("deleted", false):
			continue
		var instance: Dictionary = resolved["instance"]
		instances.append(instance)
		var prepared_cpu: Dictionary = geometry_cpu_by_instance.get(String(instance.get("instance_id", "")), {})
		var mesh_result: Dictionary = _get_or_build_geometry_mesh(instance, prepared_cpu)
		if not mesh_result.get("ok", false):
			for pending_node in pending_nodes:
				pending_node.free()
			return _record_region_failure(id, "object_mesh_build_failed:%s" % mesh_result.get("reason", "unknown"))
		if bool(instance.get("population_batched", false)) and instance.get("instance_components", {}).is_empty():
			batch_items.append({
				"instance_id": String(instance["instance_id"]),
				"mesh": mesh_result["mesh"],
				"position": Vector3(instance["position_mm"]) / 1000.0,
				"scale_milli": instance.get("default_scale_milli", Vector3i(1000, 1000, 1000)),
				"yaw_mdeg": int(instance.get("default_yaw_mdeg", 0)),
				"selection_record": _build_selection_record(instance),
			})
			continue
		var object_node := Node3D.new()
		object_node.name = "Object_%s" % String(instance["instance_id"]).sha256_text().substr(0, 12)
		object_node.position = Vector3(instance["position_mm"]) / 1000.0
		object_node.set_meta("stable_instance_id", instance["instance_id"])
		object_node.set_meta("definition_id", instance["definition_id"])
		object_node.set_meta("content_pin", instance["content_pin"])
		object_node.set_meta("recipe_algorithm", instance["recipe_algorithm"])
		object_node.set_meta("geometry_profile", instance["geometry_profile"])
		object_node.set_meta("geometry_seeds", instance["geometry_seeds"].duplicate(true))
		object_node.set_meta("geometry_adapter_version", RockMeshAdapter.GEOMETRY_VERSION)
		object_node.set_meta("instance_components", instance.get("instance_components", {}).duplicate(true))
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = mesh_result["mesh"]
		mesh_instance.material_override = _rock_material
		object_node.add_child(mesh_instance)
		_apply_components_to_node(object_node, instance)
		pending_nodes.append(object_node)
	var mesh_build_elapsed_usec := Time.get_ticks_usec() - mesh_build_started_usec
	var batch_started_usec := Time.get_ticks_usec()
	var batch_result := StaticBatchBuilder.build(batch_items)
	if not batch_result.get("ok", false):
		for pending_node in pending_nodes:
			pending_node.free()
		return _record_region_failure(id, String(batch_result.get("reason", "static_batch_failed")))
	var region_root := Node3D.new()
	region_root.name = "Objects_%d_%d" % [region_key.x, region_key.y]
	region_root.position = Spatial.region_origin_world(region_key)
	region_root.visible = objects_visible
	if batch_result.get("mesh", null) is ArrayMesh:
		var batch_node := Node3D.new()
		batch_node.name = "StaticPopulationBatch"
		batch_node.set_meta("stable_instance_ids", batch_result["instance_ids"])
		batch_node.set_meta("population_batch_version", 1)
		var selection_records: Array[Dictionary] = []
		for batch_item in batch_items:
			selection_records.append(batch_item["selection_record"])
		batch_node.set_meta("selection_records", selection_records)
		var batch_mesh_instance := MeshInstance3D.new()
		batch_mesh_instance.mesh = batch_result["mesh"]
		batch_mesh_instance.material_override = _rock_material
		batch_node.add_child(batch_mesh_instance)
		region_root.add_child(batch_node)
	for object_node in pending_nodes:
		region_root.add_child(object_node)
	if request_serial >= 0 and request_serial == _debug_fail_visual_request_serial:
		_debug_fail_visual_request_serial = -1
		region_root.free()
		for pending_node in pending_nodes:
			if is_instance_valid(pending_node) and pending_node.get_parent() == null:
				pending_node.free()
		return _record_region_failure(id, "debug_visual_publication_failure")
	if _regions.has(id):
		var previous_root: Node3D = _regions[id]["root"]
		if is_instance_valid(previous_root):
			remove_child(previous_root)
			previous_root.free()
	_regions.erase(id)
	add_child(region_root)
	_regions[id] = {"root": region_root, "region_key": region_key, "instances": instances, "base_instances": base_instances, "world_state": state, "world_seed": region_world_seed}
	_total_published_instance_count += instances.size()
	var batch_elapsed_usec := Time.get_ticks_usec() - batch_started_usec
	_last_region_metrics = {
		"region_key": region_key,
		"instance_count": instances.size(),
		"batched_instance_count": batch_items.size(),
		"individual_node_count": pending_nodes.size(),
		"candidate_cell_count": candidate_cell_count,
		"surface_anchor_count": surface_anchor_count,
		"generation_usec": generation_usec,
		"generation_worker_usec": generation_worker_usec,
		"geometry_cpu_worker_usec": geometry_cpu_worker_usec,
		"main_thread_reconstruction_usec": main_thread_reconstruction_usec,
		"logical_reconstruction_usec": _last_reconstruction_usec,
		"mesh_build_usec": mesh_build_elapsed_usec,
		"batch_build_usec": batch_elapsed_usec,
		"publication_usec": Time.get_ticks_usec() - publication_started_usec,
		"batch_vertex_count": int(batch_result.get("vertex_count", 0)),
	}
	_peak_region_generation_usec = maxi(_peak_region_generation_usec, int(_last_region_metrics["generation_usec"]))
	_peak_mesh_build_usec = maxi(_peak_mesh_build_usec, mesh_build_elapsed_usec)
	_peak_batch_build_usec = maxi(_peak_batch_build_usec, batch_elapsed_usec)
	if publication_token >= 0:
		_published_publication_tokens[id] = publication_token
	_region_errors.erase(id)
	return {"ok": true, "reason": "ok", "instance_count": instances.size()}


func get_instance_ids() -> Array[String]:
	var ids: Array[String] = []
	for entry in _regions.values():
		for instance in entry.get("instances", []):
			ids.append(String(instance.get("instance_id", "")))
	ids.sort()
	return ids


func get_instance_state_revision() -> int:
	return int(state_service.get_revision()) if state_service != null and state_service.initialized else 0


func get_entity_command_service() -> RefCounted:
	return entity_command_service


func get_command_world_revision() -> int:
	return int(state_service.get_revision()) if state_service != null and state_service.initialized else 0


func is_entity_command_ready() -> bool:
	return entity_command_service != null and bool(entity_command_service.get("initialized")) and _command_migration_sync_regions.is_empty()


func get_command_migration_preflight() -> Dictionary:
	if state_service == null or not bool(state_service.get("initialized")):
		return _failure("object_state_service_not_initialized")
	return state_service.preflight_history_snapshot_upgrade()


func migrate_command_snapshot_explicitly() -> Dictionary:
	var preflight := get_command_migration_preflight()
	if not preflight.get("ok", false):
		return preflight
	var migrated: Dictionary = state_service.upgrade_history_snapshot_schema()
	if not migrated.get("ok", false):
		entity_command_service = null
		return migrated
	_initialize_entity_command_service()
	if entity_command_service == null or not bool(entity_command_service.get("initialized")):
		return {"ok": false, "reason": "command_service_initialization_failed_after_migration", "committed": true, "generation": int(migrated.get("generation", -1))}
	_command_migration_sync_regions.clear()
	for id_value in _regions.keys():
		_command_migration_sync_regions[String(id_value)] = true
	var queued_result := retry_command_migration_region_publications()
	queued_result["revision"] = int(migrated.get("revision", 0))
	queued_result["generation"] = int(migrated.get("generation", 0))
	queued_result["backup_generation"] = int(migrated.get("backup_generation", 0))
	queued_result["source_payload_sha256"] = String(migrated.get("source_payload_sha256", ""))
	queued_result["preserved_receipt_count"] = int(migrated.get("preserved_receipt_count", 0))
	return queued_result


func retry_command_migration_region_publications() -> Dictionary:
	if entity_command_service == null or not bool(entity_command_service.get("initialized")):
		return _failure("command_snapshot_migration_required")
	var queued_count := 0
	for id_value in _command_migration_sync_regions.keys().duplicate():
		var id := String(id_value)
		if not _regions.has(id):
			_command_migration_sync_regions.erase(id)
			continue
		if _pending_region_publications.has(id):
			continue
		var entry: Dictionary = _regions[id]
		var queued := enqueue_region_publication(entry["region_key"], entry["world_state"], int(_published_publication_tokens.get(id, -1)), true)
		if not queued.get("ok", false):
			return {"ok": false, "committed": true, "reason": "migration_committed_visual_queue_failed:%s" % queued.get("reason", "unknown"), "queued_regions": queued_count, "remaining_regions": _command_migration_sync_regions.size(), "generation": int(state_service.get("storage_generation"))}
		queued_count += 1
	return {"ok": true, "reason": "history_schema_upgraded_explicitly", "committed": true, "revision": int(state_service.get_revision()), "generation": int(state_service.get("storage_generation")), "queued_regions": queued_count, "remaining_regions": _command_migration_sync_regions.size()}


func dispatch_entity_command(command: Dictionary) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	if entity_command_service == null or not bool(entity_command_service.get("initialized")):
		return _failure("command_snapshot_migration_required")
	if not _command_migration_sync_regions.is_empty():
		return _failure("command_region_rebuild_pending")
	var operation := String(command.get("operation", ""))
	var entity_id := String(command.get("entity_id", ""))
	var temporary_reconstruction := false
	var temporary_region := Vector2i.ZERO
	var region_reconstruction_usec := 0
	if operation == "ENTITY_RESTORE":
		var located: Dictionary = entity_command_service.get_entity_region(entity_id)
		if not located.get("ok", false):
			var identity: Dictionary = state_service.get_deleted_identity(entity_id)
			if identity.is_empty():
				var placed: Dictionary = state_service.snapshot.get("placed_entities", {}).get(entity_id, {})
				identity = placed.get("identity", {})
			if identity.is_empty() or typeof(identity.get("region_key", null)) != TYPE_ARRAY or identity.region_key.size() != 2:
				return _failure("restore_identity_unavailable")
			var values: Array = identity.region_key
			temporary_region = Vector2i(int(values[0]), int(values[1]))
			var rebuilt: Dictionary = entity_command_service.reconstruct_region(temporary_region)
			if not rebuilt.get("ok", false):
				return _failure(String(rebuilt.get("reason", "restore_region_reconstruction_failed")))
			temporary_reconstruction = not _regions.has(_region_id(temporary_region))
			region_reconstruction_usec = int(rebuilt.get("reconstruction_usec", 0))
	elif operation != "ENTITY_PLACE":
		if not entity_command_service.get_entity_region(entity_id).get("ok", false):
			return _failure("entity_not_reconstructed_or_content_missing")
	if operation == "ENTITY_PLACE":
		var place_region_values: Array = command.get("region_key", [])
		if place_region_values.size() != 2:
			return _failure("place_region_invalid")
		var place_region := Vector2i(int(place_region_values[0]), int(place_region_values[1]))
		if not _regions.has(_region_id(place_region)):
			return _failure("place_region_not_published")
	var affected_region := Vector2i.ZERO
	if operation == "ENTITY_PLACE":
		var placed_result: Dictionary = entity_command_service.dispatch(command)
		if not placed_result.get("ok", false):
			return placed_result
		entity_id = String(placed_result.get("entity_id", ""))
		var placed_location: Dictionary = entity_command_service.get_entity_region(entity_id)
		if not placed_location.get("ok", false):
			return {"ok": true, "committed": true, "reason": "committed_but_identity_cache_missing", "entity_id": entity_id, "world_revision": int(placed_result.get("world_revision", -1)), "entity_revision": int(placed_result.get("entity_revision", -1))}
		affected_region = Vector2i(placed_location.region_key)
		return _queue_committed_visual_update(placed_result, affected_region, started_usec, region_reconstruction_usec)
	var old_location: Dictionary = entity_command_service.get_entity_region(entity_id)
	if old_location.get("ok", false):
		affected_region = Vector2i(old_location.region_key)
	var result: Dictionary = entity_command_service.dispatch(command)
	if not result.get("ok", false):
		if temporary_reconstruction:
			entity_command_service.release_region(temporary_region)
		return result
	var new_location: Dictionary = entity_command_service.get_entity_region(entity_id)
	if new_location.get("ok", false):
		affected_region = Vector2i(new_location.region_key)
	if temporary_reconstruction and not _regions.has(_region_id(temporary_region)):
		entity_command_service.release_region(temporary_region)
	return _queue_committed_visual_update(result, affected_region, started_usec, region_reconstruction_usec)


func _queue_committed_visual_update(result: Dictionary, region_key: Vector2i, started_usec: int, region_reconstruction_usec: int = 0) -> Dictionary:
	var output: Dictionary = result.duplicate(true)
	output["committed"] = true
	var timings: Dictionary = output.get("timings_usec", {}).duplicate(true)
	timings["visual_queue_usec"] = 0
	timings["regional_reconstruction_usec"] = region_reconstruction_usec
	timings["command_total_usec"] = Time.get_ticks_usec() - started_usec
	output["timings_usec"] = timings
	var region_id := _region_id(region_key)
	if not _regions.has(region_id):
		output["visual_status"] = "not_resident_rebuild_on_next_load"
		_last_entity_command_metrics = timings.duplicate(true)
		return output
	var enqueue_started_usec := Time.get_ticks_usec()
	var entry: Dictionary = _regions[region_id]
	var token := int(_published_publication_tokens.get(region_id, -1))
	var queued := enqueue_region_publication(region_key, entry["world_state"], token, true)
	timings["visual_queue_usec"] = Time.get_ticks_usec() - enqueue_started_usec
	output["timings_usec"] = timings
	_last_entity_command_metrics = timings.duplicate(true)
	if not queued.get("ok", false):
		output["reason"] = "committed_visual_update_queue_failed:%s" % queued.get("reason", "unknown")
		output["visual_status"] = "failed"
		_last_command_visual_result = {"entity_id": String(output.get("entity_id", "")), "operation": String(output.get("operation", "")), "world_revision": int(output.get("world_revision", -1)), "ok": false, "reason": String(output["reason"])}
		return output
	var request_serial := int(queued.get("request_serial", -1))
	_command_visual_pending[region_id] = {
		"entity_id": String(output.get("entity_id", "")),
		"operation": String(output.get("operation", "")),
		"world_revision": int(output.get("world_revision", -1)),
		"queued_usec": Time.get_ticks_usec(),
		"command_started_usec": started_usec,
		"request_serial": request_serial,
	}
	# Failure injection is command-scoped, not globally consumed by whichever
	# unrelated region worker happens to publish first.
	if debug_fail_next_visual_publication:
		debug_fail_next_visual_publication = false
		_debug_fail_visual_request_serial = request_serial
	output["visual_status"] = "queued"
	return output


func consume_last_command_visual_result() -> Dictionary:
	var result := _last_command_visual_result.duplicate(true)
	_last_command_visual_result.clear()
	return result


func get_last_entity_command_metrics() -> Dictionary:
	return _last_entity_command_metrics.duplicate(true)


func get_deleted_instance_ids() -> Array[String]:
	var result: Array[String] = []
	if state_service == null:
		return result
	for entity_id in state_service.snapshot.get("deleted", {}):
		result.append(String(entity_id))
	result.sort()
	return result


func get_latest_deleted_instance_id() -> String:
	if state_service == null:
		return ""
	var deleted: Dictionary = state_service.snapshot.get("deleted", {})
	var receipts: Dictionary = state_service.snapshot.get("command_receipts", {})
	var selected_id := ""
	var latest_revision := -1
	for command_id in receipts:
		var receipt: Dictionary = receipts[command_id]
		var candidate_id := String(receipt.get("entity_id", ""))
		if String(receipt.get("operation", "")) == "ENTITY_DELETE" and deleted.has(candidate_id) and int(receipt.get("world_revision", -1)) > latest_revision:
			latest_revision = int(receipt.world_revision)
			selected_id = candidate_id
	if selected_id.is_empty() and not deleted.is_empty():
		var ids: Array[String] = []
		for entity_id in deleted:
			ids.append(String(entity_id))
		ids.sort()
		selected_id = ids.back()
	return selected_id


func get_entity_summary(instance_id: String) -> Dictionary:
	if state_service == null or instance_id.is_empty():
		return _failure("entity_not_found")
	for entry in _regions.values():
		for base_instance in entry.get("base_instances", []):
			if String(base_instance.get("instance_id", "")) != instance_id:
				continue
			var identity: Dictionary = StateContract.identity_for_instance(base_instance)
			var resolved: Dictionary = state_service.resolve_instance(base_instance)
			if not resolved.get("ok", false):
				return _failure(String(resolved.get("reason", "entity_state_resolution_failed")))
			return {"ok": true, "entity_id": instance_id, "identity": identity, "definition_id": String(base_instance.get("definition_id", "")), "identity_kind": String(identity.get("identity_kind", "procedural")), "deleted": bool(resolved.get("deleted", false)), "world_revision": int(state_service.get_revision()), "entity_revision": int(state_service.get_entity_revision(instance_id)), "region_key": Vector2i(base_instance.get("region_key", Vector2i.ZERO))}
	var deleted_identity: Dictionary = state_service.get_deleted_identity(instance_id)
	if not deleted_identity.is_empty():
		var key: Array = deleted_identity.get("region_key", [0, 0])
		return {"ok": true, "entity_id": instance_id, "identity": deleted_identity, "definition_id": String(deleted_identity.get("definition_id", "")), "identity_kind": String(deleted_identity.get("identity_kind", "procedural")), "deleted": true, "world_revision": int(state_service.get_revision()), "entity_revision": int(state_service.get_entity_revision(instance_id)), "region_key": Vector2i(int(key[0]), int(key[1]))}
	return _failure("entity_not_found")


func has_published_region(region_key: Vector2i) -> bool:
	return _regions.has(_region_id(region_key))


func find_instance_along_ray(ray_origin: Vector3, ray_direction: Vector3, max_distance: float = 120.0) -> Dictionary:
	if not ray_origin.is_finite() or not ray_direction.is_finite() or ray_direction.length_squared() < 0.000001 or not objects_visible:
		return _failure("selection_ray_invalid")
	var direction := ray_direction.normalized()
	var best_distance := max_distance
	var best: Dictionary = {}
	for entry in _regions.values():
		var region_key: Vector2i = entry["region_key"]
		var region_origin: Vector3 = Spatial.region_origin_world(region_key)
		for instance in entry.get("instances", []):
			var position_mm: Vector3i = instance.get("position_mm", Vector3i.ZERO)
			var geometry: Dictionary = instance.get("geometry", {})
			var components: Dictionary = instance.get("instance_components", {})
			var transform: Dictionary = components.get(StateContract.COMPONENT_TRANSFORM, {})
			var properties: Dictionary = transform.get("properties", {})
			var translation: Array = properties.get("translation_mm", [0, 0, 0])
			var scale_values: Array = properties.get("scale_milli", [1000, 1000, 1000])
			var default_scale: Vector3i = instance.get("default_scale_milli", Vector3i(1000, 1000, 1000))
			var scale := Vector3(default_scale) if transform.is_empty() else Vector3(float(scale_values[0]), float(scale_values[1]), float(scale_values[2]))
			var delta := Vector3.ZERO if transform.is_empty() else Vector3(float(translation[0]), float(translation[1]), float(translation[2])) / 1000.0
			var half_extents := Vector3(float(geometry.get("half_extent_x_mm", 600)), float(geometry.get("half_extent_y_mm", 600)), float(geometry.get("half_extent_z_mm", 600))) / 1000.0
			var center := region_origin + Vector3(position_mm) / 1000.0 + delta + Vector3(0.0, half_extents.y * scale.y / 1000.0, 0.0)
			var radius := (half_extents * scale / 1000.0).length()
			var along := (center - ray_origin).dot(direction)
			if along < 0.0 or along > max_distance:
				continue
			var perpendicular_squared := (center - (ray_origin + direction * along)).length_squared()
			if perpendicular_squared > radius * radius:
				continue
			var hit_distance := maxf(0.0, along - sqrt(maxf(0.0, radius * radius - perpendicular_squared)))
			if hit_distance < best_distance:
				best_distance = hit_distance
				best = {"ok": true, "entity_id": String(instance.get("instance_id", "")), "distance": hit_distance, "region_key": region_key, "batched": bool(instance.get("population_batched", false)) and components.is_empty()}
	return best if not best.is_empty() else _failure("selection_no_entity_hit")


func set_instance_component(instance_id: String, component_id: String, value: Dictionary) -> Dictionary:
	var located := _find_base_instance(instance_id)
	if not located.get("ok", false):
		return _failure(String(located.get("reason", "instance_not_active")))
	var result: Dictionary = state_service.set_component(located.instance, component_id, value)
	if not result.get("ok", false):
		return result
	var rebuilt := _republish_after_state_mutation(located.region_key, located.world_state)
	if not rebuilt.get("ok", false):
		return _failure("state_committed_region_rebuild_failed")
	return result


func delete_instance(instance_id: String) -> Dictionary:
	var located := _find_base_instance(instance_id)
	if not located.get("ok", false):
		return _failure(String(located.get("reason", "instance_not_active")))
	var result: Dictionary = state_service.delete_instance(located.instance)
	if not result.get("ok", false):
		return result
	var rebuilt := _republish_after_state_mutation(located.region_key, located.world_state)
	if not rebuilt.get("ok", false):
		return _failure("state_committed_region_rebuild_failed")
	return result


func restore_instance(instance_id: String) -> Dictionary:
	var located := _find_base_instance(instance_id, true)
	if not located.get("ok", false):
		var deleted_identity: Dictionary = state_service.get_deleted_identity(instance_id)
		if deleted_identity.is_empty():
			return _failure(String(located.get("reason", "instance_not_active")))
		var region_values: Array = deleted_identity.get("region_key", [])
		if region_values.size() != 2:
			return _failure("deleted_instance_identity_invalid")
		var region_key := Vector2i(int(region_values[0]), int(region_values[1]))
		var rebuilt: Dictionary = ObjectWorld.build_region_instances(world_seed, world_id, region_key, registry)
		if not rebuilt.get("ok", false):
			return _failure("deleted_instance_baseline_rebuild_failed")
		var baseline: Dictionary = {}
		for candidate in rebuilt.instances:
			if String(candidate.instance_id) == instance_id:
				baseline = candidate
				break
		if baseline.is_empty():
			return _failure("deleted_instance_identity_no_longer_generated")
		var resolved: Dictionary = state_service.resolve_instance(baseline)
		if not resolved.get("ok", false) or not resolved.get("deleted", false):
			return _failure(String(resolved.get("reason", "deleted_instance_content_pin_mismatch")))
		var restored_unloaded: Dictionary = state_service.restore_instance(baseline)
		return restored_unloaded
	var result: Dictionary = state_service.restore_instance(located.instance)
	if not result.get("ok", false):
		return result
	var rebuilt := _republish_after_state_mutation(located.region_key, located.world_state)
	if not rebuilt.get("ok", false):
		return _failure("state_committed_region_rebuild_failed")
	return result


func _find_base_instance(instance_id: String, include_deleted: bool = false) -> Dictionary:
	for region_id in _regions:
		var entry: Dictionary = _regions[region_id]
		for instance in entry.get("base_instances", []):
			if String(instance.get("instance_id", "")) == instance_id:
				if not include_deleted and state_service.snapshot.get("deleted", []).has(instance_id):
					return _failure("instance_logically_deleted")
				return {"ok": true, "instance": instance, "region_key": instance.region_key, "world_state": entry.world_state}
	return _failure("instance_not_active")


func _republish_after_state_mutation(region_key: Vector2i, world_state: RefCounted) -> Dictionary:
	var token := int(_expected_publication_tokens.get(_region_id(region_key), -1))
	return publish_region(region_key, world_state, true, token)


func _apply_components_to_node(node: Node3D, instance: Dictionary) -> void:
	var default_scale: Vector3i = instance.get("default_scale_milli", Vector3i(1000, 1000, 1000))
	var default_yaw := int(instance.get("default_yaw_mdeg", 0))
	node.scale = Vector3(default_scale) / 1000.0
	node.rotation = Vector3(0.0, float(default_yaw) * (PI / 180000.0), 0.0)
	var components: Dictionary = instance.get("instance_components", {})
	var transform_component: Dictionary = components.get("core.transform", {})
	if not transform_component.is_empty():
		var values: Dictionary = transform_component.get("properties", {})
		var position_delta: Array = values.get("translation_mm", [0, 0, 0])
		var rotation_mdeg: Array = values.get("rotation_mdeg", [0, 0, 0])
		var scale_milli: Array = values.get("scale_milli", [1000, 1000, 1000])
		node.position = Vector3(instance["position_mm"]) / 1000.0 + Vector3(position_delta[0], position_delta[1], position_delta[2]) / 1000.0
		node.rotation = Vector3(rotation_mdeg[0], rotation_mdeg[1], rotation_mdeg[2]) * (PI / 180000.0)
		node.scale = Vector3(scale_milli[0], scale_milli[1], scale_milli[2]) / 1000.0
	var appearance: Dictionary = components.get("core.appearance", {})
	if not appearance.is_empty():
		var properties: Dictionary = appearance.properties
		var tint: Array = properties.get("tint_milli", [1000, 1000, 1000])
		var label := String(properties.get("label", ""))
		node.set_meta("instance_label", label)
		if node.get_child_count() > 0 and node.get_child(0) is MeshInstance3D:
			var mesh_instance: MeshInstance3D = node.get_child(0)
			var material := _rock_material.duplicate() as StandardMaterial3D
			material.albedo_color = _rock_material.albedo_color * Color(float(tint[0]) / 1000.0, float(tint[1]) / 1000.0, float(tint[2]) / 1000.0, 1.0)
			mesh_instance.material_override = material
	var logical: Dictionary = components.get("core.logical", {})
	if not logical.is_empty():
		node.set_meta("logical_state", logical.get("properties", {}).get("values", {}).duplicate(true))


func unload_region(region_key: Vector2i) -> void:
	var id := _region_id(region_key)
	_mark_region_generation_cancelled(id)
	_region_errors.erase(id)
	_pending_region_publications.erase(id)
	_pending_publication_order.erase(id)
	_command_visual_pending.erase(id)
	_command_migration_sync_regions.erase(id)
	if entity_command_service != null and bool(entity_command_service.get("initialized")):
		entity_command_service.release_region(region_key)
	if terrain_effect_projection_service != null:
		terrain_effect_projection_service.release_scope(region_key)
	if not _regions.has(id):
		return
	var region_root: Node3D = _regions[id]["root"]
	_regions.erase(id)
	if is_instance_valid(region_root):
		remove_child(region_root)
		region_root.free()


func get_terrain_effect_snapshot_for_chunks(requests: Array) -> Dictionary:
	if terrain_effect_projection_service == null:
		return {
			"ok": true,
			"terrain_object_local_frames": [],
			"terrain_object_sampling_frames": [],
			"terrain_object_effect_count": 0,
			"terrain_object_effect_snapshot_sha256": "none",
		}
	return terrain_effect_projection_service.local_snapshot_for_chunks(requests)


func consume_terrain_effect_dirty_chunk_ids() -> Array[String]:
	var result := _terrain_effect_dirty_chunk_ids.duplicate()
	_terrain_effect_dirty_chunk_ids.clear()
	return result


func set_object_visibility(enabled: bool) -> void:
	objects_visible = enabled
	for entry in _regions.values():
		(entry["root"] as Node3D).visible = enabled


func get_visible_instance_count() -> int:
	var count := 0
	if not objects_visible:
		return 0
	for entry in _regions.values():
		count += (entry["instances"] as Array).size()
	return count


func get_active_region_count() -> int:
	return _regions.size()


func get_region_instance_records(region_key: Vector2i) -> Array[Dictionary]:
	var entry: Dictionary = _regions.get(_region_id(region_key), {})
	var result: Array[Dictionary] = []
	for instance in entry.get("instances", []):
		result.append(instance.duplicate(true))
	return result


func _build_selection_record(instance: Dictionary) -> Dictionary:
	var geometry: Dictionary = instance.get("geometry", {})
	var extents := Vector3(float(geometry.get("half_extent_x_mm", 600)), float(geometry.get("half_extent_y_mm", 600)), float(geometry.get("half_extent_z_mm", 600))) / 1000.0
	var scale_milli: Vector3i = instance.get("default_scale_milli", Vector3i(1000, 1000, 1000))
	var position: Vector3 = Vector3(instance.get("position_mm", Vector3i.ZERO)) / 1000.0
	return {
		"entity_id": String(instance.get("instance_id", "")),
		"definition_id": String(instance.get("definition_id", "")),
		"identity_kind": String(instance.get("entity_identity", {}).get("identity_kind", "procedural")),
		"center_local": position + Vector3(0.0, extents.y * float(scale_milli.y) / 1000.0, 0.0),
		"radius": (extents * Vector3(scale_milli) / 1000.0).length(),
	}


func get_definition_ids() -> Array[String]:
	return _definition_ids.duplicate()


func get_placeable_definition_ids() -> Array[String]:
	var ids: Array[String] = []
	if registry == null:
		return ids
	for definition_id in _definition_ids:
		var recipe: Dictionary = registry.evaluate_rock_recipe(definition_id, 1)
		if recipe.get("ok", false) and String(recipe.get("algorithm", "")) == RockMeshAdapter.ALGORITHM:
			ids.append(definition_id)
	ids.sort()
	return ids


func get_population_rule_ids() -> Array[String]:
	return _population_rule_ids.duplicate()


func get_performance_snapshot() -> Dictionary:
	var resident_instances := 0
	var resident_batched := 0
	for entry in _regions.values():
		resident_instances += (entry.get("instances", []) as Array).size()
		for instance in entry.get("instances", []):
			if bool(instance.get("population_batched", false)) and instance.get("instance_components", {}).is_empty():
				resident_batched += 1
	return {
		"active_region_count": _regions.size(),
		"pending_region_publication_count": _pending_region_publications.size() + _region_generation_jobs.size(),
		"region_generation_jobs_in_flight": _region_generation_jobs.size(),
		"active_instance_count": resident_instances,
		"batched_instance_count": resident_batched,
		"geometry_cache_variant_count": _geometry_mesh_cache.size(),
		"last_region": _last_region_metrics.duplicate(true),
		"peak_generation_usec": _peak_region_generation_usec,
		"peak_geometry_build_usec": _peak_mesh_build_usec,
		"peak_batch_build_usec": _peak_batch_build_usec,
		"peak_publications_per_process_tick": _peak_publications_per_process_tick,
		"publications_last_process_tick": _publications_last_process_tick,
	}


func get_error_summary() -> String:
	if not initialized:
		return initialization_error
	if _region_errors.is_empty():
		return ""
	var ids: Array[String] = []
	for id_value in _region_errors:
		ids.append(String(id_value))
	ids.sort()
	return "region %s: %s" % [ids[0], _region_errors[ids[0]]]


func get_package_discovery_diagnostics() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value in _package_discovery_report.get("diagnostics", []):
		if value is Dictionary:
			result.append(value.duplicate(true))
	return result


func get_package_discovery_summary() -> String:
	if _package_discovery_report.is_empty():
		return ""
	var ignored_count := int(_package_discovery_report.get("optional_directory_ignored_count", 0))
	if bool(_package_discovery_report.get("ok", false)):
		if ignored_count == 0:
			return ""
		return "Mod discovery warning: ignored %d undeclared folder(s) in optional user mods; package contents were not loaded" % ignored_count
	var reason := String(_package_discovery_report.get("reason", "unknown"))
	if reason == "missing_manifest":
		return "Mod discovery blocked: a required package directory has no manifest; restore a valid package manifest"
	if reason == "malformed_manifest":
		return "Mod discovery blocked: a declared package manifest is malformed; correct or remove that declared package"
	if reason == "malformed_content" or reason == "content_root_unavailable" or reason == "content_unreadable":
		return "Mod discovery blocked: declared package content is invalid or unavailable; correct that package before retrying"
	if reason.begins_with("reparse_") or reason.begins_with("unsafe_") or reason == "unauthorized_package_root":
		return "Mod discovery blocked by a package path safety check; inspect the mod folder layout"
	return "Mod discovery blocked (%s); inspect the declared package and its dependencies" % reason


func _configured_package_roots() -> Array[String]:
	var user_root := ProjectSettings.globalize_path("user://mods")
	if not Loader._is_authorized_root("user://mods"):
		initialization_error = "package_discovery_failed:unauthorized_package_root"
		return []
	var mkdir_error := DirAccess.make_dir_recursive_absolute(user_root)
	if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
		initialization_error = "user_mod_directory_unavailable"
		return []
	return ["res://mods/first-party", "user://mods"]


func _discover_configured_packages(base_roots: Array[String]) -> Dictionary:
	# Repository examples are documentation/test fixtures, not runtime dependencies.
	# Bundled first-party and installed user packages share this one discovery path.
	return Loader.discover_and_validate(base_roots, ["user://mods"])


func _configured_optional_roots(roots: Array[String]) -> Array[String]:
	return Loader.optional_user_roots(roots)


func _terrain_effect_projection_directory(seed_value: int) -> String:
	var root: String
	if state_directory_override.is_empty():
		root = ProjectSettings.globalize_path(
			"user://worlds/%s/terrain-object-effects" % world_id
		)
	else:
		var object_root := state_directory_override
		object_root = ProjectSettings.globalize_path(object_root) 			if object_root.begins_with("user://") or object_root.begins_with("res://") 			else object_root
		root = object_root + "-terrain-object-effects"
	return root.path_join(
		"seed-%d-generator-%d" % [seed_value, FIELD.GENERATOR_VERSION]
	)


func _initialize_state_service(seed_value: int) -> Dictionary:
	var base_directory := state_directory_override
	if base_directory.is_empty():
		base_directory = ProjectSettings.globalize_path("user://worlds/%s/object-state" % world_id)
	else:
		base_directory = ProjectSettings.globalize_path(base_directory) if base_directory.begins_with("user://") or base_directory.begins_with("res://") else base_directory
	var partition := base_directory.path_join("seed-%d-generator-%d" % [seed_value, FIELD.GENERATOR_VERSION])
	var candidate: RefCounted = StateServiceScript.new()
	var loaded: Dictionary = candidate.initialize(world_id, seed_value, FIELD.GENERATOR_VERSION, partition)
	if not loaded.get("ok", false):
		state_service = null
		return loaded
	state_service = candidate
	return loaded


func _initialize_entity_command_service() -> void:
	entity_command_service = null
	if state_service == null or registry == null or not bool(state_service.get("initialized")):
		return
	if int(state_service.snapshot.get("schema_version", 0)) != StateContract.HISTORY_SNAPSHOT_SCHEMA_VERSION:
		return
	var candidate: RefCounted = EntityCommandServiceScript.new()
	var initialized_result: Dictionary = candidate.initialize(state_service, registry)
	if initialized_result.get("ok", false):
		entity_command_service = candidate


func _fail_initialize(reason: String) -> Dictionary:
	_clear_region_nodes()
	initialized = false
	registry = null
	_definition_ids.clear()
	_mod_count = 0
	_region_errors.clear()
	initialization_error = reason
	return _failure(reason)


func _record_region_failure(region_id: String, reason: String) -> Dictionary:
	_region_errors[region_id] = reason
	return _failure(reason)


func _clear_region_nodes() -> void:
	_wait_for_region_generation_jobs()
	_pending_region_publications.clear()
	_pending_publication_order.clear()
	for entry in _regions.values():
		var region_root: Node3D = entry.get("root")
		if is_instance_valid(region_root):
			if region_root.get_parent() == self:
				remove_child(region_root)
			region_root.free()
	_regions.clear()
	_region_errors.clear()


func _mark_region_generation_cancelled(id: String) -> void:
	if not _region_generation_task_by_id.has(id):
		return
	var task_id := int(_region_generation_task_by_id[id])
	if not _region_generation_jobs.has(task_id):
		_region_generation_task_by_id.erase(id)
		return
	var record: Dictionary = _region_generation_jobs[task_id]
	record["cancelled"] = true
	_region_generation_jobs[task_id] = record


func _wait_for_region_generation_jobs() -> void:
	for task_id_value in _region_generation_jobs.keys():
		WorkerThreadPool.wait_for_task_completion(int(task_id_value))
	_region_generation_jobs.clear()
	_region_generation_task_by_id.clear()


func _exit_tree() -> void:
	_wait_for_region_generation_jobs()


func _region_id(region_key: Vector2i) -> String:
	return "%d,%d" % [region_key.x, region_key.y]


func _get_or_build_geometry_mesh(instance: Dictionary, prepared_cpu: Dictionary = {}) -> Dictionary:
	# Procedural geometry is immutable for a fixed content pin + recipe + seed.
	# Transform/appearance/logical components never mutate mesh topology, so all
	# representatives (legacy, population and placed) can share this bounded cache.
	var key_data := {
		"definition_id": instance.get("definition_id", ""),
		"content_pin": instance.get("content_pin", {}),
		"algorithm": instance.get("recipe_algorithm", ""),
		"geometry": instance.get("geometry", {}),
		"geometry_seeds": instance.get("geometry_seeds", {}),
	}
	var cache_key := JSON.stringify(key_data, "", true, true).sha256_text()
	if _geometry_mesh_cache.has(cache_key):
		_geometry_mesh_cache_order.erase(cache_key)
		_geometry_mesh_cache_order.append(cache_key)
		return {"ok": true, "reason": "cache_hit", "mesh": _geometry_mesh_cache[cache_key]}
	var result: Dictionary
	if not prepared_cpu.is_empty():
		result = RockMeshAdapter.mesh_from_cpu_data(prepared_cpu)
	else:
		result = RockMeshAdapter.build_mesh(instance["geometry"], instance["geometry_seeds"])
	if result.get("ok", false):
		_geometry_mesh_cache[cache_key] = result["mesh"]
		_geometry_mesh_cache_order.append(cache_key)
		while _geometry_mesh_cache_order.size() > MAX_CACHED_GEOMETRY_VARIANTS:
			var evicted: String = _geometry_mesh_cache_order.pop_front()
			_geometry_mesh_cache.erase(evicted)
	return result


func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
