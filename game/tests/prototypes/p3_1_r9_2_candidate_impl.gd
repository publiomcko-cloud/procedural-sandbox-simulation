extends RefCounted

## R9-D test-only revisioned materialized-density volume. The ledger snapshot
## is the rebuild source. A volume revision is published only after complete
## sampling, serialization hash validation and extraction from its own bytes.
## Extraction is fixed marching tetrahedra over volume samples, not the live
## production mesh path. It does not claim canonical continuous-SDF equality.
const Core := preload("res://tests/prototypes/p3_1_r9_2_diagnostic_base.gd")
const IndependentExtractor := preload("res://tests/prototypes/p3_1_r9_3d_reference_extractor.gd")
const Topology := preload("res://tests/prototypes/p3_1_r9_6_surface_topology.gd")
var ROI_MIN: Vector3 = Vector3(8.0,-2.0,3.0)
var CELLS: Vector3i = Vector3i(8,20,12)
var STEP: float = 0.5
const MAX_NODES := 10000
const MAX_TRIANGLES := 20000
const MAX_USEC := 60000000
const D2_REFINE_TETS := {"60,8,25":[0,1,2,5],"61,8,25":[4],"62,9,24":[2,3],"66,7,29":[4]}
const D2_TARGET_SCENARIOS := ["R9.2.SEAM.XPLUS_EQUAL.v1","R9.2.SEAM.XPLUS_MIXED_LOD.v1","R9.2.HIST.XPLUS_DEFECT.v1"]
var _started := 0
var _assertions := 0
var _failures: Array[String] = []
var _d2_enabled: bool = false
var _d2_scenario_id: String = ""
var _d2_materialized_values_sha256: String = ""
var _d2_materialized_values_sha256_after: String = ""
var _d2_refined_cells: Dictionary = {}
var _d2_recorded_roots: Dictionary = {}
var _d2_centroid_sample_evidence: Array[Dictionary] = []
var _d2_new_vertex_evidence: Array[Dictionary] = []
var _d2_additional_volume_derived_samples: int = 0
var _d2_new_surface_roots: int = 0
var _d2_parent_tetrahedra_refined: int = 0
var _d2_child_tetrahedra_processed: int = 0
var _d2_refined_patch_emitted_triangles: int = 0

func configure_roi(roi: Dictionary) -> void:
	ROI_MIN = Core.world_min(roi)
	CELLS = Core.cell_counts(roi)
	STEP = Core.step(roi)

