# Local Persistent World Save Slice

**State:** implementation candidate; draft PR, not integrated. This bounded local persistence slice is aligned with the open P0.2 domain/save work. The label “P1.2” is not an approved roadmap phase and this document does not change roadmap decisions.

## Scope

The playable demo stores one local world slot, `sandbox-default`, under Godot `user://worlds/sandbox-default/`. The save is a versioned ordered command ledger plus world seed and SDF generator version. Meshes, scene nodes, camera state, streaming state, entities, simulation state and multiplayer data are not serialized. Existing seed/generator behavior, global command order, region ownership, streaming and LOD meshing remain the sources used to reconstruct derived meshes.

Each generation is written to a new `save-NNNNNNNN.tmp`, flushed, read back and validated, then renamed in the same directory to immutable `save-NNNNNNNN.json`. The outer JSON envelope is canonical sorted-key JSON and includes schema, generation, exact `payload_json` UTF-8 bytes and SHA-256 of those exact payload bytes. The payload is semantically validated for world/generator identity, safe integer metadata, at most 256 operations, ordered unique commands, supported CARVE/FILL modes, finite bounded centers/radii and consistent revision/sequence metadata. This avoids treating Godot 4.7 JSON integer-token float Variants as canonical lexical integers while retaining an exact payload-byte digest. A complete temporary generation can be recovered on load; an incomplete temporary is ignored when a prior valid generation exists. The newest two valid finalized generations are retained after a verified commit. Corrupt or incompatible saves are not partially applied; when an invalid existing save is found during startup, automatic saving is blocked to avoid overwriting potentially recoverable data.

Loading builds a candidate ledger in temporary state. Runtime load keeps the current ledger and published meshes until all full-rebuild targets have completed; the world seed and ledger are swapped immediately before coherent mesh publication. Failed rebuilds keep the old published world. Startup loads the validated ledger before the first world mesh build. P saves; O loads. Save/load are refused while an edit/rebuild transaction is in flight.

## Limits and recovery claims

- One local slot; schema 1 accepts only the current SDF generator version. There is no migration path yet.
- The current global ledger cap remains 256 accepted edits; sequence/revision history, including gaps from focused resets, is preserved.
- A SHA-256 detects accidental payload corruption; it is not authentication against a local user who can rewrite both payload and hash.
- Same-directory rename and retained generations protect against ordinary process interruption around a write. Godot's `FileAccess.flush()` does not establish an OS-level fsync or power-loss durability guarantee; sudden power loss, storage-controller behavior and filesystem recovery remain unqualified.
- No autosave, entity/simulation persistence, cross-device migration, cloud synchronization, save deletion UI or schema upgrade is included.
- Headless tests verify serialization, process restart, command replay and derived LOD mesh inputs. Owner GUI retest is still required for controls and visual reconstruction. No visual acceptance or release readiness is claimed.

## Test evidence expected for this candidate

Godot 4.7.2 focused persistence tests cover ordered round trip with sequence/revision gaps, negative/cross-region edits, save/load across separate engine processes, reconstructed samples, LOD0/LOD1 derived mesh generation, incomplete and complete temporary generations, corrupted bytes, unsupported schema and operation mode, 256-edit capacity, 257th rejection, and atomic rejection of malformed ledger restore. The repository validation script includes this suite. Results belong to the exact feature commit recorded in its implementation checkpoint.
