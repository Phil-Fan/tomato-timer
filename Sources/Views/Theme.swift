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

extension Phase {
    var tint: Color {
        switch self {
        case .focus: Color(red: 0.89, green: 0.24, blue: 0.20)
        case .shortBreak: Color(red: 0.22, green: 0.63, blue: 0.43)
        case .longBreak: Color(red: 0.18, green: 0.49, blue: 0.78)
        }
    }
}
