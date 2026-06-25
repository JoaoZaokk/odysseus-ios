import SwiftUI

// Image-generation server settings: configure ComfyUI / OpenWebUI Gen / generic Diffusion
// endpoints, a default provider, automatic fallback, and a live "Test connection" that pulls
// real status (GPUs / VRAM / models / queue) straight from the user's ComfyUI server and
// estimates which models fit the machine. Architecture + config + status this phase; deep
// workflow generation (txt2img/upscale/inpaint) is documented in DIFFUSION_COMFYUI_PLAN.md.

enum ImageGenProvider: String, CaseIterable, Identifiable {
    case openwebui, comfyui, generic
    var id: String { rawValue }
    var label: String {
        switch self {
        case .openwebui: return "OpenWebUI Gen"
        case .comfyui: return "ComfyUI"
        case .generic: return "Diffusion API"
        }
    }
}

/// Client-side config (the servers are the user's own; no secrets). Persisted in UserDefaults.
enum DiffusionConfigKeys {
    static let comfyURL = "diffusion.comfyURL"
    static let openwebuiURL = "diffusion.openwebuiURL"
    static let genericURL = "diffusion.genericURL"
    static let defaultProvider = "diffusion.defaultProvider"
    static let fallback = "diffusion.fallbackEnabled"
    static let timeout = "diffusion.timeoutSeconds"
}

@MainActor final class DiffusionProbeVM: ObservableObject {
    @Published var loading = false
    @Published var stats: ComfyStats?
    @Published var models: ComfyModels?
    @Published var queue: (Int, Int)?
    @Published var error: String?
    @Published var lastTestedURL: String?

