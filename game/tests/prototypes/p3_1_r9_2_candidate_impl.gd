extends RefCounted

## R9-D test-only revisioned materialized-density volume. The ledger snapshot
## is the rebuild source. A volume revision is published only after complete
## sampling, serialization hash validation and extraction from its own bytes.
## Extraction is fixed marching tetrahedra over volume samples, not the live
## production mesh path. It does not claim canonical continuous-SDF equality.
const Core := preload("res://tests/prototypes/p3_1_r9_2_diagnostic_base.gd")
const IndependentExtractor := preload("res://tests/prototypes/p3_1_r9_3d_reference_extractor.gd")
var ROI_MIN: Vector3 = Vector3(8.0,-2.0,3.0)
var CELLS: Vector3i = Vector3i(8,20,12)
var STEP: float = 0.5
const MAX_NODES := 10000
const MAX_TRIANGLES := 20000
const MAX_USEC := 60000000
var _started := 0
var _assertions := 0
var _failures: Array[String] = []

func configure_roi(roi: Dictionary) -> void:
	ROI_MIN = Core.world_min(roi)
	CELLS = Core.cell_counts(roi)
	STEP = Core.step(roi)

func build(snapshot: Dictionary, _row: Dictionary, _variant: Dictionary) -> Dictionary:
	var volume: Dictionary = _materialize(snapshot, int(snapshot.get("revision", 0)))
	if not volume.get("valid", false):
		return volume
	var saved: Dictionary = _persist_and_reload(volume.bytes, String(volume.sha256))
	if not saved.get("valid", false):
		return saved
	var extracted: Dictionary = _extract(saved.values)
	if not extracted.get("valid", false):
		return extracted
	var dims: Vector3i = CELLS + Vector3i.ONE
	var reference: Dictionary = IndependentExtractor.new().extract(saved.values, dims, CELLS, ROI_MIN, STEP)
	if not reference.get("valid", false):
		return {"valid": false, "reason": "independent_reference_extractor_failed", "detail": reference}
	var bounds_max: Vector3 = ROI_MIN + Vector3(CELLS) * STEP
	var reference_topology: Dictionary = Core.topology(reference.mesh, ROI_MIN, bounds_max)
	return {"valid": true, "mesh": extracted.mesh, "mesh_sha256": extracted.mesh_sha256,
		"metrics": {"volume": volume.metrics, "extract": extracted.metrics,
			"independent_reference": reference.metrics,
			"candidate_topology": Core.topology(extracted.mesh, ROI_MIN, bounds_max),
			"reference_topology": reference_topology,
			"extractor_mesh_hashes_equal": extracted.mesh_sha256 == reference.mesh_sha256,
			"reference_extractor_identity": "R9.3-D-test-only-angle-ordered-tetra-v1"}, "volume": volume}

func corruption_reload_probe(snapshot: Dictionary) -> Dictionary:
	var volume: Dictionary = _materialize(snapshot, int(snapshot.get("revision", 0)))
	if not volume.get("valid", false):
		return {"valid": false, "reason": "pre_corruption_materialization_failed", "detail": volume}
	var corrupt: PackedByteArray = volume.bytes.duplicate()
	if corrupt.is_empty():
		return {"valid": false, "reason": "serialized_volume_empty"}
	corrupt[corrupt.size() - 1] = corrupt[corrupt.size() - 1] ^ 1
	var reload: Dictionary = _persist_and_reload(corrupt, String(volume.sha256))
	return {"valid": not reload.get("valid", false), "rejected": not reload.get("valid", false),
		"reason": reload.get("reason", "unexpected_corrupt_acceptance"), "expected_sha256": volume.sha256,
		"corrupt_sha256": Core.sha256(corrupt), "reloaded_corrupt_bytes_from_disk": true}
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
	var position_bytes:PackedByteArray=m.positions.to_byte_array()
	var normal_bytes:PackedByteArray=m.normals.to_byte_array()
	var c:=HashingContext.new()
	c.start(HashingContext.HASH_SHA256)
	# Prefix lengths so empty arrays remain distinguishable and never call update with zero bytes.
	c.update(("%d:%d:" % [position_bytes.size(),normal_bytes.size()]).to_utf8_buffer())
	if not position_bytes.is_empty():c.update(position_bytes)
	if not normal_bytes.is_empty():c.update(normal_bytes)
	return c.finish().hex_encode()
