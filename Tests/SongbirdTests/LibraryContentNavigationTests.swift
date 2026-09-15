import Foundation
import Testing
@testable import SongbirdLib

@Suite("Content-owned library navigation")
struct LibraryContentNavigationTests {
    /// A source-boundary guard supplements the executable coordinator test.
    /// It cannot prove rendered position, focus, or absence of native chrome;
    /// those remain the parent's black-box acceptance gate.
    @Test("All route destinations suppress implicit Back and the content control owns the shortcut")
    func routeBoundaryAndBackWiring() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/Views/MainView.swift"))
        let start = try #require(source.range(of: ".navigationDestination(for: LibraryRoute.self)"))
        let boundary = source[start.lowerBound...].prefix(300)
        #expect(boundary.contains(".navigationBarBackButtonHidden(true)"))
        #expect(source.contains("libraryNavigation.pop()"))
        #expect(source.contains(".accessibilityLabel(\"Back\")"))
        #expect(source.contains(".keyboardShortcut(\"[\", modifiers: .command)"))
        #expect(source.components(separatedBy: "Button(\"Back\"").count - 1 == 1)
        #expect(source.contains("NavigationStack(path: $libraryNavigation.path)"))
    }

    @Test("Back unwinds album, artist, genre, and health routes to the original root")
    @MainActor
    func backRestoresSidebarSelectionForEveryRoute() {
        let coordinator = LibraryNavigationCoordinator(selectedRoot: .allTracks)
        let routes: [LibraryRoute] = [.album(albumID: UUID()), .artist(name: "Fixture Artist"),
                                      .genre(name: "Fixture Genre"), .health(category: .missingArtwork)]
        routes.forEach { coordinator.push($0) }
        for index in routes.indices.reversed() {
            #expect(coordinator.selectedSidebarDestination == routes[index].sidebarDestination)
            coordinator.pop()
            #expect(coordinator.path == Array(routes.prefix(index)))
        }
        #expect(coordinator.rootDestination == .allTracks)
        #expect(coordinator.selectedSidebarDestination == .allTracks)
        coordinator.pop()
        #expect(coordinator.path.isEmpty)
    }
}