    func test(_ url: String, timeout: TimeInterval) async {
        loading = true; error = nil; stats = nil; models = nil; queue = nil
        defer { loading = false }
        let client = ComfyUIClient(baseURL: url, timeout: timeout)
        do {
            stats = try await client.systemStats()
            models = try? await client.models()
            queue = try? await client.queueCounts()
            lastTestedURL = url
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Checkpoints + UNETs annotated with a fit estimate against the best GPU.
    func fitRows() -> [(name: String, fit: ComfyCapacity.Fit)] {
        guard let stats, let models else { return [] }
        let free = stats.maxGPUFreeGB
        let names = (models.checkpoints + models.unets)
        return names.map { ($0, ComfyCapacity.fit(filename: $0, maxGPUFreeGB: free)) }
    }
}

struct DiffusionServersView: View {
    @Environment(\.theme) private var theme
    @StateObject private var vm = DiffusionProbeVM()

    @AppStorage(DiffusionConfigKeys.comfyURL) private var comfyURL = ""
    @AppStorage(DiffusionConfigKeys.openwebuiURL) private var openwebuiURL = ""
    @AppStorage(DiffusionConfigKeys.genericURL) private var genericURL = ""
    @AppStorage(DiffusionConfigKeys.defaultProvider) private var defaultProvider = ImageGenProvider.comfyui.rawValue
    @AppStorage(DiffusionConfigKeys.fallback) private var fallbackEnabled = true
    @AppStorage(DiffusionConfigKeys.timeout) private var timeoutSeconds = 20

    var body: some View {
        SettingsScroll("Geração de imagem", subtitle: "Provedores de imagem, fallback e capacidade do servidor.") {
            providersCard
            comfyCard
            otherProvidersCard
            fallbackNote
        }
    }

    // MARK: Providers / defaults

    private var providersCard: some View {
        SettingsCard {
            Text("Provedores").font(.ody(.subheadline, design: .monospaced, weight: .semibold)).foregroundStyle(theme.fg)
            SettingsUI.menuRow("Provedor padrão",
                               value: ImageGenProvider(rawValue: defaultProvider)?.label ?? "ComfyUI",
                               options: ImageGenProvider.allCases.map(\.label), theme: theme) { picked in
                if let p = ImageGenProvider.allCases.first(where: { $0.label == picked }) { defaultProvider = p.rawValue }
            }
            Toggle(isOn: $fallbackEnabled) {
                Text("Fallback automático").font(.ody(.subheadline, design: .monospaced)).foregroundStyle(theme.fg)
            }.tint(theme.accent)
            Text("Se o provedor padrão falhar, tenta os outros na ordem: \(fallbackOrderText).")
                .font(.ody(size: 10, design: .monospaced)).foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("Timeout").font(.ody(.subheadline, design: .monospaced)).foregroundStyle(theme.fg)
                Spacer()
                Stepper("\(timeoutSeconds)s", value: $timeoutSeconds, in: 5...120, step: 5)
                    .font(.ody(size: 11, design: .monospaced)).fixedSize()
            }
        }
    }

    private var fallbackOrderText: String {
        var order = ImageGenProvider.allCases.map(\.label)
        if let i = order.firstIndex(of: ImageGenProvider(rawValue: defaultProvider)?.label ?? "") {
            let d = order.remove(at: i); order.insert(d, at: 0)
        }
        return order.joined(separator: " → ")
    }

    // MARK: ComfyUI (configurable + live status)

    private var comfyCard: some View {
        SettingsCard {
            HStack {
                Image(systemName: "cpu").foregroundStyle(theme.accent)
                Text("ComfyUI").font(.ody(.subheadline, design: .monospaced, weight: .semibold)).foregroundStyle(theme.fg)
                Spacer()
                statusBadge
            }
            SettingsUI.field("Endereço do servidor", $comfyURL, placeholder: "http://comfyui-host:8190", theme: theme)
            HStack(spacing: 10) {
                Button { Task { await vm.test(comfyURL, timeout: TimeInterval(timeoutSeconds)) } } label: {
                    Label("Testar conexão", systemImage: "bolt.horizontal")
                        .font(.ody(size: 12, design: .monospaced)).foregroundStyle(theme.accent)
                }.buttonStyle(.plain).disabled(comfyURL.isEmpty || vm.loading)
                if vm.loading { ProgressView().controlSize(.small) }
                Spacer()
            }
            if let e = vm.error {
                Text(e).font(.ody(size: 11, design: .monospaced)).foregroundStyle(Color(hex: "e05a4a"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let s = vm.stats { statusDetail(s) }
        }
    }

    private var statusBadge: some View {
        Group {
            if vm.loading { Text("testando…").foregroundStyle(theme.secondaryText) }
            else if vm.stats != nil { Text("online").foregroundStyle(theme.green) }
            else if vm.error != nil { Text("offline").foregroundStyle(Color(hex: "e05a4a")) }
            else { Text("não testado").foregroundStyle(theme.secondaryText) }
        }
        .font(.ody(size: 10, design: .monospaced))
    }

    @ViewBuilder private func statusDetail(_ s: ComfyStats) -> some View {
        Divider().overlay(theme.border)
        infoRow("Versão", "ComfyUI \(s.comfyVersion) · \(s.os)")
        infoRow("Python / Torch", "\(s.pythonVersion) · \(s.pytorchVersion)")
        infoRow("RAM", String(format: "%.0f GB livre / %.0f GB", s.ramFreeGB, s.ramTotalGB))
        ForEach(s.gpus) { g in
            infoRow("GPU \(g.index)", "\(g.name.replacingOccurrences(of: "NVIDIA GeForce ", with: "")) · " +
                    String(format: "%.1f GB livre / %.1f GB", g.vramFreeGB, g.vramTotalGB))
        }
        if let q = vm.queue { infoRow("Fila", "\(q.0) rodando · \(q.1) na fila") }
        if let m = vm.models {
            infoRow("Modelos", "\(m.checkpoints.count) ckpt · \(m.unets.count) unet · \(m.loras.count) lora · \(m.vae.count) vae · \(m.controlnet.count) cnet")
            fitSection()
        }
    }

    @ViewBuilder private func fitSection() -> some View {
        let rows = vm.fitRows()
        if !rows.isEmpty {
            Divider().overlay(theme.border)
            Text("Cabe na máquina (estimativa, melhor GPU)")
                .font(.ody(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(theme.fg)
            ForEach(rows.prefix(14), id: \.name) { row in
                HStack(spacing: 8) {
                    fitDot(row.fit)
                    Text(row.name).font(.ody(size: 9, design: .monospaced)).foregroundStyle(theme.secondaryText)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(fitLabel(row.fit)).font(.ody(size: 9, design: .monospaced)).foregroundStyle(fitColor(row.fit))
                }
            }
            Text("Estimativa por nome (fp8≈1B/param, fp16/bf16≈2B/param) + ~3 GB de folga. Não substitui um teste real.")
                .font(.ody(size: 9, design: .monospaced)).foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func fitDot(_ f: ComfyCapacity.Fit) -> some View {
        Circle().fill(fitColor(f)).frame(width: 6, height: 6)
    }
    private func fitColor(_ f: ComfyCapacity.Fit) -> Color {
        switch f {
        case .fits: return theme.green
        case .tight: return Color(hex: "e0a33a")
        case .tooBig: return Color(hex: "e05a4a")
        case .unknown: return theme.secondaryText
        }
    }
    private func fitLabel(_ f: ComfyCapacity.Fit) -> String {
        switch f {
        case .fits: return "cabe"
        case .tight: return "apertado"
        case .tooBig: return "não cabe"
        case .unknown: return "—"
        }
    }

    // MARK: Other providers

    private var otherProvidersCard: some View {
        SettingsCard {
            Text("Outros provedores").font(.ody(.subheadline, design: .monospaced, weight: .semibold)).foregroundStyle(theme.fg)
            SettingsUI.field("OpenWebUI Gen URL", $openwebuiURL, placeholder: "vazio = usa o servidor principal", theme: theme)
            SettingsUI.field("Diffusion API URL", $genericURL, placeholder: "http://host:porta", theme: theme)
            Text("OpenWebUI Gen usa a sessão do servidor principal por padrão. A Diffusion API genérica é um endpoint compatível para fallback.")
                .font(.ody(size: 10, design: .monospaced)).foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var fallbackNote: some View {
        SettingsCard {
            Text("Como o fallback funciona").font(.ody(.subheadline, design: .monospaced, weight: .semibold)).foregroundStyle(theme.fg)
            Text("Pedido de imagem → provedor padrão → se falhar e o fallback estiver ligado, tenta os próximos → se todos falharem, erro claro. Logs sem dados sensíveis. Geração profunda (txt2img, upscale, inpaint, outpaint, multi-GPU) está documentada em DIFFUSION_COMFYUI_PLAN.md para a próxima fase.")
                .font(.ody(size: 10, design: .monospaced)).foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func infoRow(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).font(.ody(size: 11, design: .monospaced)).foregroundStyle(theme.secondaryText).frame(width: 110, alignment: .leading)
            Text(v).font(.ody(size: 11, design: .monospaced)).foregroundStyle(theme.fg)
                .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
        }
    }
}
