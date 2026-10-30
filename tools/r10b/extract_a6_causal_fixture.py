#!/usr/bin/env python3
"""Extract and validate the immutable R10-A6 causal fixture for R10-B.

The archived R10-A JSON contains raw U+001F separators, which are invalid JSON
control bytes. This reader hashes the original bytes first, then creates an
in-memory escaped parsing view. It never rewrites the archived inputs.
"""

from __future__ import annotations

import hashlib
import json
import math
import struct
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any


EXPECTED_GATE_SHA256 = "664bb61fd060cff689e0b251517503dcb888ead21622d8caae7535f6b66155dc"
EXPECTED_RAY_SHA256 = "327a87ee0608eb95a8b9492c98ff7a7038b88d7aba20be0bc833f32dae738a9d"
EXPECTED_CANDIDATE_D_SHA256 = "334db9e3e9dfe3aca4a590845ba6b792629d204c0f1d6a3fc8a3898e7cbb020a"
EXPECTED_MANIFEST_SHA256 = "1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972"
EXPECTED_SOURCE_TOPOLOGY_SHA256 = "4ecbb2496fb34f1cf3c05a60192f76bdce7a52ec3148d02ba041510b804a8c95"
EXPECTED_SCENARIO = "R9.2.SEAM.XPLUS_EQUAL.v1"
EXPECTED_RAY_SCENARIO = "R9.2.RAY.CANONICAL_PICKER.v1"
CUTOFF_SQUARED = 1.0e-12


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def parse_preserved_json(path: Path, expected: str) -> tuple[dict[str, Any], str, int]:
    raw = path.read_bytes()
    observed = sha256(raw)
    if observed != expected:
        raise ValueError(f"raw_input_sha256_mismatch:{path.name}:{observed}:{expected}")
    control_count = raw.count(b"\x1f")
    # Preserve the original file; only the parser view replaces invalid raw
    # JSON control characters with the equivalent JSON escape sequence.
    parsed = json.loads(raw.replace(b"\x1f", b"\\u001f"))
    return parsed, observed, control_count


def f32_hex(value: float) -> str:
    return struct.pack("<f", float(value)).hex()


def f64_hex(value: float) -> str:
    return struct.pack("<d", float(value)).hex()


