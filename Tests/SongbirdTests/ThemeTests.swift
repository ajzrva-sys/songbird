import AppKit
import SongbirdDockIconSupport
import SwiftUI
import Testing
import XCTest
@testable import SongbirdLib

final class ThemeTests: XCTestCase {
    func testTerminalChoiceUsesBirdArtworkLabel() {
        XCTAssertEqual(SongbirdDockIconChoice.terminalAmber.displayName, "Amber Bird")
        XCTAssertEqual(SongbirdDockIconChoice.terminalAmber.rawValue, "terminalAmber")
        XCTAssertEqual(SongbirdDockIconChoice.terminalAmber.resourceName, "dock-icon-blackbird-amber")
    }

    @MainActor
    func testRestoredArtworkUsesItsPerFileCrop() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        bitmap.size = NSSize(width: 1024, height: 1024)
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let colors: [NSColor] = [.red, .green, .blue, .yellow]
        for index in 0..<4 {
            colors[index].setFill()
            NSBezierPath(rect: NSRect(x: CGFloat(index % 2) * 512,
                                      y: CGFloat(index / 2) * 512,
                                      width: 512, height: 512)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let source = NSImage(size: NSSize(width: 1024, height: 1024))
        source.addRepresentation(bitmap)
        func pixels(_ name: String) throws -> Data {
            let rendered = SongbirdDockIconArtwork.dockReadyImage(from: source, resourceName: name)
            let tiff = try XCTUnwrap(rendered.tiffRepresentation)
            let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
            let bytes = try XCTUnwrap(rep.bitmapData)
            return Data(bytes: bytes, count: rep.bytesPerRow * rep.pixelsHigh)
        }
        XCTAssertNotEqual(try pixels("dock-icon-blue-outline"),
                       try pixels("dock-icon-silverwing-frame"))
    }

    func testMuseIsANewSystemAdaptiveFeather() {
        XCTAssertEqual(SongbirdThemeID.muse.displayName, "Muse")
        XCTAssertFalse(SongbirdThemeID.muse.isClassicFeather)
        XCTAssertEqual(SongbirdThemeID.muse.appearance, .system)
        XCTAssertNil(SongbirdThemeID.muse.appearance.preferredColorScheme)
    }

    func testExistingFeathersKeepTheirAppearancePolicy() {
        let lightFeathers: [SongbirdThemeID] = [
            .blueMonday,
            .gonzo,
            .pinkMartini,
            .nightingale,
            .bowie,
            .dove,
            .silverwing,
            .musicLight,
        ]
        let darkFeathers: [SongbirdThemeID] = [
            .purpleRain,
            .blackbird,
            .musicDark,
            .terminal,
        ]

        for feather in lightFeathers {
            XCTAssertEqual(feather.appearance, .light, "\(feather.displayName) changed appearance")
            XCTAssertEqual(feather.appearance.preferredColorScheme, .light)
        }
        for feather in darkFeathers {
            XCTAssertEqual(feather.appearance, .dark, "\(feather.displayName) changed appearance")
            XCTAssertEqual(feather.appearance.preferredColorScheme, .dark)
        }
    }

    func testMuseHasDistinctLightAndDarkPalettes() {
        let light = SongbirdThemePalette.palette(for: .muse, colorScheme: .light)
        let dark = SongbirdThemePalette.palette(for: .muse, colorScheme: .dark)

        XCTAssertNotEqual(rgb(light.background), rgb(dark.background))
        XCTAssertNotEqual(rgb(light.sidebar), rgb(dark.sidebar))
        XCTAssertNotEqual(rgb(light.text), rgb(dark.text))
        XCTAssertNotEqual(rgb(light.faceplateTop), rgb(dark.faceplateTop))
    }

    func testExistingPalettesDoNotChangeWithRequestedColorScheme() {
        for feather in SongbirdThemeID.allCases where feather != .muse {
            let light = SongbirdThemePalette.palette(for: feather, colorScheme: .light)
            let dark = SongbirdThemePalette.palette(for: feather, colorScheme: .dark)

            XCTAssertEqual(
                rgb(light.background),
                rgb(dark.background),
                "\(feather.displayName) unexpectedly became adaptive"
            )
        }
    }

    func testDockIconChoicesAreScopedToInitialFeathers() {
        XCTAssertEqual(
            SongbirdThemeID.blueMonday.dockIconChoices,
            [.blueOutline, .blueVinyl]
        )
        XCTAssertEqual(
            SongbirdThemeID.purpleRain.dockIconChoices,
            [.purpleRim, .purpleNeon]
        )
        XCTAssertEqual(
            SongbirdThemeID.gonzo.dockIconChoices,
            [.gonzoLight, .gonzoDark]
        )
        XCTAssertEqual(
            SongbirdThemeID.pinkMartini.dockIconChoices,
            [.pinkLacquer, .pinkBurgundy, .pinkTerrazzo]
        )
        XCTAssertEqual(
            SongbirdThemeID.nightingale.dockIconChoices,
            [.nightingaleGlow, .nightingaleGlass]
        )
        XCTAssertEqual(
            SongbirdThemeID.blackbird.dockIconChoices,
            [.blackbirdGraphite, .blackbirdAmber]
        )
        XCTAssertEqual(
            SongbirdThemeID.terminal.dockIconChoices,
            []
        )
        XCTAssertEqual(
            SongbirdThemeID.bowie.dockIconChoices,
            [.bowieSilverBlue, .bowiePrism]
        )
        XCTAssertEqual(
            SongbirdThemeID.dove.dockIconChoices,
            [.dovePearl, .doveMarble]
        )
        XCTAssertEqual(
            SongbirdThemeID.silverwing.dockIconChoices,
            [.silverwingFrame, .silverwingGraphite]
        )
        XCTAssertEqual(
            SongbirdThemeID.musicLight.dockIconChoices,
            [.musicLightLacquer]
        )
        XCTAssertEqual(
            SongbirdThemeID.musicDark.dockIconChoices,
            [.musicDarkRed]
        )
        XCTAssertEqual(SongbirdThemeID.blueMonday.defaultDockIconChoice, .blueOutline)
        XCTAssertEqual(SongbirdThemeID.gonzo.defaultDockIconChoice, .gonzoLight)
        XCTAssertEqual(SongbirdThemeID.pinkMartini.defaultDockIconChoice, .pinkLacquer)
        XCTAssertEqual(SongbirdThemeID.purpleRain.defaultDockIconChoice, .purpleRim)
        XCTAssertEqual(SongbirdThemeID.nightingale.defaultDockIconChoice, .nightingaleGlow)
        XCTAssertEqual(SongbirdThemeID.blackbird.defaultDockIconChoice, .blackbirdGraphite)
        XCTAssertNil(SongbirdThemeID.terminal.defaultDockIconChoice)
        XCTAssertEqual(SongbirdThemeID.bowie.defaultDockIconChoice, .bowieSilverBlue)
        XCTAssertEqual(SongbirdThemeID.dove.defaultDockIconChoice, .dovePearl)
        XCTAssertEqual(SongbirdThemeID.silverwing.defaultDockIconChoice, .silverwingFrame)
        XCTAssertEqual(SongbirdThemeID.musicLight.defaultDockIconChoice, .musicLightLacquer)
        XCTAssertEqual(SongbirdThemeID.musicDark.defaultDockIconChoice, .musicDarkRed)
    }

    func testDockIconChoicePersistsIndependentlyPerFeather() throws {
        let suiteName = "ThemeTests.DockIcons.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        SongbirdDockIconPreference.setChoice(.blueVinyl, for: .blueMonday, defaults: defaults)
        SongbirdDockIconPreference.setChoice(.purpleNeon, for: .purpleRain, defaults: defaults)

        XCTAssertEqual(
            SongbirdDockIconPreference.choice(for: .blueMonday, defaults: defaults),
            .blueVinyl
        )
        XCTAssertEqual(
            SongbirdDockIconPreference.choice(for: .purpleRain, defaults: defaults),
            .purpleNeon
        )
    }

    func testDockIconPreferenceRejectsChoiceFromAnotherFeather() throws {
        let suiteName = "ThemeTests.DockIcons.Invalid.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        SongbirdDockIconPreference.setChoice(.purpleNeon, for: .blueMonday, defaults: defaults)

        XCTAssertEqual(
            SongbirdDockIconPreference.choice(for: .blueMonday, defaults: defaults),
            .blueOutline
        )
    }

    func testActiveDockIconResourcePersistsForRetainedDockTile() throws {
        let suiteName = "ThemeTests.DockIcons.Active.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        SongbirdDockIconPreference.setActiveChoice(.pinkTerrazzo, defaults: defaults)

        XCTAssertEqual(
            SongbirdDockIconPreference.activeResourceName(defaults: defaults),
            SongbirdDockIconChoice.pinkTerrazzo.resourceName
        )
    }

    func testClearingActiveDockIconRestoresTheBundleIconState() throws {
        let suiteName = "ThemeTests.DockIcons.ClearActive.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        SongbirdDockIconPreference.setActiveChoice(.blackbirdAmber, defaults: defaults)

        SongbirdDockIconPreference.clearActiveChoice(defaults: defaults)

        XCTAssertNil(SongbirdDockIconPreference.activeResourceName(defaults: defaults))
    }

    func testRetainedDockTileRejectsUnknownResourceName() throws {
        let suiteName = "ThemeTests.DockIcons.Active.Invalid.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            "not-a-songbird-icon",
            forKey: SongbirdDockIconArtwork.activeResourceStorageKey
        )

        XCTAssertNil(SongbirdDockIconPreference.activeResourceName(defaults: defaults))
    }

