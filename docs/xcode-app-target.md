# Xcode + SwiftPM layout

The repo contains:

1. **`Package.swift`** — Swift Package Manager: libraries **GrizzyClawCore**, **GrizzyClawUI**, and executable product **GrizzyClaw** (target `RunGrizzy`).
2. **`GrizzyClawMac.xcodeproj`** — macOS **Application** target **GrizzyClawMac** with a **local package** reference (`.`) that links the **GrizzyClawUI** product. UI lives in the package; the app target only provides a thin `@main` in `App/MacHost/main.swift`.

Requires **Xcode 15+** (local package reference / `XCLocalSwiftPackageReference`).

## Open the committed project

1. **File → Open…** → select `GrizzyClaw-mac/GrizzyClawMac.xcodeproj`.
2. Scheme **GrizzyClawMac** → **Run** (⌘R).

Or open **`Package.swift`** alone if you only want to hack SPM targets without building the `.app`.

## Command-line build

With full Xcode selected (`xcode-select -s /Applications/Xcode.app/Contents/Developer`):

```bash
xcodebuild -project GrizzyClawMac.xcodeproj -scheme GrizzyClawMac -configuration Release build
```

## Why two entry points?

- **`swift run GrizzyClaw`** uses `Sources/RunGrizzy/main.swift` → `GrizzyClawRootApp.main()`.
- **Xcode app** uses `App/MacHost/main.swift` → same call, so behavior matches without duplicating SwiftUI trees.

Shared UI is in **`GrizzyClawUI`**.

## Entitlements & signing

- Target uses **Automatic** signing and **Generated Info.plist**; add entitlements (sandbox, hardened runtime) in Xcode when you prepare for notarization.
- Set your **Team** for release builds.

## CI

- SPM: `swift build` / `swift test` (when tests exist).
- App: `xcodebuild` as above on a macOS runner with Xcode.
