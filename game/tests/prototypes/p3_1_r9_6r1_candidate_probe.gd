extends SceneTree

const Core := preload("res://tests/prototypes/p3_1_r9_2_diagnostic_base.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")
const CandidateA := preload("res://tests/prototypes/p3_1_r9_2_candidate_impl.gd")
const CandidateC := preload("res://tests/prototypes/r9_5_source_snapshots/candidate_c.gd")
const CandidateD := preload("res://tests/prototypes/p3_1_r9_2_candidate_impl.gd")
const BaselineA := preload("res://tests/prototypes/r9_5_source_snapshots/candidate_a.gd")
const BaselineD := preload("res://tests/prototypes/r9_5_source_snapshots/candidate_d.gd")
const FaceInterfacePatch := preload("res://tests/prototypes/p3_1_r9_6r1_face_interface_patch.gd")
const MANIFEST_SHA := "1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972"
const CANDIDATE_FILE_SHA := {"A":"927994b97664778e0d77f62eba47ed09328e0664642936e5d2b1e89d8646ea91", "D":"334db9e3e9dfe3aca4a590845ba6b792629d204c0f1d6a3fc8a3898e7cbb020a"}
const BASELINE_FILE_SHA := {"A":"970fe99f192ea2a3fea3e682072ed3562e6f57c843561dd4440e46381a384d8a", "D":"a33b464ea569f54fb39b72d2198fa971796c0cb5370a64a9696362cd0313f2a6"}
const FACE_INTERFACE_PATCH_FILE_SHA := "b26028b4d637ff90cb4b451cf010ff599bcdefef7c0dc3e1bdc4d9418e98ff8b"
const SEED := 131102026
var cid := ""
var csha := ""
var run_id := ""
var attempt_id := ""
var failures := 0
var roi_ray_mismatches := 0
var interface_attempts_executed := 0
var artifact_paths: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	cid = OS.get_environment("R95_CANDIDATE_ID")
	csha = OS.get_environment("R95_CANDIDATE_SOURCE_SHA")
	run_id = OS.get_environment("R95_RUN_ID")
	attempt_id = OS.get_environment("R96R1_ATTEMPT")
	var oracle_sha := OS.get_environment("R95_ORACLE_SHA")
	var candidate_file_sha := _sha_res_file("res://tests/prototypes/p3_1_r9_2_candidate_impl.gd")
	var baseline_file_sha := _sha_res_file("res://tests/prototypes/r9_5_source_snapshots/candidate_%s.gd" % cid.to_lower())
	var interface_patch_file_sha := _sha_res_file("res://tests/prototypes/p3_1_r9_6r1_face_interface_patch.gd")
	var manifest := Core.load_manifest()
	var d3_attempt:bool=attempt_id.begins_with("ATTEMPT_D3")
	var interface_patch_pin_valid:bool=not (attempt_id=="ATTEMPT_A3" or d3_attempt) or interface_patch_file_sha==FACE_INTERFACE_PATCH_FILE_SHA
	if not ["A","D"].has(cid) or csha.length()!=40 or not csha.is_valid_hex_number() or run_id.is_empty() or not ["ATTEMPT_A2","ATTEMPT_A3","ATTEMPT_D2","ATTEMPT_D3","ATTEMPT_D3_2","ATTEMPT_D3_3","ATTEMPT_1_TOPOLOGY_FIRST"].has(attempt_id) or candidate_file_sha != String(CANDIDATE_FILE_SHA.get(cid,"")) or baseline_file_sha != String(BASELINE_FILE_SHA.get(cid,"")) or not interface_patch_pin_valid or oracle_sha.length() != 40 or not oracle_sha.is_valid_hex_number() or not manifest.get("valid", false) or manifest.get("sha256", "") != MANIFEST_SHA:
		print("R96R1_BLOCKED " + JSON.stringify({"candidate":cid,"candidate_sha":csha,"attempt_id":attempt_id,"candidate_file_sha256":candidate_file_sha,"baseline_file_sha256":baseline_file_sha,"interface_patch_file_sha256":interface_patch_file_sha,"interface_patch_pin_valid":interface_patch_pin_valid,"oracle_sha":oracle_sha,"manifest":manifest.get("reason","ok")})); quit(2); return
	var script: Script = CandidateA if cid == "A" else CandidateD
	var candidate: RefCounted = script.new()
	var baseline_script: Script = BaselineA if cid == "A" else BaselineD
	var baseline: RefCounted = baseline_script.new()
	var root_identity_probe:Dictionary=candidate.call("canonical_root_identity_probe",{})
	if not bool(root_identity_probe.get("valid",false)):failures+=1
	print("R96R1_ROOT_IDENTITY "+JSON.stringify({"candidate":cid,"source_sha":csha,"probe":root_identity_probe}))
	var ray_row: Dictionary = Core.case_by_id(manifest.rows,"R9.2.RAY.CANONICAL_PICKER.v1")
	var setup: Dictionary = Core.make_snapshot(ray_row)
	candidate.call("configure_roi",ray_row.roi)
	var built: Dictionary = candidate.call("build",setup.snapshot,ray_row,{"id":"default","roi":ray_row.roi})
	if not built.get("valid",false): print("R96R1_BLOCKED " + JSON.stringify({"reason":"ray_mesh_build_failed","detail":built.get("reason","unknown")})); quit(2); return
	var ray_artifact := _write_topology_artifact("R9.2.RAY.CANONICAL_PICKER.v1", "default", built, ray_row.roi)
	if not bool(ray_artifact.get("valid",false)):
		print("R96R1_BLOCKED " + JSON.stringify({"reason":"ray_topology_artifact_failed","detail":ray_artifact}));quit(2);return
	var rays: Array[Dictionary] = Core.ray_grid(ray_row.roi,ray_row.ray_grid)
	var classes := {}
	var legacy: Dictionary = Core.compare_mesh_rays(rays,built.mesh,setup.snapshot,int(ray_row.seed),256)
	var legacy_hit_miss_indices:Array[int]=[]
	for ray_index in range(legacy.get("rays",[]).size()):
		var legacy_row:Dictionary=legacy.rays[ray_index]
		if bool(legacy_row.reference_hit)!=bool(legacy_row.mesh_hit):legacy_hit_miss_indices.append(ray_index)
	for i in range(rays.size()):
		var ray: Dictionary = rays[i]
		var exact: Dictionary = _analytic_roots(ray,int(ray_row.seed),setup.snapshot)
		var adaptive: Dictionary = _adaptive_roots(ray,setup.snapshot)
		var finite: Dictionary = Core.canonical_ray_roots(ray.origin,ray.direction,float(ray.length),setup.snapshot,int(ray_row.seed),256,32)
		var hits: Dictionary = _mesh_hits(ray,built.mesh)
		var root_comparison: Dictionary = _compare_root_sets(exact,adaptive)
		var finite_root_comparison: Dictionary = _compare_root_sets(exact,finite)
		var lo: Vector3 = Core.world_min(ray_row.roi)
		var hi: Vector3 = lo + Vector3(Core.cell_counts(ray_row.roi))*Core.step(ray_row.roi)
		var roi_roots: Array[Dictionary] = []
		var roi_boundary_roots: Array[Dictionary] = []
		var roi_side_face_roots: Array[Dictionary] = []
		for root in exact.get("roots",[]):
			var p: Vector3 = root.position
			if p.x>=lo.x-1e-6 and p.x<=hi.x+1e-6 and p.y>=lo.y-1e-6 and p.y<=hi.y+1e-6 and p.z>=lo.z-1e-6 and p.z<=hi.z+1e-6:
				if absf(p.y-lo.y)<=1e-6 or absf(p.y-hi.y)<=1e-6: roi_boundary_roots.append({"root":root,"boundary":"ray_axis_y_cropped_endpoint","mesh_intersection_required":false})
				else:
					roi_roots.append(root)
					var side_faces:Array[String]=[]
					if absf(p.x-lo.x)<=1e-6:side_faces.append("X_MIN")
					if absf(p.x-hi.x)<=1e-6:side_faces.append("X_MAX")
					if absf(p.z-lo.z)<=1e-6:side_faces.append("Z_MIN")
					if absf(p.z-hi.z)<=1e-6:side_faces.append("Z_MAX")
					if not side_faces.is_empty():roi_side_face_roots.append({"root":root,"faces":side_faces,"mesh_intersection_required":true})
		var hit_distances: Array[float] = _cluster_hit_distances(hits.get("hits",[]),1e-5)
		var position_deltas: Array[Dictionary] = _mesh_root_deltas(roi_roots,hit_distances)
		var first: Dictionary = exact.get("first",{})
		var first_inside := false
		if not first.is_empty():
			var first_position: Vector3 = first.position
			first_inside=first_position.x>=lo.x-1e-6 and first_position.x<=hi.x+1e-6 and first_position.y>=lo.y-1e-6 and first_position.y<=hi.y+1e-6 and first_position.z>=lo.z-1e-6 and first_position.z<=hi.z+1e-6
		var hit_miss_disagrees := (not roi_roots.is_empty()) != (not hit_distances.is_empty())
		if hit_miss_disagrees: roi_ray_mismatches += 1
		var classification := "ROOT_ORACLES_CONCORDANT"
		if not exact.valid or not adaptive.valid or not root_comparison.valid:
			classification="ROOT_ORACLE_INCOMPLETE_OR_DISAGREEMENT"
			failures += 1
		elif hit_miss_disagrees: classification="IN_ROI_HIT_MISS"
		elif not position_deltas.is_empty(): classification="IN_ROI_DISTANCE_DIAGNOSTIC"
		else: classification="IN_ROI_HIT_STATE_MATCH"
		if not first_inside and not first.is_empty(): classification += "_GLOBAL_FIRST_ROOT_CROPPED"
		classes[classification]=int(classes.get(classification,0))+1
		print("R95_RAY " + JSON.stringify({"run_id":run_id,"candidate":cid,"source_sha":csha,"oracle_sha":oracle_sha,"ray_index":i,"ray":ray,"analytic":exact,"adaptive":adaptive,"finite_scan_256":finite,"finite_vs_analytic_root_comparison":finite_root_comparison,"analytic_vs_adaptive_root_comparison":root_comparison,"canonical_roots_in_closed_roi_excluding_y_end_faces":roi_roots,"canonical_roots_on_roi_y_end_faces_cropped_not_required":roi_boundary_roots,"canonical_roots_on_xz_side_faces_still_expected":roi_side_face_roots,"mesh_two_sided":hits,"unique_mesh_hit_distances_clustered_1e-5_for_dedup_only":hit_distances,"mesh_root_distance_deltas":position_deltas,"roi_hit_miss_disagrees":hit_miss_disagrees,"global_first_root_inside_mesh_roi":first_inside,"classification":classification}))
	print("R95_RAY_SUMMARY " + JSON.stringify({"candidate":cid,"source_sha":csha,"manifest_sha":MANIFEST_SHA,"ray_count":rays.size(),"roi_scoped_hit_miss_disagreements":roi_ray_mismatches,"classifications":classes,"candidate_mesh_sha256":built.get("mesh_sha256",""),"roi":ray_row.roi,"metrics":built.get("metrics",{})}))
	if rays.size()!=25 or roi_ray_mismatches!=0:failures+=1
	print("R95_LEGACY_SCAN_COMPARISON " + JSON.stringify({"candidate":cid,"source_sha":csha,"ray_count":legacy.get("ray_count",0),"finite_scan_hit_miss_disagreements":legacy.get("hit_miss_disagreements",-1),"finite_scan_disagreement_indices":legacy_hit_miss_indices,"absolute_position_error_p50":legacy.get("position_error_abs_p50",null),"absolute_position_error_p95":legacy.get("position_error_abs_p95",null),"absolute_position_error_max":legacy.get("position_error_abs_max",null),"completeness":legacy.get("root_scan_completeness","unknown")}))
	_print_shared_samples(setup.snapshot)
	_run_xplus(candidate,baseline,manifest)
	_run_frozen_controls(candidate,baseline,manifest)
	_run_preserved_geometry_controls(candidate,baseline,manifest)
	if cid=="D" and d3_attempt and interface_attempts_executed!=3:
		failures+=1
		print("R96R1_BLOCKED "+JSON.stringify({"reason":"expected_D3_interface_probe_count_not_reached","attempt_id":attempt_id,"expected":3,"actual":interface_attempts_executed}))
	print("R96R1_COMPLETE " + JSON.stringify({"candidate":cid,"source_sha":csha,"run_id":run_id,"attempt_id":attempt_id,"candidate_file_sha256":candidate_file_sha,"baseline_file_sha256":baseline_file_sha,"oracle_sha":oracle_sha,"manifest_sha256":MANIFEST_SHA,"ray_count":rays.size(),"roi_scoped_hit_miss_disagreements":roi_ray_mismatches,"root_identity_probe":root_identity_probe.get("valid",false),"interface_attempts_executed":interface_attempts_executed,"artifacts":artifact_paths,"failure_count":failures,"status":"ATTEMPT_%s_RESULTS_CAPTURED" % attempt_id})); quit(1 if failures>0 else 0)

