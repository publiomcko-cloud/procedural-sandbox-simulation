#!/usr/bin/env python3
"""Freeze the R9.7/R10-A ray comparison inputs and provenance."""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path
from typing import Any

MANIFEST_SHA = "1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972"
R97_ARTIFACT_SHA = "87623cd4a55f27a0677d522056b02f847e24409755eb4a227cbde57c77d579ec"
R97_STDOUT_SHA = "343753e424bce61edf764f4fe634f917789739f6565999bd0616a7223580fefa"
A6_RAY_SHA = "327a87ee0608eb95a8b9492c98ff7a7038b88d7aba20be0bc833f32dae738a9d"
SCENARIO = "R9.2.RAY.CANONICAL_PICKER.v1"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def parse_vector3(value: Any) -> list[float]:
    if not isinstance(value, str) or not (value.startswith("(") and value.endswith(")")):
        raise ValueError(f"vector3_encoding_invalid:{value!r}")
    parts = [part.strip() for part in value[1:-1].split(",")]
    if len(parts) != 3:
        raise ValueError(f"vector3_component_count_invalid:{value!r}")
    return [float(part) for part in parts]


def load_preserved(path: Path, expected: str) -> tuple[dict[str, Any], str, int]:
    data = path.read_bytes()
    digest = sha256(data)
    if digest != expected:
        raise ValueError(f"sha256_mismatch:{path}:{digest}:{expected}")
    controls = data.count(b"\x1f")
    return json.loads(data.replace(b"\x1f", b"\\u001f")), digest, controls


