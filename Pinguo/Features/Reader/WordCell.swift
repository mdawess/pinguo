import SwiftUI

struct WordCellStyle {
    var fontSize: CGFloat
    var showsRubyRow: Bool
    var toneColours: Bool
    var traditional: Bool
}

struct WordCell: View {
    let token: ReaderToken
    let annotation: WordAnnotation?
    let familiarity: Familiarity
    let showsPinyin: Bool
    let isSelected: Bool
    let isSpoken: Bool
    let style: WordCellStyle

    var body: some View {
        VStack(spacing: 2) {
            if style.showsRubyRow {
                Text(showsPinyin ? (annotation?.pinyin ?? " ") : " ")
                    .font(.geist(11))
                    .foregroundStyle(isSelected ? Color.inkInverse.opacity(0.8) : Color.inkSecondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            hanzi
                .background {
                    if token.isLexical, familiarity.isLearning, !isSelected {
                        RoundedRectangle(cornerRadius: 3).fill(Color.learning)
                    }
                }
                .overlay(alignment: .bottom) {
                    if token.isLexical, familiarity == .new, !isSelected {
                        DottedUnderline()
                            .stroke(Color.newWord, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [0.1, 3]))
                            .frame(height: 1.2)
                            .offset(y: 3)
                    }
                }
        }
        .padding(.horizontal, style.showsRubyRow && token.isLexical ? 2 : 0)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 5).fill(Color.ink).padding(.vertical, -2)
            } else if isSpoken {
                Rectangle().fill(Color.currentSentence).padding(.vertical, -4)
            }
        }
        .contentShape(Rectangle())
    }

    private var displayText: String {
        if style.traditional, let traditional = annotation?.traditional, traditional.count == token.text.count {
            return traditional
        }
        return token.text
    }

    private var hanzi: Text {
        let font = Font.chineseSerif(style.fontSize)
        if isSelected {
            return Text(displayText).font(font).foregroundStyle(Color.inkInverse)
        }
        guard style.toneColours, token.isLexical, let tones = annotation?.tones, tones.count == displayText.count else {
            return Text(displayText).font(font).foregroundStyle(familiarity.isLearning && token.isLexical ? Color.learningText : Color.readerText)
        }
        var attributed = AttributedString()
        for (character, tone) in zip(displayText, tones) {
            var piece = AttributedString(String(character))
            piece.foregroundColor = ToneColors.color(for: tone)
            attributed += piece
        }
        return Text(attributed).font(font)
    }
}

struct DottedUnderline: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 1, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - 1, y: rect.midY))
        return path
    }
}
