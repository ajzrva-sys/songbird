import Testing
@testable import SongbirdLib

@Suite("Track table presentation modes")
struct TrackTablePresentationTests {
    @Test("Classic mode hides artwork")
    func classicMode() {
        let classic = TrackTablePresentation.classic
        #expect(!classic.showsArtwork)
        #expect(classic.artworkGutterWidth == 0)
        #expect(classic.rowVerticalInset < TrackTablePresentation.comfortable.rowVerticalInset)
        #expect(classic.headerHeight < TrackTablePresentation.comfortable.headerHeight)
    }

    @Test("Comfortable mode shows artwork and uses standard metrics")
    func comfortableMode() {
        let comfortable = TrackTablePresentation.comfortable
        #expect(comfortable.showsArtwork)
        #expect(comfortable.artworkGutterWidth == 36)
        #expect(comfortable.rowVerticalInset == 4)
        #expect(comfortable.headerHeight == 22)
    }

    @Test("Invalid stored values resolve to Classic")
    func invalidValueDefaults() {
        #expect(TrackTablePresentation.resolved(from: nil) == .classic)
        #expect(TrackTablePresentation.resolved(from: "invalid") == .classic)
        #expect(TrackTablePresentation.resolved(from: "") == .classic)
    }

    @Test("Valid stored values resolve correctly")
    func validValueResolution() {
        #expect(TrackTablePresentation.resolved(from: "classic") == .classic)
        #expect(TrackTablePresentation.resolved(from: "comfortable") == .comfortable)
    }

    // MARK: - Cross-feature independence regressions

    @Test("Table presentation and sidebar metrics are independent storage keys")
    func presentationAndMetricsKeysAreIndependent() {
        #expect(TrackTablePresentation.storageKey != ServicePaneMetrics.storageKey)
    }

    @Test("Table presentation mode does not affect sidebar metrics")
    func presentationDoesNotAffectMetrics() {
        let standardMetrics = ServicePaneMetrics.standard
        // Sidebar metrics are independent of table presentation
        #expect(standardMetrics.rowVerticalPadding != TrackTablePresentation.classic.rowVerticalInset)
    }

    @Test("Cascade filter column order is independent of presentation mode")
    func cascadeOrderIsIndependent() {
        let order = CascadeFilterColumn.defaultOrder
        #expect(order == [.genre, .artist, .album])
        // Cascade order doesn't change when presentation changes
        #expect(order.count == 3)
    }

    @Test("Layout presets are independent of table presentation")
    func layoutPresetsAreIndependent() {
        let classic = NowPlayingLayoutPreset.classic.configuration
        let balanced = NowPlayingLayoutPreset.balanced.configuration
        let compact = NowPlayingLayoutPreset.compact.configuration
        // Presets are distinct from each other
        #expect(classic != balanced)
        #expect(balanced != compact)
        #expect(classic != compact)
        // Presets don't share storage keys with table presentation
        #expect(NowPlayingLayoutSettings.faceplateWidthKey != TrackTablePresentation.storageKey)
    }

    @Test("Status presentation format is independent of other preferences")
    func statusPresentationIsIndependent() {
        let resting = LibraryStatusPresentation.resting(count: 100, duration: 3600)
        #expect(resting.text == "100 items · 1:00:00")
        // Status format doesn't depend on table or sidebar settings
        #expect(!resting.text.contains("classic"))
        #expect(!resting.text.contains("comfortable"))
    }
}
