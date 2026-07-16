import SwiftUI

/// Explains a context trim or an agent guard inline in the transcript.
///
/// Without this the same events read as the assistant silently forgetting the
/// start of the conversation, or stopping mid-task for no reason. The server
/// sends an English `message` on some of them — we ignore it and phrase the
/// notice here so it follows the app's language.
struct ChatNoticeBanner: View {
    @Environment(\.theme) private var theme
    let notice: ChatNotice

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: notice.icon)
                .font(.system(size: 11))
                .foregroundStyle(theme.accent)
                .padding(.top, 1)
            label
                .font(.ody(size: 12))
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(theme.panel.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
    }

    /// The counted variants only run for 2+. The source has a single `%lld` form,
    /// so "1 mensagens" would be ungrammatical in pt-BR and in most of the 43
    /// translations — a count of one falls back to the count-free sentence rather
    /// than dragging a .stringsdict plural table into every language.
    @ViewBuilder
    private var label: some View {
        switch notice.kind {
        case .contextTrimmed(let removed) where removed > 1:
            Text("\(removed) mensagens antigas saíram do contexto para caber no limite.")
        case .contextTrimmed:
            Text("Mensagens antigas saíram do contexto para caber no limite.")
        case .compacted:
            Text("O histórico foi resumido para caber no limite de contexto.")
        case .roundsExhausted(let rounds) where rounds > 1:
            Text("O agente parou ao atingir o limite de \(rounds) rodadas.")
        case .roundsExhausted:
            Text("O agente parou ao atingir o limite de rodadas.")
        case .budgetExceeded(let limit, _) where limit > 1:
            Text("O agente parou ao atingir o limite de \(limit) chamadas de ferramenta.")
        case .budgetExceeded:
            Text("O agente parou ao atingir o limite de chamadas de ferramenta.")
        case .loopBreaker:
            Text("O agente repetia as mesmas ferramentas sem avançar, então foi interrompido para responder com o que já tinha.")
        case .intentNudgeExhausted:
            Text("O agente não conseguiu executar a ação pedida e parou.")
        }
    }
}
