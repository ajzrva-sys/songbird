import Foundation

public enum DiscogsGenreSuggestionPolicy {
    public static func suggestedGenre(from candidateGenres: [[String]]) -> String? {
        for genres in candidateGenres {
            guard let first = genres.first else { continue }
            let normalized = GenreMetadata.normalized(first)
            if normalized.isEmpty == false {
                return normalized
            }
        }
        return nil
    }
}
