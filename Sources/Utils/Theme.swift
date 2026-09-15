import SwiftUI

public enum SongbirdThemeID: String, CaseIterable, Identifiable {
    // Original Songbird/Nightingale feathers
    case blueMonday
    case gonzo
    case pinkMartini
    case purpleRain
    // New feathers
    case nightingale
    case blackbird
    case bowie
    case dove
    case silverwing
    case musicLight
    case musicDark
    case muse
    case terminal

    public static let storageKey = "songbird.themeID"
    public static let legacyBlueMondaySourceRawValue = "blueMondaySource"

    public static func resolved(rawValue: String?) -> SongbirdThemeID {
        if rawValue == legacyBlueMondaySourceRawValue { return .blueMonday }
        return rawValue.flatMap(SongbirdThemeID.init(rawValue:)) ?? .blueMonday
    }

    public static func migrateLegacySelectionIfNeeded(
        defaults: UserDefaults = .standard
    ) {
        guard defaults.string(forKey: storageKey) == legacyBlueMondaySourceRawValue else {
            return
        }
        defaults.set(SongbirdThemeID.blueMonday.rawValue, forKey: storageKey)
    }

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .blueMonday: return "Blue Monday"
        case .gonzo: return "Gonzo"
        case .pinkMartini: return "Pink Martini"
        case .purpleRain: return "Purple Rain"
        case .nightingale: return "Nightingale"
        case .blackbird: return "Blackbird"
        case .bowie: return "Bowie"
        case .dove: return "Dove"
        case .silverwing: return "Silverwing"
        case .musicLight: return "Music Light"
        case .musicDark: return "Music Dark"
        case .muse: return "Muse"
        case .terminal: return "Terminal"
        }
    }

    /// Original shipped feathers vs new Songbird additions.
    public var isClassicFeather: Bool {
        switch self {
        case .blueMonday, .gonzo, .pinkMartini, .purpleRain:
            return true
        default:
            return false
        }
    }

    public var appearance: SongbirdThemeAppearance {
        switch self {
        case .purpleRain, .blackbird, .musicDark, .terminal:
            return .dark
        case .muse:
            return .system
        default:
            return .light
        }
    }
}

public enum SongbirdThemeAppearance: Equatable {
    case light
    case dark
    case system

    public var preferredColorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}

public struct SongbirdThemePalette {
    public static let museAccent = Color(red: 0.10, green: 0.58, blue: 0.84)
    public static let terminalAccent = Color(red: 0.88, green: 0.48, blue: 0.20)
    public static let blueMondayAccent = Color(red: 0.18, green: 0.55, blue: 0.78)
    public static let gonzoAccent = Color(red: 0.78, green: 0.62, blue: 0.22)
    public static let purpleRainAccent = Color(red: 0.55, green: 0.28, blue: 0.72)

    public let background: Color
    public let sidebar: Color
    public let sidebarSelected: Color
    public let text: Color
    public let secondaryText: Color
    public let divider: Color
    public let nowPlayingBar: Color
    public let placeholder: Color
    public let faceplateTop: Color
    public let faceplateBottom: Color
    public let lcdText: Color

