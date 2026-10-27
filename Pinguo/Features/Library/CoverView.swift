import SwiftUI

/// 2:3 book cover; falls back to a typeset cover when the source has no image.
struct CoverView: View {
    let document: Document
    var width: CGFloat?

    private static let palettes: [(background: UInt32, text: UInt32)] = [
        (0x1E2530, 0xEDEBE8), (0xDDE2EB, 0x1E2530), (0xE6DACB, 0x3A2E22),
        (0xE1E7DC, 0x26321F), (0xEDE1E4, 0x3A2228), (0xF4F2EF, 0x111111),
    ]

    var body: some View {
        Group {
            if let data = document.coverImage, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                typesetCover
            }
        }
        .frame(width: width)
        .aspectRatio(2 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.black.opacity(0.06)))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 6)
    }

    private var palette: (background: Color, text: Color) {
        let hash = document.title.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
        let choice = Self.palettes[abs(hash) % Self.palettes.count]
        return (Color(light: choice.background, dark: choice.background), Color(light: choice.text, dark: choice.text))
    }

    private var typesetCover: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / 104
            ZStack(alignment: .topLeading) {
                palette.background
                VStack(alignment: .leading) {
                    Text(document.title)
                        .font(.chineseSerif(22 * scale))
                        .lineLimit(3)
                        .minimumScaleFactor(0.6)
                    Spacer()
                    if let author = document.author {
                        Text(author).font(.chineseSans(9 * scale)).lineLimit(1)
                    }
                }
                .foregroundStyle(palette.text)
                .padding(10 * scale)
            }
        }
    }
}
