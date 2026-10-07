import Foundation
import Testing
@testable import SongbirdLib

@Suite("Notice source regressions", .serialized)
@MainActor
struct LibraryNoticeSourceRegressionTests {
    private func isolatedStatus() -> LibraryStatus {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("songbird-notice-\(UUID().uuidString).json")
        return LibraryStatus(activity: LibraryActivityStore(storage: LibraryActivityStorage(url: url)))
    }

    @Test("Successful playback only clears playback failures and preserves queued catalog failures")
    func playbackClearPreservesCatalogFailures() {
        let status = isolatedStatus()
        status.showNotice("Could not save title", severity: .error, source: .metadata)
        status.showNotice("Could not save playlist", severity: .error, source: .library)
        status.showPlaybackError("Missing audio file")

        status.clearPlaybackError()
        #expect(status.notices.notice?.source == .metadata)
        #expect(status.notices.notice?.message == "Could not save title")
        status.dismissCurrentNotice()
        #expect(status.notices.notice?.source == .library)
        #expect(status.notices.notice?.message == "Could not save playlist")
        status.dismissCurrentNotice()
        #expect(status.notices.notice == nil)
        #expect(Set(status.activity.records.map(\.source)) == [.metadata, .library, .playback])
    }

    @Test("A file warning remains visible without duplicating its existing activity result")
    func correlatedFileWarning() throws {
        let status = isolatedStatus()
        let id = status.activity.begin(kind: .fileTagWrite, source: .metadata, total: 2)
        status.showNotice("Could not write tags", severity: .warning, source: .metadata,
                          activityOperationID: id)
        status.activity.finish(id: id, status: .completedWithWarnings, severity: .warning,
            failures: [.init(fileName: "02.flac", category: .permissionDenied)],
            counts: .init(filesAttempted: 2, filesSaved: 1, filesFailed: 1))

        let record = try #require(status.activity.records.first)
        #expect(status.activity.records.count == 1)
        #expect(record.id == id)
        #expect(record.kind == .fileTagWrite)
        #expect(record.status == .completedWithWarnings)
        #expect(record.counts?.filesFailed == 1)
        #expect(status.notices.notice?.source == .metadata)
        #expect(status.notices.notice?.severity == .warning)
    }
}