func _analytic_roots(ray: Dictionary, seed: int, snapshot: Dictionary) -> Dictionary:
	var o: Vector3 = ray.origin
	var d: Vector3 = ray.direction.normalized()
	if absf(d.x)>1e-8 or absf(d.z)>1e-8 or d.y>=-0.999999 or not snapshot.get("edits",[]).is_empty(): return {"valid":false,"reason":"requires_zero_edit_vertical_ray"}
	var phase := float(posmod(seed,100003))*0.000173
	var sy := 3.8+1.25*sin(o.x*0.22+phase)+0.70*cos(o.z*0.31-phase*0.7)+0.28*sin((o.x+o.z)*0.11+phase*0.3)
	var cy := 1.15+0.24*sin(o.x*0.25+phase)
	var cz := 6.0+1.05*sin(o.x*0.17+phase*0.6)
	var radial := 0.92*0.92-pow(o.z-cz,2.0)
	var candidates: Array = [{"branch":"top_surface","y":sy},{"branch":"lower_bound","y":Field.MIN_Y}]
	var tangent := false
	if radial>=-1e-12:
		tangent=absf(radial)<=1e-12
		var off := sqrt(maxf(0.0,radial)); candidates.append({"branch":"cave_upper","y":cy+off}); candidates.append({"branch":"cave_lower","y":cy-off})
	var roots: Array[Dictionary]=[]; var rejected: Array[Dictionary]=[]
	for c in candidates:
		var p := Vector3(o.x,float(c.y),o.z); var t := (o.y-p.y)/-d.y
		if t<0.0 or t>float(ray.length): rejected.append({"candidate":c,"reason":"outside_interval"}); continue
		var density := Core.sample(p,snapshot,seed)
		if absf(density)<=2e-5: roots.append({"branch":c.branch,"position":p,"distance":t,"residual":density,"tangent_candidate":tangent and String(c.branch).begins_with("cave")})
		else: rejected.append({"candidate":c,"reason":"inactive_min_branch","density":density})
	roots.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return float(a.distance)<float(b.distance))
	return {"valid":not roots.is_empty(),"roots":roots,"root_count":roots.size(),"first":roots[0] if not roots.is_empty() else {},"rejected_component_roots":rejected,"method":"closed-form roots for all zero-edit SdfWorld-v1 vertical branches; verified against full canonical sampler","tangent_candidate":tangent}

func _adaptive_roots(ray: Dictionary,snapshot: Dictionary)->Dictionary:
	var o:Vector3=ray.origin;var d:Vector3=ray.direction.normalized();var length:=float(ray.length)
	var ctx:Dictionary={"o":o,"d":d,"snapshot":snapshot,"evaluations":0,"roots":[],"unresolved":[],"failure":""}
	var f0:=_f(0.0,ctx);var f1:=_f(length,ctx);_visit(0.0,length,f0,f1,0,ctx)
	if not String(ctx.failure).is_empty():return {"valid":false,"reason":ctx.failure,"evaluations":ctx.evaluations}
	var roots:Array=ctx.roots;roots.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return float(a.distance)<float(b.distance))
	var unresolved:Array=[];var resolved_adjacent_same_sign:=0
	for span in ctx.unresolved:
		var explained_by_root:bool=false
		for root in roots:
			var t:float=float(root.distance)
			if t>=float(span.lo)-5e-5 and t<=float(span.hi)+5e-5:explained_by_root=true;break
		if explained_by_root:resolved_adjacent_same_sign+=1
		else:unresolved.append(span)
	return {"valid":true,"roots":roots,"root_count":roots.size(),"unresolved_tangent_intervals":unresolved,"same_sign_intervals_explained_by_neighboring_roots":resolved_adjacent_same_sign,"raw_same_sign_candidate_intervals":ctx.unresolved.size(),"evaluations":ctx.evaluations,"distance_tolerance":1e-5,"bound":"1-Lipschitz exclusion only when an endpoint absolute value exceeds the complete interval width; unresolved same-sign candidates remain explicit","method":"bounded adaptive subdivision plus bisection; not claimed complete for tangencies"}

func _f(t:float,ctx:Dictionary)->float:
	ctx.evaluations=int(ctx.evaluations)+1
	if int(ctx.evaluations)>50000:ctx.failure="evaluation_stop_loss";return NAN
	return Core.sample(ctx.o+ctx.d*t,ctx.snapshot,SEED)

func _visit(a:float,b:float,fa:float,fb:float,depth:int,ctx:Dictionary)->void:
	if not String(ctx.failure).is_empty():return
	var width:=b-a
	# For a 1-Lipschitz field, |f(endpoint)| greater than the complete interval
	# width proves that zero cannot occur anywhere in this interval. Using half
	# a child width here is unsound when a root lies near that child's far end.
	if absf(fa)>width+1e-7 or absf(fb)>width+1e-7:return
	var m:=(a+b)*0.5;var fm:=_f(m,ctx);if not is_finite(fm):ctx.failure="nonfinite_density";return
	var left_change:=(fa<0.0)!=(fm<0.0);var right_change:=(fm<0.0)!=(fb<0.0)
	if width<=1e-5 or depth>=24:
		if fa==0.0:_record_root(a,ctx,"exact_endpoint")
		if left_change:_bisect(a,m,fa,ctx)
		if fm==0.0:_record_root(m,ctx,"exact_midpoint")
		if right_change:_bisect(m,b,fm,ctx)
		if fb==0.0:_record_root(b,ctx,"exact_endpoint")
		if not left_change and not right_change and fa!=0.0 and fm!=0.0 and fb!=0.0 and minf(absf(fa),minf(absf(fm),absf(fb)))<=width+1e-7:
			ctx.unresolved.append({"lo":a,"hi":b,"sample_abs_min":minf(absf(fa),minf(absf(fm),absf(fb)))})
		return
	_visit(a,m,fa,fm,depth+1,ctx)
	_visit(m,b,fm,fb,depth+1,ctx)

func _record_root(t:float,ctx:Dictionary,kind:String)->void:
	for old in ctx.roots:
		if absf(float(old.distance)-t)<2e-5:return
	ctx.roots.append({"distance":t,"interval":[t,t],"residual":_f(t,ctx),"kind":kind})

func _compare_root_sets(exact:Dictionary,adaptive:Dictionary)->Dictionary:
	var missing:Array=[];var matched:Array=[];var tangent_unresolved:Array=[];var extras:Array=[];var unmatched_unresolved:Array=[]
	var exact_roots:Array=exact.get("roots",[]);var adaptive_roots:Array=adaptive.get("roots",[]);var unresolved:Array=adaptive.get("unresolved_tangent_intervals",[])
	for expected in exact_roots:
		var t:float=float(expected.distance);var nearest:float=INF
		for actual in adaptive_roots:nearest=minf(nearest,absf(float(actual.distance)-t))
		if nearest<=5e-5:matched.append({"distance":t,"adaptive_delta":nearest})
		else:
			var interval_match:bool=false
			if bool(expected.tangent_candidate):
				for span in unresolved:
					if t>=float(span.lo)-1e-5 and t<=float(span.hi)+1e-5:interval_match=true;break
			if interval_match:tangent_unresolved.append(t)
			else:missing.append({"distance":t,"branch":expected.branch,"nearest_adaptive_delta":nearest})
	for actual in adaptive_roots:
		var nearest:float=INF
		for expected in exact_roots:nearest=minf(nearest,absf(float(expected.distance)-float(actual.distance)))
		if nearest>5e-5:extras.append({"distance":actual.distance,"nearest_analytic_delta":nearest})
	for span in unresolved:
		var belongs_to_tangent:bool=false
		for expected in exact_roots:
			if bool(expected.tangent_candidate) and float(expected.distance)>=float(span.lo)-1e-5 and float(expected.distance)<=float(span.hi)+1e-5:belongs_to_tangent=true;break
		if not belongs_to_tangent:unmatched_unresolved.append(span)
	return {"valid":missing.is_empty() and extras.is_empty() and unmatched_unresolved.is_empty(),"matched":matched,"tangent_unresolved_matches":tangent_unresolved,"missing":missing,"extras":extras,"unresolved_interval_count":unresolved.size(),"unmatched_unresolved_count":unmatched_unresolved.size(),"unresolved_intervals_first_8":unresolved.slice(0,8)}

func _bisect(a:float,b:float,fa:float,ctx:Dictionary)->void:
	var lo:=a;var hi:=b;var low:=fa
	for _i in range(32):
		var mid:=(lo+hi)*0.5;var fm:=_f(mid,ctx);if not is_finite(fm):ctx.failure="bisection_nonfinite";return
		if fm==0.0:lo=mid;hi=mid;break
		if (fm<0.0)==(low<0.0):lo=mid;low=fm
		else:hi=mid
	var root:=(lo+hi)*0.5
	for old in ctx.roots:
		if absf(float(old.distance)-root)<2e-5:return
	ctx.roots.append({"distance":root,"interval":[lo,hi],"residual":_f(root,ctx)})

func _cluster_hit_distances(hits:Array,tolerance:float)->Array[float]:
	var ordered:Array[float]=[]
	for hit in hits:ordered.append(float(hit.distance))
	ordered.sort()
	var unique:Array[float]=[]
	for t in ordered:
		if unique.is_empty() or absf(t-unique[unique.size()-1])>tolerance:unique.append(t)
	return unique

func _mesh_root_deltas(roots:Array[Dictionary],hit_distances:Array[float])->Array[Dictionary]:
	var rows:Array[Dictionary]=[]
	for root in roots:
		var nearest:=INF
		for t in hit_distances:nearest=minf(nearest,absf(t-float(root.distance)))
		rows.append({"canonical_branch":root.branch,"canonical_distance":root.distance,"nearest_two_sided_mesh_distance":null if nearest==INF else nearest,"nearest_absolute_distance_error":null if nearest==INF else nearest})
	return rows

