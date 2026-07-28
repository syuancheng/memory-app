import SwiftUI

enum AppThemeChoice: String, CaseIterable, Identifiable {
    case forest
    case ink
    case plum

    var id: String { rawValue }

    var title: String {
        switch self {
        case .forest: return "Forest"
        case .ink: return "Ink"
        case .plum: return "Plum"
        }
    }

    var subtitle: String {
        switch self {
        case .forest: return "soft green"
        case .ink: return "quiet blue"
        case .plum: return "warm violet"
        }
    }
}

private struct AppPalette {
    let background: Color
    let background2: Color
    let background3: Color
    let screen: Color
    let panel: Color
    let panel2: Color
    let paper: Color
    let text: Color
    let muted: Color
    let accent: Color
    let accent2: Color
    let accentSoft: Color
    let warning: Color
    let line: Color
}

enum Theme {
    static let storageKey = "appColorTheme"

    static var choice: AppThemeChoice {
        let rawValue = UserDefaults.standard.string(forKey: storageKey) ?? AppThemeChoice.forest.rawValue
        return AppThemeChoice(rawValue: rawValue) ?? .forest
    }

    private static var palette: AppPalette {
        switch choice {
        case .forest:
            return AppPalette(
                background: Color(hex: 0xF5F3EF),
                background2: Color(hex: 0xF8F1E7),
                background3: Color(hex: 0xECE7DC),
                screen: Color(hex: 0xFBFAF7),
                panel: Color(hex: 0xFFFAF1),
                panel2: Color(hex: 0xF8F1E6),
                paper: Color(hex: 0xFFFAF1),
                text: Color(hex: 0x1F2933),
                muted: Color(hex: 0x7B817C),
                accent: Color(hex: 0x2F6F5E),
                accent2: Color(hex: 0x335E4B),
                accentSoft: Color(hex: 0xE8F2EE),
                warning: Color(hex: 0xD84A3A),
                line: Color(hex: 0xE6E0D7)
            )
        case .ink:
            return AppPalette(
                background: Color(hex: 0xF1F4F5),
                background2: Color(hex: 0xEEF4F7),
                background3: Color(hex: 0xDDE7EA),
                screen: Color(hex: 0xFBFCFC),
                panel: Color(hex: 0xFAFCFD),
                panel2: Color(hex: 0xEDF4F6),
                paper: Color(hex: 0xFAFCFD),
                text: Color(hex: 0x202A33),
                muted: Color(hex: 0x768189),
                accent: Color(hex: 0x315F74),
                accent2: Color(hex: 0x244B5E),
                accentSoft: Color(hex: 0xE5F0F4),
                warning: Color(hex: 0xB96150),
                line: Color(hex: 0xDDE6E8)
            )
        case .plum:
            return AppPalette(
                background: Color(hex: 0xF6F2F4),
                background2: Color(hex: 0xF7EEF2),
                background3: Color(hex: 0xEBE0E6),
                screen: Color(hex: 0xFCFAFB),
                panel: Color(hex: 0xFFFAF7),
                panel2: Color(hex: 0xF6EDF1),
                paper: Color(hex: 0xFFFAF7),
                text: Color(hex: 0x2F2930),
                muted: Color(hex: 0x82767C),
                accent: Color(hex: 0x7B5267),
                accent2: Color(hex: 0x654255),
                accentSoft: Color(hex: 0xF0E5EA),
                warning: Color(hex: 0xC05B4B),
                line: Color(hex: 0xE8DDE2)
            )
        }
    }

    static var background: Color { palette.background }
    static var background2: Color { palette.background2 }
    static var background3: Color { palette.background3 }
    static var screen: Color { palette.screen }
    static var panel: Color { palette.panel }
    static var panel2: Color { palette.panel2 }
    static var paper: Color { palette.paper }
    static var text: Color { palette.text }
    static var muted: Color { palette.muted }
    static var green: Color { palette.accent }
    static var green2: Color { palette.accent2 }
    static var greenSoft: Color { palette.accentSoft }
    static var red: Color { palette.warning }
    static var line: Color { palette.line }
}

enum AppFont {
    static func regular(_ size: CGFloat) -> Font {
        .custom("OPPOSans-Regular", size: size)
    }

    static func medium(_ size: CGFloat) -> Font {
        .custom("OPPOSans-Medium", size: size)
    }

    static func bold(_ size: CGFloat) -> Font {
        .custom("OPPOSans-Bold", size: size)
    }
}

extension View {
    func appCard() -> some View {
        self
            .background(Theme.paper.opacity(0.96))
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Theme.green.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: Theme.text.opacity(0.10), radius: 34, y: 14)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, opacity: opacity)
    }
}

struct ScreenBackground: View {
    var homeStyle = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: homeStyle
                    ? [Theme.screen, Theme.background, Theme.background3]
                    : [Theme.background2, Theme.background3],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [Color.white.opacity(homeStyle ? 0.72 : 0.76), .clear],
                center: homeStyle ? UnitPoint(x: 0.20, y: 0.10) : UnitPoint(x: 0.78, y: 0.16),
                startRadius: 0,
                endRadius: 260
            )

            RadialGradient(
                colors: [Theme.green.opacity(homeStyle ? 0.10 : 0.055), .clear],
                center: homeStyle ? UnitPoint(x: 0.50, y: 0.64) : UnitPoint(x: 0.08, y: 0.86),
                startRadius: 0,
                endRadius: 300
            )
        }
        .ignoresSafeArea()
    }
}

struct SheetPanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 99)
                .fill(Theme.green.opacity(0.18))
                .frame(width: 42, height: 5)
                .padding(.bottom, 14)

            content
        }
        .padding(.top, 14)
        .padding(.horizontal, 16)
        .padding(.bottom, 18)
        .background(
            LinearGradient(
                colors: [Theme.paper.opacity(0.98), Theme.panel2.opacity(0.96)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Theme.green.opacity(0.11), lineWidth: 1)
        )
        .shadow(color: Theme.green.opacity(0.20), radius: 60, y: 24)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }
}
