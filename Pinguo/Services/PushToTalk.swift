@preconcurrency import AVFoundation
import Observation
@preconcurrency import Speech

/// Hold-to-speak recognition: on-device Speech framework first, ElevenLabs Scribe on the recorded audio if that fails.
@Observable
final class PushToTalk {
    private(set) var isRecording = false
    private(set) var partialTranscript = ""
    private(set) var errorMessage: String?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recordingFile: AVAudioFile?
    private var recordingURL: URL?
    private var locale = Locale(identifier: "zh-CN")
    private var finalTranscript = ""

    static func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        let microphone = await AVAudioApplication.requestRecordPermission()
        return speech && microphone
    }

    func start(locale: Locale) async {
        guard !isRecording else { return }
        errorMessage = nil
        partialTranscript = ""
        finalTranscript = ""
        self.locale = locale
        guard await Self.requestPermissions() else {
            errorMessage = "Allow microphone and speech recognition in Settings to speak."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.addsPunctuation = true
            let recognizer = SFSpeechRecognizer(locale: locale)
            if recognizer?.supportsOnDeviceRecognition == true { request.requiresOnDeviceRecognition = true }
            self.request = request

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            let url = URL.temporaryDirectory.appending(path: "utterance-\(UUID().uuidString).caf")
            recordingFile = try AVAudioFile(forWriting: url, settings: format.settings)
            recordingURL = url
            let file = recordingFile
            // The tap runs on the audio thread, so it must not inherit main-actor isolation.
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in
                request.append(buffer)
                try? file?.write(from: buffer)
            }
            engine.prepare()
            try engine.start()
            isRecording = true

            let owner = WeakOwner(self)
            task = recognizer?.recognitionTask(with: request) { @Sendable result, _ in
                guard let text = result?.bestTranscription.formattedString else { return }
                Task { @MainActor in owner.value?.receive(text) }
            }
        } catch {
            errorMessage = error.localizedDescription
            teardown()
        }
    }

    private func receive(_ text: String) {
        partialTranscript = text
        finalTranscript = text
    }

    /// Stops listening and returns the best transcript, falling back to cloud transcription when needed.
    func stop() async -> String {
        guard isRecording else { return "" }
        request?.endAudio()
        try? await Task.sleep(for: .milliseconds(450))
        let recognized = finalTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let audioURL = recordingURL
        teardown()
        if !recognized.isEmpty { return recognized }
        guard let audioURL else { return "" }
        do {
            let language = locale.identifier.hasPrefix("zh") ? "zho" : "eng"
            return try await ElevenLabsClient().transcribe(fileURL: audioURL, languageCode: language).text
        } catch {
            errorMessage = "Couldn't hear that. Try again or type instead."
            return ""
        }
    }

    func cancel() {
        teardown()
    }

    private func teardown() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        task?.cancel()
        task = nil
        request = nil
        recordingFile = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
    }
}

private final class WeakOwner: @unchecked Sendable {
    weak var value: PushToTalk?

    init(_ value: PushToTalk) {
        self.value = value
    }
}
