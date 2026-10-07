import Foundation
import Testing
@testable import SongbirdLib

struct HealthMetadataPresentationTests {
    @Test("Retained zero findings never hide checking, stale or failed status")
    func healthRetainedResults() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let result = LibraryHealthCategoryResult(category: .missingGenre, sourceRevision: 3,
            checkedAt: date, plan: LibraryRemediationPlan(category: .missingGenre, proposals: []))
        let states: [LibraryHealthCheckState] = [
            .checking(lastGood: result), .stale(lastGood: result),
            .failed(message: "Check failed", lastGood: result),
        ]
        for state in states {
            let presentation = LibraryHealthStatusPresentation(state: state)
            #expect(!presentation.isCurrent)
            #expect(presentation.checkedAt == date)
            #expect(presentation.findingText(count: 0) == "Previous: 0 findings")
            #expect(presentation.emptyResultDescription.contains("not current"))
        }
        #expect(LibraryHealthStatusPresentation(state: states[2]).failureMessage == "Check failed")
        let ready = LibraryHealthStatusPresentation(state: .ready(result))
        #expect(ready.isCurrent)
        #expect(ready.title == "Current")
        #expect(ready.findingText(count: 1) == "1 finding")
        #expect(ready.emptyResultDescription.contains("current library view"))
    }

    @Test("Unchecked and first-check states have no inherited timestamps")
    func healthFirstCheck() {
        let unchecked = LibraryHealthStatusPresentation(state: .notChecked)
        #expect(unchecked.title == "Not checked")
        #expect(unchecked.checkedAt == nil)
        let checking = LibraryHealthStatusPresentation(state: .checking(lastGood: nil))
        #expect(checking.title == "Checking…")
        #expect(checking.checkedAt == nil)
        let failed = LibraryHealthStatusPresentation(state: .failed(message: "Unavailable", lastGood: nil))
        #expect(failed.title == "Check failed")
        #expect(failed.failureMessage == "Unavailable")
    }

    @Test("Mixed Favorite and Rating remain untouched until explicitly chosen")
    func mixedSelection() {
        var favorite = TrackMetadataSelectionState(values: [false, true])
        var rating = TrackMetadataSelectionState(values: [0, 5])
        #expect(favorite.isMixed && favorite.edit == nil)
        #expect(rating.isMixed && rating.edit == nil)
        favorite.choose(false)
        rating.choose(0)
        #expect(!favorite.isMixed && favorite.edit == false)
        #expect(!rating.isMixed && rating.edit == 0)
        favorite.leaveUnchanged()
        rating.leaveUnchanged()
        #expect(favorite.isMixed && favorite.edit == nil)
        #expect(rating.isMixed && rating.edit == nil)
    }

    @Test("Leaving a uniform selection unchanged restores its original value")
    func uniformSelection() {
        var rating = TrackMetadataSelectionState(values: [4, 4])
        #expect(!rating.isMixed && rating.value == 4)
        rating.choose(0)
        #expect(rating.edit == 0)
        rating.leaveUnchanged()
        #expect(rating.edit == nil && rating.value == 4)
        #expect(!TrackMetadataField.favorite.supportsAudioTagWriting)
        #expect(!TrackMetadataField.rating.supportsAudioTagWriting)
        #expect(TrackMetadataField.title.supportsAudioTagWriting)
        #expect(TrackMetadataField.artwork.supportsAudioTagWriting)
        #expect(TrackMetadataWritePolicy.catalogOnly.title == "Songbird catalog only")
    }
}
