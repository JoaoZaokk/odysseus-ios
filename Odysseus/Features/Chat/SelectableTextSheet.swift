#if os(iOS)
import SwiftUI
import UIKit

/// A message's text in a view that selects by range, so a part of an answer
/// can be copied. SwiftUI's `.textSelection` on iPhone offers the whole text or
/// nothing. (On the Mac it already selects by range, so there is no sheet.)
/// Ported from the Open WebUI app 1.12.
struct SelectableTextSheet: View {
    let text: String
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SelectableTextView(text: text, color: UIColor(theme.fg))
                .padding(.horizontal, Spacing.gutter - 4)
                .background(theme.bg)
                .odyNavTitle("Selecionar texto")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { BarButton("Concluído") { dismiss() } } }
        }
        .presentationDetents([.large])
    }
}

private struct SelectableTextView: UIViewRepresentable {
    let text: String
    let color: UIColor

    func makeUIView(context: Context) -> UITextView {
        let v = UITextView()
        v.isEditable = false
        v.isSelectable = true
        v.backgroundColor = .clear
        v.font = .preferredFont(forTextStyle: .body)
        v.adjustsFontForContentSizeCategory = true
        v.textContainerInset = UIEdgeInsets(top: 12, left: 0, bottom: 24, right: 0)
        v.accessibilityIdentifier = "message.selectableText"
        return v
    }

    func updateUIView(_ v: UITextView, context: Context) {
        if v.text != text { v.text = text }
        v.textColor = color
    }
}
#endif
