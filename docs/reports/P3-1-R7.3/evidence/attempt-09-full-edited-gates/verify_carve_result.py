import hashlib, json, math, subprocess
from pathlib import Path
root=Path(r'C:\Users\PUBLI\AppData\Local\Temp\P31-R73-Full-Carve-23baef7af9b941059154b9891e9f8c6c')
checkout=root/'checkout'; evidence=root/'evidence'; raw=evidence/'carve.stdout.log'
expected_sha='7ad45d8c817ecb0f54a8eec058babce65af287db'
expected_input='47ec41f63338f98c5160f58aa71c86f6ec78412dbccad7ae86805fb115592411'
source_hashes={
'game/tests/prototypes/p3_1_r7_2_zero_edit_gate.gd':'04c3656e314ff1a21f10be2d3a034f8ee137e5024c5ea7fa50c5563de21e27d5',
'game/tests/prototypes/p3_1_r7_2_local_retriangulation.gd':'9ea65149d45be9ef6e747156ea2984e8f75269cca03e11714d72e8354330f3d2',
'game/tests/prototypes/p3_1_r7_3_minimal_carve_repair.gd':'f74a51d8f93296181325aa876b442fc42c03ac64c6cf34728b8fe4c755f2b4bf',
'game/tests/prototypes/p3_1_r7_conforming_adaptive_diagnostic.gd':'be05d2eb586b98de8f8998dd231f3e3dc5646a8bdcf6ec1fa863a56c455bb75e',
'game/tests/prototypes/p3_1_r7_conforming_mesh_fixture.gd':'65addfba047a093def229bd6e2c1c3ac363c8e559cf20cd178cdf7a1264966c7',
'game/scripts/terrain/sdf_brush_edit_state.gd':'9c715174770725fa0a45cfeab0b2e3c442e25eab8ef87b423f0de51d6ecedb44',
'game/scripts/terrain/sdf_world.gd':'a878e06d83652559c603e3e75bc3f704f1fe9222bb5f31bf6711d21b5612ac06',
'game/scripts/terrain/terrain_chunk_grid.gd':'d23e882be578c5b063cdff6ad2cffeF121623003e46826aeeFC5DC4D8'.lower(),
'game/scripts/experiments/lod01_transition_fixture.gd':'26660008d576604546cf098c54ddc0b381b579b779b993e93a1f3c467209ed0f',
'game/scripts/terrain/marching_tetrahedra.gd':'23fbc6f94ba37d070d34924e85e9bbf1bdbbb26666aba32345c0140dfc6dffe3',
'game/scripts/terrain/terrain_brush_picker.gd':'41fe707cb7d3c87a5fbededca681bc8773d75fa4e32bcf97b7f583eff1869cf4',
}
actual_sha=subprocess.check_output(['git','-C',str(checkout),'rev-parse','HEAD'],text=True).strip()
origin=subprocess.check_output(['git','-C',str(checkout),'remote','get-url','origin'],text=True).strip()
source_mismatches={p:{'expected':h,'actual':hashlib.sha256((checkout/p).read_bytes()).hexdigest()} for p,h in source_hashes.items() if hashlib.sha256((checkout/p).read_bytes()).hexdigest()!=h}
records={'R72_RESULT':[],'R72_SCENARIO':[]}
with raw.open('r',encoding='utf-8',errors='strict') as f:
 for line in f:
  for tag in records:
   prefix=tag+' '
   if line.startswith(prefix): records[tag].append(json.loads(line[len(prefix):]))
