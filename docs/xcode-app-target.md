# Adding a macOS `.app` bundle (Xcode)

The SwiftPM package builds a runnable executable with `swift run GrizzyClaw`. For a proper **Application** (icons, sandbox, signing, notarization, TestFlight/App Store), add an **Xcode macOS App** target that depends on this package.

## Option A — Open the package in Xcode (fastest)

1. Install **Xcode 15+** (Swift 5.9+).
2. **File → Open…** and select `GrizzyClaw-mac/Package.swift`.
3. Xcode shows the `GrizzyClaw` executable and `GrizzyClawCore` library; use **Product → Run** to debug the executable target.

This still produces a **command-line–style** run from Xcode unless you add an App target (see Option B).

## Option B — New macOS App project that links the package

1. **File → New → Project → macOS → App** (SwiftUI, Swift).
2. Product Name: e.g. `GrizzyClawApp`, Team/bundle ID: set your identifier (e.g. `com.yourorg.grizzyclaw.macos`).
3. Save the project **inside** `GrizzyClaw-mac/` (e.g. `GrizzyClaw-mac/App/GrizzyClawApp.xcodeproj`) or as a sibling folder — keep one repo.
4. **File → Add Package Dependencies… → Add Local…** and select the **folder** containing `Package.swift` (`GrizzyClaw-mac` root).
5. Add **GrizzyClawCore** (library) to the app target’s **Frameworks, Libraries, and Embedded Content**.
6. Replace the template `App` entry with a thin wrapper, or move `GrizzyClawApp` SwiftUI `@main` into the app target and remove the duplicate `executableTarget` from `Package.swift` when you’re ready (avoid two `@main`).

**Recommended long-term:** keep **business logic** in `GrizzyClawCore` and keep the Xcode app target as a thin **shell** (lifecycle, menus, sandbox entitlements).

## Entitlements & signing

- Enable **Hardened Runtime** for notarization.
- Add only entitlements you need (network client, user-selected files, etc.).
- Use **Automatic Signing** with your Apple Developer team for distribution builds.

## CI

- `xcodebuild -scheme <Scheme> -configuration Release build` after the app target exists.
- Or continue using `swift build` for the SPM-only path in CI until the App target is added.
