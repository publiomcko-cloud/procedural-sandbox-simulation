import json, sys
src, out = sys.argv[1], sys.argv[2]
scenario_lines=[]; result_lines=[]
with open(src, 'r', encoding='utf-8', errors='replace') as f:
    for line in f:
        if line.startswith('R72_SCENARIO '): scenario_lines.append(line[len('R72_SCENARIO '):])
        elif line.startswith('R72_RESULT '): result_lines.append(line[len('R72_RESULT '):])
if len(scenario_lines) != 1 or len(result_lines) != 1:
    print(json.dumps({'scenario_markers':len(scenario_lines),'result_markers':len(result_lines),'status':'INVALID_MARKER_COUNTS'})); sys.exit(2)
s=json.loads(scenario_lines[0]); r=json.loads(result_lines[0])
with open(out, 'w', encoding='utf-8', newline='\n') as f: json.dump(s, f, sort_keys=True, separators=(',',':'), allow_nan=False)
summary={
 'scenario':s.get('scenario'),'scenario_id':s.get('scenario_id'),'input_sha256':s.get('input_manifest_sha256'),
 'seed':s.get('seed'),'ledger_revision':s.get('ledger_revision'),'operation_count':s.get('operation_count'),
 'ordered_commands':s.get('ordered_commands'),'result_status':r.get('status'),'assertions':r.get('assertions'),
 'failures':r.get('failures'),'scenario_count':r.get('scenario_count'),
 'local_strategy_A_keys':sorted((s.get('local_strategy_A') or {}).keys()),
 'full_topology_keys':sorted((s.get('full_topology') or {}).keys()),
 'interface_metrics_keys':sorted((s.get('interface_metrics') or {}).keys()),
 'winding_keys':sorted((s.get('full_winding_metrics') or {}).keys()),
 'collider_keys':sorted((s.get('collider') or {}).keys()),
 'field_geometry_keys':sorted((s.get('field_geometry') or {}).keys()),
 'timing_usec':s.get('timing_usec')}
print(json.dumps(summary,sort_keys=True,separators=(',',':')))