def main() -> int:
    if len(sys.argv) != 6:
        print("usage: extract_ray_reference_fixture.py <manifest.jsonl> <r9.7-candidate.json> <r9.7-d3.5-stdout.txt> <r10a-a6-ray.json> <output.json>", file=sys.stderr)
        return 2
    manifest_path, r97_path, r97_stdout_path, a6_path, output_path = map(Path, sys.argv[1:])
    manifest_bytes = manifest_path.read_bytes()
    if sha256(manifest_bytes) != MANIFEST_SHA:
        raise ValueError("frozen_manifest_sha256_mismatch")
    manifest_rows = [json.loads(line) for line in manifest_bytes.splitlines() if line.strip()]
    row = next((item for item in manifest_rows if item.get("scenario_id") == SCENARIO), None)
    if row is None:
        raise ValueError("frozen_ray_scenario_missing")
    historical, r97_sha, r97_controls = load_preserved(r97_path, R97_ARTIFACT_SHA)
    stdout_bytes = r97_stdout_path.read_bytes()
    stdout_sha = sha256(stdout_bytes)
    if stdout_sha != R97_STDOUT_SHA:
        raise ValueError(f"R9.7_D3.5_stdout_sha256_mismatch:{stdout_sha}:{R97_STDOUT_SHA}")
    if b"\x1f" in stdout_bytes:
        raise ValueError("R9.7_D3.5_stdout_contains_raw_json_control")
    ray_records = []
    summary_records = []
    legacy_records = []
    for line in stdout_bytes.splitlines():
        if line.startswith(b"R95_RAY "):
            ray_records.append(json.loads(line[len(b"R95_RAY "):]))
        elif line.startswith(b"R95_RAY_SUMMARY "):
            summary_records.append(json.loads(line[len(b"R95_RAY_SUMMARY "):]))
        elif line.startswith(b"R95_LEGACY_SCAN_COMPARISON "):
            legacy_records.append(json.loads(line[len(b"R95_LEGACY_SCAN_COMPARISON "):]))
    a6, a6_sha, a6_controls = load_preserved(a6_path, A6_RAY_SHA)
    if historical.get("scenario_id") != SCENARIO or a6.get("scenario_id") != SCENARIO:
        raise ValueError("ray_scenario_identity_mismatch")
    if historical.get("manifest_sha256") != MANIFEST_SHA:
        raise ValueError("historical_candidate_manifest_mismatch")
    if historical.get("source_file_sha256") != "334db9e3e9dfe3aca4a590845ba6b792629d204c0f1d6a3fc8a3898e7cbb020a":
        raise ValueError("historical_candidate_source_mismatch")
    if len(ray_records) != 25 or len(summary_records) != 1 or len(legacy_records) != 1:
        raise ValueError(f"R9.7_ray_record_count_mismatch:{len(ray_records)}:{len(summary_records)}:{len(legacy_records)}")
    summary = summary_records[0]
    legacy = legacy_records[0]
    if summary.get("candidate_mesh_sha256") != historical.get("candidate_mesh_sha256") or summary.get("manifest_sha") != MANIFEST_SHA:
        raise ValueError("R9.7_ray_summary_identity_mismatch")
    if summary.get("ray_count") != 25 or summary.get("roi_scoped_hit_miss_disagreements") != 0:
        raise ValueError("R9.7_roi_scoped_ray_gate_mismatch")
    expected_legacy_indices = [2, 8, 9, 13, 14, 18, 19, 23, 24]
    if legacy.get("ray_count") != 25 or legacy.get("finite_scan_hit_miss_disagreements") != 9 or legacy.get("finite_scan_disagreement_indices") != expected_legacy_indices:
        raise ValueError("R9.7_full_ray_legacy_scan_mismatch")
    a6_compare = a6.get("ray_comparison", {})
    if a6_compare.get("ray_count") != 25 or a6_compare.get("hit_miss_disagreements") != 9:
        raise ValueError("R10A_A6_expected_ray_result_mismatch")

    grid = row["ray_grid"]
    rays = []
    index = 0
    for x in grid["x"]:
        for z in grid["z"]:
            rays.append({
                "ray_index": index,
                "origin": [float(x), float(grid["origin_y"]), float(z)],
                "direction": [float(v) for v in grid["direction"]],
                "length": float(grid["length"]),
            })
            index += 1
    if len(rays) != 25:
        raise ValueError(f"ray_count_mismatch:{len(rays)}")
    run_ids = {str(item.get("run_id", "")) for item in ray_records}
    for index, item in enumerate(ray_records):
        if item.get("candidate") != "D" or item.get("source_sha") != historical.get("source_sha") or item.get("ray_index") != index or item.get("roi_hit_miss_disagrees") is not False:
            raise ValueError(f"R9.7_ray_row_invalid:{index}")
        ray_value = item.get("ray", {})
        expected_ray = rays[index]
        actual_ray = {"origin": parse_vector3(ray_value.get("origin")), "direction": parse_vector3(ray_value.get("direction")), "length": float(ray_value.get("length", -1.0))}
        expected_ray_value = {"origin": expected_ray["origin"], "direction": expected_ray["direction"], "length": expected_ray["length"]}
        if actual_ray != expected_ray_value:
            raise ValueError(f"R9.7_ray_grid_row_mismatch:{index}:{actual_ray}:{expected_ray_value}")
    if len(run_ids) != 1 or "" in run_ids:
        raise ValueError("R9.7_ray_run_id_mismatch")
    fixture = {
        "schema": "P3.1.R10B.RayReferenceFixture.v1",
        "scenario_id": SCENARIO,
        "manifest_sha256": MANIFEST_SHA,
        "ray_grid": grid,
        "rays": rays,
        "historical_r9_7": {
            "source_sha": historical.get("source_sha"),
            "source_file_sha256": historical.get("source_file_sha256"),
            "source_report": "docs/reports/P3-1-R9.7-D3-CAMPAIGN-CLOSEOUT.md",
            "source_report_claim": "0/25 ROI-scoped hit/miss disagreements, with 9/25 disagreements under the separate full-ray finite-scan comparator.",
            "candidate_mesh_sha256": historical.get("candidate_mesh_sha256"),
            "raw_candidate_artifact_sha256": r97_sha,
            "raw_candidate_artifact_u001f_count": r97_controls,
            "raw_d3_5_stdout_sha256": stdout_sha,
            "raw_r95_ray_record_count": len(ray_records),
            "raw_r95_ray_run_id": next(iter(run_ids)),
            "roi_scoped_hit_miss_disagreements": summary.get("roi_scoped_hit_miss_disagreements"),
            "roi_scoped_disagreement_indices": [int(item["ray_index"]) for item in ray_records if item.get("roi_hit_miss_disagrees")],
            "full_ray_finite_scan_hit_miss_disagreements": legacy.get("finite_scan_hit_miss_disagreements"),
            "full_ray_finite_scan_disagreement_indices": legacy.get("finite_scan_disagreement_indices"),
            "recorded_ray_count": 25,
            "raw_per_ray_outcomes_available": True,
            "roi_scoped_ray_records": ray_records,
            "full_ray_legacy_scan_summary": legacy,
            "actual_mesh_topology": historical.get("actual_mesh_topology"),
            "candidate_topology": historical.get("candidate_metrics", {}).get("candidate_topology"),
        },
        "r10a_a6": {
            "raw_artifact_sha256": a6_sha,
            "raw_artifact_u001f_count": a6_controls,
            "mesh_sha256": a6.get("mesh_case", {}).get("geometry", {}).get("mesh_sha256"),
            "volume_sha256": a6.get("mesh_case", {}).get("volume_sha256"),
            "payload_sha256": a6.get("mesh_case", {}).get("payload_sha256"),
            "hit_miss_disagreements": a6_compare.get("hit_miss_disagreements"),
            "ray_count": a6_compare.get("ray_count"),
            "ray_outcomes": a6_compare.get("rays"),
        },
        "interpretation_limit": "R9.7 preserves 25 raw R95_RAY records for the ROI-scoped oracle and a separate full-ray finite-scan comparison. The R10A 9/25 number is the latter metric, not a conflicting geometry result. R10-B recomputes both scopes from the exact pinned Candidate D/A6 meshes.",
    }
    encoded = (json.dumps(fixture, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n").encode("utf-8")
    if output_path.exists():
        raise FileExistsError(f"refusing_to_overwrite:{output_path}")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(encoded)
    print(json.dumps({"status": "PASS", "output": str(output_path), "sha256": sha256(encoded), "rays": len(rays), "r9_7_candidate_mesh_sha256": historical.get("candidate_mesh_sha256"), "r9_7_roi_mismatches": summary.get("roi_scoped_hit_miss_disagreements"), "r9_7_full_ray_mismatches": legacy.get("finite_scan_hit_miss_disagreements"), "r10a_a6_full_ray_mismatches": a6_compare.get("hit_miss_disagreements"), "a6_mesh_sha256": a6.get("mesh_case", {}).get("geometry", {}).get("mesh_sha256")}, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"R10B_RAY_FIXTURE_BLOCKED {type(exc).__name__}:{exc}", file=sys.stderr)
        raise SystemExit(3)