    public static func palette(
        for id: SongbirdThemeID,
        colorScheme: ColorScheme = .light
    ) -> SongbirdThemePalette {
        switch id {
        case .blueMonday:
            // Native reconstruction of the checked-in Blue Monday feather:
            // pale silver library/player surfaces, a charcoal service pane,
            // blue selection, and a dark graphite LCD.
            return SongbirdThemePalette(
                background: Color(red: 0.93, green: 0.935, blue: 0.94),
                sidebar: Color(red: 0.16, green: 0.165, blue: 0.18),
                sidebarSelected: Color(red: 0.18, green: 0.29, blue: 0.42),
                text: Color(red: 0.10, green: 0.11, blue: 0.12),
                secondaryText: Color(red: 0.38, green: 0.40, blue: 0.43),
                divider: Color(red: 0.70, green: 0.71, blue: 0.73),
                nowPlayingBar: Color(red: 0.875, green: 0.875, blue: 0.87),
                placeholder: Color.black.opacity(0.08),
                faceplateTop: Color(red: 0.22, green: 0.225, blue: 0.23),
                faceplateBottom: Color(red: 0.075, green: 0.08, blue: 0.09),
                lcdText: Color(red: 0.86, green: 0.91, blue: 0.95)
            )
        case .gonzo:
            return SongbirdThemePalette(
                background: Color(red: 0.93, green: 0.91, blue: 0.86),
                sidebar: Color(red: 0.72, green: 0.68, blue: 0.58),
                sidebarSelected: Color(red: 0.90, green: 0.78, blue: 0.45),
                text: Color(red: 0.15, green: 0.12, blue: 0.08),
                secondaryText: Color(red: 0.42, green: 0.36, blue: 0.28),
                divider: Color(red: 0.78, green: 0.72, blue: 0.62),
                nowPlayingBar: Color(red: 0.88, green: 0.84, blue: 0.74),
                placeholder: Color.black.opacity(0.10),
                faceplateTop: Color(red: 0.82, green: 0.86, blue: 0.70),
                faceplateBottom: Color(red: 0.70, green: 0.76, blue: 0.58),
                lcdText: Color(red: 0.10, green: 0.14, blue: 0.08)
            )
        case .pinkMartini:
            return SongbirdThemePalette(
                // A native reconstruction of Pink Martini's visual hierarchy:
                // quiet rose library paper, mauve service pane, rose-metal shell,
                // and a high-contrast smoked faceplate.
                background: Color(red: 0.965, green: 0.94, blue: 0.95),
                sidebar: Color(red: 0.79, green: 0.72, blue: 0.75),
                sidebarSelected: Color(red: 0.89, green: 0.68, blue: 0.78),
                text: Color(red: 0.16, green: 0.08, blue: 0.12),
                secondaryText: Color(red: 0.40, green: 0.28, blue: 0.33),
                divider: Color(red: 0.65, green: 0.50, blue: 0.56),
                nowPlayingBar: Color(red: 0.82, green: 0.67, blue: 0.73),
                placeholder: Color.black.opacity(0.08),
                faceplateTop: Color(red: 0.12, green: 0.08, blue: 0.10),
                faceplateBottom: Color(red: 0.035, green: 0.02, blue: 0.03),
                lcdText: Color(red: 0.96, green: 0.78, blue: 0.86)
            )
        case .purpleRain:
            return SongbirdThemePalette(
                background: Color(red: 0.16, green: 0.12, blue: 0.20),
                sidebar: Color(red: 0.12, green: 0.09, blue: 0.16),
                sidebarSelected: Color(red: 0.35, green: 0.22, blue: 0.48),
                text: Color(red: 0.92, green: 0.88, blue: 0.96),
                secondaryText: Color(red: 0.68, green: 0.60, blue: 0.75),
                divider: Color(red: 0.28, green: 0.22, blue: 0.34),
                nowPlayingBar: Color(red: 0.14, green: 0.10, blue: 0.18),
                placeholder: Color.white.opacity(0.12),
                faceplateTop: Color(red: 0.55, green: 0.45, blue: 0.68),
                faceplateBottom: Color(red: 0.38, green: 0.28, blue: 0.52),
                lcdText: Color(red: 0.95, green: 0.90, blue: 1.0)
            )
        case .nightingale:
            // Cool silver chrome + soft teal LCD — homage to the Nightingale fork.
            return SongbirdThemePalette(
                background: Color(red: 0.91, green: 0.93, blue: 0.94),
                sidebar: Color(red: 0.72, green: 0.78, blue: 0.80),
                sidebarSelected: Color(red: 0.72, green: 0.88, blue: 0.90),
                text: Color(red: 0.08, green: 0.14, blue: 0.16),
                secondaryText: Color(red: 0.35, green: 0.45, blue: 0.48),
                divider: Color(red: 0.78, green: 0.84, blue: 0.86),
                nowPlayingBar: Color(red: 0.86, green: 0.90, blue: 0.91),
                placeholder: Color.black.opacity(0.08),
                faceplateTop: Color(red: 0.78, green: 0.90, blue: 0.88),
                faceplateBottom: Color(red: 0.62, green: 0.80, blue: 0.78),
                lcdText: Color(red: 0.06, green: 0.18, blue: 0.20)
            )
        case .blackbird:
            // Near-black charcoal with amber selection — Gonzo Complete Black energy.
            return SongbirdThemePalette(
                background: Color(red: 0.11, green: 0.11, blue: 0.12),
                sidebar: Color(red: 0.08, green: 0.08, blue: 0.09),
                sidebarSelected: Color(red: 0.42, green: 0.30, blue: 0.10),
                text: Color(red: 0.92, green: 0.90, blue: 0.86),
                secondaryText: Color(red: 0.62, green: 0.58, blue: 0.50),
                divider: Color(red: 0.22, green: 0.22, blue: 0.24),
                nowPlayingBar: Color(red: 0.14, green: 0.14, blue: 0.15),
                placeholder: Color.white.opacity(0.10),
                faceplateTop: Color(red: 0.28, green: 0.24, blue: 0.18),
                faceplateBottom: Color(red: 0.16, green: 0.14, blue: 0.10),
                lcdText: Color(red: 0.95, green: 0.78, blue: 0.35)
            )
        case .bowie:
            // Graphite metal + electric blue — Songbird 0.3 “Bowie” codename energy.
            return SongbirdThemePalette(
                background: Color(red: 0.88, green: 0.89, blue: 0.92),
                sidebar: Color(red: 0.58, green: 0.60, blue: 0.66),
                sidebarSelected: Color(red: 0.55, green: 0.72, blue: 0.95),
                text: Color(red: 0.10, green: 0.12, blue: 0.18),
                secondaryText: Color(red: 0.38, green: 0.40, blue: 0.48),
                divider: Color(red: 0.72, green: 0.74, blue: 0.80),
                nowPlayingBar: Color(red: 0.78, green: 0.80, blue: 0.86),
                placeholder: Color.black.opacity(0.10),
                faceplateTop: Color(red: 0.70, green: 0.78, blue: 0.92),
                faceplateBottom: Color(red: 0.48, green: 0.58, blue: 0.78),
                lcdText: Color(red: 0.06, green: 0.10, blue: 0.22)
            )
        case .dove:
            // Porcelain light + pale sky selection — softest daytime feather.
            return SongbirdThemePalette(
                background: Color(red: 0.97, green: 0.97, blue: 0.98),
                sidebar: Color(red: 0.90, green: 0.92, blue: 0.94),
                sidebarSelected: Color(red: 0.82, green: 0.90, blue: 0.98),
                text: Color(red: 0.18, green: 0.20, blue: 0.24),
                secondaryText: Color(red: 0.48, green: 0.52, blue: 0.58),
                divider: Color(red: 0.88, green: 0.90, blue: 0.92),
                nowPlayingBar: Color(red: 0.94, green: 0.95, blue: 0.96),
                placeholder: Color.black.opacity(0.06),
                faceplateTop: Color(red: 0.94, green: 0.96, blue: 0.98),
                faceplateBottom: Color(red: 0.86, green: 0.90, blue: 0.95),
                lcdText: Color(red: 0.22, green: 0.28, blue: 0.36)
            )
        case .silverwing:
            // Neutral early-Songbird chrome: pale library panes, graphite
            // separators, and a near-black faceplate with a smoky LCD.
            return SongbirdThemePalette(
                background: Color(white: 0.90),
                sidebar: Color(white: 0.82),
                sidebarSelected: Color(white: 0.72),
                text: Color(white: 0.18),
                secondaryText: Color(white: 0.43),
                divider: Color(white: 0.68),
                nowPlayingBar: Color(white: 0.84),
                placeholder: Color.black.opacity(0.07),
                faceplateTop: Color(white: 0.15),
                faceplateBottom: Color(white: 0.035),
                lcdText: Color(white: 0.67)
            )
        case .musicLight:
            // Apple Music-inspired daylight chrome: warm white surfaces,
            // quiet alternating rows, and a vivid music-red accent.
            return SongbirdThemePalette(
                background: Color(red: 0.98, green: 0.98, blue: 0.98),
                sidebar: Color(red: 0.965, green: 0.965, blue: 0.97),
                sidebarSelected: Color(red: 0.91, green: 0.91, blue: 0.92),
                text: Color(red: 0.08, green: 0.08, blue: 0.09),
                secondaryText: Color(red: 0.48, green: 0.48, blue: 0.50),
                divider: Color(red: 0.86, green: 0.86, blue: 0.87),
                nowPlayingBar: Color(red: 0.965, green: 0.965, blue: 0.97),
                placeholder: Color.black.opacity(0.055),
                faceplateTop: Color(red: 0.99, green: 0.99, blue: 0.995),
                faceplateBottom: Color(red: 0.92, green: 0.92, blue: 0.93),
                lcdText: Color(red: 0.12, green: 0.12, blue: 0.13)
            )
        case .musicDark:
            // Apple Music-inspired night chrome: blue-charcoal panels with
            // soft graphite selection and high-contrast type.
            return SongbirdThemePalette(
                background: Color(red: 0.12, green: 0.14, blue: 0.17),
                sidebar: Color(red: 0.07, green: 0.085, blue: 0.11),
                sidebarSelected: Color(red: 0.145, green: 0.165, blue: 0.19),
                text: Color(red: 0.91, green: 0.92, blue: 0.93),
                secondaryText: Color(red: 0.59, green: 0.60, blue: 0.63),
                divider: Color(red: 0.20, green: 0.22, blue: 0.25),
                nowPlayingBar: Color(red: 0.085, green: 0.10, blue: 0.125),
                placeholder: Color.white.opacity(0.09),
                faceplateTop: Color(red: 0.12, green: 0.14, blue: 0.17),
                faceplateBottom: Color(red: 0.055, green: 0.07, blue: 0.09),
                lcdText: Color(red: 0.89, green: 0.90, blue: 0.92)
            )
        case .terminal:
            // Ratatui-inspired graphite surfaces, burnt-orange state, and
            // warm-white text. This intentionally stays darker and quieter
            // than Blackbird's amber-metal treatment.
            return SongbirdThemePalette(
                background: Color(red: 0.067, green: 0.075, blue: 0.082),
                sidebar: Color(red: 0.090, green: 0.098, blue: 0.102),
                sidebarSelected: Color(red: 0.23, green: 0.13, blue: 0.075),
                text: Color(red: 0.94, green: 0.93, blue: 0.91),
                secondaryText: Color(red: 0.60, green: 0.62, blue: 0.61),
                divider: Color(red: 0.21, green: 0.23, blue: 0.24),
                nowPlayingBar: Color(red: 0.105, green: 0.118, blue: 0.122),
                placeholder: Color.white.opacity(0.08),
                faceplateTop: Color(red: 0.085, green: 0.098, blue: 0.092),
                faceplateBottom: Color(red: 0.040, green: 0.050, blue: 0.046),
                lcdText: Color(red: 0.94, green: 0.93, blue: 0.91)
            )
        case .muse:
            if colorScheme == .dark {
                return SongbirdThemePalette(
                    background: Color(red: 0.105, green: 0.105, blue: 0.11),
                    sidebar: Color(red: 0.075, green: 0.075, blue: 0.08),
                    sidebarSelected: Color(red: 0.22, green: 0.25, blue: 0.28),
                    text: Color(red: 0.93, green: 0.93, blue: 0.94),
                    secondaryText: Color(red: 0.64, green: 0.64, blue: 0.66),
                    divider: Color(red: 0.24, green: 0.24, blue: 0.25),
                    nowPlayingBar: Color(red: 0.14, green: 0.14, blue: 0.15),
                    placeholder: Color.white.opacity(0.10),
                    faceplateTop: Color(red: 0.20, green: 0.20, blue: 0.21),
                    faceplateBottom: Color(red: 0.12, green: 0.12, blue: 0.13),
                    lcdText: Color(red: 0.94, green: 0.94, blue: 0.95)
                )
            }
            return SongbirdThemePalette(
                background: Color(red: 0.975, green: 0.97, blue: 0.955),
                sidebar: Color(red: 0.90, green: 0.90, blue: 0.89),
                sidebarSelected: Color(red: 0.76, green: 0.88, blue: 0.96),
                text: Color(red: 0.14, green: 0.14, blue: 0.15),
                secondaryText: Color(red: 0.43, green: 0.43, blue: 0.45),
                divider: Color(red: 0.80, green: 0.80, blue: 0.79),
                nowPlayingBar: Color(red: 0.93, green: 0.93, blue: 0.92),
                placeholder: Color.black.opacity(0.07),
                faceplateTop: Color(red: 0.98, green: 0.98, blue: 0.975),
                faceplateBottom: Color(red: 0.84, green: 0.84, blue: 0.83),
                lcdText: Color(red: 0.16, green: 0.16, blue: 0.17)
            )
        }
    }
}

