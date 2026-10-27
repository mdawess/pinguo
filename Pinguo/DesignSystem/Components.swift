import SwiftUI

struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }

    var kind: Kind = .primary
    var height: CGFloat = 48

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.geist(16, .medium))
            .padding(.horizontal, 22)
            .frame(minHeight: height)
            .foregroundStyle(kind == .primary ? Color.inkInverse : Color.ink)
            .background {
                Capsule().fill(kind == .primary ? Color.ink : Color.background)
            }
            .overlay {
                if kind == .secondary { Capsule().strokeBorder(Color.hairline, lineWidth: 1) }
            }
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle() }
    static var pillSecondary: PillButtonStyle { PillButtonStyle(kind: .secondary) }
}

struct CircleIconButton: View {
    let systemName: String
    var size: CGFloat = 44
    var filled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.36, weight: .light))
                .frame(width: size, height: size)
                .foregroundStyle(filled ? Color.inkInverse : Color.ink)
                .background(Circle().fill(filled ? Color.ink : Color.background))
                .overlay { if !filled { Circle().strokeBorder(Color.hairline, lineWidth: 1) } }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

struct SegmentedPicker<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    var height: CGFloat = 44
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = option.value }
                } label: {
                    Text(option.label)
                        .font(.geist(15, selection == option.value ? .medium : .regular))
                        .foregroundStyle(selection == option.value ? Color.ink : Color.inkSecondary)
                        .frame(maxWidth: .infinity, minHeight: height - 8)
                        .background {
                            if selection == option.value {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.background)
                                    .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "thumb", in: thumb)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.surface))
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle().fill(Color.hairline).frame(height: 1)
    }
}

struct IconTile: View {
    let systemName: String
    var size: CGFloat = 40
    var tint: Color = .surface

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.4, weight: .light))
            .foregroundStyle(Color.ink)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(tint))
    }
}

struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.geist(17, .semibold))
            Spacer()
            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}

struct FamiliarityBar: View {
    let familiarity: Familiarity
    let onChange: (Familiarity) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Familiarity").font(.meta13).foregroundStyle(Color.inkSecondary)
                Spacer()
                Text(familiarity.label).font(.geist(13, .semibold)).foregroundStyle(Color.ink)
            }
            HStack(spacing: 4) {
                ForEach(Familiarity.allCases, id: \.self) { level in
                    Button {
                        onChange(level)
                    } label: {
                        Capsule()
                            .fill(level.rawValue <= familiarity.rawValue ? Color.ink : Color.hairline)
                            .frame(height: 4)
                            .frame(maxWidth: .infinity, minHeight: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(level.label)
                }
            }
            .frame(height: 32)
            .padding(.top, -12)
            .padding(.bottom, -12)
        }
    }
}

struct ProgressLine: View {
    let value: Double
    var height: CGFloat = 3

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.hairline)
                Capsule().fill(Color.ink).frame(width: proxy.size.width * min(1, max(0, value)))
            }
        }
        .frame(height: height)
    }
}
