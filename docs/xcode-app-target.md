# Xcode + SwiftPM layout

The repo contains:

1. **`Package.swift`** — Swift Package Manager: libraries **GrizzyClawCore**, **GrizzyClawUI**, and executable product **GrizzyClaw** (target `RunGrizzy`).
2. **`GrizzyClawMac.xcodeproj`** — macOS **Application** target **GrizzyClawMac** with a **local package** reference (`.`) that links the **GrizzyClawUI** product. UI lives in the package; the app target only provides a thin `@main` in `App/MacHost/GrizzyClawMacApp.swift` (do **not** name this file `main.swift` — the Swift driver rejects `@main` in that case).

Requires **Xcode 15+** (local package reference / `XCLocalSwiftPackageReference`).

## Open the committed project

1. **File → Open…** → select `GrizzyClaw-mac/GrizzyClawMac.xcodeproj`.
2. Scheme **GrizzyClawMac** → **Run** (⌘R).

Or open **`Package.swift`** alone if you only want to hack SPM targets without building the `.app`.

## Archive: you want `GrizzyClawMac.app`, not a Swift Package archive

**Symptom:** **Product → Archive** produces **`…/Products/usr/local/bin/GrizzyClaw`** (or **GrizzyClawMac-Package** in Organizer) — that is the **Swift Package** executable, **not** a macOS app bundle.

**Cause:** Xcode was opened on the **package** (folder or **`Package.swift`**). Package archives only contain SPM products.

**Fix:**

1. **Close** the package-only window (or ignore it).
2. **File → Open…** and choose **`GrizzyClawMac.xcodeproj`** (the **`.xcodeproj`** file, not the folder root).
3. In the scheme picker, select **GrizzyClawMac** — the run destination can stay **My Mac** (that is correct for a Mac app).
4. Confirm the active scheme shows a **Mac app** icon and product **GrizzyClawMac.app** (not a plain “GrizzyClaw” tool icon from SPM-only schemes).
5. **Product → Archive**. In Organizer, **Distribute App** / **Show in Finder** — the archived product should be **`GrizzyClawMac.app`**.

**CLI archive (app bundle):**

```bash
xcodebuild -project GrizzyClawMac.xcodeproj -scheme GrizzyClawMac -configuration Release archive -archivePath ./build/GrizzyClawMac.xcarchive
```

The `.app` is at `build/GrizzyClawMac.xcarchive/Products/Applications/GrizzyClawMac.app`.

## Command-line build

With full Xcode selected (`xcode-select -s /Applications/Xcode.app/Contents/Developer`):

```bash
xcodebuild -project GrizzyClawMac.xcodeproj -scheme GrizzyClawMac -configuration Release build
```

## Why two entry points?

- **`swift run GrizzyClaw`** uses `Sources/RunGrizzy/RunGrizzyEntry.swift` (`@main struct … App`); the file must not be named `main.swift` (SwiftPM treats that name as top-level entry and conflicts with `@main`).
- **Xcode app** uses `App/MacHost/GrizzyClawMacApp.swift` with **`@NSApplicationDelegateAdaptor(GrizzyClawAppDelegate.self)`** so **`NSApp.setActivationPolicy(.regular)`** runs in **`applicationWillFinishLaunching`**, and **`SingleInstanceLock.acquireAdvisoryLock()`** runs shortly after **`applicationDidFinishLaunching`** (so the first window can appear before any lock warning on stderr). Then **`GrizzyClawRootScene()`** in `body`. Avoid delegating to **`GrizzyClawRootApp.main()`** from a custom `main` — that can leave a running process with no visible window on some setups.

Shared UI is in **`GrizzyClawUI`** (`GrizzyClawRootScene`).

## Entitlements & signing

- Target uses **Automatic** signing and **Generated Info.plist**; add entitlements (sandbox, hardened runtime) in Xcode when you prepare for notarization.
- Set your **Team** for release builds.

## CI

- SPM: `swift build` / `swift test` (when tests exist).
- App: `xcodebuild` as above on a macOS runner with Xcode.

## Troubleshooting: “Missing package product 'Yams'” or **'SwifCron'**

SwiftPM’s **package identity** comes from the dependency URL (often **lowercase**), not the repository display name. **`GrizzyClawCore`** must use:

```swift
.product(name: "Yams", package: "yams")
.product(name: "SwifCron", package: "swifcron")
```

Using `package: "Yams"` or `package: "SwifCron"` breaks resolution in Xcode. After pulling the fix: **File → Packages → Reset Package Caches**, then **Resolve Package Versions** (or close the project, delete Derived Data for this project, reopen).

## Troubleshooting: “Missing package product 'GrizzyClawUI'”

1. **Use the `.xcodeproj`**, not `Package.swift` alone, when you need the app target. The local package must resolve from the same folder as **`Package.swift`** (sibling of `GrizzyClawMac.xcodeproj`).
2. **File → Packages → Reset Package Caches**, then **File → Packages → Resolve Package Versions**.
3. Quit Xcode, delete **Derived Data** for this project (`~/Library/Developer/Xcode/DerivedData/…GrizzyClawMac…`), reopen **`GrizzyClawMac.xcodeproj`**, build again.
4. The project includes **`GrizzyClawMac.xcodeproj/project.xcworkspace/contents.xcworkspacedata`**. If that file is missing, Xcode’s embedded workspace can fail to attach the Swift package graph — restore it from git or recreate the standard `self:` workspace file.
5. From Terminal (sanity check):  
   `xcodebuild -project GrizzyClawMac.xcodeproj -resolvePackageDependencies`  
   You should see `GrizzyClawMac: … @ local` and `Yams` resolved. If that works but Xcode still errors, restart Xcode after step 2–3.

## Troubleshooting: build succeeds but no window

Older builds called **`exit(1)`** when **`grizzyclaw-mac.lock`** was busy (another `swift run`, second Xcode run, or Release without a `DEBUG` flag on SPM deps), so the process quit before any UI. **Current behavior:** the lock is **advisory only** — a warning is printed to **stderr** and the app **always continues** so a window can open. If you still see no window, check the Xcode **Debug area** for a crash or assert, confirm scheme **GrizzyClawMac** (not a package library), and try **Window** menu / **Bring All to Front**. Activation policy is applied in **`GrizzyClawAppDelegate.applicationWillFinishLaunching`** so the process is allowed to show a normal window.

The Xcode target sets **`NSSupportsAutomaticTermination`** and **`NSSupportsSuddenTermination`** to **NO** in the generated Info.plist (some templates default to behaviors that interact badly with SwiftUI’s first window). The app delegate returns **`false`** from **`applicationShouldTerminateAfterLastWindowClosed`** so startup is not cut short before the first window is registered. The main UI uses SwiftUI’s **`Window`** scene (single window) instead of **`WindowGroup`**.

If you are testing the **Python / PyInstaller** app (`dist/GrizzyClaw.app` in the other repo), these Swift changes do not apply — use **`GrizzyClaw-mac`** and **`GrizzyClawMac.xcodeproj`** for this UI.