def stable_edge(a: str, b: str) -> str:
    return "|".join(sorted((a, b)))


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: extract_a6_causal_fixture.py <a6-gate.json> <a6-ray.json> <output.json>", file=sys.stderr)
        return 2
    gate_path, ray_path, output_path = map(Path, sys.argv[1:])
    gate, gate_sha, gate_controls = parse_preserved_json(gate_path, EXPECTED_GATE_SHA256)
    ray, ray_sha, ray_controls = parse_preserved_json(ray_path, EXPECTED_RAY_SHA256)

    if gate.get("scenario_id") != EXPECTED_SCENARIO or ray.get("scenario_id") != EXPECTED_RAY_SCENARIO:
        raise ValueError("scenario_identity_mismatch")
    geometry = gate["geometry"]
    proof = geometry["source_topology_graph_proof"]
    if proof.get("topology_sha256") != EXPECTED_SOURCE_TOPOLOGY_SHA256:
        raise ValueError("source_topology_hash_mismatch")
    reconstruction = geometry["component_reconstruction"]
    patch = next((p for p in reconstruction["patches"] if p.get("status") == "UNRESOLVED"), None)
    if patch is None or patch.get("component_id") != "60,8,25|tet:0":
        raise ValueError("unresolved_component_identity_mismatch")

    source_polygon_ids = list(patch["source_polygon_ids"])
    source_polygon_set = set(source_polygon_ids)
    polygons_by_id = {p["id"]: p for p in reconstruction["polygons"]}
    source_polygons = [polygons_by_id[pid] for pid in source_polygon_ids if pid in polygons_by_id]
    if len(source_polygons) != 84 or len(source_polygon_ids) != 84:
        raise ValueError(f"source_polygon_count_mismatch:{len(source_polygons)}")

    root_ids = sorted({rid for p in source_polygons for rid in p["root_ids"]})
    canonical_roots = {row[0]: row for row in geometry["topology_graph"]["canonical"]["roots"]}
    root_authority: dict[str, Any] = {}
    for rid in root_ids:
        row = canonical_roots.get(rid)
        if row is None or len(row) < 5:
            raise ValueError(f"missing_canonical_root:{rid}")
        xyz = [float(row[1]), float(row[2]), float(row[3])]
        if not all(math.isfinite(v) for v in xyz):
            raise ValueError(f"nonfinite_root:{rid}")
        incident_source = sorted(p["id"] for p in reconstruction["polygons"] if rid in p["root_ids"] and p["id"] in source_polygon_set)
        incident_neighbors = sorted(p["id"] for p in reconstruction["polygons"] if rid in p["root_ids"] and p["id"] not in source_polygon_set)
        root_authority[rid] = {
            "xyz": xyz,
            "xyz_float32_le_hex": [f32_hex(v) for v in xyz],
            "authority": row[4],
            "source_component_polygons": incident_source,
            "neighbor_polygons": incident_neighbors,
        }

    boundary = patch["boundary"]
    if boundary.get("path_count") != 1 or boundary.get("closed_loop_count") != 1 or boundary.get("open_path_count") != 0:
        raise ValueError("boundary_cycle_not_single_closed_loop")
    boundary_path = boundary["paths"][0]
    boundary_root_ids = list(boundary_path["root_ids"])
    boundary_arc_ids = list(boundary_path["edge_keys"])
    inserted = list(patch["triangulation"]["interior_root_insertions"])
    interior_root_ids = [row["root_id"] for row in inserted]
    if len(root_ids) != 73 or len(boundary_root_ids) != 34 or len(interior_root_ids) != 39:
        raise ValueError(f"root_partition_count_mismatch:{len(root_ids)}:{len(boundary_root_ids)}:{len(interior_root_ids)}")
    if len(set(boundary_root_ids)) != len(boundary_root_ids) or len(set(interior_root_ids)) != len(interior_root_ids):
        raise ValueError("duplicate_boundary_or_interior_root")
    if set(boundary_root_ids) & set(interior_root_ids) or set(boundary_root_ids) | set(interior_root_ids) != set(root_ids):
        raise ValueError("boundary_interior_root_partition_mismatch")

    source_arcs = reconstruction["arcs"]
    if not isinstance(source_arcs, dict):
        raise ValueError("source_arc_table_not_dictionary")
    boundary_arc_records = []
    for arc_id in boundary_arc_ids:
        arc = source_arcs.get(arc_id)
        if arc is None:
            raise ValueError(f"missing_boundary_arc:{arc_id}")
        boundary_arc_records.append({"arc_id": arc_id, **arc})
    component_arc_records = []
    for arc_id, arc in sorted(source_arcs.items()):
        if source_polygon_set.intersection(arc.get("polygon_ids", [])):
            component_arc_records.append({"arc_id": arc_id, **arc})

    final_state = patch["triangulation"]
    final_triangles = []
    edge_incidence: dict[str, list[int]] = defaultdict(list)
    for index, triangle in enumerate(final_state["triangles"]):
        ids = list(triangle["root_ids"])
        if len(ids) != 3 or any(rid not in root_authority for rid in ids):
            raise ValueError(f"invalid_final_triangle_root_ids:{index}")
        row = {"triangle_index": index, **triangle}
        final_triangles.append(row)
        for edge_index in range(3):
            edge_incidence[stable_edge(ids[edge_index], ids[(edge_index + 1) % 3])].append(index)
    internal_edges = [
        {"edge_id": edge_id, "triangle_indices": indices, "incidence": len(indices)}
        for edge_id, indices in sorted(edge_incidence.items())
    ]

    subcutoff = []
    for row in final_state["remaining_subcutoff_triangles"]:
        value = float(row["cross_squared"])
        if not value <= CUTOFF_SQUARED:
            raise ValueError("subcutoff_triangle_does_not_match_frozen_cutoff")
        subcutoff.append({**row, "cross_squared_decimal17": format(value, ".17g"), "cross_squared_float64_le_hex": f64_hex(value)})
    if len(subcutoff) != 2 or final_state.get("flip_count") != 33 or final_state.get("inserted_root_count") != 39:
        raise ValueError("A6_expected_causal_observation_mismatch")

    neighbor_ids: set[str] = set()
    for arc in component_arc_records:
        neighbor_ids.update(pid for pid in arc.get("polygon_ids", []) if pid not in source_polygon_set)
    vertex_neighbor_ids = {
        p["id"] for p in reconstruction["polygons"]
        if p["id"] not in source_polygon_set and root_ids and set(p["root_ids"]).intersection(root_ids)
    }
    neighbor_polygon_records = [
        polygons_by_id[pid] for pid in sorted(neighbor_ids | vertex_neighbor_ids) if pid in polygons_by_id
    ]

    source_polygon_records = []
    for p in source_polygons:
        source_polygon_records.append({
            "id": p["id"], "cell": p.get("cell"), "tet_index": p.get("tet_index"),
            "root_ids": p["root_ids"], "face_ids": p.get("face_ids", []),
            "points_as_recorded": p.get("points", []), "toward_empty_as_recorded": p.get("toward_empty"),
            "realization": p.get("realization"),
        })

    fixture = {
        "schema": "P3.1.R10B.A6CausalFixture.v1",
        "provenance": {
            "r10a_remote_head": "f6f4a47bcb9f98ee7b8648f88a4db2ccf8317294",
            "r10a_remote_tree": "09b3eb8ac59e77e0dfa44c82175b4180c3629d21",
            "r10a_local_equivalent_head": "4b7b0ea58c125da2365033440d04003fb31a2ba1",
            "r10a_measured_source_local": "da55e6e97bd56c31034b2d84c68a245a2f0973a1",
            "r10a_measured_source_blob_topology_authority": "732f143939ac6980e1c7e77703dd7ee549206c0e",
            "r10a_measured_source_physical_sha256_recorded": "bdc4b40a3f3ebd3bb37bf0510449b34d279bd3c85632f13323c5eee9bfc2c5db",
            "r10a_current_tree_physical_line_ending_note": "R10A measured worktree bytes verified at C:\\r10a-20261029; R10B checkout is LF-normalized by current .gitattributes; git blob is identical.",
            "candidate_d_path": "game/tests/prototypes/p3_1_r9_2_candidate_impl.gd",
            "candidate_d_sha256": EXPECTED_CANDIDATE_D_SHA256,
            "manifest_path": "game/tests/prototypes/p3_1_r9_2_e2e_inputs.jsonl",
            "manifest_sha256": EXPECTED_MANIFEST_SHA256,
            "godot_sha256": "c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643",
            "cutoff_cross_squared": CUTOFF_SQUARED,
            "a6_gate_raw_sha256": gate_sha,
            "a6_ray_raw_sha256": ray_sha,
            "a6_gate_raw_u001f_count": gate_controls,
            "a6_ray_raw_u001f_count": ray_controls,
            "parse_view_only_replacement": "raw byte 0x1f to JSON escape \\\\u001f; source artifacts remain unchanged",
        },
        "equal_lod_roi_id": EXPECTED_SCENARIO,
        "candidate_d_volume": {
            "sha256": gate["volume_sha256"], "payload_sha256": gate["payload_sha256"],
            "revision": gate["volume_revision"], "materialized_bytes": gate["materialized_bytes"],
            "identity_preserved": gate["volume_identity_preserved"],
        },
        "source_topology": {
            "topology_sha256": proof["topology_sha256"], "valid": proof["valid"],
            "root_count": proof["root_count"], "polygon_count": proof["polygon_count"],
            "arc_count": proof["arc_count"], "unresolved_required_arc_count": proof["unresolved_required_arc_count"],
            "nonmanifold_required_arc_count": proof["nonmanifold_required_arc_count"],
        },
        "failed_component": {
            "component_id": patch["component_id"], "status": patch["status"],
            "source_authority": patch["source_authority"], "source_cell_count": patch["source_cell_count"],
            "source_euler_characteristic": patch["source_euler_characteristic"],
            "source_polygon_ids": source_polygon_ids, "source_polygons": source_polygon_records,
            "source_root_count": patch["source_root_count"], "boundary_root_count": patch["boundary_root_count"],
            "interior_root_count": patch["interior_root_count"], "ordered_boundary_root_ids": boundary_root_ids,
            "interior_root_ids": interior_root_ids, "roots": root_authority,
            "boundary_arc_ids": boundary_arc_ids, "boundary_arc_records": boundary_arc_records,
            "component_arc_records": component_arc_records,
            "neighbor_polygon_ids": sorted(neighbor_ids), "vertex_neighbor_polygon_ids": sorted(vertex_neighbor_ids),
            "neighbor_polygon_records": neighbor_polygon_records,
            "source_orientation_authority": {
                "field": patch["source_authority"],
                "per_polygon_toward_empty_vectors_as_recorded": {p["id"]: p.get("toward_empty") for p in source_polygons},
            },
            "a6_final_triangulation": {
                "valid": final_state["valid"], "reason": final_state["reason"],
                "triangle_count": len(final_triangles), "triangles": final_triangles,
                "edge_incidence": internal_edges,
                "flip_count": final_state["flip_count"], "flip_history": final_state["flips"],
                "inserted_root_count": final_state["inserted_root_count"],
                "all_requested_roots_inserted": final_state["all_requested_roots_inserted"],
                "interior_root_insertions": inserted,
                "minimum_cross_squared": final_state["minimum_cross_squared"],
                "remaining_subcutoff_triangles": subcutoff,
                "max_flip_limit": final_state["max_flip_limit"], "limit_reached": final_state["limit_reached"],
                "cutoff_squared": CUTOFF_SQUARED,
            },
        },
        "a6_gate_metrics": {
            "mesh_topology": geometry["mesh_topology"],
            "required_adjacency_missing_count": geometry["required_adjacency_missing_count"],
            "required_adjacency_nonmanifold_count": geometry["required_adjacency_nonmanifold_count"],
            "winding_valid": geometry["winding_valid"],
            "geometry_realization_complete": geometry["geometry_realization_complete"],
            "required_topology_complete": geometry["required_topology_complete"],
            "controls": {"passed": 6, "total": 6},
            "ray_hit_miss_disagreements": ray["ray_comparison"]["hit_miss_disagreements"],
            "ray_count": ray["ray_comparison"]["ray_count"],
        },
        "a6_rays_recorded_outcomes": ray["ray_comparison"]["rays"],
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    encoded = (json.dumps(fixture, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n").encode("utf-8")
    if output_path.exists():
        raise FileExistsError(f"refusing to overwrite fixture:{output_path}")
    output_path.write_bytes(encoded)
    print(json.dumps({
        "status": "PASS", "fixture": str(output_path), "fixture_sha256": sha256(encoded),
        "source_topology_sha256": proof["topology_sha256"], "component_id": patch["component_id"],
        "polygons": len(source_polygon_records), "roots": len(root_authority),
        "boundary_roots": len(boundary_root_ids), "interior_roots": len(interior_root_ids),
        "component_arcs": len(component_arc_records), "boundary_arcs": len(boundary_arc_records),
        "neighbor_polygons": len(neighbor_polygon_records), "final_triangles": len(final_triangles),
        "edge_records": len(internal_edges), "flips": final_state["flip_count"],
        "subcutoff": subcutoff,
        "volume_sha256": gate["volume_sha256"], "volume_revision": gate["volume_revision"],
        "raw_gate_sha256": gate_sha, "raw_ray_sha256": ray_sha,
    }, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # report a concise fail-closed extraction cause
        print(f"R10B_STAGE0_BLOCKED {type(exc).__name__}:{exc}", file=sys.stderr)
        raise SystemExit(3)
