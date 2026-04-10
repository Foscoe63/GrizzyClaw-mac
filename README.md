# GrizzyClaw (macOS, Swift)

Native macOS rebuild of [GrizzyClaw](../GrizzyClaw) using Swift. This repository is a **sibling** to the Python/PyInstaller app: the legacy build stays in `../GrizzyClaw` and is unchanged.

## Layout

| Path | Role |
|------|------|
| `Sources/GrizzyClawCore/` | Shared models, services, persistence (no UI). |
| `Sources/GrizzyClaw/` | SwiftUI app entry (`swift run` executable). |

## Requirements

- macOS 13+
- Swift 5.9+ (Xcode 15+)

## Build and run

```bash
cd GrizzyClaw-mac
swift build
swift run GrizzyClaw
```

## Next steps

- Add an **Xcode** macOS App target (`.app` bundle, icons, signing) that depends on `GrizzyClawCore` via local SPM, or open this folder in Xcode (**File → Open** `Package.swift`).
- Define **parity** with the Python app (workspaces, agent, watchers) in issues or `docs/` as you implement.

## Relationship to the Python app

- **Bundle ID placeholder**: `com.grizzyclaw.macos` — change before App Store or notarization.
- No shared git history required; keep releases independent until you intentionally align versions.