public struct SongbirdChromePalette: Equatable {
    public let highlight: Color
    public let base: Color
    public let shadow: Color
    public let edge: Color
    public let faceplateStroke: Color
}

/// Describes visual structure that goes beyond a feather's color palette.
/// The values are intentionally semantic so views can keep native controls
/// and accessibility while sharing one recognizable shell treatment.
public enum SongbirdFeatherTreatment: Equatable {
    case standard
    case blueMonday
    case gonzo
    case pinkMartini
    case purpleRain
    case terminal

    public static func treatment(for feather: SongbirdThemeID) -> SongbirdFeatherTreatment {
        switch feather {
        case .blueMonday: return .blueMonday
        case .gonzo: return .gonzo
        case .pinkMartini: return .pinkMartini
        case .purpleRain: return .purpleRain
        case .terminal: return .terminal
        default: return .standard
        }
    }

    public var usesLayeredChrome: Bool { self == .pinkMartini }
    public var usesBlueMondayChrome: Bool { self == .blueMonday }
    public var usesBlueControlRims: Bool { self == .blueMonday }
    public var usesGraphiteFaceplate: Bool { self == .blueMonday }
    public var usesSmokedFaceplate: Bool { self == .pinkMartini }
    public var usesDarkControlWells: Bool { self == .pinkMartini }
    public var usesGonzoChrome: Bool { self == .gonzo }
    public var usesGoldControlRims: Bool { self == .gonzo }
    public var usesWarmFaceplate: Bool { self == .gonzo }
    public var usesPurpleChrome: Bool { self == .purpleRain }
    public var usesPurpleControlRims: Bool { self == .purpleRain }
    public var usesVioletFaceplate: Bool { self == .purpleRain }
    public var usesTerminalChrome: Bool { self == .terminal }
    public var usesSquareControls: Bool { self == .terminal }
    public var usesSquareFaceplate: Bool { self == .terminal }
    public var usesMonospacedTypography: Bool { self == .terminal }
}

