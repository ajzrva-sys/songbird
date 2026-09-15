import SwiftUI
import Testing
@testable import SongbirdLib

@Suite("Faceplate style tokens")
struct FaceplateStyleTests {
    @Test("Faceplate style resolves distinct corner radii per treatment")
    func cornerRadiusDiffersByTreatment() {
        let standard = FaceplateStyle.resolve(
            treatment: .standard,
            palette: SongbirdThemePalette.palette(for: .dove),
            isDark: false
        )
        let terminal = FaceplateStyle.resolve(
            treatment: .terminal,
            palette: SongbirdThemePalette.palette(for: .terminal),
            isDark: true
        )
        #expect(standard.cornerRadius == 7)
        #expect(terminal.cornerRadius == 2)
    }

    @Test("Faceplate style uses palette colors for background")
    func backgroundUsesPaletteColors() {
        let style = FaceplateStyle.resolve(
            treatment: .standard,
            palette: SongbirdThemePalette.palette(for: .blueMonday),
            isDark: false
        )
        #expect(style.backgroundTop != style.backgroundBottom)
        #expect(style.lcdText != style.backgroundTop)
    }

    @Test("Graphite faceplate uses blue Monday accent stroke")
    func graphiteFaceplateStroke() {
        let style = FaceplateStyle.resolve(
            treatment: .blueMonday,
            palette: SongbirdThemePalette.palette(for: .blueMonday),
            isDark: false
        )
        // Blue Monday uses graphite faceplate, so stroke should be accent-derived
        #expect(style.strokeColor != Color.black.opacity(0.20))
    }

    @Test("Smoked faceplate uses rose-tinted stroke")
    func smokedFaceplateStroke() {
        let style = FaceplateStyle.resolve(
            treatment: .pinkMartini,
            palette: SongbirdThemePalette.palette(for: .pinkMartini),
            isDark: false
        )
        // Pink Martini uses smoked faceplate
        let expected = Color(red: 0.44, green: 0.18, blue: 0.29)
        #expect(style.strokeColor == expected)
    }

    @Test("Dark non-themed faceplate uses stronger stroke opacity")
    func darkFaceplateStroke() {
        let style = FaceplateStyle.resolve(
            treatment: .standard,
            palette: SongbirdThemePalette.palette(for: .dove),
            isDark: true
        )
        #expect(style.strokeColor == Color.black.opacity(0.55))
    }

    @Test("Light non-themed faceplate uses lighter stroke opacity")
    func lightFaceplateStroke() {
        let style = FaceplateStyle.resolve(
            treatment: .standard,
            palette: SongbirdThemePalette.palette(for: .dove),
            isDark: false
        )
        #expect(style.strokeColor == Color.black.opacity(0.20))
    }

    @Test("Faceplate style is Equatable")
    func equatable() {
        let a = FaceplateStyle.resolve(
            treatment: .standard,
            palette: SongbirdThemePalette.palette(for: .dove),
            isDark: false
        )
        let b = FaceplateStyle.resolve(
            treatment: .standard,
            palette: SongbirdThemePalette.palette(for: .dove),
            isDark: false
        )
        #expect(a == b)
    }

    @Test("Different feathers produce different faceplate styles")
    func differentFeathersDifferentStyles() {
        let blue = FaceplateStyle.resolve(
            treatment: .blueMonday,
            palette: SongbirdThemePalette.palette(for: .blueMonday),
            isDark: false
        )
        let purple = FaceplateStyle.resolve(
            treatment: .purpleRain,
            palette: SongbirdThemePalette.palette(for: .purpleRain),
            isDark: true
        )
        #expect(blue != purple)
    }
}
