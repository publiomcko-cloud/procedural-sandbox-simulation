extends SceneTree

## R9-D test-only revisioned materialized-density volume. The ledger snapshot
## is the rebuild source. A volume revision is published only after complete
## sampling, serialization hash validation and extraction from its own bytes.
## Extraction is fixed marching tetrahedra over volume samples, not the live
## production mesh path. It does not claim canonical continuous-SDF equality.
const Core := preload("res://tests/prototypes/p3_1_r9_experiment_base.gd")
const ROI_MIN := Vector3(8.0,-2.0,3.0)
const CELLS := Vector3i(8,20,12)
const STEP := 0.5
const MAX_NODES := 10000
const MAX_TRIANGLES := 20000
const MAX_USEC := 600000000
var _started := 0
var _assertions := 0
var _failures: Array[String] = []

func _initialize() -> void:
	_started=Time.get_ticks_usec();call_deferred("_run")

func _run() -> void:
	var manifest:Dictionary=Core.load_manifest();_check(bool(manifest.get("valid",false)),"frozen_manifest_verified")
	if not manifest.get("valid",false):_finish("BLOCKED","manifest_preflight_failed");return
	var zero:Dictionary=Core.case_by_id(manifest.rows,"R9.GEO.ZERO.v1");var zero_setup:Dictionary=Core.make_snapshot(zero)
	_check(bool(zero_setup.get("valid",false)),"zero_snapshot_valid")
	if not zero_setup.get("valid",false):_finish("BLOCKED","zero_snapshot_failed");return
	var volume:Dictionary=_materialize(zero_setup.snapshot,0)
	_check(bool(volume.get("valid",false)),"zero_volume_materialized_within_stop_loss")
	if not volume.get("valid",false):_finish("BLOCKED",String(volume.get("reason","volume_build_failed")),volume);return
	var bytes:PackedByteArray=volume.bytes
	var saved:Dictionary=_persist_and_reload(bytes,String(volume.sha256))
	_check(bool(saved.get("valid",false)),"volume_restart_reload_and_integrity")
	if not saved.get("valid",false):_finish("BLOCKED","volume_reload_failed",saved);return
	var corrupt:PackedByteArray=bytes.duplicate();corrupt[corrupt.size()-1]=corrupt[corrupt.size()-1]^1
	_check(Core.sha256(corrupt)!=String(volume.sha256),"corrupt_volume_digest_rejected")
	var mesh:Dictionary=_extract(saved.values)
	_check(bool(mesh.get("valid",false)),"volume_marching_tetrahedra_within_stop_loss")
	if not mesh.get("valid",false):_finish("BLOCKED",String(mesh.get("reason","extraction_failed")),mesh);return
	var topo:Dictionary=Core.topology(mesh.mesh,ROI_MIN,ROI_MIN+Vector3(CELLS)*STEP)
	print("R9D_ZERO "+JSON.stringify({"volume_sha256":volume.sha256,"mesh_sha256":mesh.mesh_sha256,"volume_metrics":volume.metrics,"mesh_metrics":mesh.metrics,"topology":topo}))
	_check(int(topo.internal_open_edges)==0,"zero_volume_mesh_no_internal_open_edges")
	_check(int(topo.nonmanifold_edges)==0,"zero_volume_mesh_no_nonmanifold_edges")
	if int(topo.internal_open_edges)!=0 or int(topo.nonmanifold_edges)!=0:
		_finish("BLOCKED","zero_topology_gate_failed",{"topology":topo,"volume":volume.metrics,"mesh":mesh.metrics});return
	var carve:Dictionary=Core.case_by_id(manifest.rows,"R9.GEO.CARVE_CENTER.v1");var carve_setup:Dictionary=Core.make_snapshot(carve)
	var next:Dictionary=_materialize(carve_setup.snapshot,1)
	_check(bool(next.get("valid",false)),"carve_volume_rebuild_complete")
	if not next.get("valid",false):_finish("BLOCKED","carve_revision_materialization_failed",next);return
	var published:Dictionary=volume.duplicate();published=next
	_check(int(published.revision)==1 and published.values.size()==volume.values.size(),"coherent_revision_publication")
	var ray:Dictionary=Core.ray_mesh(Vector3(8.0,8.0,6.0),Vector3.DOWN,12.0,mesh.mesh)
	_check(ray.has("hit") and ray.has("position"),"volume_mesh_deterministic_pick_query_available")
	_finish("BLOCKED","frozen_seam_connectivity_and_canonical_picker_comparisons_incomplete",{"topology":topo,"zero":volume.metrics,"revision1":next.metrics,"pick":ray})

