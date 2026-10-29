import SwiftUI

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&value)
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}

enum CategoryColors {
    static let all: [Color] = CategoryPalette.hexes.map { Color(hex: $0) }

    static func color(for index: Int) -> Color {
        all[CategoryPalette.colorIndex(for: index)]
    }
}

extension FocusCategory {
    var tint: Color { CategoryColors.color(for: colorIndex) }
}

enum TomatoTheme {
    static let focus = Color(red: 0.89, green: 0.24, blue: 0.20)
}
