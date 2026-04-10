import GrizzyClawCore
import SwiftUI

/// Shared SwiftUI app chrome for `swift run` and the Xcode `.app` host.
public struct GrizzyClawRootApp: App {
    public init() {}

    public var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

public struct ContentView: View {
    public init() {}

    public var body: some View {
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
