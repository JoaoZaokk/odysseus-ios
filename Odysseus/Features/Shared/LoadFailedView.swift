import SwiftUI

/// Shown when a screen's load *failed* and it has nothing to show — as opposed to
/// having loaded successfully and found nothing.
///
/// Those are different facts, and every list screen used to render them the same
/// way: the empty state was gated on `items.isEmpty` alone, so a failed fetch told
/// the user their notes, memories or documents did not exist. The `error` those
/// view models had already captured was never displayed anywhere.
struct LoadFailedView: View {
    let message: String
    var retry: (() -> Void)?
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.ody(size: 44)).foregroundStyle(theme.accent)
            // No generic headline on purpose: the message itself says what went
            // wrong, and it is a pt-BR literal that doubles as a catalogue key —
            // the contract every other error line in the app relies on. Adding a
            // heading would mean a 45th untranslated string for no information.
            Text(LocalizedStringKey(message))
                .font(.ody(.headline, design: .monospaced))
                .foregroundStyle(theme.fg)
                .multilineTextAlignment(.center)
            if let retry {
                Button(action: retry) {
                    Text("Tentar de novo")
                        .font(.ody(.footnote, design: .monospaced))
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .overlay(Capsule().stroke(theme.border, lineWidth: 1))
                }
                .padding(.top, 2)
            }
        }
        .padding(40)
    }
}
