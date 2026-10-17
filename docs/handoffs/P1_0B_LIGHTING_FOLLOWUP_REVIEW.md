# Independent review handoff — Issue #89 lighting follow-up

Review the exact head of `fix/p1-0b-terrain-depth-lighting` against `13d08b828553df4a3b2bb9d3eb783b4cc3f45beb`.

Inspect the complete diff and confirm the change is limited to the lighting balance, its tests/capture helper, paired visual evidence and focused documentation. Verify the new key orientation and ambient/fill balance in Godot 4.7.2 Compatibility assumptions; confirm shaded green terrain remains, both shadow maps remain off, and no streaming, SDF, chunk, control, persistence or networking implementation changed. Review the paired PNGs and JSON for identical seed, viewport and camera poses; assess the shadow cost/result as measured evidence, not a universal performance claim. Run `scripts/validate.ps1` with the pinned Godot 4.7.2 binary.

Do not access protected C:/G: paths, perform F2-G1 operations, alter the VM/ACLs, merge, release, or treat automated captures as owner GUI acceptance. Keep all five F2-G1 operational holds unchanged. Report exact candidate SHA, parent, changed paths, test counts, image evidence, defects and residual visual/performance limitations.
