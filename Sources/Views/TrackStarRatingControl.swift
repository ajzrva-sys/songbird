import SwiftUI

/// Interactive star rating control styled after the original Songbird's
/// gold/amber rating stars. Displays 0-5 stars with hover preview.
public struct TrackStarRatingControl: View {
    @Binding var rating: Int
    var maxRating: Int = 5
    var starSize: CGFloat = 12
    var allowsClear: Bool = true

    @State private var hoverRating: Int?

    private var displayedRating: Int {
        hoverRating ?? rating
    }

    public init(rating: Binding<Int>, maxRating: Int = 5, starSize: CGFloat = 12, allowsClear: Bool = true) {
        self._rating = rating
        self.maxRating = maxRating
        self.starSize = starSize
        self.allowsClear = allowsClear
    }

    public var body: some View {
        HStack(spacing: 1) {
            ForEach(1...maxRating, id: \.self) { star in
                Button {
                    if allowsClear, rating == star {
                        rating = 0
                    } else {
                        rating = star
                    }
                } label: {
                    Image(systemName: star <= displayedRating ? "star.fill" : "star")
                        .font(.system(size: starSize, weight: .medium))
                        .foregroundColor(starColor(for: star))
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    hoverRating = hovering ? star : nil
                }
                .contentShape(Rectangle())
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rating")
        .accessibilityValue("\(rating) of \(maxRating) stars")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                rating = min(rating + 1, maxRating)
            case .decrement:
                rating = max(rating - 1, 0)
            @unknown default:
                break
            }
        }
    }

    private func starColor(for star: Int) -> Color {
        if star <= displayedRating {
            // Gold/amber color inspired by the original Songbird rating stars
            return RatingStarStyle.filledColor
        } else if hoverRating != nil, star <= (hoverRating ?? 0) {
            // Hover preview at reduced opacity
            return RatingStarStyle.filledColor.opacity(0.6)
        } else {
            return RatingStarStyle.emptyColor
        }
    }
}

/// Display-only star rating view for table cells and non-interactive contexts.
public struct StarRatingDisplay: View {
    let rating: Int
    var maxRating: Int = 5
    var starSize: CGFloat = 10

    public init(rating: Int, maxRating: Int = 5, starSize: CGFloat = 10) {
        self.rating = rating
        self.maxRating = maxRating
        self.starSize = starSize
    }

    public var body: some View {
        HStack(spacing: 1) {
            ForEach(1...maxRating, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .font(.system(size: starSize, weight: .medium))
                    .foregroundColor(star <= rating ? RatingStarStyle.filledColor : RatingStarStyle.emptyColor)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rating")
        .accessibilityValue("\(rating) of \(maxRating) stars")
    }
}

/// Style tokens for the rating star control.
public enum RatingStarStyle {
    /// Gold/amber filled star color, matching the original Songbird aesthetic.
    public static let filledColor = Color(red: 0.85, green: 0.65, blue: 0.13)
    /// Empty star color using tertiary label.
    public static let emptyColor = Color.secondary.opacity(0.4)
    /// Hover preview color.
    public static let hoverColor = filledColor.opacity(0.6)
}
