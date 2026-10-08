import SwiftUI

/// The empty state of a list or grid screen.
///
/// It sits a fixed `Spacing.voidOffset` under whatever is above it, and does
/// not centre itself in the leftover height: centred, it floated at a
/// different height on every screen and device ("Como posso ajudar?" at
/// y≈390 in a void that ran to 1100).
struct EmptyStateView: View {
    let icon: String
    let title: String
    var message: String? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.ody(size: 44))
                .foregroundStyle(theme.accent)
                .accessibilityHidden(true)
            Text(LocalizedStringKey(title))
                .font(.ody(.headline))
                .foregroundStyle(theme.fg)
            if let message {
                Text(LocalizedStringKey(message))
                    .font(.ody(.footnote))
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, Spacing.gutter)
        .voidAnchored()
    }
}

extension View {
    /// Puts a lone block `Spacing.voidOffset` under the content above it and
    /// lets the rest of the height stay empty below it.
    func voidAnchored() -> some View {
        padding(.top, Spacing.voidOffset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

extension String {
    /// First letter up, the rest as the formatter wrote it.
    ///
    /// `.capitalized` raises every word: "qui., 17 de set." became
    /// "Qui., 17 De Set." and "segunda-feira" became "Segunda-Feira".
    func capitalizedFirst(_ locale: Locale) -> String {
        guard let first else { return self }
        return String(first).uppercased(with: locale) + dropFirst()
    }
}
