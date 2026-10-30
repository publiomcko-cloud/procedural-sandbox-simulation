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
A6_RAY_SHA = "327a87ee0608eb95a8b9492c98ff7a7038b88d7aba20be0bc833f32dae738a9d"
SCENARIO = "R9.2.RAY.CANONICAL_PICKER.v1"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def load_preserved(path: Path, expected: str) -> tuple[dict[str, Any], str, int]:
    data = path.read_bytes()
    digest = sha256(data)
    if digest != expected:
        raise ValueError(f"sha256_mismatch:{path}:{digest}:{expected}")
    controls = data.count(b"\x1f")
    return json.loads(data.replace(b"\x1f", b"\\u001f")), digest, controls


def main() -> int:
    if len(sys.argv) != 5:
        print("usage: extract_ray_reference_fixture.py <manifest.jsonl> <r9.7-candidate.json> <r10a-a6-ray.json> <output.json>", file=sys.stderr)
        return 2
    manifest_path, r97_path, a6_path, output_path = map(Path, sys.argv[1:])
    manifest_bytes = manifest_path.read_bytes()
    if sha256(manifest_bytes) != MANIFEST_SHA:
        raise ValueError("frozen_manifest_sha256_mismatch")
    manifest_rows = [json.loads(line) for line in manifest_bytes.splitlines() if line.strip()]
    row = next((item for item in manifest_rows if item.get("scenario_id") == SCENARIO), None)
    if row is None:
        raise ValueError("frozen_ray_scenario_missing")
    historical, r97_sha, r97_controls = load_preserved(r97_path, R97_ARTIFACT_SHA)
    a6, a6_sha, a6_controls = load_preserved(a6_path, A6_RAY_SHA)
    if historical.get("scenario_id") != SCENARIO or a6.get("scenario_id") != SCENARIO:
        raise ValueError("ray_scenario_identity_mismatch")
    if historical.get("manifest_sha256") != MANIFEST_SHA:
        raise ValueError("historical_candidate_manifest_mismatch")
    if historical.get("source_file_sha256") != "334db9e3e9dfe3aca4a590845ba6b792629d204c0f1d6a3fc8a3898e7cbb020a":
        raise ValueError("historical_candidate_source_mismatch")
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
            "source_report_claim": "0/25 hit/miss disagreements; per-ray result rows were not present in the preserved Candidate D artifact.",
            "candidate_mesh_sha256": historical.get("candidate_mesh_sha256"),
            "raw_candidate_artifact_sha256": r97_sha,
            "raw_candidate_artifact_u001f_count": r97_controls,
            "recorded_hit_miss_disagreements": 0,
            "recorded_ray_count": 25,
            "raw_per_ray_outcomes_available": False,
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
        "interpretation_limit": "The R9.7 0/25 value is a report-recorded historical result; exact per-ray outcomes were not in the preserved Candidate D JSON. R10-B D3 must independently replay the exact pinned Candidate D mesh and current frozen ray grid.",
    }
    encoded = (json.dumps(fixture, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n").encode("utf-8")
    if output_path.exists():
        raise FileExistsError(f"refusing_to_overwrite:{output_path}")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(encoded)
    print(json.dumps({"status": "PASS", "output": str(output_path), "sha256": sha256(encoded), "rays": len(rays), "r9_7_candidate_mesh_sha256": historical.get("candidate_mesh_sha256"), "r9_7_reported_mismatches": 0, "r10a_a6_mismatches": a6_compare.get("hit_miss_disagreements"), "a6_mesh_sha256": a6.get("mesh_case", {}).get("geometry", {}).get("mesh_sha256")}, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"R10B_RAY_FIXTURE_BLOCKED {type(exc).__name__}:{exc}", file=sys.stderr)
        raise SystemExit(3)