func _mesh_hits(ray:Dictionary,mesh:Dictionary)->Dictionary:
	var p:PackedVector3Array=mesh.get("positions",PackedVector3Array());var d:Vector3=ray.direction.normalized();var hits:Array[Dictionary]=[]
	for i in range(0,p.size(),3):
		var a:Vector3=p[i];var b:Vector3=p[i+1];var c:Vector3=p[i+2];var e1:=b-a;var e2:=c-a;var h:=d.cross(e2);var det:=e1.dot(h)
		if absf(det)<1e-10:continue
		var inv:=1.0/det;var s:Vector3=ray.origin-a;var u:=inv*s.dot(h);if u< -1e-7 or u>1.0+1e-7:continue
		var q:=s.cross(e1);var v:=inv*d.dot(q);if v< -1e-7 or u+v>1.0+1e-7:continue
		var t:=inv*e2.dot(q);if t<0.0 or t>float(ray.length):continue
		hits.append({"distance":t,"triangle_index":i/3,"normal_dot_direction":e1.cross(e2).dot(d),"face":"front" if e1.cross(e2).dot(d)<0.0 else "back"})
	hits.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return float(a.distance)<float(b.distance))
	return {"hit":not hits.is_empty(),"hit_count":hits.size(),"distance":hits[0].distance if not hits.is_empty() else null,"first":hits[0] if not hits.is_empty() else {},"hits":hits,"method":"independent two-sided Moller-Trumbore"}

func _run_xplus(candidate:RefCounted,baseline:RefCounted,manifest:Dictionary)->void:
	for id in ["R9.2.SEAM.XPLUS_EQUAL.v1","R9.2.SEAM.XPLUS_MIXED_LOD.v1","R9.2.HIST.XPLUS_DEFECT.v1"]:
		var row:Dictionary=Core.case_by_id(manifest.rows,id);if row.is_empty():continue
		var setup:Dictionary=Core.make_snapshot(row);candidate.call("configure_roi",row.roi);var full:Dictionary=candidate.call("build",setup.snapshot,row,{"id":"default","roi":row.roi})
		baseline.call("configure_roi",row.roi);var baseline_full:Dictionary=baseline.call("build",setup.snapshot,row,{"id":"default","roi":row.roi})
		var full_hash_equal:bool=full.get("valid",false) and baseline_full.get("valid",false) and String(full.get("mesh_sha256",""))==String(baseline_full.get("mesh_sha256",""))
		if full.get("valid",false):
			var full_artifact:Dictionary=_write_topology_artifact(id,"full_roi",full,row.roi)
			if not bool(full_artifact.get("valid",false)):failures+=1
		else:failures+=1
		var lo:Vector3=Core.world_min(row.roi);var hi:=lo+Vector3(Core.cell_counts(row.roi))*Core.step(row.roi)
		if full.get("valid",false) and cid=="A":
			var a_metrics:Dictionary=full.get("metrics",{})
			if bool(a_metrics.get("a2_enabled",false)):
				print("R96R1_A2_PATCH "+JSON.stringify({"scenario_id":id,"candidate":cid,"source_sha":csha,"method":a_metrics.get("a2_refinement_method",""),"refined_cells":a_metrics.get("a2_refined_cells",[]),"refined_cell_count":a_metrics.get("a2_refined_cell_count",0),"refined_parent_tetrahedra":a_metrics.get("a2_refined_parent_tetrahedra",0),"additional_sdf_evaluations":a_metrics.get("a2_additional_sdf_evaluations",0),"steiner_vertices":a_metrics.get("a2_steiner_vertices",0),"new_surface_roots":a_metrics.get("a2_new_surface_roots",0),"refined_patch_emitted_triangles":a_metrics.get("a2_refined_patch_emitted_triangles",0),"max_vertex_displacement":a_metrics.get("a2_max_vertex_displacement",0.0),"max_root_residual":a_metrics.get("a2_max_root_residual",0.0),"root_residual_bound":a_metrics.get("a2_root_residual_bound",0.0),"vertex_evidence":a_metrics.get("a2_vertex_evidence",[])}))
			else:
				print("R95_CUTOFF_TRACE "+JSON.stringify(_trace_a_cutoffs(candidate,setup.snapshot,row.roi,full.mesh,int(a_metrics.get("cutoff_drops",-1)))))
		elif full.get("valid",false) and cid=="D":
			var volume:Dictionary=full.get("volume",{})
			print("R95_CUTOFF_TRACE "+JSON.stringify(_trace_d_cutoffs(candidate,volume.get("values",PackedFloat32Array()),row.roi,full.mesh,int(full.get("metrics",{}).get("extract",{}).get("cutoff_drops",-1)))))
		print("R95_XPLUS "+JSON.stringify({"scenario_id":id,"candidate":cid,"source_sha":csha,"scope":"single-ROI historical proxy, not chunk join","mesh_sha256":full.get("mesh_sha256",""),"baseline_mesh_sha256":baseline_full.get("mesh_sha256",""),"baseline_mesh_hash_equal":full_hash_equal,"metrics":full.get("metrics",{}),"exact_topology":_exact_topology(full.get("mesh",Core.new_mesh()),lo,hi) if full.get("valid",false) else {}, "valid":full.get("valid",false)}))
		var mixed: bool = id.ends_with("MIXED_LOD.v1");var left_roi:Dictionary={"id":"L","min":[15.0,1.0,6.0],"cells":[2,4,4] if mixed else [4,8,8],"step":0.5 if mixed else 0.25};var right_roi:Dictionary={"id":"R","min":[16.0,1.0,6.0],"cells":[4,8,8],"step":0.25}
		candidate.call("configure_roi",left_roi);var left:Dictionary=candidate.call("build",setup.snapshot,row,{"id":"L","roi":left_roi});candidate.call("configure_roi",right_roi);var right:Dictionary=candidate.call("build",setup.snapshot,row,{"id":"R","roi":right_roi})
		baseline.call("configure_roi",left_roi);var baseline_left:Dictionary=baseline.call("build",setup.snapshot,row,{"id":"L","roi":left_roi});baseline.call("configure_roi",right_roi);var baseline_right:Dictionary=baseline.call("build",setup.snapshot,row,{"id":"R","roi":right_roi})
		var split_hashes_equal:bool=left.get("valid",false) and right.get("valid",false) and baseline_left.get("valid",false) and baseline_right.get("valid",false) and String(left.get("mesh_sha256",""))==String(baseline_left.get("mesh_sha256","")) and String(right.get("mesh_sha256",""))==String(baseline_right.get("mesh_sha256",""))
		if left.get("valid",false):
			var left_artifact:Dictionary=_write_topology_artifact(id,"left_roi",left,left_roi)
			if not bool(left_artifact.get("valid",false)):failures+=1
		else:failures+=1
		if right.get("valid",false):
			var right_artifact:Dictionary=_write_topology_artifact(id,"right_roi",right,right_roi)
			if not bool(right_artifact.get("valid",false)):failures+=1
		else:failures+=1
		if not left.get("valid",false) or not right.get("valid",false):print("R95_SPLIT_BLOCKED "+JSON.stringify({"id":id,"left":left.get("reason","ok"),"right":right.get("reason","ok")}));failures+=1;continue
		var left_slice:Dictionary=_mesh_plane_segments(left.mesh,0,16.0);var right_slice:Dictionary=_mesh_plane_segments(right.mesh,0,16.0)
		var ls:Dictionary=left_slice.segments;var rs:Dictionary=right_slice.segments;var delta:=_dict_delta(ls,rs);var combined:=_combine(left.mesh,right.mesh)
		var left_values:PackedFloat32Array=left.get("volume",{}).get("values",PackedFloat32Array()) if cid=="D" else PackedFloat32Array()
		var right_values:PackedFloat32Array=right.get("volume",{}).get("values",PackedFloat32Array()) if cid=="D" else PackedFloat32Array()
		var oracle_l:Dictionary=_face_oracle(setup.snapshot,left_roi,1,int(row.seed),left_values,cid=="D")
		var oracle_r:Dictionary=_face_oracle(setup.snapshot,right_roi,0,int(row.seed),right_values,cid=="D")
		if not oracle_l.get("valid",false) or not oracle_r.get("valid",false):
			print("R95_FACE_ORACLE_BLOCKED "+JSON.stringify({"scenario_id":id,"candidate":cid,"left":oracle_l,"right":oracle_r}))
			failures+=1
			continue
		var ldiff:=_dict_delta(ls,oracle_l.segments);var rdiff:=_dict_delta(rs,oracle_r.segments)
		var left_coplanar_edges:Dictionary=_boundary_segments(left.mesh,16.0);var right_coplanar_edges:Dictionary=_boundary_segments(right.mesh,16.0)
		if attempt_id=="ATTEMPT_A3" or (cid=="D" and attempt_id.begins_with("ATTEMPT_D3")):
			interface_attempts_executed+=1
			var left_payload:String=String(left.get("metrics",{}).get("materialized_volume_sha256","canonical_sdf"))
			var right_payload:String=String(right.get("metrics",{}).get("materialized_volume_sha256","canonical_sdf"))
			var left_min:Vector3=Core.world_min(left_roi);var right_min:Vector3=Core.world_min(right_roi)
			var left_max:Vector3=left_min+Vector3(Core.cell_counts(left_roi))*Core.step(left_roi)
			var right_max:Vector3=right_min+Vector3(Core.cell_counts(right_roi))*Core.step(right_roi)
			var interface_roi_min:=Vector3(minf(left_min.x,right_min.x),minf(left_min.y,right_min.y),minf(left_min.z,right_min.z))
			var interface_roi_max:=Vector3(maxf(left_max.x,right_max.x),maxf(left_max.y,right_max.y),maxf(left_max.z,right_max.z))
			var interface_identity:Dictionary={"candidate":cid,"left_chunk_id":String(left_roi.id),"right_chunk_id":String(right_roi.id),
				"lod_pair":[1,0] if mixed else [0,0],"field_revision":int(setup.snapshot.get("revision",-1)),
				"edit_revision":int(setup.snapshot.get("revision",-1)),"volume_payload_hashes":[left_payload,right_payload],
				"interface_roi_min":[interface_roi_min.x,interface_roi_min.y,interface_roi_min.z],
				"interface_roi_max":[interface_roi_max.x,interface_roi_max.y,interface_roi_max.z]}
			var patch_started:int=Time.get_ticks_usec()
			var patch_result:Dictionary=FaceInterfacePatch.new().build(interface_identity,left.mesh,right.mesh,0,16.0)
			var patch_elapsed:int=Time.get_ticks_usec()-patch_started
			var patched_combined:Dictionary=_combine(left.mesh,right.mesh)
			var patched_topology:Dictionary={"valid":false,"reason":"patch_not_generated"}
			var patch_field:Dictionary={"valid":false,"reason":"patch_not_generated"}
			var patch_artifact:Dictionary={"valid":false,"reason":"patch_not_generated"}
			if bool(patch_result.get("valid",false)):
				var patch_mesh:Dictionary=patch_result.mesh
				patched_combined.positions.append_array(patch_mesh.get("positions",PackedVector3Array()))
				patched_combined.normals.append_array(patch_mesh.get("normals",PackedVector3Array()))
				patched_topology=_exact_topology(patched_combined,Vector3(15,1,6),Vector3(17,3,8))
				patch_field=_interface_patch_field_diagnostic(patch_mesh,setup.snapshot,int(row.seed))
				patch_artifact=_write_interface_patch_artifact(id,patch_result,interface_identity)
				if bool(patch_artifact.get("valid",false)):artifact_paths.append(String(patch_artifact.path))
			var interface_label:String="R96R1_A3_INTERFACE" if attempt_id=="ATTEMPT_A3" else "R96R1_D3_INTERFACE"
			print(interface_label+" "+JSON.stringify({"candidate":cid,"source_sha":csha,"attempt":attempt_id,"scenario_id":id,
				"interface_identity":interface_identity,"axis":0,"global_face_coordinate":16.0,"shared_patch_generated_once":bool(patch_result.get("valid",false)),
				"left_consumes_patch_key":patch_result.get("left_consumes_patch_key",false),"right_consumes_patch_key":patch_result.get("right_consumes_patch_key",false),
				"patch_key_sha256":patch_result.get("patch_key_sha256",""),"patch_mode":patch_result.get("mode","failed"),
				"patch_generation_usec":patch_elapsed,"left_boundary_edges":left_coplanar_edges.size(),"right_boundary_edges":right_coplanar_edges.size(),
				"left_graph":patch_result.get("left_graph",{}),"right_graph":patch_result.get("right_graph",{}),"patch_graph":patch_result.get("patch_graph",{}),
				"shared_interface_root_count":patch_result.get("interface_vertex_count",0),
				"shared_boundary_vertex_key_count":patch_result.get("shared_boundary_vertex_key_count",0),
				"left_boundary_vertex_keys":patch_result.get("left_boundary_vertex_keys",[]),
				"right_boundary_vertex_keys":patch_result.get("right_boundary_vertex_keys",[]),
				"patch_vertex_count":patch_result.get("interface_vertex_count",0) if patch_result.get("mode","")!="shared_existing_contour" else 0,
				"patch_triangle_count":patch_result.get("triangle_count",0),
				"patch_minimum_cross_squared":patch_result.get("minimum_cross_squared",null),
				"patch_cutoff_rejections":patch_result.get("cutoff_rejections",0),
				"patch_cutoff_rejected_candidates":patch_result.get("cutoff_rejected_candidates",0),
				"patch_correspondence_mode":patch_result.get("correspondence_mode","none"),
				"patch_endpoint_connectors":patch_result.get("endpoint_connectors",[]),
				"patch_winding_compatible":patch_result.get("winding_compatible",false),
				"patch_failure_reason":patch_result.get("reason",""),"patch_failure_detail":patch_result.get("detail",{}),
				"base_combined_internal_open_edges":_exact_topology(_combine(left.mesh,right.mesh),Vector3(15,1,6),Vector3(17,3,8)).internal_open_edges,
				"patched_combined_topology":patched_topology,"canonical_surface_diagnostic_only":patch_field,
				"materialized_volume_identity_before_after":{"left":left_payload,"right":right_payload,"mutation":"none; patch receives emitted mesh contours only"},
				"patch_artifact":patch_artifact,"geometry_claim":"experimental topological bridge on the shared plane; this does not certify a canonical zero-SDF surface"}))
		print("R96R1_SPLIT_PAIR " + JSON.stringify({
			"scenario_id": id, "candidate": cid, "lod_pair": [1, 0] if mixed else [0, 0], "plane_x": 16.0,
			"left_mesh_sha256": left.get("mesh_sha256", ""), "right_mesh_sha256": right.get("mesh_sha256", ""),
			"baseline_mesh_hashes_equal": split_hashes_equal,
			"left_segments": ls.size(), "right_segments": rs.size(), "left_only": delta.left.size(), "right_only": delta.right.size(),
			"left_expected": oracle_l.segments.size(), "left_missing": ldiff.right.size(), "left_extra": ldiff.left.size(),
			"right_expected": oracle_r.segments.size(), "right_missing": rdiff.right.size(), "right_extra": rdiff.left.size(),
			"left_endpoint_delta": _segment_endpoint_deltas(ls, oracle_l.segment_rows),
			"right_endpoint_delta": _segment_endpoint_deltas(rs, oracle_r.segment_rows),
			"combined_topology": _exact_topology(combined, Vector3(15, 1, 6), Vector3(17, 3, 8)),
			"scope": "candidate-generated separate ROIs; not production chunk acceptance"}))

