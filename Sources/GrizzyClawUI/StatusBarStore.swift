import Foundation
import SwiftUI
import Combine
import GrizzyClawCore

/// Global UI state for the GrizzyClaw status bar (full-width bottom bar).
/// Parity with Python `main_window.py` (QStatusBar + session summary label).
@MainActor
public final class StatusBarStore: ObservableObject {
    @Published public private(set) var statusMessage: String = "Ready"
    @Published public private(set) var sessionStatus: String = ""

    private var messageTimer: Timer?

    public init() {}

    /// Shows a temporary message in the status bar (left side).
    /// Parity with `QStatusBar.showMessage(text, timeout)`.
    public func showMessage(_ text: String, timeoutMs: Int = 0) {
        GrizzyClawLog.debug("Status bar: \(text)")
        messageTimer?.invalidate()
        statusMessage = text

        if timeoutMs > 0 {
            messageTimer = Timer.scheduledTimer(withTimeInterval: Double(timeoutMs) / 1000.0, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    if self?.statusMessage == text {
                        self?.statusMessage = "Ready"
                    }
                }
            }
        }
    }

    /// Clears the status message immediately.
    public func clearMessage() {
        messageTimer?.invalidate()
        statusMessage = "Ready"
    }

    /// Updates the permanent session status label (right side).
    /// Parity with `_update_session_status` in `main_window.py`.
    public func updateSessionStatus(messages: Int, tokens: Int) {
        let tokK = tokens / 1000
        sessionStatus = "~\(messages) msgs, ~\(tokK)k tokens"
    }
}
