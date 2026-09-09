import SwiftUI

/// The assistant's question back to the user, rendered where the reply would
/// have been.
///
/// The agent's `ask_user` tool ends the turn with no text at all: the question
/// IS the reply, and the answer is the next message. A client that drops the
/// event leaves the user looking at an empty turn — which is exactly what the
/// 1.8 reviews described.
///
/// Two shapes share the card. A plain question offers its options plus a
/// free-text way out. A tool approval (`kind == "tool_approval"`) shows the
/// exact action being authorized and only its own buttons — a typed answer is
/// not an authorization.
struct AskUserCard: View {
    @Environment(\.theme) private var theme
    let ask: AskUser
    /// Chosen labels — one, or several when `ask.multi`.
    var onAnswer: ([String]) -> Void
    /// An approval decision, carried by the option itself.
    var onDecide: (AskUser.Option) -> Void
    var onDismiss: () -> Void

    @State private var picked: Set<String> = []
    @State private var other = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let d = ask.description, !d.isEmpty {
                Text(d)
                    .font(.ody(size: 12))
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let action = ask.action { actionDetail(action) }
            VStack(spacing: 6) {
                ForEach(ask.options) { option($0) }
            }
            if !ask.isApproval { freeText }
        }
        .padding(12)
        .background(theme.panel.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.accent.opacity(0.5), lineWidth: 1))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: ask.isApproval ? "lock.shield" : "questionmark.bubble")
                .font(.system(size: 13))
                .foregroundStyle(theme.accent)
                .padding(.top, 1)
            Text(ask.question)
                .font(.ody(size: 14).weight(.semibold))
                .foregroundStyle(theme.fg)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Fechar"))
        }
    }

    /// Verbatim, monospaced: the user is authorizing this exact command, so it
    /// must not be reworded or truncated into something friendlier.
    private func actionDetail(_ a: AskUser.Action) -> some View {
        let lines = [a.tool, a.content,
                     (a.effects?.isEmpty == false) ? a.effects!.joined(separator: ", ") : nil,
                     a.workspace, a.documentID]
            .compactMap { $0 }.filter { !$0.isEmpty }
        return Text(lines.joined(separator: "\n"))
            .font(.ody(size: 11).monospaced())
            .foregroundStyle(theme.secondaryText)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(theme.bg.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func option(_ o: AskUser.Option) -> some View {
        Button {
            if ask.isApproval { onDecide(o) }
            else if ask.multi { toggle(o.label) }
            else { onAnswer([o.label]) }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                if ask.multi && !ask.isApproval {
                    Image(systemName: picked.contains(o.label) ? "checkmark.square.fill" : "square")
                        .font(.system(size: 13))
                        .foregroundStyle(picked.contains(o.label) ? theme.accent : theme.secondaryText)
                        .padding(.top, 1)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(o.label)
                        .font(.ody(size: 13))
                        .foregroundStyle(theme.fg)
                        .multilineTextAlignment(.leading)
                    if let d = o.description, !d.isEmpty {
                        Text(d)
                            .font(.ody(size: 11))
                            .foregroundStyle(theme.secondaryText)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.bg.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var freeText: some View {
        HStack(spacing: 8) {
            TextField("Outra resposta…", text: $other)
                .textFieldStyle(.plain)
                .font(.ody(size: 13))
                .foregroundStyle(theme.fg)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(theme.bg.opacity(0.55), in: Capsule())
                .overlay(Capsule().stroke(theme.border, lineWidth: 1))
                .onSubmit(submit)
            Button(action: submit) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(canSubmit ? theme.bg : theme.secondaryText)
                    .frame(width: 30, height: 30)
                    .background(canSubmit ? theme.accent : theme.panel, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .accessibilityLabel(Text("Enviar mensagem"))
        }
    }

    private var canSubmit: Bool {
        !other.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (ask.multi && !picked.isEmpty)
    }

    private func toggle(_ label: String) {
        if picked.contains(label) { picked.remove(label) } else { picked.insert(label) }
    }

    /// Multi-select sends the ticks plus anything typed, in the order shown —
    /// `picked` is a Set, so the option list is what fixes the order.
    private func submit() {
        let typed = other.trimmingCharacters(in: .whitespacesAndNewlines)
        var answers = ask.multi ? ask.options.map(\.label).filter(picked.contains) : []
        if !typed.isEmpty { answers.append(typed) }
        guard !answers.isEmpty else { return }
        other = ""
        picked = []
        onAnswer(answers)
    }
}