// MARK: - Chrome color derivation helpers

/// Derive a lightened variant of a color, clamping each channel upward.
private func lightened(_ color: Color, by amount: CGFloat) -> Color {
    let ns = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor(color)
    return Color(
        red: Double(min(ns.redComponent + amount, 1.0)),
        green: Double(min(ns.greenComponent + amount, 1.0)),
        blue: Double(min(ns.blueComponent + amount, 1.0))
    )
}

/// Derive a darkened variant of a color, clamping each channel downward.
private func darkened(_ color: Color, by amount: CGFloat) -> Color {
    let ns = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor(color)
    return Color(
        red: Double(max(ns.redComponent - amount, 0.0)),
        green: Double(max(ns.greenComponent - amount, 0.0)),
        blue: Double(max(ns.blueComponent - amount, 0.0))
    )
}

/// Relative luminance of a color using WCAG coefficients.
private func chromeLuminance(_ color: Color) -> CGFloat {
    let ns = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor(color)
    return 0.2126 * ns.redComponent + 0.7152 * ns.greenComponent + 0.0722 * ns.blueComponent
}

// MARK: - Bar gradient style extraction

/// Pure value that extracts themed bar gradient stops from a palette.
public enum NowPlayingChromeStyle {
    /// Returns the 3-stop gradient array for the player bar background,
    /// derived from the given feather's nowPlayingBar token.
    public static func barGradientStops(
        for feather: SongbirdThemeID,
        colorScheme: ColorScheme = .light
    ) -> [Color] {
        let chrome = SongbirdThemePalette.palette(for: feather, colorScheme: colorScheme).playerChrome
        return [chrome.highlight, chrome.base, chrome.shadow]
    }
}