    func testEveryDockIconChoiceIsSupportedByRetainedDockTile() {
        for choice in SongbirdDockIconChoice.allCases {
            XCTAssertEqual(
                SongbirdDockIconArtwork.validatedResourceName(choice.resourceName),
                choice.resourceName
            )
        }
    }

    @MainActor
    func testDockIconResourcesLoad() {
        for choice in SongbirdDockIconChoice.allCases {
            guard let image = SongbirdDockIconManager.image(for: choice) else {
                return XCTFail("Missing Dock icon resource: \(choice.resourceName).png")
            }
            XCTAssertTrue(
                image === SongbirdDockIconManager.image(for: choice),
                "Settings and Dock should receive the same cached image for \(choice.displayName)"
            )
            let representation = image.tiffRepresentation.flatMap(NSBitmapImageRep.init)
            XCTAssertEqual(image.size, NSSize(width: 1024, height: 1024))
            XCTAssertEqual(representation?.pixelsWide, 1024)
            XCTAssertEqual(representation?.pixelsHigh, 1024)
            XCTAssertEqual(representation?.hasAlpha, true)
            XCTAssertEqual(
                representation?.colorAt(x: 50, y: 512)?.alphaComponent ?? 1,
                0,
                accuracy: 0.01
            )
            XCTAssertGreaterThan(
                representation?.colorAt(x: 512, y: 512)?.alphaComponent ?? 0,
                0.99
            )
        }
    }

