import AppKit
import SwiftUI

/// Parity with Python `BrowserDialog` (`grizzyclaw/gui/browser_dialog.py`): navigation, quick actions, custom Playwright-style actions, output log.
/// Playwright runs inside the Python app; this UI mirrors controls and logs the equivalent action payloads.
public struct BrowserMainView: View {
    public var theme: String

    @Environment(\.colorScheme) private var colorScheme

    @State private var urlField = ""
    @State private var fullPageScreenshot = false
    @State private var customActionIndex = 0
    @State private var selectorField = ""
    @State private var valueField = ""
    @State private var outputText = ""
    @State private var busy = false

    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false

    private static let customActions = ["click", "fill", "type", "press_key", "wait_for_selector"]

    private var isDark: Bool {
        AppearanceTheme.isEffectivelyDark(theme: theme, colorScheme: colorScheme)
    }

    private var palette: (fg: Color, summaryBg: Color, border: Color, accent: Color, inputBg: Color) {
        if isDark {
            return (
                Color.white,
                Color(red: 0.18, green: 0.18, blue: 0.18),
                Color(red: 0.23, green: 0.23, blue: 0.24),
                Color(red: 0.04, green: 0.52, blue: 1.0),
                Color(red: 0.23, green: 0.23, blue: 0.24)
            )
        }
        return (
            Color(red: 0.11, green: 0.11, blue: 0.12),
            Color(red: 0.96, green: 0.97, blue: 0.98),
            Color(red: 0.90, green: 0.90, blue: 0.92),
            Color(red: 0, green: 0.48, blue: 1),
            Color.white
        )
    }

    public init(theme: String) {
        self.theme = theme
    }

