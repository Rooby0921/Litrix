import SwiftUI

enum PaperRatingPalette {
    static let filledColor = Color(
        red: 0x5D / 255.0,
        green: 0xC3 / 255.0,
        blue: 0xF5 / 255.0
    )
}

struct StarRatingView: View {
    @Binding var rating: Int
    var starSize: CGFloat = 14
    var showsLabel = false

    private var currentRating: Int {
        PaperRatingScale.clamped(rating)
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...PaperRatingScale.maximum, id: \.self) { value in
                Button {
                    rating = rating == value ? 0 : value
                } label: {
                    Image(systemName: value <= currentRating ? "star.fill" : "star")
                        .font(.system(size: starSize, weight: .medium))
                        .foregroundStyle(value <= currentRating ? PaperRatingPalette.filledColor : Color.secondary.opacity(0.55))
                }
                .buttonStyle(.plain)
            }

            if showsLabel {
                Text("\(currentRating) / \(PaperRatingScale.maximum)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
        }
    }
}

struct StarRatingBadge: View {
    let rating: Int

    private var currentRating: Int {
        PaperRatingScale.clamped(rating)
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...PaperRatingScale.maximum, id: \.self) { value in
                Image(systemName: value <= currentRating ? "star.fill" : "star")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(value <= currentRating ? PaperRatingPalette.filledColor : Color.secondary.opacity(0.45))
            }
        }
    }
}