    // MARK: - Player chrome derivation tests (Phase 1)

    func testPlayerChromeDerivesFromActiveFeather() {
        let blue = SongbirdThemePalette.palette(for: .blueMonday).playerChrome
        let gonzo = SongbirdThemePalette.palette(for: .gonzo).playerChrome
        XCTAssertNotEqual(rgb(blue.base), rgb(gonzo.base), "Blue Monday and Gonzo must resolve distinct chrome base colors")
    }

    func testPlayerChromeMaintainsOrderedHighlightAndShadow() {
        for feather in SongbirdThemeID.allCases {
            let chrome = SongbirdThemePalette.palette(for: feather, colorScheme: feather == .muse ? .light : .light).playerChrome
            let hl = luminance(chrome.highlight)
            let base = luminance(chrome.base)
            let sh = luminance(chrome.shadow)
            XCTAssertGreaterThan(hl, base, "\(feather.displayName) highlight must be brighter than base")
            XCTAssertGreaterThan(base, sh, "\(feather.displayName) base must be brighter than shadow")
        }
    }

    func testPlayerChromeHasFaceplateStroke() {
        for feather in SongbirdThemeID.allCases {
            let chrome = SongbirdThemePalette.palette(for: feather).playerChrome
            // faceplateStroke must exist and not be fully transparent
            let alpha = NSColor(chrome.faceplateStroke).usingColorSpace(.deviceRGB)?.alphaComponent ?? 0
            XCTAssertGreaterThan(alpha, 0, "\(feather.displayName) faceplateStroke must have nonzero alpha")
        }
    }

