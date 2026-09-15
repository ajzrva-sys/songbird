import Testing
@testable import SongbirdLib

struct GenreMetadataTests {
    @Test("Blank and whitespace-only genres are missing")
    func missingGenres() {
        #expect(GenreMetadata.isMissing(""))
        #expect(GenreMetadata.isMissing("   "))
        #expect(GenreMetadata.isMissing("\n\t"))
        #expect(GenreMetadata.isMissing("\u{2009}"))
    }

    @Test("Visible genre text remains assigned")
    func assignedGenre() {
        #expect(GenreMetadata.isMissing(" Rock ") == false)
    }

    @Test("Normalization removes surrounding whitespace")
    func normalization() {
        #expect(GenreMetadata.normalized("  Alternative\n") == "Alternative")
    }
}
