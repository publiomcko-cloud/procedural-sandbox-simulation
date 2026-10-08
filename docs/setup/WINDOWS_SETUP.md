# Windows 11 development environment

Reference setup: Windows 11, VS Code, PowerShell 7, Git, Python 3.11+ (optional for support scripts), Godot **4.7.2 stable standard build**, Codex VS Code extension. Windows host is the authoritative GUI/visual-test environment; WSL2 can be used for ancillary tooling, but avoid having two engines mutate the same `.godot` cache.

## 1. Prerequisites
- Install [Git for Windows](https://git-scm.com/download/win), [VS Code](https://code.visualstudio.com/), [PowerShell 7](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows), and [Godot 4.7.2 stable](https://godotengine.org/download/archive/4.7.2-stable/) (standard/non-.NET build; GDScript is primary).
- From VS Code Extensions install official Godot Tools and official Codex extension. Sign in to the Codex extension using the account/access method presented by the extension; the product's model/effort menu may change. Select your available **Luna / High** configuration if shown; do not assume this preset is universally exposed.
- Optional: Python 3.11+, GitHub CLI (`gh`) and 7-Zip. Do not install third-party Godot voxel addons yet. Verify publisher of every extension.
- Add the directory of `Godot_v4.7.2-stable_win64.exe` to PATH, or set `GODOT_BIN` to its full path.

```powershell
$env:GODOT_BIN = 'C:\Tools\Godot\Godot_v4.7.2-stable_win64.exe' # adjust path
& $env:GODOT_BIN --version
git --version
code --version
pwsh --version
```

## 2. Extract and establish Git repository
```powershell
New-Item -ItemType Directory -Force C:\Dev | Out-Null
Expand-Archive .\sandbox-sim-starter.zip -DestinationPath C:\Dev -Force
Set-Location C:\Dev\sandbox-sim-starter
git init
git add .
git commit -m 'chore: baseline architecture and phase-0 starter'
git branch -M main
```
For Git commit identity, run `git config user.name` and `git config user.email` if necessary. Do not set remote until you have chosen the repository.

## 3. Isolated developer worktree
```powershell
Set-Location C:\Dev\sandbox-sim-starter
git worktree add -b feat/phase0-prototype ../sandbox-sim-phase0 main
code ../sandbox-sim-phase0
```
Codex edits the feature worktree only. Keep main untouched. Review can use a separate detached worktree pointed at a supplied SHA. `git worktree list` shows active worktrees.

## 4. Verify project
```powershell
Set-Location C:\Dev\sandbox-sim-phase0
pwsh -File scripts/check-env.ps1
pwsh -File scripts/validate.ps1
& $env:GODOT_BIN --editor --path game
```
If `GODOT_BIN` is unset and `godot` is in PATH, scripts use `godot`. The bootstrap should display a basic titled 3D view; it is **not** generated terrain. For GUI opening use Godot Project Manager and import `game/project.godot` if preferred.

## 5. Rendering and architecture notes
- Windows local editor: use the standard 3D renderer and measure on the actual target GPU; on lower-end devices change renderer explicitly, document it and rerun benchmarks.
- CI/headless tests do not replace visual testing or gameplay collision inspection.
- Commit project source and authored data; ignore `.godot/`, `.import/`, binaries, user saves and temp files.
- Keep `res://` path casing stable. Use UTF-8, LF where possible, and no whitespace-only changes in feature reviews.

## 6. Troubleshooting
- Command not found: validate `GODOT_BIN` and re-open PowerShell after editing PATH.
- Import errors: run `--headless --editor --path game --import` first.
- Stale scene or extension artifacts: shut down editors before removing local `.godot/` cache; never purge saves or source.
- Windows execution policy: run `pwsh -File ...` from a PowerShell 7 terminal. Adjust local policy only if required by your organization.
- VS Code Codex model selection is UI/account-dependent; report the actually selected model and effort rather than assuming a fixed command.