    func testPlayerChromeEdgeIsDarkerThanBase() {
        for feather in SongbirdThemeID.allCases {
            let chrome = SongbirdThemePalette.palette(for: feather).playerChrome
            XCTAssertLessThanOrEqual(
                luminance(chrome.edge),
                luminance(chrome.base),
                "\(feather.displayName) edge must be no brighter than base"
            )
        }
    }

    func testTopChromeStyleConsistencyAcrossPalettes() {
        // Blue Monday light and dark (non-muse) palettes must produce identical chrome
        // since non-muse palettes ignore colorScheme.
        let light = SongbirdThemePalette.palette(for: .blueMonday, colorScheme: .light).playerChrome
        let dark = SongbirdThemePalette.palette(for: .blueMonday, colorScheme: .dark).playerChrome
        XCTAssertEqual(rgb(light.base), rgb(dark.base), "Non-muse feather chrome must not vary by colorScheme")
    }

    // MARK: - NowPlayingBar chrome style test (Phase 1 Task 3)

    func testNowPlayingChromeStyleDiffersPerFeather() {
        // Extract bar gradient stops for different feathers — they must not all be the same gray.
        let blueStops = NowPlayingChromeStyle.barGradientStops(for: .blueMonday)
        let gonzoStops = NowPlayingChromeStyle.barGradientStops(for: .gonzo)
        let purpleStops = NowPlayingChromeStyle.barGradientStops(for: .purpleRain)

        // At least the first stop must differ between blue and gonzo
        XCTAssertNotEqual(
            rgb(blueStops[0]), rgb(gonzoStops[0]),
            "Blue Monday and Gonzo bar gradients must differ"
        )
        XCTAssertNotEqual(
            rgb(blueStops[0]), rgb(purpleStops[0]),
            "Blue Monday and Purple Rain bar gradients must differ"
        )
    }