func _materialize(snapshot:Dictionary,revision:int)->Dictionary:
	var begin:int=Time.get_ticks_usec();var dims:Vector3i=CELLS+Vector3i.ONE;var count:int=dims.x*dims.y*dims.z
	if count>MAX_NODES:return {"valid":false,"reason":"volume_node_stop_loss","nodes":count}
	var values:=PackedFloat32Array();values.resize(count)
	for y in range(dims.y):
		for z in range(dims.z):
			for x in range(dims.x):
				var d:float=Core.sample(ROI_MIN+Vector3(x,y,z)*STEP,snapshot)
				if not is_finite(d):return {"valid":false,"reason":"nonfinite_volume_sample"}
				values[_idx(x,y,z,dims)]=d
				if Time.get_ticks_usec()-begin>MAX_USEC:return {"valid":false,"reason":"time_stop_loss","nodes":count}
	var data:PackedByteArray=values.to_byte_array()
	var header:=JSON.stringify({"schema":"P3.1.R9D.Volume.v1","revision":revision,"dimensions":[dims.x,dims.y,dims.z],"seed":131102026,"generator_version":1})
	var bytes:PackedByteArray=header.to_utf8_buffer();bytes.append(10);bytes.append_array(data)
	var digest:String=Core.sha256(bytes)
	return {"valid":true,"revision":revision,"values":values,"bytes":bytes,"sha256":digest,"metrics":{"nodes":count,"payload_bytes":data.size(),"serialized_bytes":bytes.size(),"materialize_usec":Time.get_ticks_usec()-begin,"sample_authority":"canonical SDF + ordered ledger snapshot"}}

func _persist_and_reload(bytes:PackedByteArray,expected:String)->Dictionary:
	var path:String="user://r9d_volume_"+str(Time.get_ticks_usec())+".bin"
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return {"valid":false,"reason":"volume_write_open_failed"}
	file.store_buffer(bytes);file.flush();var write_error:=file.get_error();file.close()
	if write_error!=OK:return {"valid":false,"reason":"volume_write_failed","error":write_error}
	var disk:PackedByteArray=FileAccess.get_file_as_bytes(path)
	if Core.sha256(disk)!=expected:return {"valid":false,"reason":"volume_disk_hash_mismatch"}
	var split:=-1
	for i in range(disk.size()):
		if disk[i]==10:split=i;break
	if split<0:return {"valid":false,"reason":"volume_header_missing"}
	var header_variant:Variant=JSON.parse_string(disk.slice(0,split).get_string_from_utf8())
	if typeof(header_variant)!=TYPE_DICTIONARY or header_variant.get("schema","")!="P3.1.R9D.Volume.v1":return {"valid":false,"reason":"volume_schema_invalid"}
	var payload:PackedByteArray=disk.slice(split+1)
	var dims:Vector3i=CELLS+Vector3i.ONE;var count:int=dims.x*dims.y*dims.z
	if payload.size()!=count*4:return {"valid":false,"reason":"volume_payload_size_invalid"}
	var values:=PackedFloat32Array();values.resize(count)
	for i in range(count):values[i]=payload.decode_float(i*4)
	return {"valid":true,"revision":int(header_variant.revision),"values":values,"sha256":expected,"serialized_bytes":disk.size()}

