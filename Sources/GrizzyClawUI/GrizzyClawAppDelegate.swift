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
        logWindowDetails(phase: "applicationDidFinishLaunching")
        _ = NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // Let SwiftUI create the NSWindow first; then take the advisory lock (stderr message won’t precede a blank screen)
        // and force windows forward — some setups leave the process running with no visible window otherwise.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            GrizzyClawLaunchDiagnostics.log("postLaunch: before SingleInstanceLock + orderFront")
            self.logWindowDetails(phase: "postLaunch-before-orderFront")
            SingleInstanceLock.acquireAdvisoryLock()
            self.ensureWindowsAreVisible()
            self.logWindowDetails(phase: "postLaunch-after-orderFront")
            GrizzyClawLaunchDiagnostics.log("postLaunch: after orderFront, windows.count=\(NSApp.windows.count)")
        }
    }

    /// Must be `false` here: returning `true` with SwiftUI `WindowGroup`/`Window` has been observed to end the
    /// process during startup before the first window is fully registered (build succeeds, app “stops”, no UI).
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @MainActor
    private func ensureWindowsAreVisible() {
        let currentApp = NSRunningApplication.current
        currentApp.activate(options: [.activateAllWindows])

        for window in NSApp.windows {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            if shouldRecenter(window: window) {
                window.center()
            }
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
        }
    }

    @MainActor
    private func shouldRecenter(window: NSWindow) -> Bool {
        let frame = window.frame
        guard !frame.isEmpty else { return true }
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return false }
        return !screens.contains { screen in
            screen.visibleFrame.intersects(frame)
        }
    }

    @MainActor
    private func logWindowDetails(phase: String) {
        for (index, window) in NSApp.windows.enumerated() {
            let title = window.title.isEmpty ? "<untitled>" : window.title
            let frame = NSStringFromRect(window.frame)
            GrizzyClawLaunchDiagnostics.log(
                "\(phase) window[\(index)] title=\(title) visible=\(window.isVisible) mini=\(window.isMiniaturized) key=\(window.isKeyWindow) main=\(window.isMainWindow) frame=\(frame)"
            )
        }
    }
}
