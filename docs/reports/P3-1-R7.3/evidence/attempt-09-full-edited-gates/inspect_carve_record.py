import json,sys
s=[]
for line in open(sys.argv[1],encoding='utf-8',errors='replace'):
 if line.startswith('R72_SCENARIO '): s.append(json.loads(line[13:]))
x=s[0]; out={
 'scenario':x['scenario_id'],'input_sha':x['input_manifest_sha256'],'commands':x['ordered_commands'],
 'local_A':{k:x['local_strategy_A'].get(k) for k in ['valid','disposition','external_boundary_unchanged','surface_metrics']},
 'local_before':{k:x['local_before'].get(k) for k in ['face_count','internal_open_edges','external_open_edges','degenerate_triangles','nonmanifold_edges','same_winding_edges','t_junctions','face_component_count','threshold_cross_squared']},
 'full_topology':{k:v for k,v in x['full_topology'].items() if not isinstance(v,(list,dict))},
 'interface':{k:v for k,v in x['interface_metrics'].items() if not isinstance(v,(list,dict))},
 'winding':{k:v for k,v in x['full_winding_metrics'].items() if not isinstance(v,(list,dict))},
 'field_geometry':x['field_geometry'],'surface':{k:v for k,v in x['surface_geometry'].items() if not isinstance(v,(list,dict))},
 'collider':{k:v for k,v in x['collider'].items() if not isinstance(v,(list,dict))},
 'components_before_after':[x.get('face_component_count_before'),x.get('face_component_count_after')],
 'timing_usec':x['timing_usec'],'mesh_sha256':x.get('repaired_mesh_sha256'),
 'source_mesh_sha256':x.get('source_mesh_sha256')}
print(json.dumps(out,sort_keys=True,separators=(',',':')))