import GrizzyClawUI
import SwiftUI

/// Xcode `.app` target: use a normal `@main` `App` so SwiftUI creates the window (avoid `enum` + `App.main()`).
/// File must not be named `main.swift` — that name makes the Swift driver treat the file as script entry and breaks `@main`.
@main
struct GrizzyClawMacHost: App {
    @NSApplicationDelegateAdaptor(GrizzyClawAppDelegate.self) private var appDelegate

    init() {
        GrizzyClawLaunchDiagnostics.log("GrizzyClawMacHost.init")
    }

    var body: some Scene {
        GrizzyClawRootScene()
    }
}