func _interface_patch_field_diagnostic(mesh:Dictionary,snapshot:Dictionary,seed:int)->Dictionary:
	var positions:PackedVector3Array=mesh.get("positions",PackedVector3Array())
	var normals:PackedVector3Array=mesh.get("normals",PackedVector3Array())
	if positions.is_empty() or positions.size()%3!=0:return {"valid":false,"reason":"patch_mesh_empty_or_malformed","authority":"canonical SDF diagnostic only; not used to build patch"}
	var residuals:Array[float]=[];var normal_angles:Array[float]=[];var finite_samples:=0
	for i in range(positions.size()):
		var p:Vector3=positions[i];var density:float=Core.sample(p,snapshot,seed)
		if not is_finite(density):return {"valid":false,"reason":"nonfinite_canonical_patch_vertex_sample"}
		residuals.append(absf(density));finite_samples+=1
	for i in range(0,positions.size(),3):
		var centroid:Vector3=(positions[i]+positions[i+1]+positions[i+2])/3.0
		var density:float=Core.sample(centroid,snapshot,seed)
		if not is_finite(density):return {"valid":false,"reason":"nonfinite_canonical_patch_centroid_sample"}
		residuals.append(absf(density));finite_samples+=1
		var epsilon:=1.0e-4
		var gradient:=Vector3(Core.sample(centroid+Vector3(epsilon,0,0),snapshot,seed)-Core.sample(centroid-Vector3(epsilon,0,0),snapshot,seed),
			Core.sample(centroid+Vector3(0,epsilon,0),snapshot,seed)-Core.sample(centroid-Vector3(0,epsilon,0),snapshot,seed),
			Core.sample(centroid+Vector3(0,0,epsilon),snapshot,seed)-Core.sample(centroid-Vector3(0,0,epsilon),snapshot,seed))
		if gradient.is_finite() and gradient.length_squared()>1.0e-18:
			var patch_normal:Vector3=normals[i].normalized();var angle:float=rad_to_deg(acos(clampf(patch_normal.dot(gradient.normalized()),-1.0,1.0)));normal_angles.append(angle)
	residuals.sort();normal_angles.sort()
	return {"valid":true,"authority":"canonical SDF diagnostic only; no geometry generation, projection, or D-volume resampling","sample_count":finite_samples,
		"absolute_density_residual":{"p50":_percentile(residuals,0.5),"p95":_percentile(residuals,0.95),"max":residuals.back() if not residuals.is_empty() else null},
		"patch_vs_canonical_gradient_normal_degrees":{"p50":_percentile(normal_angles,0.5),"p95":_percentile(normal_angles,0.95),"max":normal_angles.back() if not normal_angles.is_empty() else null},"normal_samples":normal_angles.size()}

func _write_interface_patch_artifact(scenario_id:String,patch:Dictionary,identity:Dictionary)->Dictionary:
	var artifact_root:=OS.get_environment("R96R1_ARTIFACT_DIR")
	if artifact_root.is_empty() or not DirAccess.dir_exists_absolute(artifact_root):return {"valid":false,"reason":"interface_patch_artifact_root_invalid"}
	var safe_id:=scenario_id.replace("/","_").replace(":","_")
	var path:=artifact_root.path_join("%s_%s_interface_patch.json"%[attempt_id,safe_id])
	if FileAccess.file_exists(path):return {"valid":false,"reason":"interface_patch_artifact_overwrite_refused","path":path}
	var mesh:Dictionary=patch.get("mesh",{});var positions:PackedVector3Array=mesh.get("positions",PackedVector3Array());var normals:PackedVector3Array=mesh.get("normals",PackedVector3Array())
	var vertices:Array=[];var vertex_sources:Array=[]
	for p in positions:
		vertices.append([p.x,p.y,p.z])
		vertex_sources.append({"position":[p.x,p.y,p.z],"root_identity":Core._point_key(p),"authority":"INTERPOLATED_VOLUME"})
	var normal_rows:Array=[];for n in normals:normal_rows.append([n.x,n.y,n.z])
	var body:Dictionary={"schema":"P3.1.R9.7.InterfacePatch.v1","attempt":attempt_id,"candidate":cid,"source_sha":csha,
		"scenario_id":scenario_id,"patch_key_sha256":patch.get("patch_key_sha256",""),"identity":identity,"identity_text":patch.get("identity_text",""),
		"mode":patch.get("mode",""),"mesh_sha256":patch.get("mesh_sha256",""),"triangle_count":patch.get("triangle_count",0),
		"vertices":vertices,"vertex_sources":vertex_sources,"vertex_authority":"INTERPOLATED_VOLUME",
		"left_boundary_vertex_keys":patch.get("left_boundary_vertex_keys",[]),"right_boundary_vertex_keys":patch.get("right_boundary_vertex_keys",[]),
		"shared_boundary_vertex_key_count":patch.get("shared_boundary_vertex_key_count",0),
		"endpoint_connectors":patch.get("endpoint_connectors",[]),
		"correspondence_mode":patch.get("correspondence_mode","none"),"component_pairs":patch.get("component_pairs",[]),
		"minimum_cross_squared":patch.get("minimum_cross_squared",null),"cutoff_squared":patch.get("cutoff_squared",1.0e-12),
		"normals":normal_rows,"left_graph":patch.get("left_graph",{}),"right_graph":patch.get("right_graph",{}),
		"patch_graph":patch.get("patch_graph",{}),"boundary_edge_count":patch.get("patch_boundary_edge_count",0),
		"winding_compatible":patch.get("winding_compatible",false),"scope":"experimental shared face bridge; not production geometry"}
	var text:=JSON.stringify(body,"\t");var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return {"valid":false,"reason":"interface_patch_artifact_open_failed"}
	file.store_string(text);file.flush();var err:=file.get_error();file.close()
	if err!=OK:return {"valid":false,"reason":"interface_patch_artifact_write_failed","error":err}
	var bytes:=FileAccess.get_file_as_bytes(path)
	return {"valid":not bytes.is_empty(),"path":path,"bytes":bytes.size(),"sha256":Core.sha256(bytes),"mesh_sha256":patch.get("mesh_sha256","")}

func _trace_a_cutoffs(candidate:RefCounted,snapshot:Dictionary,roi:Dictionary,mesh:Dictionary,reported_drops:int)->Dictionary:
	var roi_min:Vector3=Core.world_min(roi);var cells:Vector3i=Core.cell_counts(roi);var step:float=Core.step(roi);var dims:Vector3i=cells+Vector3i.ONE;var values:=PackedFloat32Array();values.resize(dims.x*dims.y*dims.z)
	for y in range(dims.y):
		for z in range(dims.z):
			for x in range(dims.x):values[(y*dims.z+z)*dims.x+x]=Core.sample(roi_min+Vector3(x,y,z)*step,snapshot)
	var incidence:Dictionary=_mesh_edge_incidence(mesh);var internal_open:Dictionary=_internal_open_edge_keys(mesh,roi_min,roi_min+Vector3(cells)*step);var records:Array[Dictionary]=[];var dropped_count:int=0
	for y in range(cells.y):
		for z in range(cells.z):
			for x in range(cells.x):
				var points:Array[Vector3]=[];var densities:Array[float]=[]
				for corner in Core.GRID_CORNERS:
					var ix:int=x+corner.x;var iy:int=y+corner.y;var iz:int=z+corner.z;points.append(roi_min+Vector3(ix,iy,iz)*step);densities.append(float(values[(iy*dims.z+iz)*dims.x+ix]))
				for tet_index in range(Core.TETS.size()):
					var tet:Array=Core.TETS[tet_index];var scratch:Dictionary=Core.new_mesh();var outcome:Dictionary=candidate.call("_polygonize_tet",tet,points,densities,snapshot,scratch);var dropped:int=int(outcome.get("dropped",0))
					if dropped<=0:continue
					dropped_count+=dropped;var trace:Dictionary=_a_cutoff_tet(candidate,tet,points,densities,snapshot,step)
					for edge in trace.get("removed_polygon_edges",[]):
						var key:String=String(edge.key);edge["full_mesh_incidence"]=int(incidence.get(key,0));edge["is_internal_open_edge"]=internal_open.has(key)
					records.append({"cell_index":[x,y,z],"cell_world_min":points[0],"tetrahedron_index":tet_index,"tetrahedron_corner_indices":tet,"tetrahedron_source_samples":trace.get("source_samples",[]),"cutoff_drop_count":dropped,"reason":trace.get("reason","polygonizer_cutoff"),"crossing_edges_and_roots":trace.get("root_edges",[]),"candidate_polygon":trace.get("polygon",[]),"candidate_area_tests":trace.get("area_tests",[]),"removed_polygon_edges":trace.get("removed_polygon_edges",[])})
	var explained:Dictionary={};for record in records:
		for edge in record.removed_polygon_edges:
			if edge.is_internal_open_edge:explained[edge.key]=true
	var unexplained:Array=[];for key in internal_open:
		if not explained.has(key):unexplained.append(key)
	var open_records:Array[Dictionary]=_internal_open_edge_records(mesh,roi_min,roi_min+Vector3(cells)*step)
	return {"candidate":"A","candidate_source_sha":csha,"roi":roi,"reported_cutoff_drop_count":reported_drops,"traced_cutoff_drop_count":dropped_count,"cutoff_squared":1e-12,"dropped_tetrahedra":records,"full_mesh_internal_open_edge_count":internal_open.size(),"internal_open_edges":open_records,"cutoff_loop_patch_feasibility":_open_cycle_triangulation_probe(open_records,1e-12),"unique_internal_open_edges_explained_by_cutoff_perimeters":explained.size(),"unexplained_internal_open_edges_first_32":unexplained.slice(0,32),"trace_matches_reported_metric":dropped_count==reported_drops,"mesh_incidence_source":"exact binary32 position keys from full candidate mesh"}

