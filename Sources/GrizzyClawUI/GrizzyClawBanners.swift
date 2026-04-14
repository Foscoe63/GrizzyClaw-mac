import SwiftUI

/// Red strip matching Chat `statusLine` styling — use for errors across tabs.
public struct GrizzyClawStatusBanner: View {
    let text: String
    var recoverySuggestion: String?

    public init(text: String, recoverySuggestion: String? = nil) {
        self.text = text
        self.recoverySuggestion = recoverySuggestion
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(.caption)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let recoverySuggestion, !recoverySuggestion.isEmpty {
                Text(recoverySuggestion)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color.red.opacity(0.08))
    }
}

/// Secondary strip matching Chat `infoLine` styling.
public struct GrizzyClawInfoBanner: View {
    let text: String

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.06))
    }
}

/// Unified `loadError` / `saveError` surface for stores (Workspaces, Watchers, Config).
public struct GrizzyClawStoreErrorBanner: View {
    let loadError: String?
    let saveError: String?

    public init(loadError: String?, saveError: String?) {
        self.loadError = loadError
        self.saveError = saveError
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let loadError, !loadError.isEmpty {
                GrizzyClawStatusBanner(text: loadError)
            }
            if let saveError, !saveError.isEmpty {
                GrizzyClawStatusBanner(text: "Save failed: \(saveError)")
            }
        }
    }
}
