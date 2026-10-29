extends SceneTree

const Core := preload("res://tests/prototypes/p3_1_r9_2_diagnostic_base.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")
const CandidateA := preload("res://tests/prototypes/r9_5_source_snapshots/candidate_a.gd")
const CandidateC := preload("res://tests/prototypes/r9_5_source_snapshots/candidate_c.gd")
const CandidateD := preload("res://tests/prototypes/r9_5_source_snapshots/candidate_d.gd")
const MANIFEST_SHA := "1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972"
const SOURCE := {"A":"f0c93415dd56886a1c05ff2e6a1340e420f22c59", "C":"af4d6027d9d57c9f2b8023aa27b31d2dd2dcedf2", "D":"6ea04229b5ff06090f346c8749c1f5a53994227c"}
const SEED := 131102026
var cid := ""
var csha := ""
var run_id := ""
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	cid = OS.get_environment("R95_CANDIDATE_ID")
	csha = OS.get_environment("R95_CANDIDATE_SOURCE_SHA")
	run_id = OS.get_environment("R95_RUN_ID")
	var oracle_sha := OS.get_environment("R95_ORACLE_SHA")
	var manifest := Core.load_manifest()
	if not SOURCE.has(cid) or SOURCE[cid] != csha or oracle_sha.length() != 40 or not oracle_sha.is_valid_hex_number() or not manifest.get("valid", false) or manifest.get("sha256", "") != MANIFEST_SHA:
		print("R95_BLOCKED " + JSON.stringify({"candidate":cid,"candidate_sha":csha,"oracle_sha":oracle_sha,"manifest":manifest.get("reason","ok")})); quit(2); return
	var script: Script = CandidateA if cid == "A" else (CandidateC if cid == "C" else CandidateD)
	var candidate: RefCounted = script.new()
	var ray_row: Dictionary = Core.case_by_id(manifest.rows,"R9.2.RAY.CANONICAL_PICKER.v1")
	var setup: Dictionary = Core.make_snapshot(ray_row)
	candidate.call("configure_roi",ray_row.roi)
	var built: Dictionary = candidate.call("build",setup.snapshot,ray_row,{"id":"default","roi":ray_row.roi})
	if not built.get("valid",false): print("R95_BLOCKED " + JSON.stringify({"reason":"ray_mesh_build_failed","detail":built.get("reason","unknown")})); quit(2); return
	var rays: Array[Dictionary] = Core.ray_grid(ray_row.roi,ray_row.ray_grid)
	var classes := {}
	for i in range(rays.size()):
		var ray: Dictionary = rays[i]
		var exact: Dictionary = _analytic_roots(ray,int(ray_row.seed),setup.snapshot)
		var adaptive: Dictionary = _adaptive_roots(ray,setup.snapshot)
		var hits: Dictionary = _mesh_hits(ray,built.mesh)
		var first: Dictionary = exact.get("first",{})
		var lo: Vector3 = Core.world_min(ray_row.roi)
		var hi: Vector3 = lo + Vector3(Core.cell_counts(ray_row.roi))*Core.step(ray_row.roi)
		var inside := false
		if not first.is_empty():
			var p: Vector3 = first.position
			inside = p.x>=lo.x-1e-6 and p.x<=hi.x+1e-6 and p.y>=lo.y-1e-6 and p.y<=hi.y+1e-6 and p.z>=lo.z-1e-6 and p.z<=hi.z+1e-6
		var classification := "ANALYTIC_ADAPTIVE_AGREE"
		if not exact.valid or not adaptive.valid: classification="ROOT_ORACLE_INCOMPLETE"
		elif int(exact.root_count) != int(adaptive.root_count) or (not first.is_empty() and absf(float(adaptive.roots[0].distance)-float(first.distance))>5e-5):
			classification="ANALYTIC_ADAPTIVE_ROOT_MISMATCH"; failures += 1
		elif not inside: classification="FIRST_ROOT_OUTSIDE_CROPPED_MESH_ROI"
		elif bool(hits.hit)!=(not first.is_empty()): classification="IN_ROI_HIT_MISS"
		elif not first.is_empty() and absf(float(hits.distance)-float(first.distance))>0.01: classification="IN_ROI_POSITION"
		classes[classification]=int(classes.get(classification,0))+1
		print("R95_RAY " + JSON.stringify({"run_id":run_id,"candidate":cid,"source_sha":csha,"oracle_sha":oracle_sha,"ray_index":i,"ray":ray,"analytic":exact,"adaptive":adaptive,"mesh_two_sided":hits,"first_root_inside_roi":inside,"classification":classification}))
	print("R95_RAY_SUMMARY " + JSON.stringify({"candidate":cid,"source_sha":csha,"manifest_sha":MANIFEST_SHA,"ray_count":rays.size(),"classifications":classes,"candidate_mesh_sha256":built.get("mesh_sha256",""),"roi":ray_row.roi,"metrics":built.get("metrics",{})}))
	_print_shared_samples(setup.snapshot)
	_run_xplus(candidate,manifest)
	_run_frozen_controls(candidate,manifest)
	print("R95_COMPLETE " + JSON.stringify({"candidate":cid,"source_sha":csha,"oracle_sha":oracle_sha,"failure_count":failures,"status":"DIAGNOSTIC_COMPLETE_ONLY"})); quit(1 if failures>0 else 0)

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
	return {"valid":true,"roots":roots,"root_count":roots.size(),"unresolved_tangent_intervals":ctx.unresolved,"evaluations":ctx.evaluations,"distance_tolerance":1e-5,"bound":"1-Lipschitz interval exclusion; unresolved same-sign candidates remain explicit","method":"bounded adaptive subdivision plus bisection; not claimed complete for tangencies"}