func _a_cutoff_tet(candidate:RefCounted,tet:Array,points:Array[Vector3],densities:Array[float],snapshot:Dictionary,step:float)->Dictionary:
	var inside:Array[int]=[];var outside:Array[int]=[];var samples:Array[Dictionary]=[]
	for raw in tet:
		var i:int=int(raw);if densities[i]>=0.0:inside.append(i)
		else:outside.append(i)
		samples.append({"corner_index":i,"position":points[i],"density":densities[i],"binary32_hex":PackedFloat32Array([densities[i]]).to_byte_array().hex_encode(),"side":"solid" if densities[i]>=0.0 else "empty"})
	var roots:Array[Vector3]=[];var root_edges:Array[Dictionary]=[];var polygon:Array[Vector3]=[];var areas:Array[Dictionary]=[];var reason:String="single_triangle_cutoff"
	if inside.is_empty() or outside.is_empty():return {"source_samples":samples,"reason":"no_crossing_not_a_cutoff"}
	if inside.size()==1 or outside.size()==1:
		var pivot:int=inside[0] if inside.size()==1 else outside[0];var others:Array=outside if inside.size()==1 else inside
		for other in others:
			var other_index:int=int(other);var root:Dictionary=candidate.call("_edge_root",pivot,other_index,points,densities,snapshot);roots.append(root.point);root_edges.append(_a_root_edge_record(pivot,other_index,points,root.point,step))
		polygon=roots.duplicate();areas.append(_a_area_record(polygon[0],polygon[1],polygon[2],"single"))
	else:
		var edge_pairs:Array[Vector2i]=[Vector2i(inside[0],outside[0]),Vector2i(inside[0],outside[1]),Vector2i(inside[1],outside[0]),Vector2i(inside[1],outside[1])]
		for pair in edge_pairs:
			var root:Dictionary=candidate.call("_edge_root",pair.x,pair.y,points,densities,snapshot);roots.append(root.point);root_edges.append(_a_root_edge_record(pair.x,pair.y,points,root.point,step))
		var a:Vector3=roots[0];var b:Vector3=roots[1];var c:Vector3=roots[2];var d:Vector3=roots[3];polygon=[a,b,d,c]
		areas=[_a_area_record(a,b,d,"historical_1"),_a_area_record(a,d,c,"historical_2"),_a_area_record(a,b,c,"alternate_1"),_a_area_record(b,d,c,"alternate_2")]
		reason="both_complete_quad_diagonals_contain_sub_cutoff_triangle"
	return {"source_samples":samples,"root_edges":root_edges,"polygon_kind":"quad" if roots.size()==4 else "triangle","polygon":polygon,"area_tests":areas,"reason":reason,"removed_polygon_edges":_polygon_edge_records(polygon)}

func _a_root_edge_record(ai:int,bi:int,points:Array[Vector3],root:Vector3,step:float)->Dictionary:
	var a:Vector3=points[ai];var b:Vector3=points[bi];var na:Vector3i=Vector3i(roundi(a.x/step),roundi(a.y/step),roundi(a.z/step));var nb:Vector3i=Vector3i(roundi(b.x/step),roundi(b.y/step),roundi(b.z/step))
	return {"corner_indices":[ai,bi],"world_endpoints":[a,b],"lattice_endpoint_indices":[na,nb],"root":root}

func _a_area_record(a:Vector3,b:Vector3,c:Vector3,label:String)->Dictionary:
	var cross:Vector3=(b-a).cross(c-a);return {"triangle":label,"cross_squared":cross.length_squared(),"finite":cross.is_finite(),"passes_unchanged_cutoff":cross.is_finite() and cross.length_squared()>1e-12}

func _polygon_edge_records(polygon:Array[Vector3])->Array[Dictionary]:
	var edges:Array[Dictionary]=[]
	for i in range(polygon.size()):
		var a:Vector3=polygon[i];var b:Vector3=polygon[(i+1)%polygon.size()];var ka:String=_exact_key(a);var kb:String=_exact_key(b);edges.append({"key":ka+"|"+kb if ka<kb else kb+"|"+ka,"a":a,"b":b})
	return edges

func _mesh_edge_incidence(mesh:Dictionary)->Dictionary:
	var counts:Dictionary={};var p:PackedVector3Array=mesh.get("positions",PackedVector3Array())
	for i in range(0,p.size(),3):
		for e in [Vector2i(0,1),Vector2i(1,2),Vector2i(2,0)]:
			var ka:String=_exact_key(p[i+e.x]);var kb:String=_exact_key(p[i+e.y]);var key:String=ka+"|"+kb if ka<kb else kb+"|"+ka;counts[key]=int(counts.get(key,0))+1
	return counts

func _internal_open_edge_keys(mesh:Dictionary,lo:Vector3,hi:Vector3)->Dictionary:
	var incidence:Dictionary=_mesh_edge_incidence(mesh);var p:PackedVector3Array=mesh.get("positions",PackedVector3Array());var ends:Dictionary={};var out:Dictionary={}
	for i in range(0,p.size(),3):
		for e in [Vector2i(0,1),Vector2i(1,2),Vector2i(2,0)]:
			var a:Vector3=p[i+e.x];var b:Vector3=p[i+e.y];var ka:String=_exact_key(a);var kb:String=_exact_key(b);var key:String=ka+"|"+kb if ka<kb else kb+"|"+ka;ends[key]=[a,b]
	for key in incidence:
		if int(incidence[key])!=1:continue
		var edge:Array=ends[key];var on_roi_boundary:bool=false
		for axis in range(3):
			if (absf(edge[0][axis]-lo[axis])<2e-5 and absf(edge[1][axis]-lo[axis])<2e-5) or (absf(edge[0][axis]-hi[axis])<2e-5 and absf(edge[1][axis]-hi[axis])<2e-5):on_roi_boundary=true
		if not on_roi_boundary:out[key]=true
	return out

func _internal_open_edge_records(mesh:Dictionary,lo:Vector3,hi:Vector3)->Array[Dictionary]:
	var incidence:Dictionary=_mesh_edge_incidence(mesh);var p:PackedVector3Array=mesh.get("positions",PackedVector3Array());var ends:Dictionary={};var out:Array[Dictionary]=[]
	for i in range(0,p.size(),3):
		for e in [Vector2i(0,1),Vector2i(1,2),Vector2i(2,0)]:
			var a:Vector3=p[i+e.x];var b:Vector3=p[i+e.y];var ka:String=_exact_key(a);var kb:String=_exact_key(b);var key:String=ka+"|"+kb if ka<kb else kb+"|"+ka
			if not ends.has(key):ends[key]=[a,b]
	for key in incidence:
		if int(incidence[key])!=1:continue
		var edge:Array=ends[key];var on_roi_boundary:bool=false
		for axis in range(3):
			if (absf(edge[0][axis]-lo[axis])<2e-5 and absf(edge[1][axis]-lo[axis])<2e-5) or (absf(edge[0][axis]-hi[axis])<2e-5 and absf(edge[1][axis]-hi[axis])<2e-5):on_roi_boundary=true
		if not on_roi_boundary:out.append({"key":key,"a":edge[0],"b":edge[1],"incidence":int(incidence[key])})
	return out

func _open_cycle_triangulation_probe(edge_rows:Array[Dictionary],cutoff_squared:float)->Dictionary:
	var adjacency:Dictionary={};var point_by_key:Dictionary={}
	for row in edge_rows:
		var a:Vector3=row.a;var b:Vector3=row.b;var ka:String=_exact_key(a);var kb:String=_exact_key(b)
		point_by_key[ka]=a;point_by_key[kb]=b
		if not adjacency.has(ka):adjacency[ka]=[]
		if not adjacency.has(kb):adjacency[kb]=[]
		if not adjacency[ka].has(kb):adjacency[ka].append(kb)
		if not adjacency[kb].has(ka):adjacency[kb].append(ka)
	var keys:Array[String]=[]
	for key in adjacency:keys.append(String(key))
	keys.sort()
	var visited:Dictionary={};var cycles:Array[Dictionary]=[];var open_or_branch_components:Array[Dictionary]=[]
	for start in keys:
		if visited.has(start):continue
		var stack:Array[String]=[start];var component:Array[String]=[];visited[start]=true
		while not stack.is_empty():
			var current:String=stack.pop_back();component.append(current)
			for neighbor_value in adjacency[current]:
				var neighbor:String=String(neighbor_value)
				if not visited.has(neighbor):visited[neighbor]=true;stack.append(neighbor)
		var degree_two:bool=component.size()>=3
		for vertex in component:
			if adjacency[vertex].size()!=2:degree_two=false
		if not degree_two:
			var degree_sum:int=0
			for vertex in component:degree_sum+=adjacency[vertex].size()
			open_or_branch_components.append({"vertex_count":component.size(),"edge_count":degree_sum/2,"degree_sequence":_component_degrees(component,adjacency)})
			continue
		component.sort();var ordered:Array[String]=[component[0]];var first_neighbors:Array[String]=[]
		for neighbor_value in adjacency[component[0]]:first_neighbors.append(String(neighbor_value))
		first_neighbors.sort();var previous:String=component[0];var current:String=first_neighbors[0]
		while current!=component[0] and ordered.size()<=component.size():
			ordered.append(current);var choices:Array[String]=[]
			for neighbor_value in adjacency[current]:
				var neighbor:String=String(neighbor_value)
				if neighbor!=previous:choices.append(neighbor)
			previous=current;current=choices[0] if not choices.is_empty() else component[0]
		var points:Array[Vector3]=[]
		for key in ordered:points.append(point_by_key[key])
		var best_min:float=_max_min_cycle_triangulation(points)
		var diameter:float=0.0
		for a in points:
			for b in points:diameter=maxf(diameter,a.distance_to(b))
		cycles.append({"vertex_count":points.size(),"edge_count":points.size(),"ordered_boundary_vertices":points,"diameter":diameter,"maximum_possible_minimum_cross_squared_over_all_polygon_triangulations":best_min,"unchanged_cutoff_squared":cutoff_squared,"vertex_preserving_cutoff_pass_possible":best_min>cutoff_squared,"method":"dynamic-programming maximum bottleneck triangle area over every triangulation of the ordered boundary polygon; feasibility only, does not validate winding, planarity, manifold join, or SDF deviation"})
	return {"closed_internal_cycles":cycles,"open_or_branch_components":open_or_branch_components,"scope":"internal-open-edge boundary vertices only; ROI-cropped boundary portions excluded","cutoff_squared":cutoff_squared}