    public var body: some View {
        let p = palette
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Browser Automation")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(p.fg)

                statusBlock(p: p)

                GroupBox("Navigation") {
                    HStack(alignment: .firstTextBaseline) {
                        Text("URL:")
                        TextField("https://example.com", text: $urlField)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { navigate() }
                        Button("Go") { navigate() }
                            .keyboardShortcut(.defaultAction)
                            .disabled(busy)
                    }
                }

                GroupBox("Quick Actions") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Button("📸 Screenshot") { takeScreenshot() }
                            Toggle("Full Page", isOn: $fullPageScreenshot)
                            Button("📝 Get Text") { getPageText() }
                            Button("🔗 Get Links") { getPageLinks() }
                        }
                        .disabled(busy)
                        HStack {
                            Button("⬇️ Scroll Down") { scroll("down") }
                            Button("⬆️ Scroll Up") { scroll("up") }
                            Spacer()
                        }
                        .disabled(busy)
                    }
                }

                GroupBox("Custom Action") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Action:")
                            Picker("", selection: $customActionIndex) {
                                ForEach(Self.customActions.indices, id: \.self) { i in
                                    Text(Self.customActions[i]).tag(i)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: 280)
                        }
                        HStack {
                            Text("Selector:")
                            TextField("CSS selector (e.g., button.submit, #email)", text: $selectorField)
                                .textFieldStyle(.roundedBorder)
                        }
                        HStack {
                            Text("Value:")
                            TextField("Value (for fill/type actions)", text: $valueField)
                                .textFieldStyle(.roundedBorder)
                        }
                        HStack {
                            Button("▶️ Execute") { executeCustom() }
                                .disabled(busy)
                            Spacer()
                        }
                    }
                }

                GroupBox("Output") {
                    VStack(alignment: .leading, spacing: 8) {
                        ScrollView {
                            Text(outputText)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(minHeight: 200)
                        .padding(8)
                        .background(p.inputBg)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(p.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        Button("Clear Output") {
                            outputText = ""
                        }
                        .disabled(busy)
                    }
                }
            }
            .padding(20)
        }
        .background(isDark ? Color(red: 0.12, green: 0.12, blue: 0.12) : Color.white)
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    @ViewBuilder
    private func statusBlock(p _: (fg: Color, summaryBg: Color, border: Color, accent: Color, inputBg: Color)) -> some View {
        let greenBg = Color(red: 0.83, green: 0.93, blue: 0.85)
        let greenFg = Color(red: 0.08, green: 0.45, blue: 0.15)
        VStack(alignment: .leading, spacing: 6) {
            Text(
                "This window previews actions and shows the JSON that Playwright would receive. "
                    + "Chromium automation (including page screenshots) runs only in the Python GrizzyClaw app, not inside this native Mac build."
            )
            .font(.system(size: 14))
            .foregroundStyle(greenFg)
            Text("Use Python GrizzyClaw → 🌐 Browser Automation for real runs. “Go” below also opens the URL in your default browser.")
                .font(.system(size: 13))
                .foregroundStyle(greenFg.opacity(0.9))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(greenBg)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func log(_ line: String) {
        if outputText.isEmpty {
            outputText = line
        } else {
            outputText += "\n\n" + line
        }
    }

    /// Logs a preview stub (native Mac has no embedded Playwright/Chromium).
    private func runAction(_ action: String, params: [String: Any]) {
        busy = true
        log("[\(action)] ⏳ Preview (not executed in this app)…")

        if action == "navigate", let urlStr = params["url"] as? String, let opened = URL(string: urlStr) {
            NSWorkspace.shared.open(opened)
            log("[navigate] Opened in your default browser: \(urlStr)")
        }

        let payload = jsonString(params)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            let tail: String
            switch action {
            case "navigate":
                tail =
                    "[navigate] Automated Playwright navigation (cookies, in-page scripts, etc.) only runs in Python GrizzyClaw → 🌐 Browser Automation. "
                    + "Your default browser was opened for a quick manual view."
            case "screenshot":
                tail =
                    "[screenshot] Page screenshots need Chromium + Playwright. Use Python GrizzyClaw → 🌐 Browser Automation. "
                    + "This native app only shows the payload preview below."
            default:
                tail =
                    "[\(action)] Not executed here — no embedded Playwright/Chromium. "
                    + "Run in Python GrizzyClaw → 🌐 Browser Automation."
            }
            log(tail)
            log("Params:\n\(payload)")
            busy = false
        }
    }

    private func jsonString(_ obj: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(obj),
              let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .prettyPrinted]),
              let s = String(data: data, encoding: .utf8)
        else {
            return String(describing: obj)
        }
        return s
    }

    private func navigate() {
        var url = urlField.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.isEmpty {
            alertTitle = "No URL"
            alertMessage = "Please enter a URL."
            showAlert = true
            return
        }
        if !url.hasPrefix("http://"), !url.hasPrefix("https://") {
            url = "https://" + url
            urlField = url
        }
        runAction("navigate", params: ["url": url])
    }

    private func takeScreenshot() {
        runAction("screenshot", params: ["full_page": fullPageScreenshot])
    }

    private func getPageText() {
        runAction("get_text", params: ["selector": "body"])
    }

    private func getPageLinks() {
        runAction("get_links", params: [:])
    }

    private func scroll(_ direction: String) {
        runAction("scroll", params: ["direction": direction, "amount": 500])
    }

    private func executeCustom() {
        let action = Self.customActions[customActionIndex]
        let selector = selectorField.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = valueField.trimmingCharacters(in: .whitespacesAndNewlines)

        if selector.isEmpty, action != "press_key" {
            alertTitle = "No Selector"
            alertMessage = "Please enter a CSS selector."
            showAlert = true
            return
        }

        let params: [String: Any]
        switch action {
        case "click":
            params = ["selector": selector]
        case "fill":
            params = ["selector": selector, "value": value]
        case "type":
            params = ["selector": selector, "text": value]
        case "press_key":
            params = ["key": value.isEmpty ? "Enter" : value]
        case "wait_for_selector":
            params = ["selector": selector]
        default:
            params = [:]
        }
        runAction(action, params: params)
    }
}