    func testDedicatedNativeFeatherTreatmentsStayScoped() {
        XCTAssertEqual(
            SongbirdFeatherTreatment.treatment(for: .pinkMartini),
            .pinkMartini
        )
        XCTAssertTrue(
            SongbirdFeatherTreatment.treatment(for: .pinkMartini).usesLayeredChrome
        )
        XCTAssertTrue(
            SongbirdFeatherTreatment.treatment(for: .pinkMartini).usesSmokedFaceplate
        )
        XCTAssertTrue(
            SongbirdFeatherTreatment.treatment(for: .pinkMartini).usesDarkControlWells
        )

        XCTAssertEqual(
            SongbirdFeatherTreatment.treatment(for: .blueMonday),
            .blueMonday
        )
        XCTAssertTrue(
            SongbirdFeatherTreatment.treatment(for: .blueMonday).usesBlueMondayChrome
        )
        XCTAssertTrue(
            SongbirdFeatherTreatment.treatment(for: .blueMonday).usesBlueControlRims
        )
        XCTAssertTrue(
            SongbirdFeatherTreatment.treatment(for: .blueMonday).usesGraphiteFaceplate
        )

        XCTAssertEqual(
            SongbirdFeatherTreatment.treatment(for: .gonzo),
            .gonzo
        )
        XCTAssertTrue(
            SongbirdFeatherTreatment.treatment(for: .gonzo).usesGonzoChrome
        )
        XCTAssertTrue(
            SongbirdFeatherTreatment.treatment(for: .gonzo).usesGoldControlRims
        )
        XCTAssertTrue(
            SongbirdFeatherTreatment.treatment(for: .gonzo).usesWarmFaceplate
        )

        XCTAssertEqual(
            SongbirdFeatherTreatment.treatment(for: .purpleRain),
            .purpleRain
        )
        XCTAssertTrue(
            SongbirdFeatherTreatment.treatment(for: .purpleRain).usesPurpleChrome
        )
        XCTAssertTrue(
            SongbirdFeatherTreatment.treatment(for: .purpleRain).usesPurpleControlRims
        )
        XCTAssertTrue(
            SongbirdFeatherTreatment.treatment(for: .purpleRain).usesVioletFaceplate
        )

        XCTAssertEqual(
            SongbirdFeatherTreatment.treatment(for: .terminal),
            .terminal
        )
        XCTAssertTrue(
            SongbirdFeatherTreatment.treatment(for: .terminal).usesTerminalChrome
        )
        XCTAssertTrue(
            SongbirdFeatherTreatment.treatment(for: .terminal).usesSquareControls
        )
        XCTAssertTrue(
            SongbirdFeatherTreatment.treatment(for: .terminal).usesSquareFaceplate
        )
        XCTAssertTrue(
            SongbirdFeatherTreatment.treatment(for: .terminal).usesMonospacedTypography
        )
        for feather in SongbirdThemeID.allCases
            where feather != .blueMonday
                && feather != .gonzo
                && feather != .pinkMartini
                && feather != .purpleRain
                && feather != .terminal {
            XCTAssertEqual(
                SongbirdFeatherTreatment.treatment(for: feather),
                .standard,
                "\(feather.displayName) unexpectedly received a dedicated treatment"
            )
        }
    }

    func testGonzoUsesWarmEarthGoldAccentAndReadablePalette() {
        XCTAssertEqual(SongbirdThemeID.gonzo.displayName, "Gonzo")
        XCTAssertTrue(SongbirdThemeID.gonzo.isClassicFeather)
        XCTAssertEqual(SongbirdThemeID.gonzo.appearance, .light)

        let gonzo = SongbirdThemePalette.palette(for: .gonzo)

        XCTAssertEqual(
            rgb(SongbirdThemePalette.gonzoAccent),
            rgb(Color(red: 0.78, green: 0.62, blue: 0.22))
        )
        XCTAssertGreaterThanOrEqual(contrastRatio(gonzo.text, gonzo.background), 4.5)
        XCTAssertGreaterThanOrEqual(contrastRatio(gonzo.text, gonzo.sidebar), 4.5)
        XCTAssertGreaterThanOrEqual(contrastRatio(gonzo.lcdText, gonzo.faceplateTop), 4.5)
        XCTAssertLessThan(relativeLuminance(gonzo.faceplateBottom), relativeLuminance(gonzo.faceplateTop))
    }