func _component_degrees(component:Array[String],adjacency:Dictionary)->Array[int]:
	var out:Array[int]=[]
	for key in component:out.append(adjacency[key].size())
	out.sort()
	return out

func _max_min_cycle_triangulation(points:Array[Vector3])->float:
	var count:int=points.size()
	if count<3:return -1.0
	var dp:Array=[]
	for i in range(count):
		var row:Array[float]=[];row.resize(count)
		for j in range(count):row[j]=-INF
		dp.append(row)
	for i in range(count-1):dp[i][i+1]=INF
	for span in range(2,count):
		for i in range(count-span):
			var j:int=i+span
			for k in range(i+1,j):
				var cross:Vector3=(points[k]-points[i]).cross(points[j]-points[i]);var score:float=cross.length_squared() if cross.is_finite() else -INF
				var bottleneck:float=minf(minf(dp[i][k],dp[k][j]),score)
				dp[i][j]=maxf(dp[i][j],bottleneck)
	return dp[0][count-1]

func _trace_d_cutoffs(candidate:RefCounted,values:PackedFloat32Array,roi:Dictionary,mesh:Dictionary,reported_drops:int)->Dictionary:
	var roi_min:Vector3=Core.world_min(roi);var cells:Vector3i=Core.cell_counts(roi);var step:float=Core.step(roi);var dims:Vector3i=cells+Vector3i.ONE;var incidence:Dictionary=_mesh_edge_incidence(mesh);var internal_open:Dictionary=_internal_open_edge_keys(mesh,roi_min,roi_min+Vector3(cells)*step);var records:Array[Dictionary]=[];var root_cache:Dictionary={};var dropped_count:int=0
	if values.size()!=dims.x*dims.y*dims.z:return {"candidate":"D","valid":false,"reason":"materialized_volume_size_mismatch","actual":values.size(),"expected":dims.x*dims.y*dims.z}
	for y in range(cells.y):
		for z in range(cells.z):
			for x in range(cells.x):
				var points:Array[Vector3]=[];var densities:Array[float]=[];var source_samples:Array[Dictionary]=[];var solid:Vector3=Vector3.ZERO;var empty:Vector3=Vector3.ZERO;var solid_count:int=0;var empty_count:int=0
				for corner in Core.GRID_CORNERS:
					var ix:int=x+corner.x;var iy:int=y+corner.y;var iz:int=z+corner.z;var point:Vector3=roi_min+Vector3(ix,iy,iz)*step;var density:float=values[(iy*dims.z+iz)*dims.x+ix]
					points.append(point);densities.append(density);source_samples.append({"corner_index":points.size()-1,"position":point,"density_float32":density,"binary32_hex":PackedFloat32Array([density]).to_byte_array().hex_encode()})
					if density>=0.0:solid+=point;solid_count+=1
					else:empty+=point;empty_count+=1
				if solid_count==0 or empty_count==0:continue
				var toward_empty:Vector3=empty/float(empty_count)-solid/float(solid_count)
				for tet_index in range(Core.TETS.size()):
					var tet:Array=Core.TETS[tet_index];var hits:Array[Vector3]=[];var identities:Array[String]=[];var root_edges:Array[Dictionary]=[];var identity_seen:Dictionary={}
					for edge in [Vector2i(0,1),Vector2i(0,2),Vector2i(0,3),Vector2i(1,2),Vector2i(1,3),Vector2i(2,3)]:
						var a:int=int(tet[edge.x]);var b:int=int(tet[edge.y]);if (densities[a]>=0.0)==(densities[b]>=0.0):continue
						var node_a:Vector3i=Vector3i(x,y,z)+Core.GRID_CORNERS[a];var node_b:Vector3i=Vector3i(x,y,z)+Core.GRID_CORNERS[b];var root:Dictionary=candidate.call("_canonical_volume_root",root_cache,node_a,node_b,densities[a],densities[b],points[a],points[b])
						if not root.get("valid",false):continue
						var identity:String=String(root.get("root_identity",root.get("edge_key","")));if identity_seen.has(identity):continue
						identity_seen[identity]=true;identities.append(identity);hits.append(root.point);root_edges.append({"tet_edge_corners":[a,b],"lattice_nodes":[node_a,node_b],"root_identity":identity,"root":root.point,"reused":root.get("reused",false)})
					if hits.size()<3:continue
					var tet_toward:Vector3=candidate.call("_tetra_toward_empty",points,densities,tet);var ordered:Array[Vector3]=candidate.call("_order_polygon",hits,tet_toward)
					if ordered.size()!=hits.size():continue
					for fan in range(1,ordered.size()-1):
						var tri:Array[Vector3]=[ordered[0],ordered[fan],ordered[fan+1]];var cross:Vector3=(tri[1]-tri[0]).cross(tri[2]-tri[0]);var scratch:Dictionary=Core.new_mesh();var passes:bool=Core.add_triangle(scratch,tri[0],tri[1],tri[2],tet_toward,1e-12)
						if passes:continue
						dropped_count+=1;var tri_edges:Array[Dictionary]=_polygon_edge_records(tri)
						for edge_record in tri_edges:
							var key:String=String(edge_record.key);edge_record["full_mesh_incidence"]=int(incidence.get(key,0));edge_record["is_internal_open_edge"]=internal_open.has(key)
						records.append({"cell_index":[x,y,z],"cell_world_min":points[0],"tetrahedron_index":tet_index,"tetrahedron_corner_indices":tet,"tetrahedron_source_samples":source_samples,"crossing_edge_roots":root_edges,"ordered_polygon_roots":ordered,"dropped_fan_index":fan,"dropped_triangle":tri,"cross_vector":cross,"cross_squared":cross.length_squared(),"threshold_squared":1e-12,"reason":"nonfinite_cross" if not cross.is_finite() else "cross_squared_at_or_below_1e-12","removed_triangle_edges":tri_edges})
	var explained:Dictionary={};for record in records:
		for edge in record.removed_triangle_edges:
			if edge.is_internal_open_edge:explained[edge.key]=true
	var unexplained:Array=[];for key in internal_open:
		if not explained.has(key):unexplained.append(key)
	var open_records:Array[Dictionary]=_internal_open_edge_records(mesh,roi_min,roi_min+Vector3(cells)*step)
	return {"candidate":"D","valid":true,"candidate_source_sha":csha,"roi":roi,"reported_cutoff_drop_count":reported_drops,"traced_cutoff_drop_count":dropped_count,"threshold_squared":1e-12,"dropped_triangles":records,"full_mesh_internal_open_edge_count":internal_open.size(),"internal_open_edges":open_records,"cutoff_loop_patch_feasibility":_open_cycle_triangulation_probe(open_records,1e-12),"unique_internal_open_edges_explained_by_cutoff_triangle_edges":explained.size(),"unexplained_internal_open_edges_first_32":unexplained.slice(0,32),"trace_matches_reported_metric":dropped_count==reported_drops,"mesh_incidence_source":"exact binary32 position keys from full candidate mesh","volume_authority":"candidate D returned materialized float32 samples from canonical SDF plus ordered frozen ledger"}

func _face_oracle(snapshot:Dictionary,roi:Dictionary,face_side:int,seed:int,materialized_values:PackedFloat32Array=PackedFloat32Array(),require_materialized:bool=false)->Dictionary:
	var lo:Vector3=Core.world_min(roi);var cells:Vector3i=Core.cell_counts(roi);var h:float=Core.step(roi);var dims:Vector3i=cells+Vector3i.ONE
	var expected_values:int=dims.x*dims.y*dims.z;var use_materialized:bool=not materialized_values.is_empty()
	if face_side!=0 and face_side!=1:return {"valid":false,"reason":"face_side_must_be_zero_or_one"}
	if require_materialized and not use_materialized:return {"valid":false,"reason":"required_materialized_face_volume_missing"}
	if use_materialized and materialized_values.size()!=expected_values:return {"valid":false,"reason":"materialized_face_volume_size_mismatch","actual":materialized_values.size(),"expected":expected_values}
	var segments:Dictionary={};var segment_rows:Array[Dictionary]=[];var triangle_count:int=0;var triangle_records:Array[Dictionary]=[]
	var local_x:int=cells.x if face_side==1 else 0;var plane_x:float=lo.x+float(local_x)*h
	for y in range(cells.y):
		for z in range(cells.z):
			for tet_index in range(Core.TETS.size()):
				var face_corners:Array[int]=[]
				for raw_corner in Core.TETS[tet_index]:
					var corner_index:int=int(raw_corner)
					if Core.GRID_CORNERS[corner_index].x==face_side:face_corners.append(corner_index)
				if face_corners.size()!=3:continue
				triangle_count+=1;var tri_points:Array[Vector3]=[];var tri_values:Array[float]=[]
				for corner_index in face_corners:
					var corner:Vector3i=Core.GRID_CORNERS[corner_index]
					var point:=Vector3(plane_x,lo.y+float(y+corner.y)*h,lo.z+float(z+corner.z)*h)
					var lattice_x:int=local_x;var lattice_y:int=y+corner.y;var lattice_z:int=z+corner.z
					var value:float=materialized_values[(lattice_y*dims.z+lattice_z)*dims.x+lattice_x] if use_materialized else Core.sample(point,snapshot,seed)
					tri_points.append(point);tri_values.append(value)
				var crossings:Array[Vector3]=[];var tri_edges:Array[Vector2i]=[Vector2i(0,1),Vector2i(1,2),Vector2i(2,0)]
				for edge in tri_edges:
					var ia:int=edge.x;var ib:int=edge.y;var da:float=tri_values[ia];var db:float=tri_values[ib];var hit:Vector3=Vector3.ZERO;var has_hit:bool=false
					if da==0.0 and db<0.0:
						hit=tri_points[ia];has_hit=true
					elif db==0.0 and da<0.0:
						hit=tri_points[ib];has_hit=true
					elif (da<0.0)!=(db<0.0):
						if use_materialized:
							var denom:float=da-db
							if denom!=0.0 and is_finite(denom):
								hit=tri_points[ia].lerp(tri_points[ib],clampf(da/denom,0.0,1.0));has_hit=true
						else:
							var low:float=0.0;var high:float=1.0;var low_value:float=da
							for _iteration in range(32):
								var mid:float=(low+high)*0.5;var mid_value:float=Core.sample(tri_points[ia].lerp(tri_points[ib],mid),snapshot,seed)
								if mid_value==0.0:low=mid;high=mid;break
								if (mid_value<0.0)==(low_value<0.0):low=mid;low_value=mid_value
								else:high=mid
								hit=tri_points[ia].lerp(tri_points[ib],(low+high)*0.5)
								has_hit=true
					if has_hit:
						var duplicate:bool=false
						for prior in crossings:
							if prior.distance_squared_to(hit)<1e-12:duplicate=true;break
						if not duplicate:crossings.append(hit)
				if crossings.size()==2:
					var a:Vector3=crossings[0];var b:Vector3=crossings[1];var ka:String=Core._point_key(a);var kb:String=Core._point_key(b);var key:String=ka+"|"+kb if ka<kb else kb+"|"+ka
					segments[key]=true;segment_rows.append({"key":key,"a":a,"b":b,"cell_y":y,"cell_z":z,"tetrahedron_index":tet_index,"face_corner_indices":face_corners,"triangle_points":tri_points,"triangle_values":tri_values})
				triangle_records.append({"cell_y":y,"cell_z":z,"tetrahedron_index":tet_index,"face_corner_indices":face_corners,"triangle_points":tri_points,"triangle_values":tri_values,"contour_segments_emitted":1 if crossings.size()==2 else 0})
	return {"valid":true,"segments":segments,"segment_rows":segment_rows,"face_triangle_count":triangle_count,"triangle_records":triangle_records,"face_side":face_side,"plane_x":plane_x,"method":"induced_face_triangles_from_frozen_Core.TETS_with_materialized_linear_edges" if use_materialized else "induced_face_triangles_from_frozen_Core.TETS_with_32step_canonical_edge_bisection","node_source":"candidate_D_returned_float32_volume" if use_materialized else "canonical_continuous_SDF"}

