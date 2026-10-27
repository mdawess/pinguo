import SwiftUI

struct ReadingSettingsSheet: View {
    @Bindable var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Reading").font(.sectionTitle)

            VStack(alignment: .leading, spacing: 10) {
                Text("Pinyin").font(.body15)
                SegmentedPicker(
                    options: PinyinMode.allCases.map { ($0, $0.label) },
                    selection: $settings.pinyinMode
                )
            }

            Toggle(isOn: $settings.toneColours) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Color tones").font(.body15)
                    Text("Tint characters by tone 1–4").font(.meta13).foregroundStyle(Color.inkSecondary)
                }
            }
            .tint(Color.ink)

            HStack {
                Text("Characters").font(.body15)
                Spacer()
                SegmentedPicker(
                    options: [(ScriptPreference.simplified, "简体"), (ScriptPreference.traditional, "繁體")],
                    selection: $settings.script,
                    height: 40
                )
                .frame(width: 124)
            }

            HStack(spacing: 14) {
                Text("字").font(.chineseSerif(13))
                Slider(value: $settings.textSize, in: 16...32, step: 1)
                    .tint(Color.ink)
                Text("字").font(.chineseSerif(24))
            }

            HStack {
                Text("Theme").font(.body15)
                Spacer()
                HStack(spacing: 14) {
                    ForEach(ReaderTheme.allCases, id: \.self) { theme in
                        Button {
                            settings.theme = theme
                        } label: {
                            Circle()
                                .fill(theme.background)
                                .frame(width: 34, height: 34)
                                .overlay(Circle().strokeBorder(Color.hairline))
                                .padding(3)
                                .overlay(Circle().strokeBorder(settings.theme == theme ? Color.ink : .clear, lineWidth: 2))
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(theme.rawValue.capitalized)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .background(Color.background)
    }
}