func _f(t:float,ctx:Dictionary)->float:
	ctx.evaluations=int(ctx.evaluations)+1
	if int(ctx.evaluations)>50000:ctx.failure="evaluation_stop_loss";return NAN
	return Core.sample(ctx.o+ctx.d*t,ctx.snapshot,SEED)

func _visit(a:float,b:float,fa:float,fb:float,depth:int,ctx:Dictionary)->void:
	if not String(ctx.failure).is_empty():return
	var m:=(a+b)*0.5;var fm:=_f(m,ctx);if not is_finite(fm):ctx.failure="nonfinite_density";return
	var left_change:=(fa<0.0)!=(fm<0.0);var right_change:=(fm<0.0)!=(fb<0.0);var width:=b-a
	if width<=1e-5 or depth>=24:
		if left_change:_bisect(a,m,fa,ctx)
		if right_change:_bisect(m,b,fm,ctx)
		if not left_change and not right_change and absf(fm)<=width*0.5+1e-7:ctx.unresolved.append({"lo":a,"hi":b,"sample_abs":absf(fm)})
		return
	if left_change or absf(fm)<=(m-a)*0.5+1e-7:_visit(a,m,fa,fm,depth+1,ctx)
	if right_change or absf(fm)<=(b-m)*0.5+1e-7:_visit(m,b,fm,fb,depth+1,ctx)

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