func _segment_endpoint_deltas(actual:Dictionary,expected_rows:Array[Dictionary])->Dictionary:
	var actual_rows:Array[Dictionary]=[]
	for key in actual:
		var parsed:Array=String(key).split("|")
		if parsed.size()!=2:continue
		var a:=_point_from_key(String(parsed[0]));var b:=_point_from_key(String(parsed[1]));actual_rows.append({"key":String(key),"a":a,"b":b})
	var forward:Array[float]=[];var reverse:Array[float]=[];var unmatched_actual:int=0;var unmatched_expected:int=0
	for row in actual_rows:
		var best:float=INF
		for expected in expected_rows:
			best=minf(best,_segment_endpoint_pair_delta(row,expected))
		forward.append(best);if is_inf(best):unmatched_actual+=1
	for expected in expected_rows:
		var best:float=INF
		for row in actual_rows:best=minf(best,_segment_endpoint_pair_delta(row,expected))
		reverse.append(best);if is_inf(best):unmatched_expected+=1
	forward.sort();reverse.sort()
	return {"actual_segment_count":actual_rows.size(),"expected_segment_count":expected_rows.size(),"actual_to_expected_endpoint_pair_distance":{"p50":_percentile(forward,0.5),"p95":_percentile(forward,0.95),"max":forward.back() if not forward.is_empty() else null},"expected_to_actual_endpoint_pair_distance":{"p50":_percentile(reverse,0.5),"p95":_percentile(reverse,0.95),"max":reverse.back() if not reverse.is_empty() else null},"unmatched_actual_count":unmatched_actual,"unmatched_expected_count":unmatched_expected,"metric":"minimum of direct/reversed max endpoint Euclidean distance per segment; diagnostic only; no acceptance tolerance"}

func _segment_endpoint_pair_delta(a:Dictionary,b:Dictionary)->float:
	var aa:Vector3=a.get("a",Vector3.ZERO);var ab:Vector3=a.get("b",Vector3.ZERO);var ba:Vector3=b.get("a",Vector3.ZERO);var bb:Vector3=b.get("b",Vector3.ZERO)
	return minf(maxf(aa.distance_to(ba),ab.distance_to(bb)),maxf(aa.distance_to(bb),ab.distance_to(ba)))

func _point_from_key(key:String)->Vector3:
	return Core._key_point(key)

func _percentile(values:Array[float],q:float)->Variant:
	if values.is_empty():return null
	var index:=clampi(int(ceil((values.size()-1)*q)),0,values.size()-1)
	return values[index]

func _boundary_segments(mesh:Dictionary,x:float)->Dictionary:
	var out:Dictionary={};var p:PackedVector3Array=mesh.get("positions",PackedVector3Array())
	for i in range(0,p.size(),3):
		for e in [Vector2i(0,1),Vector2i(1,2),Vector2i(2,0)]:
			var a:Vector3=p[i+e.x];var b:Vector3=p[i+e.y]
			if absf(a.x-x)>1e-5 or absf(b.x-x)>1e-5:continue
			var ka:=Core._point_key(a);var kb:=Core._point_key(b);out[ka+"|"+kb if ka<kb else kb+"|"+ka]=true
	return out

func _mesh_plane_segments(mesh:Dictionary,axis:int,plane:float)->Dictionary:
	var segments:Dictionary={};var rows:Array[Dictionary]=[];var positions:PackedVector3Array=mesh.get("positions",PackedVector3Array());var raw_count:int=0;var coplanar_count:int=0;var plane_epsilon:float=1e-6
	if axis<0 or axis>2 or positions.size()%3!=0:return {"valid":false,"reason":"mesh_plane_input_invalid","axis":axis,"position_count":positions.size()}
	for i in range(0,positions.size(),3):
		var triangle:Array[Vector3]=[positions[i],positions[i+1],positions[i+2]];var hits:Array[Vector3]=[];var coplanar_edges:Array[Vector2i]=[]
		for edge in [Vector2i(0,1),Vector2i(1,2),Vector2i(2,0)]:
			var a:Vector3=triangle[edge.x];var b:Vector3=triangle[edge.y];var da:float=a[axis]-plane;var db:float=b[axis]-plane;var a_on:bool=absf(da)<=plane_epsilon;var b_on:bool=absf(db)<=plane_epsilon
			if a_on and b_on:
				hits.append(a);hits.append(b);coplanar_edges.append(edge)
			elif a_on:hits.append(a)
			elif b_on:hits.append(b)
			elif (da<0.0)!=(db<0.0):
				var denominator:float=da-db
				if denominator!=0.0 and is_finite(denominator):hits.append(a.lerp(b,clampf(da/denominator,0.0,1.0)))
		var unique:Array[Vector3]=[]
		for point in hits:
			var duplicate:bool=false
			for prior in unique:
				if prior.distance_squared_to(point)<1e-12:duplicate=true;break
			if not duplicate:unique.append(point)
		if coplanar_edges.size()==3:
			coplanar_count+=1
			for edge in [Vector2i(0,1),Vector2i(1,2),Vector2i(2,0)]:_append_plane_segment(segments,rows,triangle[edge.x],triangle[edge.y],i/3,axis)
		elif unique.size()==2:_append_plane_segment(segments,rows,unique[0],unique[1],i/3,axis)
		raw_count+=1 if unique.size()==2 or coplanar_edges.size()==3 else 0
	return {"valid":true,"segments":segments,"segment_rows":rows,"raw_segment_count":raw_count,"coplanar_triangle_count":coplanar_count,"axis":axis,"plane":plane,"classification_epsilon":plane_epsilon,"method":"independent triangle-plane slicing of emitted candidate positions"}

func _append_plane_segment(segments:Dictionary,rows:Array[Dictionary],a:Vector3,b:Vector3,triangle_index:int,axis:int)->void:
	var ka:String=Core._point_key(a);var kb:String=Core._point_key(b);var key:String=ka+"|"+kb if ka<kb else kb+"|"+ka
	segments[key]=true;rows.append({"key":key,"a":a,"b":b,"triangle_index":triangle_index,"plane_axis":axis})

func _interface_incidence(mesh:Dictionary,x:float)->Dictionary:
	var counts:Dictionary={};var p:PackedVector3Array=mesh.get("positions",PackedVector3Array())
	for i in range(0,p.size(),3):
		for e in [Vector2i(0,1),Vector2i(1,2),Vector2i(2,0)]:
			var a:Vector3=p[i+e.x];var b:Vector3=p[i+e.y]
			if absf(a.x-x)>1e-5 or absf(b.x-x)>1e-5:continue
			var ka:=_exact_key(a);var kb:=_exact_key(b);var key:=ka+"|"+kb if ka<kb else kb+"|"+ka;counts[key]=int(counts.get(key,0))+1
	var one:=0;var two:=0;var high:=0
	for n in counts.values():
		if int(n)==1:one+=1
		elif int(n)==2:two+=1
		else:high+=1
	return {"unique_edges":counts.size(),"incidence_one":one,"incidence_two":two,"incidence_gt_two":high}

func _exact_topology(mesh:Dictionary,lo:Vector3,hi:Vector3)->Dictionary:
	var p:PackedVector3Array=mesh.get("positions",PackedVector3Array());var counts:Dictionary={};var ends:Dictionary={}
	if p.size()%3!=0:return {"valid":false,"reason":"triangle_data_invalid"}
	for i in range(0,p.size(),3):
		for e in [Vector2i(0,1),Vector2i(1,2),Vector2i(2,0)]:
			var a:Vector3=p[i+e.x];var b:Vector3=p[i+e.y];var ka:=_exact_key(a);var kb:=_exact_key(b);var key:=ka+"|"+kb if ka<kb else kb+"|"+ka;counts[key]=int(counts.get(key,0))+1
			if not ends.has(key):ends[key]=[a,b]
	var internal:=0;var boundary:=0;var nonmanifold:=0;var ex:Array=[]
	for key in counts:
		var n:int=counts[key]
		if n>2:nonmanifold+=1
		elif n==1:
			var edge:Array=ends[key];var on_boundary:=false
			for axis in range(3):
				if (absf(edge[0][axis]-lo[axis])<2e-5 and absf(edge[1][axis]-lo[axis])<2e-5) or (absf(edge[0][axis]-hi[axis])<2e-5 and absf(edge[1][axis]-hi[axis])<2e-5):on_boundary=true
			if on_boundary:boundary+=1
			else:
				internal+=1
				if ex.size()<24:ex.append({"key":key,"a":edge[0],"b":edge[1]})
	return {"valid":true,"internal_open_edges":internal,"roi_boundary_open_edges":boundary,"nonmanifold_edges":nonmanifold,"internal_examples_first_24":ex,"triangle_count":p.size()/3}

func _exact_key(p:Vector3)->String:return PackedVector3Array([p]).to_byte_array().hex_encode()
func _combine(a:Dictionary,b:Dictionary)->Dictionary:
	var m:=Core.new_mesh();m.positions.append_array(a.get("positions",PackedVector3Array()));m.positions.append_array(b.get("positions",PackedVector3Array()));m.normals.append_array(a.get("normals",PackedVector3Array()));m.normals.append_array(b.get("normals",PackedVector3Array()));return m
func _dict_delta(a:Dictionary,b:Dictionary)->Dictionary:
	var l:Array=[];var r:Array=[]
	for k in a:
		if not b.has(k):l.append(k)
	for k in b:
		if not a.has(k):r.append(k)
	return {"left":l,"right":r}

func _run_frozen_controls(candidate:RefCounted,baseline:RefCounted,manifest:Dictionary)->void:
	for id in ["R9.2.HIST.XMINUS_DISPLACEMENT.v1","R9.2.HIST.TRIANGLE3103.v1"]:
		var row:Dictionary=Core.case_by_id(manifest.rows,id);var setup:Dictionary=Core.make_snapshot(row);candidate.call("configure_roi",row.roi);var built:Dictionary=candidate.call("build",setup.snapshot,row,{"id":"default","roi":row.roi});baseline.call("configure_roi",row.roi);var baseline_built:Dictionary=baseline.call("build",setup.snapshot,row,{"id":"default","roi":row.roi})
		var hashes_equal:bool=built.get("valid",false) and baseline_built.get("valid",false) and String(built.get("mesh_sha256",""))==String(baseline_built.get("mesh_sha256",""))
		if not built.get("valid",false) or not baseline_built.get("valid",false) or not hashes_equal:failures+=1
		else:
			var artifact:Dictionary=_write_topology_artifact(id,"default",built,row.roi)
			if not bool(artifact.get("valid",false)):failures+=1
		if id.contains("TRIANGLE3103"):
			var corners:Array=[];var lo:Vector3=Core.world_min(row.roi)
			for c in Core.GRID_CORNERS:
				var p:Vector3=lo+Vector3(c)*Core.step(row.roi);var d:float=Core.sample(p,setup.snapshot,int(row.seed));corners.append({"point":p,"density":d,"binary32":PackedFloat32Array([d]).to_byte_array().hex_encode()})
			print("R95_TRIANGLE3103 "+JSON.stringify({"scenario_id":id,"candidate":cid,"source_sha":csha,"mesh_hash_equal_to_r95_baseline":hashes_equal,"frozen_triangle_index":row.triangle_index,"local_cell_triangle_count":built.get("mesh",{}).get("positions",PackedVector3Array()).size()/3,"corners":corners,"global_index_equivalence":"NOT_CLAIMED; one-cell ROI is not historical full-mesh ordering","cutoff":row.squared_cross_cutoff}))
		else:
			var rd:Dictionary=row.ray;var ray:Dictionary={"origin":Vector3(rd.origin[0],rd.origin[1],rd.origin[2]),"direction":Vector3(rd.direction[0],rd.direction[1],rd.direction[2]),"length":rd.length};var roots:=_adaptive_roots(ray,setup.snapshot);var hits:=_mesh_hits(ray,built.mesh);var lo:Vector3=Core.world_min(row.roi);var hi:=lo+Vector3(Core.cell_counts(row.roi))*Core.step(row.roi)
			print("R95_XMINUS "+JSON.stringify({"scenario_id":id,"candidate":cid,"source_sha":csha,"mesh_hash_equal_to_r95_baseline":hashes_equal,"metrics":built.get("metrics",{}),"adaptive_roots":roots,"mesh_hits":hits,"roi_min":lo,"roi_max":hi,"historical_root_y":row.historical_continuous_root_y,"first_root_inside_roi":float(row.historical_continuous_root_y)>=lo.y and float(row.historical_continuous_root_y)<=hi.y}))

