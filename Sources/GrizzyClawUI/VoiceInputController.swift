@preconcurrency import AVFoundation
import Foundation
import GrizzyClawCore

@MainActor
final class VoiceInputController: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var lastTranscript = ""

    private let captureQueue = DispatchQueue(label: "grizzyclaw.voice.capture")
    private var captureSession: AVCaptureSession?
    private var audioFileOutput: AVCaptureAudioFileOutput?
    private var currentRecordingURL: URL?
    private var transcriptionProvider: String = "openai"
    private var transcriptHandler: ((String) -> Void)?
    private var errorHandler: ((String) -> Void)?

    func toggle(
        preferredDeviceName: String?,
        transcriptionProvider: String,
        onTranscript: @escaping (String) -> Void,
        onError: @escaping (String) -> Void
    ) {
        if isRecording {
            stopRecording()
        } else {
            Task {
                await startRecording(
                    preferredDeviceName: preferredDeviceName,
                    transcriptionProvider: transcriptionProvider,
                    onTranscript: onTranscript,
                    onError: onError
                )
            }
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        audioFileOutput?.stopRecording()
        isRecording = false
    }

    private func startRecording(
        preferredDeviceName: String?,
        transcriptionProvider: String,
        onTranscript: @escaping (String) -> Void,
        onError: @escaping (String) -> Void
    ) async {
        transcriptHandler = onTranscript
        errorHandler = onError
        lastTranscript = ""
        self.transcriptionProvider = transcriptionProvider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard await requestMicrophonePermission() else { return }
        guard let device = AudioInputDevice.resolve(preferredName: preferredDeviceName) else {
            finishWithError("No microphone input device is available.")
            return
        }

        cleanup()

        do {
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("m4a")
            let session = AVCaptureSession()
            session.beginConfiguration()
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            } else {
                throw NSError(domain: "VoiceInputController", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not add the selected microphone input."])
            }

            let output = AVCaptureAudioFileOutput()
            if session.canAddOutput(output) {
                session.addOutput(output)
            } else {
                throw NSError(domain: "VoiceInputController", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not capture audio from the selected microphone."])
            }
            session.commitConfiguration()
            captureSession = session
            audioFileOutput = output
            currentRecordingURL = outputURL
            isRecording = true
            captureQueue.async {
                session.startRunning()
                output.startRecording(to: outputURL, outputFileType: .m4a, recordingDelegate: self)
            }
        } catch {
            finishWithError(error.localizedDescription)
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        let micGranted = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
        guard micGranted else {
            finishWithError("Microphone access was denied. Enable it in System Settings > Privacy & Security > Microphone.")
            return false
        }
        return true
    }

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                self.finishWithError(error.localizedDescription)
                return
            }
            self.captureSession?.stopRunning()
            await self.transcribeRecording(at: outputFileURL)
        }
    }

    private func finishWithError(_ message: String) {
        cleanup()
        isRecording = false
        errorHandler?(message)
    }

    private func transcribeRecording(at url: URL) async {
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        guard transcriptionProvider == "openai" else {
            finishWithError("Voice transcription currently supports the OpenAI provider only in the mac app. Change `transcription_provider` to `openai` in Settings.")
            return
        }

        let secrets = UserConfigLoader.loadSecretsWithKeychainLenient()
        guard let apiKey = secrets.openaiApiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty else {
            finishWithError("OpenAI transcription needs an `openai_api_key` in config or Keychain.")
            return
        }

        do {
            let transcript = try await OpenAITranscriptionClient.transcribeAudio(fileURL: url, apiKey: apiKey)
            lastTranscript = transcript
            cleanup()
            guard !transcript.isEmpty else {
                errorHandler?("No speech was detected. Try again and speak a little closer to the microphone.")
                return
            }
            transcriptHandler?(transcript)
        } catch {
            finishWithError(error.localizedDescription)
        }
    }

    private func cleanup() {
        captureSession?.stopRunning()
        captureSession = nil
        audioFileOutput = nil
        currentRecordingURL = nil
    }
}

private enum OpenAITranscriptionClient {
    private struct Response: Decodable {
        let text: String
    }

    static func transcribeAudio(fileURL: URL, apiKey: String) async throws -> String {
        let fileData = try Data(contentsOf: fileURL)
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        appendField(named: "model", value: "whisper-1", to: &body, boundary: boundary)
        appendFile(named: "file", filename: fileURL.lastPathComponent, mimeType: "audio/m4a", data: fileData, to: &body, boundary: boundary)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "OpenAITranscriptionClient", code: 1, userInfo: [NSLocalizedDescriptionKey: "Transcription failed: no HTTP response."])
        }
        guard (200...299).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "OpenAITranscriptionClient", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Transcription failed: \(message)"])
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func appendField(named name: String, value: String, to body: inout Data, boundary: String) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(value)\r\n".data(using: .utf8)!)
    }

    private static func appendFile(named name: String, filename: String, mimeType: String, data: Data, to body: inout Data, boundary: String) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
    }
}
