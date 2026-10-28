import SwiftUI

struct PlayerBar: View {
    let player: NarrationPlayer
    let isActive: Bool
    let voiceName: String
    let onPlay: () -> Void
    let onChooseVoice: () -> Void
    var compact = false

    private let speeds: [Double] = [0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.5]

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Text(timeLabel(isActive ? player.elapsed : 0))
                    .font(.meta12.monospacedDigit())
                    .foregroundStyle(Color.inkSecondary)
                Scrubber(value: isActive && player.total > 0 ? player.elapsed / player.total : 0) { fraction in
                    if isActive { player.seek(toFraction: fraction) }
                }
                Text(timeLabel(isActive ? player.total : 0))
                    .font(.meta12.monospacedDigit())
                    .foregroundStyle(Color.inkSecondary)
            }
            HStack {
                Menu {
                    ForEach(speeds, id: \.self) { speed in
                        Button(speedLabel(speed)) { player.speed = speed }
                    }
                } label: {
                    Text(speedLabel(player.speed))
                        .font(.geist(15, .medium))
                        .foregroundStyle(Color.ink)
                        .frame(width: 52, height: 44)
                }
                .accessibilityLabel("Playback speed")
                Spacer()
                Button { player.skipSentence(by: -1) } label: {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 20, weight: .light)).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Previous sentence")
                .disabled(!isActive)
                Spacer()
                Button {
                    isActive ? player.togglePlayPause() : onPlay()
                } label: {
                    Group {
                        if isActive && player.isLoading {
                            ProgressView().tint(Color.inkInverse)
                        } else {
                            Image(systemName: isActive && player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 20))
                        }
                    }
                    .foregroundStyle(Color.inkInverse)
                    .frame(width: 60, height: 60)
                    .background(Circle().fill(Color.ink))
                }
                .accessibilityLabel(isActive && player.isPlaying ? "Pause" : "Play")
                Spacer()
                Button { player.skipSentence(by: 1) } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 20, weight: .light)).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Next sentence")
                .disabled(!isActive)
                Spacer()
                Button(action: onChooseVoice) {
                    VoiceAvatar(name: voiceName, size: 34).frame(width: 52, height: 44)
                }
                .accessibilityLabel("Choose a voice")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.ink)
            if isActive, let error = player.errorMessage {
                Text(error).font(.meta12).foregroundStyle(Color.newWord).lineLimit(2).multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Color.background)
        .overlay(alignment: .top) { Hairline() }
    }

    private func timeLabel(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func speedLabel(_ speed: Double) -> String {
        speed.formatted(.number.precision(.fractionLength(1))) + "×"
    }
}

struct Scrubber: View {
    let value: Double
    let onSeek: (Double) -> Void
    @State private var dragValue: Double?

    var body: some View {
        GeometryReader { proxy in
            let shown = dragValue ?? value
            ZStack(alignment: .leading) {
                Capsule().fill(Color.hairline).frame(height: 3)
                Capsule().fill(Color.ink).frame(width: max(0, proxy.size.width * shown), height: 3)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { dragValue = min(1, max(0, $0.location.x / proxy.size.width)) }
                    .onEnded { _ in
                        if let dragValue { onSeek(dragValue) }
                        dragValue = nil
                    }
            )
        }
        .frame(height: 24)
        .accessibilityElement()
        .accessibilityLabel("Position")
        .accessibilityValue("\(Int(value * 100)) percent")
    }
}

struct VoiceAvatar: View {
    let name: String
    var size: CGFloat = 44

    private static let tints: [UInt32] = [0xE6E2F0, 0xDDE3EC, 0xEDE3D6, 0xE0E8E0, 0xF0E0E2]

    var body: some View {
        let initial = name.first.map(String.init) ?? "?"
        let hash = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        Text(initial)
            .font(ChineseText.containsHan(initial) ? .chineseSerif(size * 0.42) : .geist(size * 0.4, .medium))
            .foregroundStyle(Color(light: 0x2A2A2A, dark: 0x2A2A2A))
            .frame(width: size, height: size)
            .background(Circle().fill(Color(light: Self.tints[hash % Self.tints.count], dark: Self.tints[hash % Self.tints.count])))
    }
}