func _run_preserved_geometry_controls(candidate:RefCounted,baseline:RefCounted,manifest:Dictionary)->void:
	var scenario_ids:Array[String]=["R9.2.GEO.ZERO.v1","R9.2.GEO.CARVE.v1","R9.2.GEO.FILL_CARVE.v1","R9.2.CHUNK.NEIGHBOR_PAIR.v1","R9.2.SEAM.NEGATIVE_REGIONS.v1"]
	for scenario_id in scenario_ids:
		var row:Dictionary=Core.case_by_id(manifest.rows,scenario_id)
		if row.is_empty():failures+=1;print("R96R1_CONTROL_FAIL "+JSON.stringify({"scenario_id":scenario_id,"reason":"frozen_row_missing"}));continue
		var setup:Dictionary=Core.make_snapshot(row)
		if not bool(setup.get("valid",false)):failures+=1;print("R96R1_CONTROL_FAIL "+JSON.stringify({"scenario_id":scenario_id,"reason":"snapshot_rejected","detail":setup.get("reason","")}));continue
		var variants:Array=[]
		if row.has("variants"):
			variants=row.get("variants",[])
		else:
			variants=[{"id":String(row.get("roi",{}).get("id","default")),"roi":row.get("roi",{})}]
		for variant_value in variants:
			var variant:Dictionary=variant_value
			var roi:Dictionary=variant.get("roi",{})
			if roi.is_empty():failures+=1;print("R96R1_CONTROL_FAIL "+JSON.stringify({"scenario_id":scenario_id,"variant":variant.get("id",""),"reason":"roi_missing"}));continue
			candidate.call("configure_roi",roi)
			var candidate_build:Dictionary=candidate.call("build",setup.snapshot,row,variant)
			baseline.call("configure_roi",roi)
			var baseline_build:Dictionary=baseline.call("build",setup.snapshot,row,variant)
			if not bool(candidate_build.get("valid",false)) or not bool(baseline_build.get("valid",false)):
				failures+=1
				print("R96R1_CONTROL_FAIL "+JSON.stringify({"scenario_id":scenario_id,"variant":variant.get("id",""),"candidate_reason":candidate_build.get("reason","ok"),"baseline_reason":baseline_build.get("reason","ok")}))
				continue
			var lo:Vector3=Core.world_min(roi)
			var hi:Vector3=lo+Vector3(Core.cell_counts(roi))*Core.step(roi)
			var mesh_topology:Dictionary=Core.topology(candidate_build.mesh,lo,hi)
			var mesh_hash_equal:bool=String(candidate_build.get("mesh_sha256",""))==String(baseline_build.get("mesh_sha256",""))
			var internal_edges: Variant = mesh_topology.get("internal_open_edges", null)
			var nonmanifold_edges: Variant = mesh_topology.get("nonmanifold_edges", null)
			var topology_counts_valid: bool = typeof(internal_edges) == TYPE_INT and int(internal_edges) >= 0 and typeof(nonmanifold_edges) == TYPE_INT and int(nonmanifold_edges) >= 0
			var zero_internal: bool = topology_counts_valid and int(internal_edges) == 0 and int(nonmanifold_edges) == 0
			var artifact:Dictionary=_write_topology_artifact(scenario_id,String(variant.get("id","default")),candidate_build,roi,baseline_build.get("mesh_sha256",""),mesh_topology)
			var report:Dictionary=candidate_build.get("topology",{})
			var disposition:String="COMPLETE" if bool(report.get("geometry_realization_complete",false)) else "PARTIAL"
			var passed:bool=mesh_hash_equal and zero_internal and bool(artifact.get("valid",false))
			if not passed:failures+=1
			print("R96R1_CONTROL "+JSON.stringify({"scenario_id":scenario_id,"variant":variant.get("id","default"),"revision":setup.get("revision",-1),"commands":row.get("commands",[]).size(),"support_and_rebuild":row.get("support_and_rebuild",row.get("regions",{})),"candidate_mesh_sha256":candidate_build.get("mesh_sha256",""),"r95_baseline_mesh_sha256":baseline_build.get("mesh_sha256",""),"mesh_hash_equal":mesh_hash_equal,"cutoff":1.0e-12,"mesh_internal_open_edges":mesh_topology.get("internal_open_edges",-1),"mesh_nonmanifold_edges":mesh_topology.get("nonmanifold_edges",-1),"required_topology_disposition":disposition,"required_topology_summary":_topology_summary(report),"artifact":artifact,"pass":passed}))

func _topology_summary(report:Dictionary)->Dictionary:
	return {"valid":report.get("valid",false),"geometry_realization_complete":report.get("geometry_realization_complete",false),"topology_sha256":report.get("topology_sha256",""),"root_count":report.get("root_count",0),"required_triangle_count":report.get("required_triangle_count",0),"emitted_triangle_count":report.get("emitted_triangle_count",0),"rejected_triangle_count":report.get("rejected_triangle_count",0),"internal_open_edges":report.get("internal_open_edges",[]).size(),"roi_boundary_open_edges":report.get("roi_boundary_open_edges",[]).size(),"nonmanifold_edges":report.get("nonmanifold_edges",[]).size(),"missing_required_adjacency":report.get("missing_required_adjacency",[]).size(),"surface_components":report.get("surface_components",[]).size(),"surface_loops":report.get("surface_loops",[]).size(),"rejection_reasons":report.get("rejection_reasons",{})}

func _sha_res_file(path:String)->String:
	var bytes:PackedByteArray=FileAccess.get_file_as_bytes(path)
	return Core.sha256(bytes) if not bytes.is_empty() else ""

func _write_topology_artifact(scenario_id:String,variant_id:String,built:Dictionary,roi:Dictionary,
		baseline_mesh_sha:String="",mesh_topology:Dictionary={})->Dictionary:
	var artifact_root:=OS.get_environment("R96R1_ARTIFACT_DIR")
	if artifact_root.is_empty() or not artifact_root.is_absolute_path():return {"valid":false,"reason":"artifact_root_missing_or_not_absolute"}
	if not built.get("valid",false):return {"valid":false,"reason":"candidate_build_invalid"}
	var report:Dictionary=built.get("topology",{})
	if report.is_empty():return {"valid":false,"reason":"required_topology_report_missing"}
	if mesh_topology.is_empty():
		var lo:Vector3=Core.world_min(roi);var hi:Vector3=lo+Vector3(Core.cell_counts(roi))*Core.step(roi)
		mesh_topology=Core.topology(built.mesh,lo,hi)
	var safe_scenario:=scenario_id.replace("/","_").replace(":","_")
	var safe_variant:=variant_id.replace("/","_").replace(":","_")
	var path:=artifact_root.path_join("%s_%s_%s_topology.json" % [cid,safe_scenario,safe_variant])
	if FileAccess.file_exists(path):return {"valid":false,"reason":"topology_artifact_overwrite_refused","path":path}
	var payload:Dictionary={"candidate":cid,"source_sha":csha,"source_file_sha256":String(CANDIDATE_FILE_SHA.get(cid,"")),"baseline_source_sha256":String(BASELINE_FILE_SHA.get(cid,"")),"run_id":run_id,"scenario_id":scenario_id,"variant_id":variant_id,"seed":SEED,"manifest_sha256":MANIFEST_SHA,"region":roi.get("region",null),"revision":roi.get("revision",null),"roi":roi,"candidate_mesh_sha256":built.get("mesh_sha256",""),"baseline_mesh_sha256":baseline_mesh_sha,"candidate_metrics":built.get("metrics",{}),"actual_mesh_topology":mesh_topology,"required_surface_topology":report}
	var bytes:PackedByteArray=(JSON.stringify(payload)+"\n").to_utf8_buffer()
	var error:=DirAccess.make_dir_recursive_absolute(artifact_root)
	if error!=OK and error!=ERR_ALREADY_EXISTS:return {"valid":false,"reason":"artifact_directory_create_failed","error":error}
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return {"valid":false,"reason":"artifact_open_failed","path":path,"error":FileAccess.get_open_error()}
	file.store_buffer(bytes);file.flush();var write_error:=file.get_error();file.close()
	if write_error!=OK:return {"valid":false,"reason":"artifact_write_failed","path":path,"error":write_error}
	var saved:PackedByteArray=FileAccess.get_file_as_bytes(path)
	var digest:=Core.sha256(saved)
	artifact_paths.append(path)
	return {"valid":digest==Core.sha256(bytes),"path":path,"sha256":digest,"bytes":saved.size()}

func _print_shared_samples(snapshot:Dictionary)->void:
	var left:=HashingContext.new();var right:=HashingContext.new();var canonical:=HashingContext.new();left.start(HashingContext.HASH_SHA256);right.start(HashingContext.HASH_SHA256);canonical.start(HashingContext.HASH_SHA256);var mismatches:=0;var examples:Array=[]
	for iy in range(41):
		var y:float=-2.0+float(iy)*0.25
		for iz in range(13):
			var z:float=6.0+float(iz)*0.25;var a:float=Field.sample_density(SEED,Vector2i(0,0),Vector3(16,y,z),false);var b:float=Field.sample_density(SEED,Vector2i(1,0),Vector3(0,y,z),false);var c:float=Core.sample(Vector3(16,y,z),snapshot,SEED);var ab:=PackedFloat32Array([a]).to_byte_array();var bb:=PackedFloat32Array([b]).to_byte_array();var cb:=PackedFloat32Array([c]).to_byte_array();left.update(ab);right.update(bb);canonical.update(cb)
			if ab!=bb or ab!=cb:
				mismatches+=1
				if examples.size()<16:examples.append({"y":y,"z":z,"left":a,"right":b,"canonical":c})
	print("R95_SHARED533 "+JSON.stringify({"expected":533,"observed":533,"matches":533-mismatches,"mismatches":mismatches,"left_sha256":left.finish().hex_encode(),"right_sha256":right.finish().hex_encode(),"canonical_sha256":canonical.finish().hex_encode(),"first_mismatches":examples,"grid":{"x":16,"y_start":-2,"y_step":0.25,"y_count":41,"z_start":6,"z_step":0.25,"z_count":13},"scope":"independent region/local coordinate mapping oracle, not candidate chunk-call instrumentation"}))
