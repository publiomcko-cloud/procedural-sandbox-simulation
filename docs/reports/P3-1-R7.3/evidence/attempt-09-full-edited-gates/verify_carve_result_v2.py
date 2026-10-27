import hashlib, json, math, subprocess
from pathlib import Path
root=Path(r'C:\Users\PUBLI\AppData\Local\Temp\P31-R73-Full-Carve-23baef7af9b941059154b9891e9f8c6c')
checkout=root/'checkout'; evidence=root/'evidence'; raw=evidence/'carve.stdout.log'
expected_sha='7ad45d8c817ecb0f54a8eec058babce65af287db'; expected_input='47ec41f63338f98c5160f58aa71c86f6ec78412dbccad7ae86805fb115592411'
prior=json.loads(Path(r'C:\r73\docs\reports\P3-1-R7.3\evidence\attempt-07\launch-intent.json').read_text(encoding='utf-8'))
source_hashes={k:v.lower() for k,v in prior['source_sha256'].items()}
actual_sha=subprocess.check_output(['git','-C',str(checkout),'rev-parse','HEAD'],text=True).strip()
origin=subprocess.check_output(['git','-C',str(checkout),'remote','get-url','origin'],text=True).strip()
source_actual={p:hashlib.sha256((checkout/p).read_bytes()).hexdigest() for p in source_hashes}
source_mismatches={p:{'expected':source_hashes[p],'actual':source_actual[p]} for p in source_hashes if source_actual[p]!=source_hashes[p]}
records={'R72_RESULT':[],'R72_SCENARIO':[]}
with raw.open('r',encoding='utf-8',errors='strict') as f:
 for line in f:
  for tag in records:
   prefix=tag+' '
   if line.startswith(prefix): records[tag].append(json.loads(line[len(prefix):]))
assert len(records['R72_RESULT'])==1 and len(records['R72_SCENARIO'])==1
r=records['R72_RESULT'][0]; s=records['R72_SCENARIO'][0]
strategy=s['local_strategy_A']; before=s['local_before']; topo=s['full_topology']; interface=s['interface_metrics']; collider=s['collider']; field=s['field_geometry']
summary={
 'source':{'head':actual_sha,'expected_head':expected_sha,'origin':origin,'source_hash_count':len(source_hashes),'source_hash_mismatches':source_mismatches,'source_hashes':source_actual},
 'raw_stdout':{'path':str(raw),'bytes':raw.stat().st_size,'sha256':hashlib.sha256(raw.read_bytes()).hexdigest()},
 'result':r,
 'scenario':{k:s.get(k) for k in ('scenario','scenario_id','seed','ledger_revision','operation_count','input_manifest_sha256','repair_strategy','source_triangle_count_inclusive','face_component_count_before','face_component_count_after','two_sided_canonical_hit_mismatches')},
 'ordered_commands':s.get('ordered_commands',[]),
 'strategy_A':{k:strategy.get(k) for k in ('valid','disposition','external_boundary_unchanged')},
 'local_before':{k:before.get(k) for k in ('face_count','degenerate_triangles','nonzero_subthreshold_triangles','internal_open_edges','external_open_edges','nonmanifold_edges','same_winding_edges','t_junctions','threshold_cross_squared')},
 'full_topology':{k:topo.get(k) for k in ('triangle_count','unique_undirected_edges','open_edge_count','expected_open_edge_count_at_patch_boundary','internal_open_edge_crack_count','degenerate_triangle_count','nonmanifold_edge_count')},
 'interfaces':{k:interface.get(k) for k in ('internal_cell_interfaces_checked','matching_contour_segments_compared','interfaces_with_nonmatching_extracted_contours','duplicate_coplanar_surface_interfaces','strict_t_junction_vertex_on_contour_segment_count','maximum_shared_endpoint_normal_angle_degrees')},
 'winding':{k:s['full_winding_metrics'].get(k) for k in ('face_count','edge_count','open_edges','nonmanifold_edges','same_winding_edges')},
 'collider':{k:collider.get(k) for k in ('status','ray_query_count','physics_vs_two_sided_triangle_hit_mismatches_with_shape_backface_collision_enabled','physics_vs_two_sided_triangle_hit_mismatches_with_default_one_sided_shape','outside_to_cave_ray_hit_outcome_mismatches','cave_to_outside_ray_hit_outcome_mismatches','sphere_probe_count','sphere_contact_difference_world','limitations','production_terrain_collision_provider')},
 'field_geometry':{k:field.get(k) for k in ('centerline_open_samples','centerline_total_samples','picker_hit_outcomes_equal','picker_queries','picker_position_error_world','radial_diameter_world')},
 'timing_usec':s.get('timing_usec')}
gates={
 'source_identity':actual_sha==expected_sha and origin=='https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git' and not source_mismatches and len(source_actual)==11,
 'result':r.get('status')=='PASS' and r.get('failures')==[] and r.get('scenario_count')==1 and r.get('assertions')==21,
 'scenario':s.get('scenario_id')=='P3.1.R7.CAVE_WALL_CARVE.v1' and s.get('input_manifest_sha256')==expected_input and s.get('operation_count')==1 and len(s.get('ordered_commands',[]))==1 and s['ordered_commands'][0].get('mode')==0 and s['ordered_commands'][0].get('sequence')==0,
 'repair':strategy.get('valid') is True and strategy.get('external_boundary_unchanged') is True,
 'local':before.get('threshold_cross_squared')==1e-12 and before.get('internal_open_edges')==0,
 'full_topology':topo.get('internal_open_edge_crack_count')==0 and topo.get('degenerate_triangle_count')==0 and topo.get('nonmanifold_edge_count')==0 and topo.get('open_edge_count')==topo.get('expected_open_edge_count_at_patch_boundary'),
 'interfaces':interface.get('interfaces_with_nonmatching_extracted_contours')==0 and interface.get('duplicate_coplanar_surface_interfaces')==0 and interface.get('strict_t_junction_vertex_on_contour_segment_count')==0,
 'winding':s['full_winding_metrics'].get('same_winding_edges')==0,
 'two_sided_collider':collider.get('ray_query_count')==72 and collider.get('physics_vs_two_sided_triangle_hit_mismatches_with_shape_backface_collision_enabled')==0 and collider.get('sphere_probe_count')==36,
}
summary['gates']=gates; summary['all_gates_pass']=all(gates.values())
def clean(v):
 if isinstance(v,float) and not math.isfinite(v): return 'Infinity' if v>0 else '-Infinity' if v<0 else 'NaN'
 if isinstance(v,dict): return {k:clean(x) for k,x in v.items()}
 if isinstance(v,list): return [clean(x) for x in v]
 return v
summary=clean(summary)
out=evidence/'carve.acceptance-summary-verified.json'
out.write_text(json.dumps(summary,indent=2,allow_nan=False)+'\n',encoding='utf-8')
print(json.dumps({'output':str(out),'all_gates_pass':summary['all_gates_pass'],'gates':summary['gates'],'result':summary['result'],'scenario':summary['scenario'],'source_hash_count':len(source_hashes),'source_hash_mismatches':source_mismatches,'full_topology':summary['full_topology'],'interfaces':summary['interfaces'],'collider':{k:summary['collider'][k] for k in ('ray_query_count','physics_vs_two_sided_triangle_hit_mismatches_with_shape_backface_collision_enabled','physics_vs_two_sided_triangle_hit_mismatches_with_default_one_sided_shape','sphere_probe_count')},'field_geometry':summary['field_geometry'],'timing_usec':summary['timing_usec']},indent=2,allow_nan=False))
if not summary['all_gates_pass']: raise SystemExit(2)
