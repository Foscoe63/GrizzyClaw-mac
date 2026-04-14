import AppKit
import GrizzyClawCore

/// AppKit bootstrap for SwiftUI lifecycle: activation policy and single-instance lock must run in
/// `applicationWillFinishLaunching`, not in `App.init()` (too early on some macOS/Xcode combos → no window, immediate exit).
public final class GrizzyClawAppDelegate: NSObject, NSApplicationDelegate {
    public override init() {
        super.init()
        GrizzyClawLaunchDiagnostics.log("GrizzyClawAppDelegate.init")
    }

    public func applicationWillFinishLaunching(_ notification: Notification) {
        GrizzyClawLaunchDiagnostics.log("applicationWillFinishLaunching (before setActivationPolicy)")
        let policyOk = NSApp.setActivationPolicy(.regular)
        GrizzyClawLaunchDiagnostics.log("setActivationPolicy(.regular) -> \(policyOk)")
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        GrizzyClawLaunchDiagnostics.log("applicationDidFinishLaunching windows.count=\(NSApp.windows.count)")
        NSApp.activate(ignoringOtherApps: true)
        // Let SwiftUI create the NSWindow first; then take the advisory lock (stderr message won’t precede a blank screen)
        // and force windows forward — some setups leave the process running with no visible window otherwise.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            GrizzyClawLaunchDiagnostics.log("postLaunch: before SingleInstanceLock + orderFront")
            SingleInstanceLock.acquireAdvisoryLock()
            for window in NSApp.windows {
                window.makeKeyAndOrderFront(nil)
            }
            GrizzyClawLaunchDiagnostics.log("postLaunch: after orderFront, windows.count=\(NSApp.windows.count)")
        }
    }

    /// Must be `false` here: returning `true` with SwiftUI `WindowGroup`/`Window` has been observed to end the
    /// process during startup before the first window is fully registered (build succeeds, app “stops”, no UI).
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