func _run_xplus(candidate:RefCounted,manifest:Dictionary)->void:
	for id in ["R9.2.SEAM.XPLUS_EQUAL.v1","R9.2.SEAM.XPLUS_MIXED_LOD.v1","R9.2.HIST.XPLUS_DEFECT.v1"]:
		var row:Dictionary=Core.case_by_id(manifest.rows,id);if row.is_empty():continue
		var setup:Dictionary=Core.make_snapshot(row);candidate.call("configure_roi",row.roi);var full:Dictionary=candidate.call("build",setup.snapshot,row,{"id":"default","roi":row.roi})
		var lo:Vector3=Core.world_min(row.roi);var hi:=lo+Vector3(Core.cell_counts(row.roi))*Core.step(row.roi)
		print("R95_XPLUS "+JSON.stringify({"scenario_id":id,"candidate":cid,"source_sha":csha,"scope":"single-ROI historical proxy, not chunk join","mesh_sha256":full.get("mesh_sha256",""),"metrics":full.get("metrics",{}),"exact_topology":_exact_topology(full.get("mesh",Core.new_mesh()),lo,hi) if full.get("valid",false) else {}, "valid":full.get("valid",false)}))
		var mixed:=id.ends_with("MIXED_LOD.v1");var left_roi:Dictionary={"id":"L","min":[15.0,1.0,6.0],"cells":[2,4,4] if mixed else [4,8,8],"step":0.5 if mixed else 0.25};var right_roi:Dictionary={"id":"R","min":[16.0,1.0,6.0],"cells":[4,8,8],"step":0.25}
		candidate.call("configure_roi",left_roi);var left:Dictionary=candidate.call("build",setup.snapshot,row,{"id":"L","roi":left_roi});candidate.call("configure_roi",right_roi);var right:Dictionary=candidate.call("build",setup.snapshot,row,{"id":"R","roi":right_roi})
		if not left.get("valid",false) or not right.get("valid",false):print("R95_SPLIT_BLOCKED "+JSON.stringify({"id":id,"left":left.get("reason","ok"),"right":right.get("reason","ok")}));continue
		var ls:=_boundary_segments(left.mesh,16.0);var rs:=_boundary_segments(right.mesh,16.0);var delta:=_dict_delta(ls,rs);var combined:=_combine(left.mesh,right.mesh)
		var oracle_l:=_face_oracle(setup.snapshot,left_roi,16.0,int(row.seed));var oracle_r:=_face_oracle(setup.snapshot,right_roi,16.0,int(row.seed))
		var ldiff:=_dict_delta(ls,oracle_l.segments);var rdiff:=_dict_delta(rs,oracle_r.segments)
		print("R95_SPLIT_PAIR "+JSON.stringify({"scenario_id":id,"candidate":cid,"lod_pair":[1,0] if mixed else [0,0],"plane_x":16,"left_sha":left.get("mesh_sha256",""),"right_sha":right.get("mesh_sha256",""),"left_segments":ls.size(),"right_segments":rs.size(),"left_only":delta.left.size(),"right_only":delta.right.size(),"left_only_first_24":delta.left.slice(0,24),"right_only_first_24":delta.right.slice(0,24),"seam_incidence":_interface_incidence(combined,16.0),"combined_topology":_exact_topology(combined,Vector3(15,1,6),Vector3(17,3,8)),"independent_face_oracle":{"left_expected":oracle_l.segments.size(),"left_missing":ldiff.right.size(),"left_extra":ldiff.left.size(),"left_missing_first_16":ldiff.right.slice(0,16),"left_extra_first_16":ldiff.left.slice(0,16),"right_expected":oracle_r.segments.size(),"right_missing":rdiff.right.size(),"right_extra":rdiff.left.size(),"right_missing_first_16":rdiff.right.slice(0,16),"right_extra_first_16":rdiff.left.slice(0,16),"definition":"canonical SDF over an independently fixed 2D face triangulation; edge roots bisected on the continuous field"},"scope":"candidate-generated separate ROIs; not production chunk acceptance"}))

func _face_oracle(snapshot:Dictionary,roi:Dictionary,plane:float,seed:int)->Dictionary:
	var lo:Vector3=Core.world_min(roi);var cells:Vector3i=Core.cell_counts(roi);var h:float=Core.step(roi);var segments:Dictionary={}
	for y in range(cells.y):
		for z in range(cells.z):
			var p00:=Vector3(plane,lo.y+float(y)*h,lo.z+float(z)*h);var p10:=p00+Vector3(0,h,0);var p11:=p00+Vector3(0,h,h);var p01:=p00+Vector3(0,0,h)
			for tri in [[p00,p10,p11],[p00,p11,p01]]:
				var hits:Array[Vector3]=[]
				for e in [Vector2i(0,1),Vector2i(1,2),Vector2i(2,0)]:
					var a:Vector3=tri[e.x];var b:Vector3=tri[e.y];var da:float=Core.sample(a,snapshot,seed);var db:float=Core.sample(b,snapshot,seed)
					if da==0.0:hits.append(a)
					elif db==0.0:hits.append(b)
					elif (da<0.0)!=(db<0.0):
						var low:=0.0;var high:=1.0;var lv:=da
						for _i in range(32):
							var mid:float=(low+high)*0.5;var dm:float=Core.sample(a.lerp(b,mid),snapshot,seed)
							if dm==0.0:low=mid;high=mid;break
							if (dm<0.0)==(lv<0.0):low=mid;lv=dm
							else:high=mid
						hits.append(a.lerp(b,(low+high)*0.5))
				var unique:Array[Vector3]=[]
				for p in hits:
					var duplicate:=false
					for q in unique:
						if p.distance_squared_to(q)<1e-12:duplicate=true;break
					if not duplicate:unique.append(p)
				if unique.size()==2:
					var ka:=Core._point_key(unique[0]);var kb:=Core._point_key(unique[1]);segments[ka+"|"+kb if ka<kb else kb+"|"+ka]=true
	return {"segments":segments}

