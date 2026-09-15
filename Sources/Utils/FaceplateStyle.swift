import SwiftUI

/// Shared visual tokens for the faceplate (LCD display) used by both
/// the main NowPlayingBar and MiniPlayer. Extracting these into a
/// value type prevents the two views from drifting.
public struct FaceplateStyle: Equatable {
    /// Corner radius of the faceplate rounded rectangle.
    public let cornerRadius: CGFloat
    /// Width of the outer accent stroke.
    public let strokeWidth: CGFloat
    /// Top color of the faceplate gradient background.
    public let backgroundTop: Color
    /// Bottom color of the faceplate gradient background.
    public let backgroundBottom: Color
    /// Outer accent stroke color.
    public let strokeColor: Color
    /// Primary LCD text color.
    public let lcdText: Color
    /// Title font size.
    public let titleFontSize: CGFloat
    /// Title font weight.
    public let titleFontWeight: Font.Weight
    /// Subtitle font size.
    public let subtitleFontSize: CGFloat
    /// Time font size.
    public let timeFontSize: CGFloat
    /// Internal horizontal padding.
    public let horizontalPadding: CGFloat
    /// Internal vertical padding.
    public let verticalPadding: CGFloat
    /// Artwork size (square).
    public let artworkSize: CGFloat
    /// Per-feather inner glow color (LCD backlight bloom).
    public let glowColor: Color
    /// Per-feather inner glow opacity.
    public let glowOpacity: Double
    /// Scanline texture opacity (0 for light themes).
    public let scanlineOpacity: Double

    /// Derive faceplate style from the active feather treatment and palette.
    public static func resolve(
        treatment: SongbirdFeatherTreatment,
        palette: SongbirdThemePalette,
        isDark: Bool
    ) -> FaceplateStyle {
        let cornerRadius: CGFloat = treatment.usesSquareFaceplate ? 2 : 7
        let strokeColor = resolveStrokeColor(treatment: treatment, isDark: isDark)

        let glow = resolveGlow(treatment: treatment, isDark: isDark)

        return FaceplateStyle(
            cornerRadius: cornerRadius,
            strokeWidth: 1,
            backgroundTop: palette.faceplateTop,
            backgroundBottom: palette.faceplateBottom,
            strokeColor: strokeColor,
            lcdText: palette.lcdText,
            titleFontSize: 11,
            titleFontWeight: .semibold,
            subtitleFontSize: 10,
            timeFontSize: 10,
            horizontalPadding: 4,
            verticalPadding: 2,
            artworkSize: 28,
            glowColor: glow.0,
            glowOpacity: glow.1,
            scanlineOpacity: isDark ? 0.03 : 0
        )
    }

    private static func resolveGlow(
        treatment: SongbirdFeatherTreatment,
        isDark: Bool
    ) -> (Color, Double) {
        if treatment.usesGraphiteFaceplate {
            return (SongbirdThemePalette.blueMondayAccent, 0.06)
        }
        if treatment.usesSmokedFaceplate {
            return (Color(red: 0.96, green: 0.78, blue: 0.86), 0.10)
        }
        if treatment.usesVioletFaceplate {
            return (SongbirdThemePalette.purpleRainAccent, 0.08)
        }
        if treatment.usesWarmFaceplate {
            return (SongbirdThemePalette.gonzoAccent, 0.07)
        }
        if treatment.usesTerminalChrome {
            return (SongbirdThemePalette.terminalAccent, 0.05)
        }
        return (Color.white, isDark ? 0.04 : 0)
    }

    private static func resolveStrokeColor(
        treatment: SongbirdFeatherTreatment,
        isDark: Bool
    ) -> Color {
        if treatment.usesGraphiteFaceplate {
            return SongbirdThemePalette.blueMondayAccent.opacity(0.70)
        }
        if treatment.usesWarmFaceplate {
            return SongbirdThemePalette.gonzoAccent.opacity(0.60)
        }
        if treatment.usesVioletFaceplate {
            return SongbirdThemePalette.purpleRainAccent.opacity(0.55)
        }
        if treatment.usesTerminalChrome {
            return SongbirdThemePalette.terminalAccent.opacity(0.62)
        }
        if treatment.usesSmokedFaceplate {
            return Color(red: 0.44, green: 0.18, blue: 0.29)
        }
        return Color.black.opacity(isDark ? 0.55 : 0.20)
    }
}