    func testPurpleRainUsesVioletAccentAndReadablePalette() {
        XCTAssertEqual(SongbirdThemeID.purpleRain.displayName, "Purple Rain")
        XCTAssertTrue(SongbirdThemeID.purpleRain.isClassicFeather)
        XCTAssertEqual(SongbirdThemeID.purpleRain.appearance, .dark)

        let purple = SongbirdThemePalette.palette(for: .purpleRain)

        XCTAssertEqual(
            rgb(SongbirdThemePalette.purpleRainAccent),
            rgb(Color(red: 0.55, green: 0.28, blue: 0.72))
        )
        XCTAssertGreaterThanOrEqual(contrastRatio(purple.text, purple.background), 4.5)
        XCTAssertLessThan(relativeLuminance(purple.faceplateBottom), relativeLuminance(purple.faceplateTop))
    }

    func testTerminalUsesReadableGraphiteOrangeAndWarmWhitePalette() {
        XCTAssertEqual(SongbirdThemeID.terminal.displayName, "Terminal")
        XCTAssertFalse(SongbirdThemeID.terminal.isClassicFeather)
        XCTAssertEqual(SongbirdThemeID.terminal.appearance, .dark)

        let terminal = SongbirdThemePalette.palette(for: .terminal)
        let blackbird = SongbirdThemePalette.palette(for: .blackbird)

        XCTAssertNotEqual(rgb(terminal.background), rgb(blackbird.background))
        XCTAssertNotEqual(rgb(terminal.sidebarSelected), rgb(blackbird.sidebarSelected))
        XCTAssertEqual(
            rgb(SongbirdThemePalette.terminalAccent),
            rgb(Color(red: 0.88, green: 0.48, blue: 0.20))
        )
        XCTAssertGreaterThanOrEqual(contrastRatio(terminal.text, terminal.background), 4.5)
        XCTAssertGreaterThanOrEqual(contrastRatio(terminal.text, terminal.sidebar), 4.5)
        XCTAssertGreaterThanOrEqual(contrastRatio(terminal.lcdText, terminal.faceplateTop), 4.5)
        XCTAssertLessThan(relativeLuminance(terminal.faceplateBottom), relativeLuminance(terminal.faceplateTop))
    }

    func testTerminalKeepsTheCanonicalBundleIcon() {
        XCTAssertTrue(SongbirdThemeID.terminal.dockIconChoices.isEmpty)
        XCTAssertNil(SongbirdDockIconPreference.choice(for: .terminal))
    }

    func testPinkMartiniUsesReadableLightShellAndSmokedFaceplate() {
        let palette = SongbirdThemePalette.palette(for: .pinkMartini)

        XCTAssertGreaterThanOrEqual(
            contrastRatio(palette.text, palette.background),
            4.5,
            "Pink Martini library text must meet normal-text contrast"
        )
        XCTAssertGreaterThanOrEqual(
            contrastRatio(palette.text, palette.sidebar),
            4.5,
            "Pink Martini sidebar text must meet normal-text contrast"
        )
        XCTAssertGreaterThanOrEqual(
            contrastRatio(palette.lcdText, palette.faceplateTop),
            4.5,
            "Pink Martini LCD text must remain readable at the lightest faceplate edge"
        )
        XCTAssertLessThan(
            relativeLuminance(palette.faceplateBottom),
            relativeLuminance(palette.faceplateTop)
        )
    }

    // MARK: - Helpers

    private func rgb(_ color: Color) -> [CGFloat] {
        let resolved = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor(color)
        return [resolved.redComponent, resolved.greenComponent, resolved.blueComponent]
    }

    private func luminance(_ color: Color) -> CGFloat {
        let resolved = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor(color)
        // Relative luminance per WCAG
        return 0.2126 * resolved.redComponent
            + 0.7152 * resolved.greenComponent
            + 0.0722 * resolved.blueComponent
    }