func _boundary_segments(mesh:Dictionary,x:float)->Dictionary:
	var out:Dictionary={};var p:PackedVector3Array=mesh.get("positions",PackedVector3Array())
	for i in range(0,p.size(),3):
		for e in [Vector2i(0,1),Vector2i(1,2),Vector2i(2,0)]:
			var a:Vector3=p[i+e.x];var b:Vector3=p[i+e.y]
			if absf(a.x-x)>1e-5 or absf(b.x-x)>1e-5:continue
			var ka:=Core._point_key(a);var kb:=Core._point_key(b);out[ka+"|"+kb if ka<kb else kb+"|"+ka]=true
	return out

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

func _run_frozen_controls(candidate:RefCounted,manifest:Dictionary)->void:
	for id in ["R9.2.HIST.XMINUS_DISPLACEMENT.v1","R9.2.HIST.TRIANGLE3103.v1"]:
		var row:Dictionary=Core.case_by_id(manifest.rows,id);var setup:Dictionary=Core.make_snapshot(row);candidate.call("configure_roi",row.roi);var built:Dictionary=candidate.call("build",setup.snapshot,row,{"id":"default","roi":row.roi})
		if id.contains("TRIANGLE3103"):
			var corners:Array=[];var lo:Vector3=Core.world_min(row.roi)
			for c in Core.GRID_CORNERS:
				var p:Vector3=lo+Vector3(c)*Core.step(row.roi);var d:float=Core.sample(p,setup.snapshot,int(row.seed));corners.append({"point":p,"density":d,"binary32":PackedFloat32Array([d]).to_byte_array().hex_encode()})
			print("R95_TRIANGLE3103 "+JSON.stringify({"scenario_id":id,"candidate":cid,"source_sha":csha,"frozen_triangle_index":row.triangle_index,"local_cell_triangle_count":built.get("mesh",{}).get("positions",PackedVector3Array()).size()/3,"corners":corners,"global_index_equivalence":"NOT_CLAIMED; one-cell ROI is not historical full-mesh ordering","cutoff":row.squared_cross_cutoff}))
		else:
			var rd:Dictionary=row.ray;var ray:Dictionary={"origin":Vector3(rd.origin[0],rd.origin[1],rd.origin[2]),"direction":Vector3(rd.direction[0],rd.direction[1],rd.direction[2]),"length":rd.length};var roots:=_adaptive_roots(ray,setup.snapshot);var hits:=_mesh_hits(ray,built.mesh);var lo:Vector3=Core.world_min(row.roi);var hi:=lo+Vector3(Core.cell_counts(row.roi))*Core.step(row.roi)
			print("R95_XMINUS "+JSON.stringify({"scenario_id":id,"candidate":cid,"source_sha":csha,"metrics":built.get("metrics",{}),"adaptive_roots":roots,"mesh_hits":hits,"roi_min":lo,"roi_max":hi,"historical_root_y":row.historical_continuous_root_y,"first_root_inside_roi":float(row.historical_continuous_root_y)>=lo.y and float(row.historical_continuous_root_y)<=hi.y}))

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
