import SwiftUI

struct StarRatingView: View {
    @Binding var rating: Int
    var starSize: CGFloat = 14
    var showsLabel = false
    @EnvironmentObject private var settings: SettingsStore

    private var currentRating: Int {
        PaperRatingScale.clamped(rating)
    }

    // Star color comes from SettingsStore, falls back to blue (#5DC3F5).
    private var filledColor: Color {
        colorFromHex(settings.starColorHex) ?? Color(
            red: 0x5D / 255,
            green: 0xC3 / 255,
            blue: 0xF5 / 255
        )
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...PaperRatingScale.maximum, id: \.self) { value in
                Button {
                    rating = rating == value ? 0 : value
                } label: {
                    Image(systemName: value <= currentRating ? "star.fill" : "star")
                        .font(.system(size: starSize, weight: .medium))
                        .foregroundStyle(value <= currentRating ? filledColor : Color.secondary.opacity(0.55))
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
    @EnvironmentObject private var settings: SettingsStore

    private var currentRating: Int {
        PaperRatingScale.clamped(rating)
    }

    // Star color comes from SettingsStore, falls back to blue (#5DC3F5).
    private var filledColor: Color {
        colorFromHex(settings.starColorHex) ?? Color(
            red: 0x5D / 255,
            green: 0xC3 / 255,
            blue: 0xF5 / 255
        )
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...PaperRatingScale.maximum, id: \.self) { value in
                Image(systemName: value <= currentRating ? "star.fill" : "star")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(value <= currentRating ? filledColor : Color.secondary.opacity(0.45))
            }
        }
    }
}

private func colorFromHex(_ hex: String) -> Color? {
    let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
    guard cleaned.count == 6, let intValue = Int(cleaned, radix: 16) else { return nil }
    return Color(
        red: Double((intValue >> 16) & 0xFF) / 255,
        green: Double((intValue >> 8) & 0xFF) / 255,
        blue: Double(intValue & 0xFF) / 255
    )
}
