# GrizzyClaw (macOS, Swift)

Native macOS rebuild of [GrizzyClaw](../GrizzyClaw) using Swift. This repository is a **sibling** to the Python/PyInstaller app: the legacy build stays in `../GrizzyClaw` and is unchanged.

## Layout

| Path | Role |
|------|------|
| `Sources/GrizzyClawCore/` | `AppInfo`, **`GrizzyClawPaths`** (`~/.grizzyclaw` parity with Python). |
| `Sources/GrizzyClawUI/` | Shared SwiftUI (`GrizzyClawRootApp`, `ContentView`) for SPM + Xcode. |
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

Add XCTest targets later if you want `swift test` from CI; use **Xcode**’s test runner with the full macOS SDK for unit tests.

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
