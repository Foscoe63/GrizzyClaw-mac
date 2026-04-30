import AVFoundation
import Foundation

struct AudioInputDevice: Identifiable, Equatable {
    let id: String
    let name: String

    static let systemDefaultID = "__system_default__"

    static let systemDefault = AudioInputDevice(
        id: systemDefaultID,
        name: "System default"
    )

    static func availableDevices() -> [AudioInputDevice] {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )

        var seen = Set<String>()
        var rows: [AudioInputDevice] = [.systemDefault]
        for device in session.devices.sorted(by: { $0.localizedName.localizedCaseInsensitiveCompare($1.localizedName) == .orderedAscending }) {
            let id = device.uniqueID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, !seen.contains(id) else { continue }
            seen.insert(id)
            rows.append(AudioInputDevice(id: id, name: device.localizedName))
        }
        return rows
    }

    static func resolve(preferredName: String?) -> AVCaptureDevice? {
        let trimmed = preferredName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, trimmed.caseInsensitiveCompare(systemDefault.name) != .orderedSame else {
            return AVCaptureDevice.default(for: .audio)
        }

        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )

        if let exact = session.devices.first(where: { $0.localizedName == trimmed }) {
            return exact
        }

        return session.devices.first {
            $0.localizedName.caseInsensitiveCompare(trimmed) == .orderedSame
        } ?? AVCaptureDevice.default(for: .audio)
    }
}
