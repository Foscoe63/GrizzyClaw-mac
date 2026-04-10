# GrizzyClaw (macOS, Swift)

Native macOS rebuild of [GrizzyClaw](../GrizzyClaw) using Swift. This repository is a **sibling** to the Python/PyInstaller app: the legacy build stays in `../GrizzyClaw` and is unchanged.

## Layout

| Path | Role |
|------|------|
| `Sources/GrizzyClawCore/` | Shared models, services, persistence (no UI). |
| `Sources/GrizzyClaw/` | SwiftUI app entry (`swift run` executable). |
| `docs/parity-checklist.md` | Feature parity vs the Python app (living checklist). |
| `docs/xcode-app-target.md` | How to add a real `.app` bundle in Xcode. |

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

- Follow **[docs/xcode-app-target.md](docs/xcode-app-target.md)** to add a macOS App target (`.app`, signing).
- Track **[docs/parity-checklist.md](docs/parity-checklist.md)** while porting features from `../GrizzyClaw`.

## Relationship to the Python app

- **Bundle ID placeholder**: `com.grizzyclaw.macos` — change before App Store or notarization.
- No shared git history required; keep releases independent until you intentionally align versions.
