import Testing
@testable import SongbirdLib

@Suite("Browse list interactions")
struct BrowseListInteractionTests {
    @Test("An artist or genre can be reopened after navigating back")
    func repeatedSelectionIsConsumed() {
        // Given
        var selection = BrowseListSelectionState()

        // When
        selection.selected = "Ambient"
        let firstRoute = selection.consume()
        selection.selected = "Ambient"
        let secondRoute = selection.consume()

        // Then
        #expect(firstRoute == "Ambient")
        #expect(secondRoute == "Ambient")
        #expect(selection.selected == nil)
    }
}
