import GrizzyClawCore
import SwiftUI

@main
struct GrizzyClawApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("GrizzyClaw")
                .font(.largeTitle.weight(.semibold))
            Text("Native macOS build (Swift)")
                .foregroundStyle(.secondary)
            Text("Version \(AppInfo.versionLabel)")
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
        }
        .frame(minWidth: 480, minHeight: 320)
        .padding(32)
    }
}
