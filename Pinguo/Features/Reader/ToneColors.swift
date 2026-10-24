import SwiftUI

enum ToneColors {
    static func color(for tone: Int) -> Color {
        switch tone {
        case 1: Color(light: 0xC23B22, dark: 0xE8826D)
        case 2: Color(light: 0xB7791F, dark: 0xE2B866)
        case 3: Color(light: 0x2F7D4F, dark: 0x7CC49A)
        case 4: Color(light: 0x2457A6, dark: 0x86A8E0)
        default: Color.inkSecondary
        }
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

extension ReaderTheme {
    var background: Color {
        switch self {
        case .light: Color.background
        case .paper: Color(light: 0xF6F0E4, dark: 0xF6F0E4)
        case .dark: Color(light: 0x0E0E0F, dark: 0x0E0E0F)
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .light: nil
        case .paper: .light
        case .dark: .dark
        }
    }
}
