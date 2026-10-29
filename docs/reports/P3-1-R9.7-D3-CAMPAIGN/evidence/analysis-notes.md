# Evidence post-processing notes

These notes cover local post-processing only; none launched Godot or changed candidate source or frozen inputs.

- Initial topology-signature extraction treated `patch_artifact` as a path, while the captured record stores it as a dictionary with a `path` field. The extraction script was corrected to read `patch_artifact.path` and `multi_cell_patch_artifact.path`.
- A first attempt to parse the full topology diagnostic JSON with Python's strict JSON parser failed on a literal control character present in that legacy artifact. The existing artifact was parsed with PowerShell `ConvertFrom-Json`, reduced to the two required hash identities, and the derived signature was then computed from captured D3.5 stdout and verified artifact bytes.
- Neither post-processing issue affected any source pin, Godot process, geometry attempt, or original raw record. The final script, its small extracted identity record, output signature, and final checksums are included.
