import SwiftUI
#if os(iOS)
import MessageUI
#else
import AppKit
#endif

/// "Reportar bug": one text field, one sentence saying what goes, then the
/// user's own mail app with the report attached. The file can also be shared
/// or saved by hand when no mail account is set up.
struct BugReportSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var description = ""
    @State private var package: BugReport.Package?
    @State private var showMail = false
    @State private var outcome: Outcome?

    enum Outcome { case sent, shared, failed }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Vai junto: aparelho, versão do app e do sistema, memória e a última hora de registros (tempos de carga, travamentos, log do motor de voz). Nunca áudio, texto ou o endereço do seu servidor. Nada sai sem você tocar em enviar.")
                        .font(.ody(size: 11)).foregroundStyle(theme.secondaryText)
                    TextField("O que aconteceu?", text: $description, axis: .vertical)
                        .lineLimit(3...8)
                        .textFieldStyle(.plain).font(.ody(.body)).foregroundStyle(theme.fg)
                        .padding(10).background(theme.panel, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
                    #if os(iOS)
                    if MailComposer.canSend {
                        Button {
                            package = BugReport.make(description: description)
                            showMail = true
                        } label: { Label("Enviar por e-mail", systemImage: "envelope") }
                        .buttonStyle(.plain).foregroundStyle(theme.accent).font(.ody(.subheadline))
                    } else {
                        Text("Nenhum app de e-mail configurado neste aparelho. Compartilhe o arquivo por outro caminho.")
                            .font(.ody(size: 11)).foregroundStyle(theme.secondaryText)
                    }
                    #else
                    Button {
                        let p = BugReport.make(description: description)
                        outcome = MailComposerMac.send(p) ? .sent : .failed
                        if outcome == .sent { DiagnosticsStore.shared.event("bugreport.sent") }
                    } label: { Label("Enviar por e-mail", systemImage: "envelope") }
                    .buttonStyle(.plain).foregroundStyle(theme.accent).font(.ody(.subheadline))
                    #endif
                    Button {
                        Task {
                            let p = BugReport.make(description: description)
                            let ok = await SettingsUI.saveJSON(p.json, suggested: p.filename)
                            if ok == true { outcome = .shared; DiagnosticsStore.shared.event("bugreport.shared") }
                            else if ok == false { outcome = .failed }
                        }
                    } label: { Label("Compartilhar arquivo", systemImage: "square.and.arrow.up") }
                    .buttonStyle(.plain).foregroundStyle(theme.accent).font(.ody(.subheadline))
                    switch outcome {
                    case .sent: Label("Enviado", systemImage: "checkmark.circle.fill").foregroundStyle(theme.green).font(.ody(size: 11))
                    case .shared: Label("Exportado", systemImage: "checkmark.circle.fill").foregroundStyle(theme.green).font(.ody(size: 11))
                    case .failed: Label("Nenhum app de e-mail configurado neste aparelho. Compartilhe o arquivo por outro caminho.", systemImage: "exclamationmark.triangle").foregroundStyle(theme.danger).font(.ody(size: 11))
                    case nil: EmptyView()
                    }
                }
                .padding(16)
            }
            .background(theme.bg)
            .navigationTitle(L("Relatório de bug"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } }
            }
            #if os(iOS)
            .sheet(isPresented: $showMail) {
                if let package {
                    MailComposer(package: package) { result in
                        showMail = false
                        if result == .sent { outcome = .sent; DiagnosticsStore.shared.event("bugreport.sent") }
                    }
                    .ignoresSafeArea()
                }
            }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 380)
        #endif
    }
}

#if os(iOS)
/// The system mail composer, prefilled. The user sees recipient, subject,
/// body and attachment and presses Send (or Cancel) themselves.
struct MailComposer: UIViewControllerRepresentable {
    let package: BugReport.Package
    let onFinish: (MFMailComposeResult) -> Void

    static var canSend: Bool { MFMailComposeViewController.canSendMail() }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients([BugReport.recipient])
        vc.setSubject(package.subject)
        vc.setMessageBody(package.body, isHTML: false)
        vc.addAttachmentData(package.json, mimeType: "application/json", fileName: package.filename)
        return vc
    }
    func updateUIViewController(_ vc: MFMailComposeViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (MFMailComposeResult) -> Void
        init(onFinish: @escaping (MFMailComposeResult) -> Void) { self.onFinish = onFinish }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            onFinish(result)
        }
    }
}
#else
/// Mail.app (or whatever handles mail) via the system sharing service: a new
/// message with recipient, subject, body and the JSON attached.
enum MailComposerMac {
    static func send(_ p: BugReport.Package) -> Bool {
        guard let service = NSSharingService(named: .composeEmail) else { return false }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(p.filename)
        do { try p.json.write(to: url) } catch { return false }
        service.recipients = [BugReport.recipient]
        service.subject = p.subject
        let items: [Any] = [p.body, url]
        guard service.canPerform(withItems: items) else { return false }
        service.perform(withItems: items)
        return true
    }
}
#endif
