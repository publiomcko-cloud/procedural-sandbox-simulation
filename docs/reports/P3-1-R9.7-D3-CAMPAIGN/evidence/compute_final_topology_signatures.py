import hashlib, json
from pathlib import Path
root=Path(r"C:\Users\PUBLI\AppData\Local\Temp\P3_1_R97_D3_20261029_5eab760d7ce6486eaef7fb210741416e")
stdout=root/"D3.5_GEOMETRY_RUN1"/"stdout.txt"
rows=[]
for line in stdout.read_text(encoding="utf-8").splitlines():
    if not line.startswith("R96R1_D3_INTERFACE "):
        continue
    record=json.loads(line.split(" ",1)[1])
    topo=record["patched_combined_topology"]
    keys=sorted(item["key"] for item in topo.get("internal_examples_first_24", []))
    complete=len(keys)==topo["internal_open_edges"]
    signature={"internal_open_edge_keys":keys,"internal_open_edges":topo["internal_open_edges"],"nonmanifold_edges":topo["nonmanifold_edges"],"roi_boundary_open_edges":topo["roi_boundary_open_edges"],"triangle_count":topo["triangle_count"],"valid":topo["valid"]}
    raw=json.dumps(signature,sort_keys=True,separators=(",",":"),ensure_ascii=False).encode("utf-8")
    interface_path=Path(record["patch_artifact"]["path"])
    cap_path=Path(record["multi_cell_patch_artifact"]["path"])
    rows.append({"scenario_id":record["scenario_id"],"topology_signature_scope":"complete_internal_open_edge_key_set" if complete else "partial_first_24_examples","topology_signature":signature,"topology_signature_canonical_utf8_sha256":hashlib.sha256(raw).hexdigest(),"patch_winding_compatible":record["patch_winding_compatible"],"interface_patch_artifact_sha256":hashlib.sha256(interface_path.read_bytes()).hexdigest(),"multi_cell_patch_artifact_sha256":hashlib.sha256(cap_path.read_bytes()).hexdigest()})
base=json.loads((root/"D3.5-base-topology-identities.json").read_text(encoding="utf-8-sig"))
out={"algorithm":"SHA-256 of sorted-key compact UTF-8 JSON with fields internal_open_edge_keys, internal_open_edges, nonmanifold_edges, roi_boundary_open_edges, triangle_count, valid; final counts have at most 24 edge examples so key lists are complete.","source":"captured D3.5 stdout and PowerShell-parsed topology artifact; no Godot rerun","base_candidate_mesh_sha256":base["base_candidate_mesh_sha256"],"base_required_surface_topology_sha256":base["base_required_surface_topology_sha256"],"final_attempt_topologies":rows}
(root/"D3.5-topology-signatures.json").write_text(json.dumps(out,indent=2)+"\n",encoding="utf-8")
