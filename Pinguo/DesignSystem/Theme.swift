import SwiftUI

// Colour tokens come from Assets.xcassets via generated asset symbols (Color.ink, Color.surface, ...).

enum Typeface {
    case regular, medium, semibold, bold

    var postScriptName: String {
        switch self {
        case .regular: "Geist-Regular"
        case .medium: "Geist-Medium"
        case .semibold: "Geist-SemiBold"
        case .bold: "Geist-Bold"
        }
    }
}

extension Font {
    static func geist(_ size: CGFloat, _ weight: Typeface = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(weight.postScriptName, size: size, relativeTo: style)
    }

    static let largeTitle30 = geist(30, .semibold, relativeTo: .largeTitle)
    static let sectionTitle = geist(20, .semibold, relativeTo: .title3)
    static let body17 = geist(17, relativeTo: .body)
    static let body15 = geist(15, relativeTo: .subheadline)
    static let meta13 = geist(13, relativeTo: .footnote)
    static let meta12 = geist(12, relativeTo: .caption)

    static func chineseSerif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Songti SC", size: size).weight(weight)
    }

    static func chineseSans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("PingFang SC", size: size).weight(weight)
    }
}
