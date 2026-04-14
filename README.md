# GrizzyClaw (macOS, Swift)

Native macOS rebuild of [GrizzyClaw](../GrizzyClaw) using Swift. This repository is a **sibling** to the Python/PyInstaller app: the legacy build stays in `../GrizzyClaw` and is unchanged.

## Layout

| Path | Role |
|------|------|
| `Sources/GrizzyClawCore/` | `AppInfo`, **`GrizzyClawPaths`**, **`WorkspaceActivePersistence`**, **`UserConfigLoader`** (YAML subset via **Yams**). |
| `Sources/GrizzyClawUI/` | Tabbed shell (Workspaces / Chat / Config), **`WorkspaceStore`**, **`ConfigStore`**, Finder actions. |
| `Sources/RunGrizzy/` | Thin `swift run` / CLI entry (`GrizzyClaw` executable product). |
| `App/MacHost/` | Thin `@main` host for the **Xcode** `.app` target only. |
| `GrizzyClawMac.xcodeproj/` | Committed Xcode project (scheme **GrizzyClawMac**), local SPM at `.` → **GrizzyClawUI**. |
| `docs/parity-checklist.md` | Feature parity vs the Python app (living checklist). |
| `docs/xcode-app-target.md` | More detail on the Xcode + SPM setup. |

## Requirements

- macOS 13+
- Swift 5.9+ (**Xcode 15+** for the checked-in `.xcodeproj`; CLI `swift` alone is enough for SPM)

## Build and run (SwiftPM)

```bash
cd GrizzyClaw-mac
swift build
swift run GrizzyClaw
```

### Control plane & diagnostics (Osaurus-style)

GrizzyClaw includes a **localhost HTTP server** (SwiftNIO) and a **doctor** report describing paths, inference mode, and sandbox expectations — aligned with the “infrastructure & runtime” surface from apps like Osaurus. **On Apple silicon**, you can also use **on-device MLX** (`llm_provider: mlx` in workspace config, Hugging Face model id in `llm_model` / `mlx_model`); weights cache under `~/.grizzyclaw/mlx_models/` by default, or set **`mlx_models_directory`** in `~/.grizzyclaw/config.yaml` (or workspace) to use another folder. A **Linux VM sandbox** is not part of this app.

- **Print health JSON** (no server):

  ```bash
  swift run GrizzyClawCLI doctor
  swift run GrizzyClawCLI doctor --pretty
  ```

- **Serve** `GET /health` and `GET /doctor` on loopback (default port **18765**):

  ```bash
  swift run GrizzyClawCLI serve
  swift run GrizzyClawCLI serve --port 18765 --bind 127.0.0.1
  ```

  Stop with **Enter**. Inference is via your configured providers (remote HTTP APIs, or **mlx** on Apple silicon).

`swift test` runs the package’s XCTest targets from the command line when using a full Swift toolchain with the macOS SDK.

## Build the `.app` (Xcode)

1. Open **`GrizzyClawMac.xcodeproj`** in Xcode (double-click or **File → Open**).
2. Select the **GrizzyClawMac** scheme and **Product → Run** (⌘R).

Command line (full Xcode installed, not only Command Line Tools):

```bash
cd GrizzyClaw-mac
xcodebuild -project GrizzyClawMac.xcodeproj -scheme GrizzyClawMac -configuration Debug build
```

## Next steps

- Track **[docs/parity-checklist.md](docs/parity-checklist.md)** while porting features from `../GrizzyClaw`.

## Relationship to the Python app

- **Bundle ID** (Xcode target): `com.grizzyclaw.macos` — change before App Store or notarization.
- No shared git history required; keep releases independent until you intentionally align versions.
