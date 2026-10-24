import AVFoundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct TranslateAudioSheet: View {
    let onStart: () -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings
    @State private var recorder = AudioRecorder()
    @State private var pickedFile: URL?
    @State private var showsFilePicker = false
    @State private var adaptsToLevel = true
    @State private var title = ""
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Record or upload English. Pinguo transcribes it, translates each line into Mandarin and reads it back in your voice.")
                    .font(.body15)
                    .foregroundStyle(Color.inkSecondary)

                VStack(spacing: 14) {
                    Button(action: toggleRecording) {
                        Image(systemName: recorder.isRecording ? "stop.fill" : "mic")
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(Color.inkInverse)
                            .frame(width: 84, height: 84)
                            .background(Circle().fill(recorder.isRecording ? Color.newWord : Color.ink))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(recorder.isRecording ? "Stop recording" : "Record")
                    Text(recorder.isRecording ? timeLabel(recorder.elapsed) : (recorder.recordingURL != nil ? "Recorded \(timeLabel(recorder.elapsed))" : "Tap to record"))
                        .font(.body15.monospacedDigit())
                        .foregroundStyle(Color.inkSecondary)
                    Button("Choose an audio file") { showsFilePicker = true }
                        .buttonStyle(.pillSecondary)
                    if let pickedFile {
                        Label(pickedFile.lastPathComponent, systemImage: "waveform").font(.meta13).foregroundStyle(Color.inkSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.surface))

                TextField("Title (optional)", text: $title)
                    .font(.body17)
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.hairline))

                Toggle(isOn: $adaptsToLevel) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Adapt to HSK \(settings.estimatedHSKLevel)").font(.body15)
                        Text("Simpler words and grammar, same meaning").font(.meta13).foregroundStyle(Color.inkSecondary)
                    }
                }
                .tint(Color.ink)

                if let message = errorMessage ?? recorder.errorMessage {
                    Text(message).font(.meta13).foregroundStyle(Color.newWord)
                }

                Button(action: start) {
                    Text("Translate").frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle(height: 52))
                .disabled(sourceURL == nil || recorder.isRecording)
            }
            .padding(16)
        }
        .background(Color.background)
        .navigationTitle("Translate English audio")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showsFilePicker, allowedContentTypes: [.audio, .mpeg4Audio, .mp3, .wav]) { result in
            do {
                pickedFile = try ImportCoordinator.copyToTemporaryLocation(result.get())
                recorder.discard()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .onDisappear { recorder.stop() }
    }

    private var sourceURL: URL? { pickedFile ?? recorder.recordingURL }

    private func toggleRecording() {
        if recorder.isRecording {
            recorder.stop()
        } else {
            pickedFile = nil
            Task { await recorder.start() }
        }
    }

    private func start() {
        guard let sourceURL else { return }
        Task {
            // Speech recognition permission is needed before the background job can transcribe on device.
            _ = await PushToTalk.requestPermissions()
            let name = title.trimmingCharacters(in: .whitespaces)
            ImportCoordinator.start(
                .englishAudio(sourceURL, adaptToHSK: adaptsToLevel ? settings.estimatedHSKLevel : nil),
                title: name.isEmpty ? "Recording \(Date.now.formatted(date: .abbreviated, time: .shortened))" : name,
                kind: .translatedAudio,
                makesCardsFromTaps: settings.makeCardsFromTapsByDefault,
                in: modelContext
            )
            onStart()
        }
    }

    private func timeLabel(_ seconds: Double) -> String {
        String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}

@Observable
final class AudioRecorder {
    private(set) var isRecording = false
    private(set) var elapsed: Double = 0
    private(set) var recordingURL: URL?
    private(set) var errorMessage: String?
    private var recorder: AVAudioRecorder?
    private var timer: Timer?

    func start() async {
        guard await AVAudioApplication.requestRecordPermission() else {
            errorMessage = "Allow microphone access in Settings to record."
            return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try AVAudioSession.sharedInstance().setActive(true)
            let url = URL.temporaryDirectory.appending(path: "english-\(UUID().uuidString).m4a")
            let recorder = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ])
            recorder.record()
            self.recorder = recorder
            recordingURL = url
            isRecording = true
            elapsed = 0
            let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.elapsed = self?.recorder?.currentTime ?? 0 }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        guard isRecording else { return }
        elapsed = recorder?.currentTime ?? elapsed
        recorder?.stop()
        timer?.invalidate()
        isRecording = false
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
    }

    func discard() {
        stop()
        recordingURL = nil
        elapsed = 0
    }
}
