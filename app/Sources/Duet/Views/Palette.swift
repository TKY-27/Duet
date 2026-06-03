import SwiftUI

struct DuetPalette {
    var desktop: LinearGradient
    var window: Color
    var titlebar: Color
    var toolbar: Color
    var panel: Color
    var log: Color
    var card: Color
    var elevated: Color
    var border: Color
    var softBorder: Color
    var text: Color
    var secondaryText: Color
    var tertiaryText: Color
    var input: Color
    var mono: Color
    var human: Color
    var destructive: Color
    var success: Color
    var warning: Color

    static func forTheme(_ theme: DuetTheme) -> DuetPalette {
        switch theme {
        case .dark:
            DuetPalette(
                desktop: LinearGradient(colors: [Color(red: 0.18, green: 0.18, blue: 0.20), .black], startPoint: .topLeading, endPoint: .bottomTrailing),
                window: Color(red: 0.10, green: 0.10, blue: 0.12),
                titlebar: Color(red: 0.16, green: 0.16, blue: 0.18),
                toolbar: Color(red: 0.13, green: 0.13, blue: 0.15),
                panel: Color(red: 0.12, green: 0.12, blue: 0.14),
                log: Color(red: 0.075, green: 0.075, blue: 0.085),
                card: Color(red: 0.15, green: 0.15, blue: 0.17),
                elevated: Color(red: 0.17, green: 0.17, blue: 0.19),
                border: .white.opacity(0.11),
                softBorder: .white.opacity(0.06),
                text: Color(red: 0.94, green: 0.94, blue: 0.96),
                secondaryText: Color(red: 0.63, green: 0.63, blue: 0.67),
                tertiaryText: Color(red: 0.42, green: 0.42, blue: 0.46),
                input: Color(red: 0.10, green: 0.10, blue: 0.12),
                mono: Color.black.opacity(0.42),
                human: Color(red: 0.49, green: 0.42, blue: 0.94),
                destructive: Color(red: 0.88, green: 0.34, blue: 0.32),
                success: Color(red: 0.25, green: 0.78, blue: 0.43),
                warning: Color(red: 0.95, green: 0.68, blue: 0.24)
            )
        case .light:
            DuetPalette(
                desktop: LinearGradient(colors: [Color(red: 0.91, green: 0.90, blue: 0.93), Color(red: 0.80, green: 0.80, blue: 0.84)], startPoint: .topLeading, endPoint: .bottomTrailing),
                window: .white,
                titlebar: Color(red: 0.93, green: 0.93, blue: 0.95),
                toolbar: Color(red: 0.96, green: 0.95, blue: 0.97),
                panel: Color(red: 0.94, green: 0.94, blue: 0.96),
                log: .white,
                card: .white,
                elevated: .white,
                border: .black.opacity(0.11),
                softBorder: .black.opacity(0.06),
                text: Color(red: 0.11, green: 0.11, blue: 0.12),
                secondaryText: Color(red: 0.42, green: 0.42, blue: 0.46),
                tertiaryText: Color(red: 0.60, green: 0.60, blue: 0.64),
                input: .white,
                mono: Color(red: 0.94, green: 0.94, blue: 0.96),
                human: Color(red: 0.49, green: 0.42, blue: 0.94),
                destructive: Color(red: 0.76, green: 0.20, blue: 0.17),
                success: Color(red: 0.12, green: 0.54, blue: 0.30),
                warning: Color(red: 0.72, green: 0.42, blue: 0.08)
            )
        case .terminal:
            DuetPalette(
                desktop: LinearGradient(colors: [Color(red: 0.02, green: 0.08, blue: 0.04), .black], startPoint: .top, endPoint: .bottom),
                window: Color(red: 0.00, green: 0.02, blue: 0.00),
                titlebar: Color(red: 0.02, green: 0.07, blue: 0.04),
                toolbar: Color(red: 0.02, green: 0.05, blue: 0.03),
                panel: Color(red: 0.015, green: 0.045, blue: 0.025),
                log: Color(red: 0.00, green: 0.02, blue: 0.00),
                card: Color(red: 0.02, green: 0.07, blue: 0.04),
                elevated: Color(red: 0.03, green: 0.09, blue: 0.05),
                border: Color(red: 0.31, green: 0.94, blue: 0.53).opacity(0.23),
                softBorder: Color(red: 0.31, green: 0.94, blue: 0.53).opacity(0.12),
                text: Color(red: 0.73, green: 0.97, blue: 0.75),
                secondaryText: Color(red: 0.37, green: 0.69, blue: 0.43),
                tertiaryText: Color(red: 0.23, green: 0.42, blue: 0.27),
                input: Color(red: 0.01, green: 0.09, blue: 0.04),
                mono: Color(red: 0.01, green: 0.09, blue: 0.04),
                human: Color(red: 0.49, green: 0.42, blue: 0.94),
                destructive: Color(red: 1.00, green: 0.42, blue: 0.42),
                success: Color(red: 0.33, green: 0.88, blue: 0.48),
                warning: Color(red: 0.90, green: 0.86, blue: 0.30)
            )
        }
    }
}

private struct DuetPaletteKey: EnvironmentKey {
    static let defaultValue = DuetPalette.forTheme(.light)
}

extension EnvironmentValues {
    var duetPalette: DuetPalette {
        get { self[DuetPaletteKey.self] }
        set { self[DuetPaletteKey.self] = newValue }
    }
}

extension ConnectionState {
    func statusColor(in palette: DuetPalette) -> Color {
        switch self {
        case .connected:
            palette.success
        case .connecting, .reconnecting:
            palette.warning
        case .failed:
            palette.destructive
        case .disconnected:
            palette.tertiaryText
        }
    }
}