    private func relativeLuminance(_ color: Color) -> CGFloat {
        let resolved = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor(color)
        func linearize(_ component: CGFloat) -> CGFloat {
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(resolved.redComponent)
            + 0.7152 * linearize(resolved.greenComponent)
            + 0.0722 * linearize(resolved.blueComponent)
    }

    private func contrastRatio(_ first: Color, _ second: Color) -> CGFloat {
        let firstLuminance = relativeLuminance(first)
        let secondLuminance = relativeLuminance(second)
        let lighter = max(firstLuminance, secondLuminance)
        let darker = min(firstLuminance, secondLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }
}

@Suite("Blue Monday Theme")
struct BlueMondayThemeTests {
    @Test("Blue Monday is the only menu identity and resolves the legacy source selection")
    func blueMondayReplacesSourceIdentity() {
        let blueMonday = SongbirdThemeID.blueMonday

        #expect(blueMonday.rawValue == "blueMonday")
        #expect(blueMonday.displayName == "Blue Monday")
        #expect(blueMonday.isClassicFeather)
        #expect(blueMonday.appearance == .light)
        #expect(SongbirdThemeID.allCases.filter { $0.displayName == "Blue Monday" } == [.blueMonday])
        #expect(
            SongbirdThemeID.resolved(
                rawValue: SongbirdThemeID.legacyBlueMondaySourceRawValue
            ) == .blueMonday
        )
    }

    @Test("Blue Monday uses the light-shell and graphite-pane hierarchy")
    func blueMondayUsesSourceVisualHierarchy() {
        let palette = SongbirdThemePalette.palette(for: .blueMonday)

        #expect(luminance(palette.sidebar) < luminance(palette.background))
        #expect(luminance(palette.faceplateTop) < luminance(palette.nowPlayingBar))
        #expect(luminance(palette.faceplateBottom) < luminance(palette.faceplateTop))
        #expect(contrastRatio(palette.lcdText, palette.faceplateTop) >= 4.5)
        #expect(SongbirdFeatherTreatment.treatment(for: .blueMonday).usesBlueMondayChrome)
    }

    @Test("Legacy source selection and Dock choice migrate to Blue Monday")
    func legacySourcePreferencesMigrate() throws {
        let suiteName = "BlueMondayThemeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacyDockKey = "songbird.dockIcon.\(SongbirdThemeID.legacyBlueMondaySourceRawValue)"
        defaults.set(
            SongbirdThemeID.legacyBlueMondaySourceRawValue,
            forKey: SongbirdThemeID.storageKey
        )
        defaults.set(SongbirdDockIconChoice.blueVinyl.rawValue, forKey: legacyDockKey)

        SongbirdDockIconPreference.migrateLegacyBlueMondaySourceChoiceIfNeeded(defaults: defaults)
        SongbirdThemeID.migrateLegacySelectionIfNeeded(defaults: defaults)

        #expect(defaults.string(forKey: SongbirdThemeID.storageKey) == "blueMonday")
        #expect(SongbirdDockIconPreference.choice(for: .blueMonday, defaults: defaults) == .blueVinyl)
        #expect(defaults.object(forKey: legacyDockKey) == nil)
    }

    private func rgb(_ color: Color) -> [CGFloat] {
        let resolved = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor(color)
        return [resolved.redComponent, resolved.greenComponent, resolved.blueComponent]
    }

    private func luminance(_ color: Color) -> CGFloat {
        let resolved = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor(color)
        return 0.2126 * resolved.redComponent
            + 0.7152 * resolved.greenComponent
            + 0.0722 * resolved.blueComponent
    }

    private func contrastRatio(_ first: Color, _ second: Color) -> CGFloat {
        let firstLuminance = relativeLuminance(first)
        let secondLuminance = relativeLuminance(second)
        let lighter = max(firstLuminance, secondLuminance)
        let darker = min(firstLuminance, secondLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func relativeLuminance(_ color: Color) -> CGFloat {
        let resolved = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor(color)
        func linearize(_ component: CGFloat) -> CGFloat {
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(resolved.redComponent)
            + 0.7152 * linearize(resolved.greenComponent)
            + 0.0722 * linearize(resolved.blueComponent)
    }
}