assert len(records['R72_RESULT'])==1 and len(records['R72_SCENARIO'])==1
r=records['R72_RESULT'][0]; s=records['R72_SCENARIO'][0]
strategy=s['local_strategy_A']; before=s['local_before']; topo=s['full_topology']; interface=s['interface_metrics']; collider=s['collider']; field=s['field_geometry']
commands=s.get('ordered_commands',[])
summary={
 'checkout_head':actual_sha,'expected_head':expected_sha,'origin':origin,'source_hash_count':len(source_hashes),'source_hash_mismatches':source_mismatches,
 'raw_stdout_sha256':hashlib.sha256(raw.read_bytes()).hexdigest(),'raw_stdout_bytes':raw.stat().st_size,
 'result':r,'scenario':{k:s.get(k) for k in ('scenario','scenario_id','seed','ledger_revision','operation_count','input_manifest_sha256','repair_strategy','source_triangle_count_inclusive','face_component_count_before','face_component_count_after','two_sided_canonical_hit_mismatches')},
 'ordered_commands':commands,
 'strategy_A':{k:strategy.get(k) for k in ('valid','disposition','external_boundary_unchanged')},
 'local_before':{k:before.get(k) for k in ('face_count','degenerate_triangles','nonzero_subthreshold_triangles','internal_open_edges','external_open_edges','nonmanifold_edges','same_winding_edges','t_junctions','threshold_cross_squared')},
 'full_topology':{k:topo.get(k) for k in ('triangle_count','unique_undirected_edges','open_edge_count','expected_open_edge_count_at_patch_boundary','internal_open_edge_crack_count','degenerate_triangle_count','nonmanifold_edge_count')},
 'interfaces':{k:interface.get(k) for k in ('internal_cell_interfaces_checked','matching_contour_segments_compared','interfaces_with_nonmatching_extracted_contours','duplicate_coplanar_surface_interfaces','strict_t_junction_vertex_on_contour_segment_count','maximum_shared_endpoint_normal_angle_degrees')},
 'winding':{k:s['full_winding_metrics'].get(k) for k in ('face_count','edge_count','open_edges','nonmanifold_edges','same_winding_edges')},
 'collider':{k:collider.get(k) for k in ('status','ray_query_count','physics_vs_two_sided_triangle_hit_mismatches_with_shape_backface_collision_enabled','physics_vs_two_sided_triangle_hit_mismatches_with_default_one_sided_shape','outside_to_cave_ray_hit_outcome_mismatches','cave_to_outside_ray_hit_outcome_mismatches','sphere_probe_count','sphere_contact_difference_world','sphere_penetration_proxy_records','limitations','production_terrain_collision_provider')},
 'field_geometry':{k:field.get(k) for k in ('centerline_open_samples','centerline_total_samples','picker_hit_outcomes_equal','picker_queries','picker_position_error_world','radial_diameter_world')},
 'timing_usec':s.get('timing_usec'),
 'gates':{
  'source_identity':actual_sha==expected_sha and origin=='https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git' and not source_mismatches,
  'one_pass_result':r.get('status')=='PASS' and r.get('failures')==[] and r.get('scenario_count')==1 and r.get('assertions')==21,
  'frozen_scenario':s.get('scenario_id')=='P3.1.R7.CAVE_WALL_CARVE.v1' and s.get('input_manifest_sha256')==expected_input and s.get('operation_count')==1,
  'strategy_A':strategy.get('valid') is True and strategy.get('external_boundary_unchanged') is True,
  'local_threshold_and_no_interior_open':before.get('threshold_cross_squared')==1e-12 and before.get('internal_open_edges')==0,
  'full_topology':topo.get('internal_open_edge_crack_count')==0 and topo.get('degenerate_triangle_count')==0 and topo.get('nonmanifold_edge_count')==0,
  'interfaces':interface.get('interfaces_with_nonmatching_extracted_contours')==0 and interface.get('duplicate_coplanar_surface_interfaces')==0 and interface.get('strict_t_junction_vertex_on_contour_segment_count')==0,
  'two_sided_collider':collider.get('ray_query_count')==72 and collider.get('physics_vs_two_sided_triangle_hit_mismatches_with_shape_backface_collision_enabled')==0,
 }
}
# Replace any non-finite measurements with explicit strings, while preserving raw stdout untouched.
def clean(v):
 if isinstance(v,float) and not math.isfinite(v): return 'Infinity' if v>0 else '-Infinity' if v<0 else 'NaN'
 if isinstance(v,dict): return {k:clean(x) for k,x in v.items()}
 if isinstance(v,list): return [clean(x) for x in v]
 return v
summary=clean(summary)
summary['all_gates_pass']=all(summary['gates'].values())
(evidence/'carve.acceptance-summary.json').write_text(json.dumps(summary,indent=2,allow_nan=False)+'\n',encoding='utf-8')
print(json.dumps(summary,indent=2,allow_nan=False))
if not summary['all_gates_pass']: raise SystemExit(2)
