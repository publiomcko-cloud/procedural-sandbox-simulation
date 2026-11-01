# 2026-11-01 — R12-CXR R5-4 execution ID transcription correction

This append-only note supersedes the execution-ID text only in the pretarget and execution-checkout-correction checkpoints. Their source, target, gates, and prelaunch status remain unchanged.

The previous correction note transcribed one missing `8`. Direct extraction from both the external corrected dispatcher and its byte-identical repository evidence copy gives this exact literal:

```text
r5target2026110104a91e4f3e7c8f4f8f9a
```

The launcher SHA-256 remains `49dcfac759834002a7da04ab645b182e1e1c059970f164afc4541793e769949c`. Its launch-intent `execution_id`, Godot environment ID, enumeration-marker correlation, and terminal record all use the literal above. This was found during static prelaunch cross-check; the dispatcher has not been invoked, no Godot process has started, no target root exists, and R5 valid slot 4 remains available. The current open/draft PR identities were independently verified: #216 head `6407572f1ee9c57e2c530e0f021490d5a90ba8e3`; #217 head `35d15a6c525aae4ee7de8614a4e917cc0ae79f58` before this documentation commit. The target worktree remains detached at source `8e5211e0665b6f57839d5c7eeae51c28c64325f6` with clean tracked files.

Before any launch, repeat the exact-string extraction and equality check against the staged launch intent, then verify the result root is absent and the pushed draft PR head matches the final checkpoint commit. No prior checkpoint or raw evidence is rewritten. All five F2-G1 holds remain unchanged.