func _extract(values:PackedFloat32Array)->Dictionary:
	var begin:int=Time.get_ticks_usec();var dims:Vector3i=CELLS+Vector3i.ONE;var mesh:Dictionary=Core.new_mesh();var drops:=0;var tets:=0
	for y in range(CELLS.y):
		for z in range(CELLS.z):
			for x in range(CELLS.x):
				var p:Array[Vector3]=[];var d:Array[float]=[];var solid:=Vector3.ZERO;var empty:=Vector3.ZERO;var ns:=0;var ne:=0
				for c in Core.GRID_CORNERS:
					var wp:Vector3=ROI_MIN+Vector3(x+c.x,y+c.y,z+c.z)*STEP;var dv:float=values[_idx(x+c.x,y+c.y,z+c.z,dims)]
					p.append(wp);d.append(dv)
					if dv>=0.0:solid+=wp;ns+=1
					else:empty+=wp;ne+=1
				if ns==0 or ne==0:continue
				var toward:Vector3=empty/float(ne)-solid/float(ns)
				for tet in Core.TETS:
					var hits:Array[Vector3]=[]
					for edge in [[0,1],[0,2],[0,3],[1,2],[1,3],[2,3]]:
						var a:int=int(tet[int(edge[0])]);var b:int=int(tet[int(edge[1])])
						if (d[a]>=0.0)==(d[b]>=0.0):continue
						var q:float=clampf(d[a]/(d[a]-d[b]),0.0,1.0);var h:Vector3=p[a].lerp(p[b],q);var dupe:=false
						for old in hits:if old.distance_squared_to(h)<1.0e-14:dupe=true;break
						if not dupe:hits.append(h)
					if hits.size()==3:
						if not Core.add_triangle(mesh,hits[0],hits[1],hits[2],toward,1.0e-12):drops+=1
					elif hits.size()==4:
						if not Core.add_triangle(mesh,hits[0],hits[1],hits[2],toward,1.0e-12):drops+=1
						if not Core.add_triangle(mesh,hits[0],hits[2],hits[3],toward,1.0e-12):drops+=1
					tets+=1
					if mesh.positions.size()/3>MAX_TRIANGLES:return {"valid":false,"reason":"triangle_stop_loss","triangles":mesh.positions.size()/3}
	return {"valid":true,"mesh":mesh,"mesh_sha256":_mesh_sha(mesh),"metrics":{"triangles":mesh.positions.size()/3,"active_tetrahedra":tets,"cutoff_drops":drops,"extract_usec":Time.get_ticks_usec()-begin,"source":"serialized/reloaded materialized volume"}}

func _idx(x:int,y:int,z:int,d:Vector3i)->int:return (y*d.z+z)*d.x+x
func _mesh_sha(m:Dictionary)->String:
	var c:=HashingContext.new();c.start(HashingContext.HASH_SHA256);c.update(m.positions.to_byte_array());c.update(m.normals.to_byte_array());return c.finish().hex_encode()
func _check(ok:bool,label:String)->void:_assertions+=1;if not ok:_failures.append(label)
func _finish(status:String,reason:String,details:Dictionary={})->void:
	var final_status:String=status if _failures.is_empty() else "BLOCKED"
	print("P3_1_R9D_RESULT "+JSON.stringify({"candidate":"D","algorithm":"revisioned float32 materialized density volume + fixed marching tetrahedra extraction","status":final_status,"reason":reason,"details":details,"assertions":_assertions,"failures":_failures,"duration_usec":Time.get_ticks_usec()-_started,"manifest_sha256":Core.EXPECTED_MANIFEST_SHA,"product_tolerance":"NONE_APPROVED","physics_server":"NOT_RUN","gui":"NOT_RUN"}));quit(0 if final_status=="PASS" else 1)