// MARK: - SongbirdThemePalette chrome derivation

extension SongbirdThemePalette {
    /// Theme-derived chrome palette for the player bar and top titlebar cap.
    /// Colors are derived from the nowPlayingBar token so each feather
    /// produces a distinct, harmonious chrome.
    public var playerChrome: SongbirdChromePalette {
        let bar = nowPlayingBar
        let lum = chromeLuminance(bar)

        let highlight: Color
        let shadow: Color
        let edge: Color

        if lum > 0.5 {
            // Light theme: brighten top, darken bottom
            highlight = lightened(bar, by: 0.06)
            shadow = darkened(bar, by: 0.06)
            edge = darkened(bar, by: 0.10)
        } else {
            // Dark theme: subtle brighten for highlight, more darken for shadow
            highlight = lightened(bar, by: 0.04)
            shadow = darkened(bar, by: 0.06)
            edge = darkened(bar, by: 0.10)
        }

        let faceplateStroke = text.opacity(0.15)

        return SongbirdChromePalette(
            highlight: highlight,
            base: bar,
            shadow: shadow,
            edge: edge,
            faceplateStroke: faceplateStroke
        )
    }
}

enum SongbirdTheme {
    // MARK: - Legacy light tokens (Blue Monday)

    static let lightBackground = Color(red: 0.92, green: 0.92, blue: 0.92)
    static let lightSidebar = Color(red: 0.76, green: 0.76, blue: 0.76)
    static let lightSidebarSelected = Color(red: 0.85, green: 0.88, blue: 0.96)
    static let lightText = Color(red: 0.1, green: 0.1, blue: 0.1)
    static let lightSecondaryText = Color(red: 0.4, green: 0.4, blue: 0.4)
    static let lightDivider = Color(red: 0.82, green: 0.82, blue: 0.82)
    static let lightNowPlayingBar = Color(red: 0.90, green: 0.90, blue: 0.90)
    static let lightPlaceholder = Color.black.opacity(0.08)
    static let lightFaceplateTop = Color(red: 0.86, green: 0.87, blue: 0.80)
    static let lightFaceplateBottom = Color(red: 0.78, green: 0.80, blue: 0.72)
    static let lcdText = Color(red: 0.12, green: 0.12, blue: 0.10)

