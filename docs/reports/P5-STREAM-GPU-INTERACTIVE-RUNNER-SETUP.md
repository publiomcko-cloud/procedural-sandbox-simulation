# P5 GPU interactive runner — isolated setup and acceptance

## Scope
- Existing C:\actions-runner Windows service remains unchanged and continues headless P4/P5 qualification.
- Install **another** runner from the official GitHub runner package at C:\actions-runner-gpu. Never copy .runner, .credentials, or the service runner folder.
- Register the new runner only to publiomcko-cloud/procedural-sandbox-simulation, with the extra label **gpu-interactive**. GitHub adds default self-hosted, Windows, and X64 labels. Name suggestion: sandbox-gpu-interactive.
- The second runner **must run under an already signed-in, unlocked Windows desktop session**, never as a service/Session 0. Prefer a separate non-admin Windows user without personal/sensitive files. Do not enable automatic Windows login and do not save GitHub registration tokens or passwords in the repo.
- The benchmark never requires synthetic keyboard/mouse; it uses a deterministic in-engine camera path. Runs open visible Godot windows, so avoid other interactive work during a graphics run.

## One-time registration (owner action, from desktop, PowerShell without elevation)
1. Sign into Windows locally (not Session 0). Open https://github.com/publiomcko-cloud/procedural-sandbox-simulation/settings/actions/runners/new , select Windows x64.
2. Follow GitHub's **current** Download and Configure commands but change the target directory to C:\actions-runner-gpu and use the newly downloaded official package. **Do not use** C:\actions-runner (that is the existing service).
3. In the registration prompts, choose a distinct runner name (e.g. sandbox-gpu-interactive) and enter the additional label gpu-interactive. Leave work directory _work. If offered service installation, answer **N**.
4. Once configured, in a normal PowerShell console run:

   ~~~powershell
   cd C:\actions-runner-gpu
   .\run.cmd
   ~~~

   Expect Connected to GitHub and Listening for Jobs. Keep the desktop signed in and unlocked for graphics runs; a disconnected, logged-off or locked/RDP-disconnected session is not a reliable GPU performance baseline.
5. The pending experimental P5 GPU interactive runner qualification workflow runs only after the gpu-interactive runner is available. Check that it passes its **real-screen, hardware-adapter, drawn-frames, screenshot, route and seed gates** before accepting any GUI FPS benchmark.
6. Optional: after the runner is proven functional, close run.cmd and install an **interactive-token**, least-privilege at-logon scheduled task from the checked-out experimental branch:

   ~~~powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\ci\configure-p5-gpu-runner-logon.ps1 -Install
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\ci\configure-p5-gpu-runner-logon.ps1 -Start
   ~~~

   Requires a logged-on desktop; does not turn on auto-login or save a Windows password. Run with -Remove to remove only this task. Use -Start only if no run.cmd instance is already listening.

## Workflow separation and evidence
- Service preflight: runs-on: [self-hosted, Windows, X64]; diagnostics only. A Session-0 result is **expected**, not a GPU qualification.
- Graphics acceptance: runs-on: [self-hosted, Windows, X64, gpu-interactive].
- Godot pinned to C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe, Compatibility renderer using actual Windows display, never --headless.
- Each GPU run gets a unique temporary APPDATA (no owner-world saves/mods), seed 424242, in-engine 18/54 m/s straight camera route, fixed simulated movement per frame. It outputs raw stdout/stderr, exact SHA, adapter/display receipts, PNG screen capture, and validated JSON.
- The setup does not alter world authority, mods, save schemas, P4/P5 gameplay, or main-branch workflows. Never merge experimental code without full regression qualification and owner acceptance.

## Caveats
- Headless CPU comparisons and rendered-GPU results are **separate evidence sets**. Engine.max_fps and fixed simulation input do not make OS/GPU scheduling or wall-clock frame timings bitwise deterministic.
- For GUI A/B comparisons, use the same physical monitor, resolution, scaling, power plan, rendering method, warmed/cold cache controls, and ABBA repeated route order. Save frame-time percentiles, stutter and screenshots.
- An online GitHub runner with arbitrary workflow access can execute code as the logged-on user. Restrict who can push workflows and do not use an admin/personal account for untrusted PR code. No arbitrary public-fork PR workflow should have access to the GPU label.
- If Windows is locked, use a physical/local desktop session rather than forcing or bypassing the lock screen. Never auto-unlock by storing a password.