func build(snapshot: Dictionary, row: Dictionary, _variant: Dictionary) -> Dictionary:
	var scenario_id: String=String(row.get("scenario_id",""))
	_d2_scenario_id=scenario_id
	_d2_enabled=OS.get_environment("R96R1_ATTEMPT")=="ATTEMPT_D2" and D2_TARGET_SCENARIOS.has(scenario_id) and absf(ROI_MIN.x-15.0)<=1.0e-9 and absf(ROI_MIN.y-1.0)<=1.0e-9 and absf(ROI_MIN.z-6.0)<=1.0e-9 and absf(STEP-0.25)<=1.0e-9
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
		"topology": extracted.get("topology",{}),
		"metrics": {"volume": volume.metrics, "extract": extracted.metrics,
			"materialized_volume_sha256":String(volume.sha256),"persisted_reloaded_volume_sha256":String(saved.sha256),
			"materialized_volume_identity_preserved":String(volume.sha256)==String(saved.sha256) and Core.sha256(volume.bytes)==String(volume.sha256),
			"d2_full_volume_hash_before_materialization_extract":String(volume.sha256),"d2_full_volume_hash_after_persist_reload":String(saved.sha256),
			"d2_payload_hash_before_extract":String(volume.metrics.get("payload_sha256","")),"d2_payload_hash_after_extract":Core.sha256(saved.values.to_byte_array()),
			"d2_payload_identity_preserved":String(volume.metrics.get("payload_sha256",""))==Core.sha256(saved.values.to_byte_array()),
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
	return {"valid":true,"revision":revision,"values":values,"bytes":bytes,"sha256":digest,"metrics":{"nodes":count,"payload_bytes":data.size(),"payload_sha256":Core.sha256(data),"serialized_bytes":bytes.size(),"materialize_usec":Time.get_ticks_usec()-begin,"sample_authority":"canonical SDF + ordered ledger snapshot"}}

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
	return {"valid":true,"revision":int(header_variant.revision),"values":values,"sha256":expected,"payload_sha256":Core.sha256(payload),"serialized_bytes":disk.size()}

func _extract(values:PackedFloat32Array)->Dictionary:
	var begin:int=Time.get_ticks_usec();var dims:Vector3i=CELLS+Vector3i.ONE;var mesh:Dictionary=Core.new_mesh();var drops:=0;var tets:=0
	_d2_materialized_values_sha256=Core.sha256(values.to_byte_array())
	var root_cache:Dictionary={};var root_reuses:=0;var drops_three_point:=0;var drops_four_point:=0;var min_dropped_cross_squared:=INF
	_d2_refined_cells.clear();_d2_recorded_roots.clear();_d2_centroid_sample_evidence.clear();_d2_new_vertex_evidence.clear();_d2_additional_volume_derived_samples=0;_d2_new_surface_roots=0;_d2_parent_tetrahedra_refined=0;_d2_child_tetrahedra_processed=0;_d2_refined_patch_emitted_triangles=0
	var topology:RefCounted=Topology.new()
	var lattice_origin:=Vector3i(roundi(ROI_MIN.x/STEP),roundi(ROI_MIN.y/STEP),roundi(ROI_MIN.z/STEP))
	for y in range(CELLS.y):
		for z in range(CELLS.z):
			for x in range(CELLS.x):
				var p:Array[Vector3]=[];var d:Array[float]=[];var local_nodes:Array[Vector3i]=[];var solid:=Vector3.ZERO;var empty:=Vector3.ZERO;var ns:=0;var ne:=0
				for c in Core.GRID_CORNERS:
					var wp:Vector3=ROI_MIN+Vector3(x+c.x,y+c.y,z+c.z)*STEP;var dv:float=values[_idx(x+c.x,y+c.y,z+c.z,dims)]
					p.append(wp);d.append(dv)
					local_nodes.append(Vector3i(x,y,z)+c)
					if dv>=0.0:solid+=wp;ns+=1
					else:empty+=wp;ne+=1
				if ns==0 or ne==0:continue
				var toward:Vector3=empty/float(ne)-solid/float(ns)
				var cell_id := lattice_origin + Vector3i(x,y,z)
				for tet_index in range(Core.TETS.size()):
					var tet: Array = Core.TETS[tet_index]
					if _d2_enabled and _d2_tet_selected(cell_id,tet_index) and _tet_has_crossing(tet,d):
						var d2_result:Dictionary=_extract_d2_parent_tet(tet,p,d,local_nodes,cell_id,tet_index,values,dims,mesh,topology,root_cache,lattice_origin)
						if not bool(d2_result.get("valid",false)):return {"valid":false,"reason":"d2_volume_subdivision_failed","detail":d2_result,"cell":[cell_id.x,cell_id.y,cell_id.z],"tetrahedron":tet_index}
						drops+=int(d2_result.get("drops",0));root_reuses+=int(d2_result.get("root_reuses",0));drops_three_point+=int(d2_result.get("drops_three_point",0));drops_four_point+=int(d2_result.get("drops_four_point",0))
						if float(d2_result.get("minimum_dropped_cross_squared",INF))<INF:min_dropped_cross_squared=minf(min_dropped_cross_squared,float(d2_result.minimum_dropped_cross_squared))
						tets+=1
						if mesh.positions.size()/3>MAX_TRIANGLES:return {"valid":false,"reason":"triangle_stop_loss","triangles":mesh.positions.size()/3}
						continue
					var hits:Array[Vector3]=[];var hit_identities:Dictionary={};var hit_root_ids:Array[String]=[]
					for edge in [[0,1],[0,2],[0,3],[1,2],[1,3],[2,3]]:
						var a:int=int(tet[int(edge[0])]);var b:int=int(tet[int(edge[1])])
						if (d[a]>=0.0)==(d[b]>=0.0):continue
						var node_a:Vector3i=Vector3i(x,y,z)+Core.GRID_CORNERS[a]
						var node_b:Vector3i=Vector3i(x,y,z)+Core.GRID_CORNERS[b]
						var root:Dictionary=_canonical_volume_root(root_cache,node_a,node_b,d[a],d[b],p[a],p[b])
						if not root.get("valid",false):return {"valid":false,"reason":"canonical_volume_root_invalid","cell":[x,y,z]}
						if bool(root.get("reused",false)):root_reuses+=1
						var h:Vector3=root.point;var identity:String=String(root.get("root_identity",root.get("edge_key","")))
						if identity.is_empty():return {"valid":false,"reason":"canonical_root_identity_missing","cell":[x,y,z]}
						if not hit_identities.has(identity):hit_identities[identity]=true;hits.append(h);hit_root_ids.append(identity)
					if hits.size()>=3:
						var tet_toward:Vector3=_tetra_toward_empty(p,d,tet)
						var ordered:Array[Vector3]=_order_polygon(hits,tet_toward)
						if ordered.size()!=hits.size():return {"valid":false,"reason":"tetra_intersection_order_failed","cell":[x,y,z],"hit_count":hits.size()}
						var ordered_root_ids:Array[String]=_order_root_ids(ordered,hits,hit_root_ids)
						if ordered_root_ids.size()!=ordered.size():return {"valid":false,"reason":"tetra_root_identity_order_failed","cell":[x,y,z],"hit_count":hits.size()}
						for fan in range(1,ordered.size()-1):
							var points: Array = [ordered[0],ordered[fan],ordered[fan+1]]
							var triangle_roots:Array[String]=[ordered_root_ids[0],ordered_root_ids[fan],ordered_root_ids[fan+1]]
							var triangle_id: String = "%d,%d,%d|tet:%d|fan:%d" % [cell_id.x,cell_id.y,cell_id.z,tet_index,fan]
							var registered:Dictionary=_register_required_triangle(topology,triangle_id,triangle_roots,points,cell_id,tet_index)
							if not bool(registered.get("valid",false)):return {"valid":false,"reason":"topology_triangle_registration_failed","detail":registered,"cell":[x,y,z],"tetrahedron":tet_index}
							var triangle_emitted:bool=Core.add_triangle(mesh,ordered[0],ordered[fan],ordered[fan+1],tet_toward,1.0e-12)
							var marked:Dictionary=_mark_triangle(topology,triangle_id,triangle_emitted,points,"below_frozen_cross_squared_cutoff")
							if not bool(marked.get("valid",false)):return {"valid":false,"reason":"topology_triangle_realization_failed","detail":marked,"cell":[x,y,z],"tetrahedron":tet_index}
							if not triangle_emitted:
								drops+=1
								if hits.size()==3:drops_three_point+=1
								else:drops_four_point+=1
								var dropped_cross:Vector3=(ordered[fan]-ordered[0]).cross(ordered[fan+1]-ordered[0])
								min_dropped_cross_squared=minf(min_dropped_cross_squared,dropped_cross.length_squared())
					tets+=1
					if mesh.positions.size()/3>MAX_TRIANGLES:return {"valid":false,"reason":"triangle_stop_loss","triangles":mesh.positions.size()/3}
	var topology_report:Dictionary=topology.report(ROI_MIN,ROI_MIN+Vector3(CELLS)*STEP)
	if not bool(topology_report.get("valid",false)):return {"valid":false,"reason":"topology_ledger_incomplete","topology":topology_report}
	if int(topology_report.get("emitted_triangle_count",-1))!=int(mesh.positions.size()/3):return {"valid":false,"reason":"topology_geometry_count_mismatch","topology_emitted":topology_report.get("emitted_triangle_count"),"mesh_triangles":mesh.positions.size()/3,"topology":topology_report}
	_d2_materialized_values_sha256_after=Core.sha256(values.to_byte_array())
	var refined_cell_keys:Array[String]=[]
	for raw_cell_key in _d2_refined_cells.keys():refined_cell_keys.append(String(raw_cell_key))
	refined_cell_keys.sort()
	return {"valid":true,"mesh":mesh,"mesh_sha256":_mesh_sha(mesh),"topology":topology_report,"metrics":{"triangles":mesh.positions.size()/3,"active_tetrahedra":tets,"cutoff_drops":drops,"drops_from_three_root_polygons":drops_three_point,"drops_from_four_root_polygons":drops_four_point,"minimum_dropped_cross_squared":min_dropped_cross_squared if is_finite(min_dropped_cross_squared) else 0.0,"unique_lattice_roots":root_cache.size(),"cached_root_reuses":root_reuses,"extract_usec":Time.get_ticks_usec()-begin,"source":"serialized/reloaded materialized volume with canonical lattice-edge root cache",
		"d2_enabled":_d2_enabled,"d2_refinement_source":"exact materialized float32 volume; centroid density is fixed-order barycentric interpolation of four stored float32 tetrahedron samples; no canonical SDF resampling",
		"d2_materialized_values_sha256_before_extract":_d2_materialized_values_sha256,"d2_materialized_values_sha256_after_extract":_d2_materialized_values_sha256_after,"d2_materialized_values_identity_preserved":_d2_materialized_values_sha256==_d2_materialized_values_sha256_after,
		"d2_refine_tetrahedra_contract":D2_REFINE_TETS,"d2_refined_cells":refined_cell_keys,"d2_refined_cell_count":_d2_refined_cells.size(),
		"d2_parent_tetrahedra_refined":_d2_parent_tetrahedra_refined,"d2_child_tetrahedra_processed":_d2_child_tetrahedra_processed,
		"d2_additional_volume_derived_samples":_d2_additional_volume_derived_samples,"d2_canonical_sdf_probe_samples":0,"d2_new_surface_roots":_d2_new_surface_roots,"d2_max_construction_displacement":0.0,
		"d2_refined_patch_emitted_triangles":_d2_refined_patch_emitted_triangles,"d2_centroid_sample_evidence":_d2_centroid_sample_evidence,"d2_new_vertex_evidence":_d2_new_vertex_evidence}}

func _d2_tet_selected(global_cell:Vector3i,tet_index:int)->bool:
	if not D2_TARGET_SCENARIOS.has(_d2_scenario_id):return false
	var selected:Array=D2_REFINE_TETS.get(_cell_key(global_cell),[])
	return selected.has(tet_index)

func _tet_has_crossing(tet:Array,values:Array[float])->bool:
	var solid:=false;var empty:=false
	for corner in tet:
		if values[int(corner)]>=0.0:solid=true
		else:empty=true
	return solid and empty

func _extract_d2_parent_tet(tet:Array,parent_points:Array[Vector3],parent_values:Array[float],parent_nodes:Array[Vector3i],global_cell:Vector3i,parent_tet_index:int,materialized_values:PackedFloat32Array,dims:Vector3i,mesh:Dictionary,topology:RefCounted,root_cache:Dictionary,lattice_origin:Vector3i)->Dictionary:
	var source_points:Array[Vector3]=[];var source_values:Array[float]=[];var source_ids:Array[String]=[];var source_nodes:Array[Vector3i]=[]
	for corner_variant in tet:
		var corner:int=int(corner_variant);var local_node:Vector3i=parent_nodes[corner];var global_node:=lattice_origin+local_node
		source_points.append(parent_points[corner]);source_values.append(parent_values[corner]);source_nodes.append(local_node);source_ids.append("grid-node|"+_lattice_key(global_node))
	# The center scalar is a fixed-order barycentric average of the exact four
	# binary32 samples already read from the serialized and reloaded volume.
	var center_value:float=(((source_values[0]+source_values[1])+source_values[2])+source_values[3])*0.25
	if not is_finite(center_value):return {"valid":false,"reason":"nonfinite_volume_barycentric_center"}
	var center_point:Vector3=(source_points[0]+source_points[1]+source_points[2]+source_points[3])*0.25
	var center_identity:String="d2-centroid|"+_lattice_key(global_cell)+"|tet="+str(parent_tet_index)
	var source_hex:Array[String]=[]
	for source_value in source_values:source_hex.append(PackedFloat32Array([source_value]).to_byte_array().hex_encode())
	_d2_centroid_sample_evidence.append({"source_global_cell":[global_cell.x,global_cell.y,global_cell.z],"parent_tetrahedron":parent_tet_index,"parent_grid_node_identities":source_ids,"source_density_values":source_values,"source_density_binary32_hex":source_hex,"volume_payload_sha256":_d2_materialized_values_sha256,"centroid_world_position":[center_point.x,center_point.y,center_point.z],"centroid_density_fixed_order":"(((d0+d1)+d2)+d3)*0.25","centroid_density":center_value,"canonical_sdf_resampling":false})
	var center_node:Vector3i=Vector3i.ZERO
	var child_points:Array[Vector3]=[center_point]
	var child_values:Array[float]=[center_value]
	var child_ids:Array[String]=[center_identity]
	var child_nodes:Array[Vector3i]=[center_node]
	for i in range(4):child_points.append(source_points[i]);child_values.append(source_values[i]);child_ids.append(source_ids[i]);child_nodes.append(source_nodes[i])
	var child_tets:Array[Array]=[[0,1,2,3],[0,1,2,4],[0,1,3,4],[0,2,3,4]]
	var aggregate:Dictionary={"valid":true,"drops":0,"root_reuses":0,"drops_three_point":0,"drops_four_point":0,"minimum_dropped_cross_squared":INF,"children":0,"emitted_triangles":0}
	var initial_triangles:int=mesh.positions.size()/3
	_d2_refined_cells[_cell_key(global_cell)]=true;_d2_parent_tetrahedra_refined+=1;_d2_additional_volume_derived_samples+=1
	if center_value==0.0:_d2_record_centroid_zero("node|"+_world_point_key(center_point),center_point,global_cell,parent_tet_index,source_values,materialized_values,dims)
	for child_index in range(child_tets.size()):
		var child:Array=child_tets[child_index]
		var result:Dictionary=_extract_volume_tetra(child,child_points,child_values,child_ids,child_nodes,global_cell,parent_tet_index,child_index,mesh,topology,root_cache)
		if not bool(result.get("valid",false)):return result
		aggregate.drops+=int(result.get("drops",0));aggregate.root_reuses+=int(result.get("root_reuses",0));aggregate.drops_three_point+=int(result.get("drops_three_point",0));aggregate.drops_four_point+=int(result.get("drops_four_point",0));aggregate.children+=1
		if float(result.get("minimum_dropped_cross_squared",INF))<INF:aggregate.minimum_dropped_cross_squared=minf(float(aggregate.minimum_dropped_cross_squared),float(result.minimum_dropped_cross_squared))
		_d2_child_tetrahedra_processed+=1
	_d2_refined_patch_emitted_triangles+=mesh.positions.size()/3-initial_triangles
	aggregate.emitted_triangles=mesh.positions.size()/3-initial_triangles
	return aggregate

func _extract_volume_tetra(tet:Array,points:Array[Vector3],values:Array[float],point_ids:Array[String],point_nodes:Array[Vector3i],global_cell:Vector3i,parent_tet_index:int,child_tet_index:int,mesh:Dictionary,topology:RefCounted,root_cache:Dictionary)->Dictionary:
	var hits:Array[Vector3]=[];var hit_identities:Dictionary={};var hit_root_ids:Array[String]=[];var root_reuses:=0
	for edge in [[0,1],[0,2],[0,3],[1,2],[1,3],[2,3]]:
		var a:int=int(tet[int(edge[0])]);var b:int=int(tet[int(edge[1])]);var da:float=values[a];var db:float=values[b]
		if (da>=0.0)==(db>=0.0):continue
		var pa:Vector3=points[a];var pb:Vector3=points[b];var id_a:String=point_ids[a];var id_b:String=point_ids[b];var root:Dictionary
		if id_a.begins_with("d2-centroid|") or id_b.begins_with("d2-centroid|"):
			root=_d2_volume_root(pa,pb,da,db,id_a,id_b,global_cell,parent_tet_index,root_cache)
		else:
			root=_canonical_volume_root(root_cache,point_nodes[a],point_nodes[b],da,db,pa,pb)
		if not bool(root.get("valid",false)):return {"valid":false,"reason":"invalid_volume_edge_root","edge":[id_a,id_b],"detail":root}
		if bool(root.get("reused",false)):root_reuses+=1
		var identity:String=str(root.get("root_identity",""));var point:Vector3=root.point
		if identity.is_empty() or not point.is_finite():return {"valid":false,"reason":"volume_edge_root_identity_or_point_invalid","edge":[id_a,id_b]}
		if not hit_identities.has(identity):hit_identities[identity]=true;hits.append(point);hit_root_ids.append(identity)
	if hits.size()<3:return {"valid":true,"drops":0,"root_reuses":root_reuses,"drops_three_point":0,"drops_four_point":0,"minimum_dropped_cross_squared":INF}
	var toward:Vector3=_tetra_toward_empty(points,values,tet)
	var ordered:Array[Vector3]=_order_polygon(hits,toward)
	if ordered.size()!=hits.size():return {"valid":false,"reason":"d2_child_intersection_order_failed","global_cell":_lattice_key(global_cell),"parent_tetrahedron":parent_tet_index,"child_tetrahedron":child_tet_index}
	var ordered_root_ids:Array[String]=_order_root_ids(ordered,hits,hit_root_ids)
	if ordered_root_ids.size()!=ordered.size():return {"valid":false,"reason":"d2_child_root_identity_order_failed"}
	var local_drops:=0;var local_three:=0;var local_four:=0;var local_min:=INF
	for fan in range(1,ordered.size()-1):
		var triangle_id:String="%s|parent:%d|child:%d|fan:%d" % [_lattice_key(global_cell),parent_tet_index,child_tet_index,fan-1]
		var points_for_triangle:Array=[ordered[0],ordered[fan],ordered[fan+1]]
		var roots_for_triangle:Array[String]=[ordered_root_ids[0],ordered_root_ids[fan],ordered_root_ids[fan+1]]
		var registered:Dictionary=_register_required_triangle(topology,triangle_id,roots_for_triangle,points_for_triangle,global_cell,parent_tet_index)
		if not bool(registered.get("valid",false)):return {"valid":false,"reason":"d2_triangle_registration_failed","detail":registered,"triangle_id":triangle_id}
		# Keep the experimental path on the exact pre-existing cutoff.
		var emitted:bool=Core.add_triangle(mesh,ordered[0],ordered[fan],ordered[fan+1],toward,1.0e-12)
		var marked:Dictionary=_mark_triangle(topology,triangle_id,emitted,points_for_triangle,"below_frozen_cross_squared_cutoff")
		if not bool(marked.get("valid",false)):return {"valid":false,"reason":"d2_triangle_realization_failed","detail":marked,"triangle_id":triangle_id}
		if not emitted:
			local_drops+=1
			var cross:Vector3=(ordered[fan]-ordered[0]).cross(ordered[fan+1]-ordered[0]);local_min=minf(local_min,cross.length_squared())
			if ordered.size()==3:local_three+=1
			else:local_four+=1
	return {"valid":true,"drops":local_drops,"root_reuses":root_reuses,"drops_three_point":local_three,"drops_four_point":local_four,"minimum_dropped_cross_squared":local_min}

func _d2_volume_root(pa:Vector3,pb:Vector3,da:float,db:float,id_a:String,id_b:String,global_cell:Vector3i,parent_tet_index:int,root_cache:Dictionary)->Dictionary:
	# Stable endpoint ordering makes shared centroid-grid roots identical
	# regardless of child-tetrahedron traversal order.
	if id_a>id_b:
		var swap_point:Vector3=pa;pa=pb;pb=swap_point;var swap_value:float=da;da=db;db=swap_value;var swap_id:String=id_a;id_a=id_b;id_b=swap_id
	var edge_key:String="d2-edge|"+id_a+"|"+id_b
	if root_cache.has(edge_key):
		var cached:Dictionary=root_cache[edge_key]
		return {"valid":true,"root_identity":String(cached.root_identity),"point":cached.point,"reused":true}
	var root_identity:String=edge_key;var point:Vector3;var t:float=0.0;var residual:float=0.0
	if da==0.0:
		point=pa;root_identity="node|"+_world_point_key(pa);residual=da
	elif db==0.0:
		point=pb;root_identity="node|"+_world_point_key(pb);residual=db
	else:
		var denominator:float=da-db
		if denominator==0.0 or not is_finite(denominator):return {"valid":false,"reason":"invalid_volume_derived_root_denominator","da":da,"db":db}
		t=clampf(da/denominator,0.0,1.0);point=pa+(pb-pa)*t;residual=da+(db-da)*t
	if not point.is_finite() or not is_finite(t) or not is_finite(residual):return {"valid":false,"reason":"nonfinite_volume_derived_root","t":t,"residual":residual}
	root_cache[edge_key]={"point":point,"root_identity":root_identity}
	if not _d2_recorded_roots.has(root_identity) and not root_identity.begins_with("node|"):
		_d2_recorded_roots[root_identity]=true
		_d2_new_surface_roots+=1
		var endpoint_hex:Array[String]=[PackedFloat32Array([da]).to_byte_array().hex_encode(),PackedFloat32Array([db]).to_byte_array().hex_encode()]
		_d2_new_vertex_evidence.append({"vertex_identity":root_identity,"edge_identity":edge_key,"source":"exact materialized volume piecewise-linear field","source_global_cell":[global_cell.x,global_cell.y,global_cell.z],"source_parent_tetrahedron":parent_tet_index,"source_topology_edge":[id_a,id_b],"endpoint_world_positions":[[pa.x,pa.y,pa.z],[pb.x,pb.y,pb.z]],"endpoint_density_binary32_hex":endpoint_hex,"materialized_payload_sha256":_d2_materialized_values_sha256,"interpolation":{"formula":"t=da/(da-db); p=pa+(pb-pa)*t","da":da,"db":db,"t":t,"volume_field_residual":residual},"initial_construction_point":[point.x,point.y,point.z],"final_point":[point.x,point.y,point.z],"construction_displacement":0.0,"canonical_sdf_residual":"NOT_MEASURED","canonical_gradient":"NOT_MEASURED","canonical_normal":"NOT_MEASURED","bracket":"NOT_APPLICABLE; piecewise-linear volume root"})
	return {"valid":true,"root_identity":root_identity,"point":point,"reused":false}

func _d2_record_centroid_zero(identity:String,point:Vector3,global_cell:Vector3i,parent_tet_index:int,source_values:Array[float],materialized_values:PackedFloat32Array,_dims:Vector3i)->void:
	if _d2_recorded_roots.has(identity):return
	_d2_recorded_roots[identity]=true;_d2_new_surface_roots+=1
	var source_hex:Array[String]=[]
	for value in source_values:source_hex.append(PackedFloat32Array([value]).to_byte_array().hex_encode())
	_d2_new_vertex_evidence.append({"vertex_identity":identity,"source":"exact materialized volume piecewise-linear field","source_global_cell":[global_cell.x,global_cell.y,global_cell.z],"source_parent_tetrahedron":parent_tet_index,"source_topology_edge":"tetrahedron centroid is exactly zero","source_binary32_density_samples":source_values,"source_density_binary32_hex":source_hex,"materialized_payload_sha256":Core.sha256(materialized_values.to_byte_array()),"weights":[0.25,0.25,0.25,0.25],"interpolation":{"formula":"(((d0+d1)+d2)+d3)*0.25","result":0.0},"initial_construction_point":[point.x,point.y,point.z],"final_point":[point.x,point.y,point.z],"construction_displacement":0.0,"canonical_sdf_residual":"NOT_MEASURED","canonical_gradient":"NOT_MEASURED","canonical_normal":"NOT_MEASURED","bracket":"NOT_APPLICABLE; volume-derived centroid zero"})

func _cell_key(global_cell:Vector3i)->String:return _lattice_key(global_cell)

func _register_required_triangle(topology:RefCounted,triangle_id:String,root_ids:Array[String],points:Array,cell_id:Vector3i,tet_index:int)->Dictionary:
	if root_ids.size()!=3 or points.size()!=3:return {"valid":false,"reason":"triangle_root_point_count_mismatch"}
	for i in range(3):
		var added_root:Dictionary=topology.add_root(root_ids[i],points[i],"root/%s" % root_ids[i])
		if not bool(added_root.get("valid",false)):return added_root
	var cell_text: String="%d,%d,%d" % [cell_id.x,cell_id.y,cell_id.z]
	var owner_id: String="%s|tet:%d" % [cell_text,tet_index]
	return topology.add_triangle(triangle_id,root_ids,owner_id,cell_text,_roi_face_ids(points))

func _mark_triangle(topology:RefCounted,triangle_id:String,emitted:bool,points:Array,rejection_reason:String)->Dictionary:
	if points.size()!=3:return {"valid":false,"reason":"triangle_point_count_mismatch"}
	var cross:Vector3=(points[1]-points[0]).cross(points[2]-points[0])
	var cross_squared:float=cross.length_squared() if cross.is_finite() else NAN
	return topology.mark_realization(triangle_id,emitted,cross_squared,"" if emitted else rejection_reason)

func _roi_face_ids(points:Array)->Array[String]:
	var result:Array[String]=[]
	for axis in range(3):
		var on_min:=true;var on_max:=true
		for point_value in points:
			var point:Vector3=point_value
			on_min=on_min and absf(point[axis]-ROI_MIN[axis])<=1.0e-6
			on_max=on_max and absf(point[axis]-(ROI_MIN[axis]+float(CELLS[axis])*STEP))<=1.0e-6
		if on_min:result.append(String(["X_MIN","Y_MIN","Z_MIN"][axis]))
		if on_max:result.append(String(["X_MAX","Y_MAX","Z_MAX"][axis]))
	return result

func _order_root_ids(ordered:Array[Vector3],points:Array[Vector3],root_ids:Array[String])->Array[String]:
	if points.size()!=root_ids.size():return []
	var result:Array[String]=[]
	for ordered_point in ordered:
		var found:bool=false
		for i in range(points.size()):
			if ordered_point==points[i]:result.append(root_ids[i]);found=true;break
		if not found:return []
	return result

func _canonical_volume_root(cache:Dictionary,node_a:Vector3i,node_b:Vector3i,value_a:float,value_b:float,point_a:Vector3,point_b:Vector3)->Dictionary:
	var lattice_origin:=Vector3i(roundi(ROI_MIN.x/STEP),roundi(ROI_MIN.y/STEP),roundi(ROI_MIN.z/STEP))
	var key_a:String=_lattice_key(lattice_origin+node_a);var key_b:String=_lattice_key(lattice_origin+node_b)
	# Order numerically by the signed global lattice tuple. String comparison of
	# negative coordinates is not numeric (for example, "-31" sorts before
	# "-32"), and reversing endpoints changes the floating-point lerp path.
	if _lattice_before(lattice_origin+node_b,lattice_origin+node_a):
		var node_swap:Vector3i=node_a;node_a=node_b;node_b=node_swap
		var value_swap:float=value_a;value_a=value_b;value_b=value_swap
		var point_swap:Vector3=point_a;point_a=point_b;point_b=point_swap
		var key_swap:String=key_a;key_a=key_b;key_b=key_swap
	var edge_key:String=key_a+"|"+key_b
	var world_key_a:String=_world_point_key(point_a);var world_key_b:String=_world_point_key(point_b)
	if world_key_a>world_key_b:
		var world_key_swap:String=world_key_a;world_key_a=world_key_b;world_key_b=world_key_swap
	var edge_identity:String="edge|"+world_key_a+"|"+world_key_b
	if cache.has(edge_key):
		var cached:Dictionary=cache[edge_key]
		return {"valid":true,"point":cached.point,"edge_key":edge_key,"root_identity":cached.root_identity,"reused":true}
	var denominator:float=value_a-value_b
	if denominator==0.0 or not is_finite(denominator):return {"valid":false,"reason":"edge_denominator_invalid"}
	var t:float=clampf(value_a/denominator,0.0,1.0);var point:Vector3=point_a.lerp(point_b,t)
	if not point.is_finite():return {"valid":false,"reason":"edge_root_nonfinite"}
	var root_identity:String=edge_identity
	if value_a==0.0:point=point_a;root_identity="node|"+_world_point_key(point_a)
	elif value_b==0.0:point=point_b;root_identity="node|"+_world_point_key(point_b)
	cache[edge_key]={"point":point,"root_identity":root_identity}
	return {"valid":true,"point":point,"edge_key":edge_key,"root_identity":root_identity,"reused":false}

func _lattice_key(node:Vector3i)->String:
	return "%d,%d,%d"%[node.x,node.y,node.z]

func _lattice_before(a:Vector3i,b:Vector3i)->bool:
	if a.x!=b.x:return a.x<b.x
	if a.y!=b.y:return a.y<b.y
	return a.z<b.z

func _world_point_key(point:Vector3)->String:
	var packed:=PackedVector3Array();packed.append(point)
	return packed.to_byte_array().hex_encode()

func canonical_root_identity_probe(_snapshot:Dictionary)->Dictionary:
	# Synthetic exact-root identity fixture, independent of whether a particular
	# one-cell ROI contains a horizontal crossing. The same lattice edge is
	# submitted in both endpoint orders; zero-node sharing is tested separately.
	var node_a:=Vector3i(3,4,5);var node_b:=Vector3i(4,4,5)
	var point_a:=ROI_MIN+Vector3(node_a)*STEP;var point_b:=ROI_MIN+Vector3(node_b)*STEP
	var cache:Dictionary={}
	var forward:Dictionary=_canonical_volume_root(cache,node_a,node_b,-1.0,1.0,point_a,point_b)
	var reverse:Dictionary=_canonical_volume_root(cache,node_b,node_a,1.0,-1.0,point_b,point_a)
	var zero_cache:Dictionary={}
	var zero_a:Dictionary = _canonical_volume_root(zero_cache,node_a,node_b,0.0,-1.0,point_a,point_b)
	var node_c:=Vector3i(3,5,5);var point_c:=ROI_MIN+Vector3(node_c)*STEP
	var zero_b:Dictionary=_canonical_volume_root(zero_cache,node_a,node_c,0.0,-2.0,point_a,point_c)
	var zero_identity:String=String(zero_a.get("root_identity",""))
	var zero_identity_valid:bool=zero_identity.begins_with("node|") and zero_identity==String(zero_b.get("root_identity","")) and zero_a.get("point")==zero_b.get("point")
	return {"valid":forward.get("valid",false) and reverse.get("valid",false) and forward.get("point")==reverse.get("point") and forward.get("root_identity")==reverse.get("root_identity") and reverse.get("reused",false) and zero_a.get("root_identity")==zero_b.get("root_identity") and zero_identity_valid,
		"forward":forward.get("point",Vector3.ZERO),"reverse":reverse.get("point",Vector3.ZERO),
		"forward_root_identity":forward.get("root_identity",""),"reverse_root_identity":reverse.get("root_identity",""),"reverse_was_cache_hit":reverse.get("reused",false),"edge_key":forward.get("edge_key",""),
		"shared_zero_node_identity":zero_a.get("root_identity",""),"shared_zero_points_equal":zero_a.get("point")==zero_b.get("point"),"synthetic_samples":0}

func _order_polygon(points:Array[Vector3],toward_empty:Vector3)->Array[Vector3]:
	if points.size()<3 or not toward_empty.is_finite() or toward_empty.length_squared()<1.0e-16:return []
	var center:=Vector3.ZERO
	for point in points:center+=point
	center/=float(points.size())
	var normal:Vector3=toward_empty.normalized();var tangent:Vector3=(points[0]-center).normalized()
	if normal.length_squared()<0.5 or tangent.length_squared()<0.5:return []
	var bitangent:Vector3=normal.cross(tangent).normalized()
	if bitangent.length_squared()<0.5:return []
	var records:Array[Dictionary]=[]
	for point in points:
		var delta:Vector3=point-center
		records.append({"angle":atan2(delta.dot(bitangent),delta.dot(tangent)),"point":point})
	records.sort_custom(func(left:Dictionary,right:Dictionary)->bool:return float(left.angle)<float(right.angle))
	var ordered:Array[Vector3]=[]
	for record in records:ordered.append(record.point)
	return ordered

func _tetra_toward_empty(points:Array[Vector3],values:Array[float],tet:Array)->Vector3:
	var p0:Vector3=points[int(tet[0])]
	var e1:Vector3=points[int(tet[1])]-p0;var e2:Vector3=points[int(tet[2])]-p0;var e3:Vector3=points[int(tet[3])]-p0
	var d1:float=values[int(tet[1])]-values[int(tet[0])];var d2:float=values[int(tet[2])]-values[int(tet[0])];var d3:float=values[int(tet[3])]-values[int(tet[0])]
	var determinant:float=e1.dot(e2.cross(e3))
	if not is_finite(determinant) or absf(determinant)<1.0e-12:return Vector3.ZERO
	var gradient:Vector3=(d1*e2.cross(e3)+d2*e3.cross(e1)+d3*e1.cross(e2))/determinant
	return -gradient

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
