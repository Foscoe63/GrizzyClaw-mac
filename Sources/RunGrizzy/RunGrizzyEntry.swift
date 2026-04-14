import GrizzyClawUI
import SwiftUI

/// SPM executable entry. **Do not** name this file `main.swift` — that name is reserved and
/// conflicts with `@main` (`'main' attribute cannot be used in a module that contains top-level code`).
@main
struct RunGrizzyEntry: App {
    @NSApplicationDelegateAdaptor(GrizzyClawAppDelegate.self) private var appDelegate

    init() {
        GrizzyClawLaunchDiagnostics.log("RunGrizzyEntry.init")
    }

    var body: some Scene {
        GrizzyClawRootScene()
    }
}