    static let darkBackground = Color(red: 0.18, green: 0.18, blue: 0.20)
    static let darkSidebar = Color(red: 0.14, green: 0.14, blue: 0.16)
    static let darkSidebarSelected = Color(red: 0.25, green: 0.35, blue: 0.55)
    static let darkText = Color(red: 0.9, green: 0.9, blue: 0.9)
    static let darkSecondaryText = Color(red: 0.6, green: 0.6, blue: 0.6)
    static let darkDivider = Color(red: 0.25, green: 0.25, blue: 0.27)
    static let darkNowPlayingBar = Color(red: 0.16, green: 0.16, blue: 0.18)
    static let darkPlaceholder = Color.white.opacity(0.1)
    static let darkFaceplateTop = Color(red: 0.72, green: 0.74, blue: 0.68)
    static let darkFaceplateBottom = Color(red: 0.52, green: 0.55, blue: 0.50)
    static let lcdBackground = lightFaceplateTop

    // MARK: - Active palette

    static func currentPalette(for scheme: ColorScheme) -> SongbirdThemePalette {
        let raw = UserDefaults.standard.string(forKey: SongbirdThemeID.storageKey)
            ?? SongbirdThemeID.blueMonday.rawValue
        let id = SongbirdThemeID.resolved(rawValue: raw)
        return SongbirdThemePalette.palette(for: id, colorScheme: scheme)
    }

    static func background(for scheme: ColorScheme) -> Color {
        currentPalette(for: scheme).background
    }

    static func sidebar(for scheme: ColorScheme) -> Color {
        currentPalette(for: scheme).sidebar
    }

    static func sidebarSelected(for scheme: ColorScheme) -> Color {
        currentPalette(for: scheme).sidebarSelected
    }

    static func text(for scheme: ColorScheme) -> Color {
        currentPalette(for: scheme).text
    }

    static func secondaryText(for scheme: ColorScheme) -> Color {
        currentPalette(for: scheme).secondaryText
    }

    static func divider(for scheme: ColorScheme) -> Color {
        currentPalette(for: scheme).divider
    }

    static func nowPlayingBar(for scheme: ColorScheme) -> Color {
        currentPalette(for: scheme).nowPlayingBar
    }

    static func placeholder(for scheme: ColorScheme) -> Color {
        currentPalette(for: scheme).placeholder
    }

    static func faceplateTop(for scheme: ColorScheme) -> Color {
        currentPalette(for: scheme).faceplateTop
    }

    static func faceplateBottom(for scheme: ColorScheme) -> Color {
        currentPalette(for: scheme).faceplateBottom
    }

    static func lcdTextColor(for scheme: ColorScheme) -> Color {
        currentPalette(for: scheme).lcdText
    }
}
