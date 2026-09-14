# Porte: o que a rodada 1.11 do Odysseus-iOS fez, para aplicar no OpenWebUI-iOS

Escrito em 14/09/2026 a partir do código real de `/Users/joaozao/Projetos/Odysseus-iOS`
(commits `b65da03..29e3239`, main). Leitor: a sessão que trabalha em
`/Users/joaozao/Projetos/OpenWebUI-iOS` (mesmo scaffold, iPhone-only, 44 catálogos,
ainda em SwiftWhisper de 2023 + FluidAudio). Nada aqui é ordem de fazer tudo; é o
inventário do que existe, com caminho, símbolo e armadilha, para o porte ser decisão
informada e não redescoberta.

## 0. TL;DR

O que a 1.11 entregou no Odysseus (iOS build 27, macOS build 21, 351 testes, no App
Store Connect aguardando Submit do dono):

1. **Motor novo.** `SwiftWhisper` saiu. Entrou o xcframework oficial do ggml-org
   (`whisper-b5130`, corte da v1.9.4) via pacote local `Vendor/WhisperCPP`, com
   `libwhisper` **e** `libparakeet`. Parakeet TDT roda no mesmo ggml, com Metal.
2. **Um dono do motor.** `STTRunner.shared`: fila serial fora do MainActor, contexto em
   cache, solta em memory warning/background, recusa carregar quando
   `os_proc_available_memory()` não cobre `bytes × 1,3 + encoder Core ML + 300 MB`.
   Entitlement `com.apple.developer.kernel.increased-memory-limit` no iOS.
3. **Core ML que nunca ligava.** A pasta do encoder era instalada com o sufixo da
   quantização (`…-q5_0-encoder.mlmodelc`); o whisper.cpp procura `…-encoder.mlmodelc`.
   Falhava em silêncio no stderr e o turbo rodava fora do Neural Engine. Corrigido com
   a regra do próprio whisper.cpp e renomeação das pastas legadas.
4. **Catálogo por idioma.** 21 `VoiceLang` (15 novos), motor pelo prefixo do id (`p-` Parakeet,
   `w-`/`u-` Whisper), 24 espelhos próprios em `huggingface.co/JoaoZaokk/*` (23 `*-ggml`
   no app + Nemotron `-gguf` só no HF; q4_0/q5_0/q8_0, card com crédito e licença de
   origem), tamanhos reais no catálogo.
5. **Áudio salvo antes de transcrever.** `PendingAudioStore`: WAV 16 kHz mono atômico +
   sidecar, alerta Transcrever/Descartar/Depois no launch, `attempts` sobe antes do load
   (arquivo não vira laço de crash).
6. **Decode afinado.** `temperature_inc 0.4`, `best_of 2`, `audio_ctx` pelo clipe (só
   sem Core ML), `n_threads = min(4, cores)`, `suppress_nst`, `initial_prompt` por idioma
   pedindo números por extenso ("um centavo" deixou de virar "1/100").
7. **Diagnóstico local + "Reportar bug" por e-mail.** Spool NDJSON, spans abertos que
   viram `death.suspected` no launch seguinte, MetricKit (único rastro oficial de
   jetsam), log do motor num anel. **Sem telemetria de servidor** (decisão do dono
   13/09): o botão abre o app de e-mail do usuário com JSON da última hora. Ficha da App
   Store continua "Dados não coletados"; `PrivacyInfo.xcprivacy` com tipos coletados vazio.
8. **Publicação.** Entitlement nova invalida o perfil App Store gerido pelo Xcode e a
   chave de API não regenera: criar perfil pela API + export manual. `plutil -lint` no
   manifesto dentro do `.xcarchive` antes de subir.

### Restrições que valem também no OpenWebUI-iOS

- Sub-agentes e workflows: **sonnet** por padrão (quota semanal e de 5 h). Opus só a
  pedido do dono. Fable nunca.
- Host real do servidor do dono **nunca** em arquivo versionado (placeholder
  `odysseus.exemplo.com` / equivalente). Repositório público exige sanitização antes do push.
- `DEVELOPMENT_TEAM` fica em `Local.xcconfig` gitignored. Sem senhas, sem `sudo`.
- Chave privada da App Store Connect API em `~/.appstoreconnect/private_keys/`: nunca
  impressa, nunca commitada. Token de escrita do Hugging Face só o dono digita.
- Submit for Review e atualizações do servidor são do dono. Nada de uploader de
  diagnóstico, toggle de telemetria ou coletor; a decisão já foi tomada.
- f16 antigos no HF ficam (referência). Os cards creditam autor e licença; é isso que importa.

## 1. Motor: whisper.cpp 1.9.4 (xcframework) + Parakeet TDT + STTRunner

### 1.1 O que mudou e por quê

Até a 1.10, o Odysseus (como o OpenWebUI-iOS ainda hoje) dependia de `SwiftWhisper`
(`exPHAT/SwiftWhisper`, branch `master`), um wrapper que vendora um whisper.cpp de 2023:
sem Parakeet, sem `suppress_nst`, alocação por tabela fixa (não hídrica ao tamanho real do
modelo). O dono pediu um catálogo com modelos "famosos" de STT incluindo Parakeet da
NVIDIA — impossível dentro do SwiftWhisper.

A 1.11 trocou a dependência pelo **xcframework oficial do ggml-org**, que empacota
`libwhisper` e `libparakeet` num único binário Metal, e reescreveu a camada de motor do
zero em `OnDeviceSTT.swift`. Junto vieram três correções de bugs graves achados por
investigação de campo (rodada 9b, ver seção 4): o encoder Core ML nunca era encontrado em
modelo quantizado, o app carregava até três cópias do mesmo contexto (jetsam), e o load
rodava no thread principal (UI congelada por minutos na primeira compilação Core ML).

O OpenWebUI-iOS está exatamente no ponto de partida da 1.10: `SwiftWhisper` ainda importado
em `VoiceInputManager.swift` (único arquivo que o importa; `BargeInMonitor.swift`,
`NeuralVoiceStore.swift` e `SpeechManager.swift` importam `FluidAudio`, que fica); `ModelDownloadManager.coreMLFolderName` com o mesmo bug do encoder
(confirmado lendo o código — ver 5.3); nenhum gate de memória; load de modelo direto na
`VoiceInputManager` (a confirmar se está no `MainActor`, mas não há fila serial nem
`STTRunner` equivalente).

### 1.2 Arquivos e símbolos no Odysseus (caminhos reais)

- `Vendor/WhisperCPP/Package.swift` — pacote SwiftPM local que só embrulha o binário.
- `project.yml` — `packages.WhisperCPP` (`path: Vendor/WhisperCPP`), `dependencies:
  - package: WhisperCPP` nos dois targets (iOS e macOS), `CODE_SIGN_ENTITLEMENTS:
  Odysseus/Resources/Odysseus.entitlements` novo no target iOS.
- `Odysseus/Resources/Odysseus.entitlements` — arquivo novo, só
  `com.apple.developer.kernel.increased-memory-limit`.
- `Odysseus/Features/Voice/OnDeviceSTT.swift` (335 linhas) — `STTModelEngine`,
  `OnDeviceSTTError`, `OnDeviceTranscriber`, `STTPrompt`, `WhisperEngine`, `ParakeetEngine`,
  `OnDeviceSTT.load`, `STTRunner`.
- `Odysseus/Features/Voice/VoiceModels.swift` — `VoiceModel.engine` (decide pelo prefixo
  do id), `VoiceLang` com 15 casos novos (21 no total) e `whisperCode`.
- `Odysseus/Features/Voice/VoiceInputManager.swift` — `chosenWhisperCode()` (linha 364),
  chama `STTRunner.shared.transcribe(...)`.
- `Odysseus/Features/Diagnostics/MemoryBudget.swift` — `availableBytes`,
  `physicalBytes`, `mb`, `human`.
- `OdysseusTests/OnDeviceSTTTests.swift` — 5 testes (ver seção 6).

### 1.3 Trechos de código que o porte precisa

**Package.swift do vendor** (binaryTarget por URL, sem checkout de fonte):

```swift
// swift-tools-version:5.9
let package = Package(
    name: "WhisperCPP",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "WhisperCPP", targets: ["whisper"])],
    targets: [
        .binaryTarget(
            name: "whisper",
            url: "https://github.com/ggml-org/whisper.cpp/releases/download/b5130/whisper-b5130-xcframework.zip",
            checksum: "033a43b0174e8cf9b366f72e4a428cdcf126f93ad1c87d3fa119a96bed6f231a"
        ),
    ]
)
```

`b5130` é o corte nightly da tag v1.9.4 (11/09/2026) — o release v1.9.4 em si não anexou o
zip do xcframework. Para atualizar: baixar o zip novo, `swift package compute-checksum
<zip>`, trocar URL e checksum juntos.

**project.yml — como referenciar o pacote local:**

```yaml
packages:
  WhisperCPP:
    path: Vendor/WhisperCPP
...
targets:
  Odysseus:
    dependencies:
      - package: WhisperCPP
    settings:
      base:
        CODE_SIGN_ENTITLEMENTS: Odysseus/Resources/Odysseus.entitlements
```

Nada de `url:`/`branch:`/`from:` — é `path:` apontando para a pasta com o `Package.swift`
acima. O XcodeGen resolve isso como um pacote SwiftPM local igual a `OpenWebUIKit` já é no
alvo; não precisa checkout de rede no CI além do download do binaryTarget na primeira
resolução.

**Entitlement (arquivo novo, iOS apenas):**

```xml
<key>com.apple.developer.kernel.increased-memory-limit</key>
<true/>
```

**`STTModelEngine` e decisão pelo prefixo do id** (`enum` em `OnDeviceSTT.swift:13`; `var engine` em `VoiceModels.swift:94`):

```swift
enum STTModelEngine: String, Sendable { case whisper, parakeet }
var engine: STTModelEngine { id.hasPrefix("p-") ? .parakeet : .whisper }
```

Ids antigos (`w-`, `u-` = customizados por URL) continuam Whisper sem mudar nada; só `p-`
é novo.

**Regra do caminho do encoder Core ML** — a que o whisper.cpp usa de verdade
(`whisper_get_coreml_path_encoder`), reimplementada em Swift:

```swift
static func coreMLEncoderPath(forModelAt path: String) -> String {
    var p = path
    if let dot = p.lastIndex(of: "."), !p[dot...].contains("/") { p = String(p[..<dot]) }
    if let dash = p.lastIndex(of: "-") {
        let sub = p[dash...]
        if sub.count == 5, sub[sub.index(after: dash)] == "q", sub[sub.index(dash, offsetBy: 3)] == "_" {
            p = String(p[..<dash])
        }
    }
    return p + "-encoder.mlmodelc"
}
```

Ou seja: tira a extensão, e SÓ SE o resto terminar num sufixo de exatamente 5 caracteres no
formato `-qD_D` (ex.: `-q5_0`, `-q5_1`, `-q8_0`) esse sufixo também sai. `ggml-base.bin` →
`ggml-base-encoder.mlmodelc` (sem sufixo, nada muda). `ggml-large-v3-turbo-q5_0.bin` →
`ggml-large-v3-turbo-encoder.mlmodelc` (o `-q5_0` cai fora).

**Gate de memória** (`STTRunner`):

```swift
static func memoryRequired(for model: VoiceModel, coreMLBytes: Int64) -> Int64 {
    Int64(Double(model.bytes) * 1.3) + coreMLBytes + 300_000_000
}
static func fits(_ model: VoiceModel, coreMLBytes: Int64) -> Bool? {
    guard let avail = MemoryBudget.availableBytes else { return nil }
    return memoryRequired(for: model, coreMLBytes: coreMLBytes) <= avail
}
```

`MemoryBudget.availableBytes` lê `os_proc_available_memory()` no iOS (nil em macOS — sem
API equivalente, gate desligado lá). `1,3×` cobre buffers de computação e KV cache além do
peso bruto do arquivo (lido inteiro, sem mmap); `+ coreMLBytes` soma o encoder Core ML (o
whisper.cpp mantém o encoder ggml TAMBÉM, não substitui); `+ 300 MB` é a folga para o resto
do processo.

**Parâmetros de decode que reduzem passes e ruído** (`WhisperEngine.transcribe`):

```swift
params.suppress_nst = true          // "" em vez de "[BLANK_AUDIO]" em clipe mudo
params.temperature_inc = 0.4
params.greedy.best_of = 2           // default seria até 6 temps × 5 decoders = 26 passes
if !usesCoreML { params.audio_ctx = Self.audioContext(forSamples: samples.count) }
```

`audioContext`: piso 768 (mesmo do modo streaming do whisper.cpp), teto 1500 (limite do
modelo), proporcional a `n/320 + 64`. Só se aplica quando NÃO há encoder Core ML — o
encoder Core ML tem shape fixo de 30 s, então mexer em `audio_ctx` ali quebraria.

**`n_threads`:**

```swift
private var decodeThreads: Int32 {
    Int32(max(1, min(4, ProcessInfo.processInfo.activeProcessorCount)))
}
```

Não é `cores - 1` (isso jogava thread nos núcleos de eficiência em phones big.LITTLE, e
como o ggml sincroniza todas as threads por operação, o op inteiro cai na velocidade do
núcleo mais lento).

**`initial_prompt` por idioma** (`STTPrompt`, chave `voice.stt.prompt` sobrepõe via
UserDefaults, sem UI ainda):

```swift
enum STTPrompt {
    static func forLanguage(_ code: String) -> String? {
        if let custom = UserDefaults.standard.string(forKey: "voice.stt.prompt"), !custom.isEmpty { return custom }
        switch code {
        case "pt": return "Transcrição em português do Brasil. Números por extenso: um centavo, dois reais, vinte e cinco por cento, três e meio."
        case "en": return "Transcript in English. Numbers written out in words: one cent, two dollars, twenty-five percent, three and a half."
        case "es": return "Transcripción en español. Números en palabras: un centavo, dos euros, veinticinco por ciento."
        default:   return nil
        }
    }
}
```

Nunca aplicado quando `language == "auto"`. Ataca diretamente "um centavo" → "1/100" (é
normalização do próprio modelo Whisper, não bug do app).

**Log do motor para diagnóstico** (instalado uma única vez, `Void` lazy):

```swift
private let installEngineLogSink: Void = {
    let sink: ggml_log_callback = { level, text, _ in
        guard let text else { return }
        DiagnosticsStore.shared.appendEngineLog(String(cString: text))
    }
    ggml_log_set(sink, nil)
    whisper_log_set(sink, nil)
    parakeet_log_set(sink, nil)
}()
```

Sem isso, `failed to load Core ML model`, `Core ML model loaded`, `compiled … library in N
sec` e `model size = … MB` só vão para o stderr — foi assim que o bug do encoder passou
despercebido em produção (falha muda).

**`STTRunner` — dono único do contexto, fila serial fora do MainActor:**

```swift
final class STTRunner: @unchecked Sendable {
    static let shared = STTRunner()
    private let queue = DispatchQueue(label: "com.zao.odysseus.stt", qos: .userInitiated)
    private var engine: OnDeviceTranscriber?
    private var engineID = ""
```

`transcribe(model:url:coreMLBytes:samples:language:onLoading:)` é `async`, mas todo o
corpo (checar memória, carregar se o id mudou, decodificar) roda dentro de
`queue.async` via `withCheckedThrowingContinuation` — nunca no `MainActor`. Libera o
contexto em `didReceiveMemoryWarningNotification`, `didEnterBackgroundNotification`
(iOS) e quando o modelo carregado é apagado (`releaseIfLoaded(id:)`). Cada etapa arriscada
abre um span no `DiagnosticsStore` antes de rodar, então uma morte silenciosa (jetsam) deixa
rastro no próximo launch.

### 1.4 Armadilhas verificadas (bugs achados, com a causa)

1. **Nome do encoder Core ML errado para todo modelo quantizado.**
   `ModelDownloadManager.coreMLFolderName` (versão pré-1.11, e ainda a versão ATUAL do
   OpenWebUI-iOS) instalava a pasta como `<id>-<filename sem .bin>-encoder.mlmodelc`, ou
   seja, mantendo o sufixo `-q5_0`/`-q5_1`/etc. O whisper.cpp deriva o caminho tirando
   TAMBÉM esse sufixo de quantização. Resultado: o encoder Core ML nunca era encontrado em
   nenhum modelo quantizado (só nos poucos "cheios", sem sufixo). Com
   `WHISPER_COREML_ALLOW_FALLBACK=ON` (padrão do build), a falha não gera exceção nem
   crash — é uma linha em stderr, silenciosa sem o log sink acima — e o encoder inteiro
   roda fora do Neural Engine (8,6× mais lento no caso medido). **Isso invalidou uma
   medição anterior ("q5_1 é 3× mais lento"), refeita depois em 0,94×.**
2. **Três cópias do mesmo contexto no processo.** Cada instância independente de
   `VoiceInputManager` (composer do chat, folha de voz, bancada de testes em Ajustes) tinha
   seu próprio cache de contexto. Dois turbos f16 (~1,6 GB cada) no mesmo processo passam
   da linha de jetsam num iPhone de 8 GB — SIGKILL sem exceção, sem crash report, relatado
   pelo usuário como "fechou sem erro nenhum".
3. **Load no `MainActor`.** `whisper_full`/carga do `.bin`/compilação da lib Metal/e a
   compilação inicial do Core ML para a ANE (minutos na primeira vez) travavam a UI
   inteira. Corrigido movendo tudo para a fila serial do `STTRunner`.
4. **Ladder de fallback padrão caro.** 6 temperaturas × `best_of` 5 = até 26 passes de
   decode numa janela ruidosa; sem necessidade para dictado curto.
5. **`cores - 1` threads** colocava trabalho nos núcleos de eficiência em telefones
   big.LITTLE, derrubando a velocidade de TODA a operação (ggml sincroniza as threads por
   op).

### 1.5 Como portar para OpenWebUI-iOS

**Estado atual do alvo (confirmado lendo o código):**
- `project.yml` (pacotes nas linhas 18-20 e 24-26; dependências nas linhas 47 e 49 do
  target iOS, 179 e 181 do macOS) ainda declara `SwiftWhisper` (URL `exPHAT/SwiftWhisper`,
  branch `master`) e `FluidAudio` (`from: 0.12.4`) como dependências remotas nos dois targets.
- `App/Features/Voice/VoiceInputManager.swift` importa `SwiftWhisper` diretamente,
  mantém `cachedWhisper: Whisper?` e chama `Whisper(fromFileURL:)` +
  `whisper.transcribe(audioFrames:)` (linhas ~48, 241-250). Usa `WhisperLanguage` (tipo do
  SwiftWhisper) em vez de string de código.
- `App/Features/Voice/ModelDownloadManager.swift` (linhas 57-60) tem O MESMO bug do item 1
  acima: `coreMLFolderName` só tira a extensão `.bin`, não o sufixo `-qD_D`. Como o alvo
  ainda usa SwiftWhisper (que não tem esse encoder path fixo por versão nova), verificar se
  o problema já se manifesta lá antes de portar a correção — mas a correção deve entrar
  junto com a troca de motor de qualquer forma.
- `App/Resources/OpenWebUI-macOS.entitlements` existe; não há entitlements de iOS
  encontrado (`find . -path ./build-device -prune -o -iname "*.entitlements" -print` só retorna os dois arquivos macOS; `build-device/` é gitignored e traz cópias de pacotes) — então
  o target iOS hoje assina sem plist de entitlements dedicado, ou usa um caminho ainda não
  localizado; conferir no target iOS do `project.yml` antes de adicionar o novo arquivo.
- `App/Features/Shared/SpeechManager.swift`, `App/Features/Voice/BargeInMonitor.swift`,
  `App/Features/Voice/NeuralVoiceStore.swift` também importam `SwiftWhisper` ou
  `FluidAudio` — mapear cada um antes de remover os pacotes.

**Ordem sugerida:**
1. Copiar `Vendor/WhisperCPP/` (a pasta inteira, é só o `Package.swift`) do Odysseus para
   o mesmo caminho relativo no OpenWebUI-iOS.
2. `project.yml`: trocar `SwiftWhisper:` (bloco `url`/`branch`) por
   `WhisperCPP: {path: Vendor/WhisperCPP}`; trocar toda ocorrência de
   `- package: SwiftWhisper` por `- package: WhisperCPP` nos dois targets. `FluidAudio` fica: nos dois
   apps ele é o TTS (`SpeechManager`), o VAD do barge-in (`BargeInMonitor`) e as vozes
   neurais (`NeuralVoiceStore`); o Odysseus 1.11 continua com ele nos dois targets
   (`project.yml:83` e `:166`). A troca é só do STT.
3. Criar `App/Resources/OpenWebUI.entitlements` (iOS) com
   `com.apple.developer.kernel.increased-memory-limit`; apontar
   `CODE_SIGN_ENTITLEMENTS` no target iOS do `project.yml`. **Atenção:** isso vai invalidar
   o perfil de distribuição atual, exatamente como aconteceu na publicação da 1.11 (ver
   HANDOFF-ARQUITETURA.md, seção "Publicação da 1.11") — recriar o perfil pela API antes do
   próximo archive de release.
4. Copiar `Odysseus/Features/Voice/OnDeviceSTT.swift` para
   `App/Features/Voice/OnDeviceSTT.swift`, ajustando só o namespace do log
   (`DiagnosticsStore`/`VoiceLog` — conferir se o OpenWebUI-iOS tem equivalentes; se não
   tiver `DiagnosticsStore`, pelo menos manter `whisper_log_set`/`ggml_log_set`/
   `parakeet_log_set` ligados a algum sink, nem que seja só `VoiceLog.log`).
5. Copiar `Odysseus/Features/Diagnostics/MemoryBudget.swift` (arquivo pequeno, zero
   dependência externa) — pré-requisito do gate de memória do `STTRunner`.
6. Em `VoiceModels.swift` do alvo: adicionar `engine: STTModelEngine` calculado do prefixo
   do id, do jeito que está em `Odysseus/Features/Voice/VoiceModels.swift:94`, SE o
   catálogo do OpenWebUI-iOS for ganhar Parakeet também (não confirmado que é escopo desta
   rodada de porte — o pedido fala só do motor; decidir com o dono se o catálogo de modelos
   do OpenWebUI-iOS ganha os mesmos ids `p-`).
7. Reescrever `VoiceInputManager.transcribeWithWhisper()` para chamar
   `STTRunner.shared.transcribe(model:url:coreMLBytes:samples:language:onLoading:)` em vez
   de manter `cachedWhisper: Whisper?` local — isso já resolve o problema de múltiplos
   contextos SE o app também tiver mais de um `VoiceInputManager` (conferir quantas
   instâncias existem: composer do chat e talvez uma tela de voz separada).
8. Corrigir `ModelDownloadManager.coreMLFolderName` para a regra `WhisperEngine.
   coreMLEncoderPath` (tirar também o sufixo `-qD_D`), com um `legacyCoreMLFolderName` e uma
   migração no `refresh()` se já houver instalações no campo com o nome antigo — mesmo
   padrão do Odysseus.
9. Trocar `chosenWhisperLanguage() -> WhisperLanguage` (tipo do SwiftWhisper) por
   `chosenWhisperCode() -> String` sobre o `sttServerCode` de `AppLanguage`/equivalente —
   conferir se o OpenWebUI-iOS já tem essa propriedade em sua própria enum de idioma
   (`Localization.swift` ou equivalente) antes de duplicar.
10. Remover a dependência `SwiftWhisper` do `project.yml` e do `Package.resolved` só depois
    que `VoiceInputManager.swift` (único arquivo que a importa) estiver migrado — rodar `xcodegen generate` e compilar (sem `xcodebuild` real neste pass;
    apenas o comando de geração de projeto e leitura de erro estático, conforme as regras
    desta sessão de só-leitura).

### 1.6 Testes que cobrem

`OdysseusTests/OnDeviceSTTTests.swift` — o OpenWebUI-iOS **não tem target de teste do app**
(`project.yml` só declara dois `type: application`; o único alvo de teste é o
`OpenWebUIKitTests` do pacote SwiftPM, que não consegue `@testable import` do módulo do
app). Pré-requisito do porte: criar um target `OpenWebUITests` (unit-test, host app) no
`project.yml`, e só então copiar o arquivo trocando `@testable import Odysseus`:

- `testCoreMLEncoderPathMatchesWhisperCpp` — confere `WhisperEngine.coreMLEncoderPath`
  contra 6 casos reais (`q5_0`, `q5_1`, `tiny.en` sem sufixo de quantização, caminho
  absoluto, e um id `u-` customizado) — é o teste que teria pego o bug do item 4.1 antes de
  ir para produção.
- `testDownloadManagerUsesTheSameNameAndRemembersTheLegacyOne` — garante que
  `ModelDownloadManager.coreMLFolderName` bate com `WhisperEngine.coreMLEncoderPath`, e que
  existe `legacyCoreMLFolderName` para migrar instalações antigas; e que para modelo SEM
  sufixo de quantização os dois nomes (legado e atual) são idênticos (não quebra quem já
  tinha baixado).
- `testAudioContextFollowsTheClipWithinWhisperBounds` — 3 casos: clipe de 3s cai no piso
  768, 20s dá 1064, 60s satura em 1500.
- `testMemoryRequiredCountsTheCoreMLEncoderOnTop` — a fórmula `bytes×1,3 + coreML + 300MB`
  soma exatamente `coreMLBytes` a mais quando presente; em macOS, `STTRunner.fits` retorna
  `nil` (sem gate, API indisponível).
- `testPromptOnlyForKnownLanguagesAndNeverForAuto` — prompt existe para pt/en, não existe
  para ja (fora da lista), e o texto de pt contém "um centavo" (contrato textual do prompt).

`OdysseusTests/VoiceCatalogTests.swift` (9 testes, fora do escopo direto desta seção mas
relevante se o porte também trouxer o catálogo Parakeet): confirma prefixo↔engine, URLs
únicas, e que cada bucket de idioma tem pelo menos um modelo com código de 2 letras.

## 2. Catálogo por idioma, espelhos JoaoZaokk no Hugging Face e ModelDownloadManager

### 2.1 O que mudou e por quê

Pedido do dono (12/09): baixar os principais modelos de STT (Parakeet, Nemotron, Kyutai…),
converter para GGML em cada quantização, subir para a conta própria no Hugging Face e linkar
no catálogo do app. Motivo: o app vende acesso ao app, não ao modelo — o catálogo é uma lista
de links que precisa continuar resolvendo para arquivos que existem. Hospedar em contas de
terceiros (como a 1.10 fazia: `uosx`, `lucasparis1103`, `Pomni`) é um ponto de falha fora do
controle do dono; cada card no HF sob `JoaoZaokk/*` cita a fonte e mantém a licença original.

Consequência para o catálogo: de 6 buckets de idioma (universal + 5) foi para 21 buckets
(`VoiceLang` ganhou 15 casos), cada um com pelo menos um Whisper afinado próprio, mais a
família Parakeet TDT (novo engine dentro do mesmo binário whisper.cpp) e o Orukeet
(Parakeet v3 refinado para PT-BR). Junto entrou o motor `WhisperEngine`/`ParakeetEngine` sob
`OnDeviceTranscriber` (ver seção de arquitetura do rodada 9 completa em
`OnDeviceSTT.swift`), mas o que importa para este documento é a tabela de dados do catálogo e
o `ModelDownloadManager`, que tiveram um bug real de nome de pasta Core ML corrigido nesta
rodada — o mesmo padrão de bug (`coreMLFolderName` mantendo o sufixo de quantização) **ainda
existe hoje, verbatim, no OpenWebUI-iOS**.

### 2.2 Arquivos e símbolos no Odysseus (caminhos reais)

- `Odysseus/Features/Voice/VoiceModels.swift` (350 linhas) — `VoiceTask`, `VoiceLang` (21
  casos), `VoiceModel` (+ `engine`, `isCustom`, `bucket`, `humanSize`), `CustomVoiceModel`,
  `CustomModels`, `VoiceCatalog` (catálogo `builtIn`, `filtered(task:lang:)`,
  `coreMLByID`/`coreMLZipURL`/`coreMLZipBytes`).
- `Odysseus/Features/Voice/ModelDownloadManager.swift` (350 linhas) — `coreMLFolderName`,
  `legacyCoreMLFolderName`, `refresh()` (migração), download/cancel/delete de `.bin` e do zip
  Core ML, `addCustomModel(from:)`, `isWhisperGGML(at:)`.
- `Odysseus/Features/Voice/OnDeviceSTT.swift` — `STTModelEngine`, `WhisperEngine`,
  `WhisperEngine.coreMLEncoderPath(forModelAt:)` (a regra que `ModelDownloadManager` agora
  delega para cá em vez de duplicar).
- `Odysseus/Features/Localization/Localization.swift` — `AppLanguage.sttServerCode`.
- `OdysseusTests/VoiceCatalogTests.swift` (9 testes) e `OdysseusTests/OnDeviceSTTTests.swift`
  (cobre `coreMLEncoderPath`, não faz parte desta seção mas é citado pelo comentário do bug).

### 2.3 Trechos de código que o porte precisa

**Prefixo do id decide o engine** (`VoiceModels.swift:91-94`):
```swift
/// Which C engine loads the file. Encoded in the id prefix so custom
/// (`u-`) and legacy (`w-`) ids keep working unchanged: only `p-` is
/// Parakeet.
var engine: STTModelEngine { id.hasPrefix("p-") ? .parakeet : .whisper }
```

**`VoiceLang` — os 15 casos novos e o código Whisper que pinam** (`VoiceModels.swift:12-50`):
```swift
enum VoiceLang: String, Codable, CaseIterable {
    case universal
    case english, portuguese, chinese, japanese, french
    case spanish, german, italian, korean, russian, arabic, hindi, turkish, thai
    case swedish, finnish, vietnamese, hebrew, hungarian, croatian

    init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? "universal"
        self = VoiceLang(rawValue: raw == "bilingual" ? "universal" : raw) ?? .universal
    }

    var whisperCode: String? {
        switch self {
        case .universal:  nil
        case .english:    "en"
        case .portuguese: "pt"
        // ... um código de 2 letras por caso, .universal é o único nil
        }
    }
}
```

**Rótulo dos 15 casos novos via ICU, sem tradução manual** (`VoiceModels.swift:52-78`) — os 6
casos originais continuam com chave traduzida (`L(...)`); os 16 novos usam
`Locale.localizedString(forLanguageCode:)` no idioma que o app está mostrando, lido
diretamente da mesma `UserDefaults` key que `LocalizationManager` grava (`"app.language"`),
porque este `label` roda fora do MainActor:
```swift
var label: String {
    switch self {
    case .universal: return L("Universal")
    // ... os 6 antigos com L(...)
    default:
        guard let code = whisperCode,
              let name = Self.displayLocale.localizedString(forLanguageCode: code), !name.isEmpty
        else { return rawValue }
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}

private static var displayLocale: Locale {
    if let raw = UserDefaults.standard.string(forKey: "app.language"), raw != "auto" {
        return Locale(identifier: raw)
    }
    return Locale.current
}
```
Isso poupou 43 catálogos de tradução × 15 chaves novas (o comentário do código diz 17; o enum tem 15 casos novos).

**Convenção de URL do espelho** (`VoiceModels.swift:291-297`):
```swift
private static func hf(_ repo: String, _ file: String) -> URL {
    URL(string: "https://huggingface.co/\(repo)/resolve/main/\(file)")!
}
private static func mine(_ repo: String, _ file: String) -> URL {
    hf("JoaoZaokk/\(repo)", file)
}
```
Toda entrada nova do catálogo usa `mine(...)`; só `w-en-distil35` continua apontando direto
para `distil-whisper/distil-large-v3.5-ggml` (dono é o próprio autor do modelo, MIT).

**`filtered(task:lang:)` não mudou de contrato** — continua "idioma específico = modelos
daquele idioma + universais":
```swift
static func filtered(task: VoiceTask, lang: VoiceLang?) -> [VoiceModel] {
    all.filter {
        guard $0.task == task else { return false }
        guard let lang else { return true }
        if lang == .universal { return $0.lang == .universal }
        return $0.lang == lang || $0.lang == .universal
    }
}
```

**A regra do nome da pasta Core ML — o núcleo do bug de rodada 9b** (`OnDeviceSTT.swift:114-127`,
chamado de `ModelDownloadManager.coreMLFolderName`):
```swift
/// The path whisper.cpp itself derives for the Core ML encoder: drop the
/// extension, drop a trailing `-qD_D` quantization suffix, add
/// `-encoder.mlmodelc` (src/whisper.cpp, `whisper_get_coreml_path_encoder`).
static func coreMLEncoderPath(forModelAt path: String) -> String {
    var p = path
    if let dot = p.lastIndex(of: "."), !p[dot...].contains("/") { p = String(p[..<dot]) }
    if let dash = p.lastIndex(of: "-") {
        let sub = p[dash...]
        if sub.count == 5, sub[sub.index(after: dash)] == "q", sub[sub.index(dash, offsetBy: 3)] == "_" {
            p = String(p[..<dash])
        }
    }
    return p + "-encoder.mlmodelc"
}
```
`ModelDownloadManager.coreMLFolderName` hoje só delega:
```swift
nonisolated static func coreMLFolderName(id: String, filename: String) -> String {
    WhisperEngine.coreMLEncoderPath(forModelAt: "\(id)-\(filename)")
}
nonisolated static func legacyCoreMLFolderName(id: String, filename: String) -> String {
    let bin = "\(id)-\(filename)"
    let stem = bin.hasSuffix(".bin") ? String(bin.dropLast(4)) : bin
    return "\(stem)-encoder.mlmodelc"
}
```
E `refresh()` migra pastas instaladas com o nome antigo para o nome certo, uma vez, na
inicialização:
```swift
func refresh() {
    var files = Set((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
    for m in VoiceCatalog.all {
        let legacy = Self.legacyCoreMLFolderName(id: m.id, filename: m.filename)
        let wanted = Self.coreMLFolderName(id: m.id, filename: m.filename)
        guard legacy != wanted, files.contains(legacy), !files.contains(wanted) else { continue }
        if (try? FileManager.default.moveItem(at: dir.appendingPathComponent(legacy), to: dir.appendingPathComponent(wanted))) != nil {
            files.remove(legacy); files.insert(wanted)
            DiagnosticsStore.shared.event("coreml.migrated", ["model": m.id])
        }
    }
    installed = Set(VoiceCatalog.all.filter { files.contains("\($0.id)-\($0.filename)") }.map(\.id))
    coreMLInstalled = Set(VoiceCatalog.all.filter { files.contains(Self.coreMLFolderName(id: $0.id, filename: $0.filename)) }.map(\.id))
}
```

**`AppLanguage.sttServerCode`** (`Localization.swift`, inalterado no valor, só no comentário —
antes citava `VoiceInputManager.chosenWhisperLanguage()`/`WhisperLanguage`, hoje cita
`chosenWhisperCode()`):
```swift
var sttServerCode: String? { self == .ug ? nil : iso639 }
```
`VoiceInputManager.chosenWhisperCode()` (`VoiceInputManager.swift:364-367`) é quem consome:
```swift
static func chosenWhisperCode() -> String {
    guard let chosen = SpeechLanguage.pinned() else { return "auto" }
    return chosen.sttServerCode ?? "auto"
}
```
E na hora de escolher o idioma que vai pro `whisper_full`, o código do idioma pinado pelo
modelo tem prioridade sobre a configuração do app (`VoiceInputManager.swift:267`):
```swift
let lang = model.lang.whisperCode ?? Self.chosenWhisperCode()
```

### 2.4 Armadilhas verificadas (bugs achados, com a causa)

1. **Core ML nunca entrava em ação nos modelos quantizados (rodada 9b).** Causa:
   `coreMLFolderName` instalava `…-q5_0-encoder.mlmodelc`, mas o whisper.cpp real
   (`whisper_get_coreml_path_encoder`) deriva o caminho tirando também o sufixo `-qD_D`
   antes de acrescentar `-encoder.mlmodelc`, então ele procurava `…-encoder.mlmodelc` (sem o
   `-q5_0`). Com `WHISPER_COREML_ALLOW_FALLBACK=ON` a falha de abrir o encoder é silenciosa
   (uma linha em stderr) e o modelo inteiro roda fora do Neural Engine — o relato do dono foi
   "o Large-v3 Turbo demorou fudidamente para carregar". **Esse bug está presente hoje,
   verbatim, em `OpenWebUI-iOS/App/Features/Voice/ModelDownloadManager.swift:57-60`** (a
   versão "legacy" do Odysseus, sem a correção nem a migração de `refresh()`).
2. **O comentário do código documenta explicitamente a regressão** (`ModelDownloadManager.swift:56-62`):
   "1.10 kept the suffix, so `w-turbo-q5-ggml-large-v3-turbo-q5_0-encoder.mlmodelc` was
   installed while whisper.cpp opened `…-turbo-encoder.mlmodelc`, failed quietly
   (ALLOW_FALLBACK) and ran the whole encoder without the Neural Engine." — útil para colar
   direto no commit do porte.
3. **Sem quantização, o bug não aparece**: modelos sem sufixo `-qD_D` no filename (`w-tiny`,
   `w-base`, `w-small`, `w-medium`, `w-turbo`, `w-largev3` cheios) sempre bateram o nome certo
   por acidente — só os `*-q5*`/`*-q8*`/`*-q5_0`/`*-q5_1` sofrem. Isso explica por que o bug
   passou despercebido tanto tempo: os modelos "grandes de teste" muitas vezes são os cheios.
4. **`OnDeviceSTT.load(_:at:)` não pode rodar no `MainActor`** (achado na mesma rodada,
   registrado aqui porque toca o mesmo arquivo): ler o `.bin`, compilar o shader Metal e
   carregar o Core ML (minutos na primeira vez) trava a UI se chamado de dentro do
   `@MainActor` da própria `ModelDownloadManager`/`VoiceInputManager`. O Odysseus resolveu com
   `STTRunner.shared` (fila serial fora do ator principal) — fora do escopo desta seção, mas o
   porte de `ModelDownloadManager` não deve reintroduzir chamadas de load no `MainActor`.
5. **Contagem conferida (14/09, API do Hugging Face):** os 24 repositórios do handoff são
   os 23 `*-ggml` citados por `mine(...)` em `VoiceModels.swift` (tabela da seção 2.5,
   Belle ZH e EraX VI incluídos; ambos respondem 200) mais o `nemotron-3.5-asr-streaming-0.6b-gguf`,
   que só existe no HF. A conta do dono tem 45 repositórios no total; os outros 21 não são STT.

### 2.5 Os repositórios `huggingface.co/JoaoZaokk/*-ggml` (conferidos na API do HF em 14/09)

Usados no app (referenciados por `mine(repo, file)` em `VoiceModels.swift`, 23 repositórios,
cada um com q5_0 e q8_0 — exceto onde indicado):

| Repositório (`JoaoZaokk/…`) | Idioma/uso no catálogo |
|---|---|
| `parakeet-tdt-0.6b-v3-ggml` | Parakeet TDT v3, universal (25 línguas), detecta idioma |
| `parakeet-tdt-0.6b-v2-ggml` | Parakeet TDT v2, inglês |
| `parakeet-tdt-1.1b-ggml` | Parakeet TDT 1.1B, inglês |
| `orukeet-ggml` | Orukeet (Parakeet v3 + fine-tune oruk), universal, PT-BR forte |
| `Belle-whisper-large-v3-turbo-zh-ggml` | Chinês |
| `kotoba-whisper-v2.0-ggml` | Japonês |
| `distil-whisper-large-v3-ptbr-ggml` | Português (BR) |
| `whisper-large-v3-french-distil-dec16-ggml` | Francês |
| `whisper-large-v3-turbo-latam-ggml` | Espanhol (LatAm) |
| `whisper-large-v3-turbo-german-ggml` | Alemão |
| `whisper-large-v3-distil-it-v0.2-ggml` | Italiano |
| `whisper-large-v3-turbo-korean-ggml` | Coreano |
| `whisper-podlodka-turbo-ggml` | Russo |
| `whisper-large-v3-turbo-arabic-dialectal-v2-ggml` | Árabe |
| `whisper-large-v3-vaani-hindi-ggml` | Hindi (large-v3 cheio; q5 1,08 GB, q8 1,66 GB) |
| `whisper-large-v3-turkish-general-ggml` | Turco (modelo cheio) |
| `typhoon-whisper-turbo-ggml` | Tailandês |
| `kb-whisper-large-ggml` | Sueco (modelo cheio) |
| `whisper-large-v3-finnish-ggml` | Finlandês (modelo cheio) |
| `EraX-WoW-Turbo-V1.1-ggml` | Vietnamita |
| `ivrit-whisper-large-v3-turbo-ggml` | Hebraico |
| `whisper-hu-large-v3-turbo-finetuned-ggml` | Húngaro |
| `whisper-large-v3-turbo-hr-parla-ggml` | Croata |

Fora do app, só no Hugging Face (citado no handoff, não linkado em `VoiceModels.swift` porque
o whisper.cpp do app só carrega Parakeet no formato TDT):

| Repositório | Observação |
|---|---|
| `nemotron-3.5-asr-streaming-0.6b-gguf` | GGUF do NVIDIA Nemotron 3.5 streaming, quantizações q4_k/q5_k/q6_k/q8_0 + f16 (espelho do `mudler/parakeet.cpp`, requantizado via upcast f32); **não roda no app** — precisaria de um segundo runtime GGUF (parakeet.cpp) no binário |

Sem fine-tune redistribuível achado (pesquisa de 63 agentes, registrada no handoff): nl, pl,
uk, id (ficam no turbo multilíngue/Parakeet v3); cs/sk/ms refutados por dataset fraco ou
licença — cs/sk cobertos pelo Parakeet v3.

Regra geral do catálogo pós-rodada-9: **sem f16** (iPhone roda q4/q5, Mac roda q8; o campo de
URL customizada do usuário ainda aceita um f16 manual). 13 dos 23 espelhos `*-ggml` ainda
hospedam um f16 (conferido na API do HF em 14/09: Belle-zh, distil-ptbr, ivrit, kotoba,
orukeet, parakeet v2/v3/1.1b, distil-it, finnish, korean, latam, podlodka); ficam de
propósito, como referência. Os convertidos depois já saem sem ele — f16 virou só intermediário local, apagado após quantizar.

### 2.6 Como portar para OpenWebUI-iOS

Estado atual do alvo (lido de `/Users/joaozao/Projetos/OpenWebUI-iOS/App/Features/Voice/`):

- `VoiceModels.swift` (218 linhas): `VoiceLang` tem só 6 casos (`universal, english,
  portuguese, chinese, japanese, french`), sem `whisperCode`, sem regra ICU, sem `engine`
  (não existe conceito de Parakeet). O catálogo `builtIn` tem os mesmos Whisper genéricos
  (`ggerganov/whisper.cpp`) **e ainda referencia diretamente os repositórios de terceiros**
  que o Odysseus abandonou: `uosx/Belle-whisper-large-v3-turbo-zh-ggml-quantized`,
  `BELLE-2/Belle-whisper-large-v3-turbo-zh-ggml`, `kotoba-tech/kotoba-whisper-v2.0-ggml`,
  `distil-whisper/distil-large-v3.5-ggml` (esse continua igual no Odysseus),
  `lucasparis1103/distil-whisper-large-v3-ptbr-ggml`,
  `Pomni/whisper-large-v3-french-distil-dec16-GGML-allquants`. São exatamente os nomes que o
  Odysseus tinha antes da rodada 9 e trocou por espelhos próprios.
- `ModelDownloadManager.swift` (300 linhas): tem a `coreMLFolderName` **com o bug do sufixo de
  quantização não removido** (linha 57-60, ver seção 2.4) — sem `WhisperEngine.coreMLEncoderPath`
  (o alvo ainda usa `SwiftWhisper`, que não expõe essa regra), sem `legacyCoreMLFolderName`,
  sem migração em `refresh()`.

Ordem sugerida de porte (menor fatia primeiro, por `scope-smallest-first`):

1. **Corrigir o bug do Core ML primeiro, isolado.** Ele é uma correção de uma função pura,
   sem depender de nada do catálogo novo. Mas o OpenWebUI-iOS ainda está no `SwiftWhisper`
   (2023), não no xcframework `ggml-org` — então a regra de `whisper_get_coreml_path_encoder`
   precisa ser conferida contra a versão de whisper.cpp que o `SwiftWhisper` vendoriza antes de
   colar o algoritmo do Odysseus 1:1 (pode já ter mudado de comportamento entre versões).
   Escrever primeiro um teste equivalente a `OnDeviceSTTTests` fixando entradas → saídas
   esperadas do nome de pasta, depois portar `refresh()` com a migração de nomes legados.
2. **Trocar os repositórios de terceiros pelos espelhos `JoaoZaokk/*-ggml`** que já cobrem os
   mesmos 5 idiomas afinados que o OpenWebUI-iOS já suporta (zh, ja, en, pt, fr) — sem ainda
   expandir para os 16 idiomas novos. Isso já elimina a dependência de contas de terceiros e
   reaproveita conversão/QA já feita, sem tocar em `VoiceLang` nem em UI de filtro.
3. **Só depois, se o dono pedir**, portar os 15 casos novos de `VoiceLang` + a resolução de
   rótulo por `Locale.localizedString(forLanguageCode:)` (isso sim tem custo: precisa decidir
   se replica a chave `"app.language"` do `LocalizationManager` do OpenWebUI-iOS, que pode ter
   nome diferente — checar antes de copiar o `UserDefaults.standard.string(forKey: "app.language")`
   verbatim) e o catálogo Parakeet/Orukeet. O Parakeet exige o xcframework novo do whisper.cpp
   (`Vendor/WhisperCPP` no Odysseus) no lugar do `SwiftWhisper` — troca de dependência bem
   maior, fora do escopo de "levar o catálogo".
4. `AppLanguage.sttServerCode` no OpenWebUI-iOS: conferir se já existe (procurar em
   `OpenWebUIKit`/`Localization.swift` do alvo) antes de copiar o comentário do Odysseus, que
   cita símbolos (`VoiceInputManager.chosenWhisperCode()`) que só existem depois do passo 3.

### 2.7 Testes que cobrem

- `OdysseusTests/VoiceCatalogTests.swift` (9 testes, todos sobre `VoiceModel`/`VoiceLang`/
  `VoiceCatalog`, nenhum toca rede):
  - `testIDsAndURLsAreUnique` — nenhum id nem URL duplicados no catálogo embutido.
  - `testEveryURLIsAnHTTPSHuggingFaceResolveLink` — toda entrada é `https://huggingface.co/…`,
    caminho contém `/resolve/main/`, arquivo termina em `.bin`, tamanho > 10 MB (pega qualquer
    entrada nova colada errada ou com placeholder de tamanho).
  - `testEngineFollowsTheIDPrefix` — todo `p-*` é `.parakeet`, todo `w-*` é `.whisper`; um
    `CustomVoiceModel` sempre vira `.whisper`/`.universal`.
  - `testParakeetModelsExistAndHaveNoCoreMLEncoder` — pelo menos 3 variantes de Parakeet no
    catálogo, nenhuma tem entrada em `coreMLByID`.
  - `testEveryLanguageBucketHasALabelAndACode` — todo `VoiceLang` tem `label` não vazio; todo
    caso exceto `.universal` tem `whisperCode` de exatamente 2 letras; `.universal` é sempre o
    primeiro caso de `allCases` (ordem estável para UI).
  - `testEveryTunedLanguageShipsAtLeastOneModel` — nenhum bucket de idioma fica no menu de
    filtro sem nenhum modelo real por trás.
  - `testFilteringByLanguageKeepsTheUniversalModels` — `filtered(task:lang:)` inclui os
    universais junto do idioma pedido, e `.universal` sozinho não vaza modelos de idioma.
  - `testNewBucketsAreNamedInTheAppLanguage` — muda `UserDefaults["app.language"]` para
    `pt-BR`/`en`/`ja` e confere que `VoiceLang.german.label`/`.hebrew.label`/etc. seguem o
    idioma corrente (prova que o ICU dinâmico funciona sem reiniciar o app).
  - `testLegacyBilingualRawValueDecodesAsUniversal` — JSON antigo com `"bilingual"` decodifica
    como `.universal`, e um raw value desconhecido também cai em `.universal` (não trava o
    decode de preferências velhas do usuário).
- `OdysseusTests/OnDeviceSTTTests.swift` (não é desta seção no fundo, mas é quem prova o
  algoritmo de `coreMLEncoderPath` que `ModelDownloadManager.coreMLFolderName` delega): fixa
  pares entrada→pasta esperada para nomes com e sem sufixo `-qD_D`, incluindo o caso `w-tiny-en`
  (extensão dupla `.en.bin`) e um id customizado `u-1-ggml-model-q8.bin`.

## 3. VoiceInputManager: um dono do motor, áudio salvo antes de transcrever, carregamento fora da UI

### 3.1 O que mudou e por quê

Motivado pelo relato do dono em 12/09 (iPhone 15 Pro Max, iOS 27 beta): o Large-v3 Turbo
de ~2 GB "fechava o app sem nenhum erro". Investigação (rodada 9b, `docs/HANDOFF-ARQUITETURA.md`)
achou três problemas empilhados no `VoiceInputManager` da 1.10:

1. **Três donos do contexto do motor.** Havia um `VoiceInputManager` por chamador (chat,
   folha de voz, bancada de Ajustes), cada um com seu próprio `cachedWhisper: Whisper?`.
   Dois turbos f16 carregados ao mesmo tempo no mesmo processo é jetsam garantido — sem
   nenhum log, porque é o SO matando o app, não uma exceção Swift.
2. **`load()` no MainActor.** (O decode já rodava em `Task.detached`; só o load era
   síncrono no ator principal.) A UI congelava lendo o `.bin`, compilando a
   biblioteca Metal e (na primeira vez) compilando o encoder Core ML para a ANE — minutos,
   sem feedback nenhum na tela.
3. **Nada sobrevivia a uma morte no meio do caminho.** Se o processo morresse durante a
   transcrição (jetsam, watchdog, queda de rede), a gravação inteira — e as palavras do
   usuário — sumia com ele.

A correção de (1)+(2) é o `STTRunner` (dono único e serializado do contexto, fora do
`VoiceInputManager`, não coberto por este documento — está em `OnDeviceSTT.swift`); a
correção de (3), que é o que este documento cobre em detalhe, é o `PendingAudioStore`: grava
o WAV em disco **antes** de tocar em qualquer motor, e só apaga depois de um resultado.
Padrão explicitamente copiado do app Redoma do mesmo dono ("memory index": Redoma já usa
"grava primeiro, transcreve depois").

Consequência de design: o `VoiceInputManager` deixou de decidir sozinho qual motor rodar
com base em `UserDefaults` lido bem no fundo de cada `transcribeWithX()`. Agora ele lê o
motor **uma vez**, no início de `stop()`, grava o áudio rotulado com esse motor, e só então
chama uma função `transcribe(frames:engine:modelID:language:)` que aceita esses parâmetros
explicitamente — a mesma função que a recuperação de uma pendência antiga chama, passando o
que estava gravado no sidecar, não o que está selecionado agora.

### 3.2 Arquivos e símbolos no Odysseus (caminhos reais)

- `Odysseus/Features/Voice/VoiceInputManager.swift` — `stop()`, `finishedFrames()`,
  `transcribe(frames:engine:modelID:language:)`, `transcribe(pending:)`,
  `transcribeWithWhisper(frames:modelID:)`, `transcribeWithServer(frames:language:)`,
  `transcribeWithEndpoint(frames:)`, `transcribeUpload(frames:_:)`, `loadingModel`,
  `lastTranscriptionFailed`, `pending`, `chosenWhisperCode()`,
  `installedModelURL(for:)`.
- `Odysseus/Features/Voice/PendingAudioStore.swift` — arquivo inteiro é novo nesta rodada:
  `enum WAV` (`encode`/`decode`) + `enum PendingAudioStore` (`Pending`, `save`, `write`,
  `list`, `frames(of:)`, `delete`, `bumpAttempts`, `purge`).
- `Odysseus/Features/Voice/VoiceSettingsView.swift` — `coreMLControl(_:)` (bolt),
  `modelRow`, `STTTestRow` (mostram `loadingModel` e "não cabe na memória").
- `Odysseus/App/OdysseusApp.swift` — `RootView`: o `.alert` de recuperação, `pendingAudio`,
  `recovered`, `recoverPending(_:)`; `PendingAudioStore.purge()` + `.list()` no
  `.task`; só `.list()` em `scenePhase == .active`.
- `OdysseusTests/PendingAudioStoreTests.swift` — 4 testes novos.

Fora do escopo desta seção mas citado por dependência: `STTRunner` (em `OnDeviceSTT.swift`), `MemoryBudget` (em `Features/Diagnostics/MemoryBudget.swift`),
`OnDeviceSTT.swift` (o dono único do motor e o cálculo "cabe na memória?") — ver a seção do
handoff que cobre a rodada 9/9b se o porte também for atacar isso.

### 3.3 Trechos de código que o porte precisa

**`stop()` — salvar antes de transcrever** (`VoiceInputManager.swift`):
```swift
let engineNow = STTEngine.current
if engineNow != .native {
    // Save first, transcribe second (the Redoma pattern): from here on a
    // death of the process — jetsam under a big model, a watchdog, a
    // dropped connection — costs a retry, not the words.
    guard let frames = finishedFrames() else { return "" }
    let language = engineNow == .model ? nil : SpeechLanguage.pinned()?.sttServerCode
    let p = PendingAudioStore.save(frames: frames, engine: engineNow.rawValue, modelID: activeModelID, language: language)
    pending = p
    let text = await transcribe(frames: frames, engine: engineNow, modelID: activeModelID, language: language)
    if let p, !lastTranscriptionFailed { PendingAudioStore.delete(p); pending = nil }
    return text
}
```
Note: quando `engineNow == .model`, `language` é passado como `nil` para `save`/`transcribe`
— quem decide o idioma do Whisper é `transcribeWithWhisper` via `model.lang.whisperCode ??
chosenWhisperCode()`, não o parâmetro salvo. Só server/endpoint gravam `SpeechLanguage.pinned()?.sttServerCode`
no sidecar.

**Dispatcher único, reusado pela recuperação:**
```swift
func transcribe(frames: [Float], engine: STTEngine, modelID: String, language: String?) async -> String {
    lastTranscriptionFailed = false
    switch engine {
    case .server:   return await transcribeWithServer(frames: frames, language: language)
    case .endpoint: return await transcribeWithEndpoint(frames: frames)
    case .model:    return await transcribeWithWhisper(frames: frames, modelID: modelID)
    case .native:   return ""
    }
}

func transcribe(pending p: PendingAudioStore.Pending) async -> String? {
    guard let frames = PendingAudioStore.frames(of: p) else { PendingAudioStore.delete(p); return nil }
    let q = PendingAudioStore.bumpAttempts(p)
    let engine = STTEngine(rawValue: q.engine) ?? .model
    let text = await transcribe(frames: frames, engine: engine, modelID: q.modelID, language: q.language)
    if !lastTranscriptionFailed { PendingAudioStore.delete(q) }
    return text.isEmpty ? nil : text
}
```
`lastTranscriptionFailed = true` é setado em cada `catch` de `transcribeWithWhisper`,
`transcribeWithServer` e `transcribeWithEndpoint` — é o sinal para NÃO apagar o arquivo.
Um resultado vazio limpo ("não ouvi nada") não seta essa flag e o arquivo é apagado mesmo
assim.

**`PendingAudioStore.Pending` (struct completa) e a constante de retenção:**
```swift
struct Pending: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var at: Date
    var seconds: Double
    var engine: String        // STTEngine.rawValue no momento da gravação
    var modelID: String
    var language: String?
    var attempts: Int         // bumped e persistido ANTES do load do motor
}

static let maxAge: TimeInterval = 7 * 24 * 3600
static let maxFiles = 5
static let sampleRate = 16_000
```

**Escrita atômica** (`save`):
```swift
let part = dir.appendingPathComponent("\(id).wav.part")
let final = dir.appendingPathComponent("\(id).wav")
try WAV.encode(frames, sampleRate: sampleRate).write(to: part, options: [.atomic])
try FileManager.default.moveItem(at: part, to: final)
```
`.part` → rename, nunca escreve direto em `.wav`: um kill no meio do write nunca deixa um
`.wav` truncado que o próximo launch anunciaria como gravação de verdade.

**Sidecar JSON separado do áudio**, escrito por `write(_:in:)` — chamado de novo em
`bumpAttempts` para persistir o contador antes do motor carregar:
```swift
static func bumpAttempts(_ p: Pending, in dir: URL? = nil) -> Pending {
    var q = p; q.attempts += 1
    write(q, in: dir)
    return q
}
```

**Diretório e exclusão de backup:**
```swift
static func directory() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let d = base.appendingPathComponent("voice-pending", isDirectory: true)
    try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    ModelDownloadManager.excludeFromBackup(d)
    return d
}
```

**O alerta no launch** (`OdysseusApp.swift`, dentro de `RootView`):
```swift
.alert(L("Há uma gravação de %@ que não foi transcrita.", pendingAudio.map { Self.seconds($0.seconds) } ?? ""),
       isPresented: Binding(get: { pendingAudio != nil }, set: { if !$0 { pendingAudio = nil } }),
       presenting: pendingAudio) { p in
    if p.attempts < 2 {
        Button("Transcrever") { Task { await recoverPending(p) } }
    }
    Button("Descartar", role: .destructive) { PendingAudioStore.delete(p); pendingAudio = nil }
    Button("Depois", role: .cancel) { pendingAudio = nil }
} message: { p in
    Text(p.attempts >= 2
         ? L("Duas tentativas de transcrever com este modelo terminaram com o app fechado. Troque o modelo em Ajustes › Voz e modelos antes de tentar de novo.")
         : L("Motor: %@", STTEngine(rawValue: p.engine)?.label ?? p.engine))
}
```
O botão **Transcrever** só aparece com `attempts < 2` — a régua explícita "não vira loop de
crash". Disparado em dois pontos: no `.task` inicial (após `PendingAudioStore.purge()` e
`app.bootstrap()`), e em toda transição `scenePhase == .active` (`pendingAudio =
PendingAudioStore.list().last`).

**`recoverPending` cria uma instância descartável do manager**, não reusa a do chat:
```swift
private func recoverPending(_ p: PendingAudioStore.Pending) async {
    let voice = VoiceInputManager()
    voice.api = app.api
    let text = await voice.transcribe(pending: p)
    pendingAudio = nil
    recovered = text ?? voice.error ?? L("Não captei nenhuma fala.")
}
```

**UI de carregamento** (`VoiceSettingsView.swift`, `STTTestRow`):
```swift
if voice.loadingModel {
    HStack { ProgressView(); Text("Carregando modelo… A primeira vez pode levar minutos.") }
} else if voice.processing {
    HStack { ProgressView(); Text("Transcrevendo…") }
}
```
`loadingModel` é ligado em `transcribeWithWhisper` via callback `onLoading` passado ao
`STTRunner.transcribe(...)` (`Task { @MainActor in self.loadingModel = true }`) e desligado
nos dois ramos (`do`/`catch`) — isso depende do `STTRunner`, fora desta seção, mas o contrato
do `VoiceInputManager` com ele é esse: um closure de "comecei a carregar", chamado no máximo
uma vez por chamada.

**"Não cabe na memória" no `modelRow`** (depende de `STTRunner.fits`/`MemoryBudget`, também
fora desta seção, mas o padrão de uso no `VoiceInputManager`/`VoiceSettingsView` é este):
```swift
let fits = STTRunner.fits(model, coreMLBytes: downloads.coreMLBytes(model)) ?? true
...
if !fits {
    Text("Não cabe na memória deste aparelho")
        .font(.ody(size: 10)).foregroundStyle(theme.danger)
}
...
.disabled(!(STTRunner.fits(model, coreMLBytes: downloads.coreMLBytes(model)) ?? true) && !selected)
```
E no botão ⚡ (Core ML), o mesmo `STTRunner.fits` desabilita e troca o texto do `.help`, mas com `coreMLBytes` vindo de `VoiceCatalog.coreMLZipBytes(forID:)` (o zip ainda não baixado), não de `downloads.coreMLBytes(model)` como no `modelRow`.

### 3.4 Armadilhas verificadas (bugs achados, com a causa)

1. **Três `VoiceInputManager` = dois modelos grandes na RAM ao mesmo tempo.** Cada chamador
   (chat, folha de voz, bancada de Ajustes) tinha seu próprio `cachedWhisper`. A correção
   real de memória é o `STTRunner.shared` (fora desta seção); o `PendingAudioStore` não
   resolve isso sozinho — resolve "e se o processo morrer no meio", não "quantos contextos
   existem". **No porte, os dois problemas precisam ser tratados juntos ou o
   `PendingAudioStore` fica cobrindo um sintoma sem tratar a causa.**
2. **`load()` no MainActor travava a UI sem feedback** — o motivo direto de
   `loadingModel` existir. Sem essa flag, a UI mostrava "Transcrevendo…" (ou nada) durante
   minutos de compilação Core ML na primeira carga, indistinguível de travado.
3. **Motor nativo (`SFSpeechRecognizer`) é a exceção deliberada**: não passa pelo
   `PendingAudioStore` porque consome o stream do mic direto e produz parciais durante a
   gravação — não há áudio cru pra salvar, e uma morte nesse caminho perde menos (o texto
   parcial já existe). Isso está comentado explicitamente no cabeçalho do arquivo — **não
   tentar encaixar o nativo no fluxo de `pending`.**
4. **Idioma do motor Whisper NÃO é o idioma salvo no sidecar.** O `language` gravado em
   `Pending` é usado só por server/endpoint; para `.model`, `transcribeWithWhisper` recalcula
   a partir de `model.lang.whisperCode ?? chosenWhisperCode()` toda vez — inclusive na
   recuperação, com o `modelID` congelado no sidecar (`q.modelID`), não o modelo selecionado
   agora. Um porte ingênuo que reusasse `q.language` para o Whisper ignoraria modelos
   afinados por idioma.
5. **Ordem de `bumpAttempts` importa.** É incrementado e persistido **antes** de chamar o
   motor (`transcribe(pending:)` faz `let q = PendingAudioStore.bumpAttempts(p)` antes de
   `await transcribe(...)`). Se fosse depois, um crash durante o load nunca incrementaria e
   o alerta ofereceria "Transcrever" para sempre no mesmo arquivo fatal.
6. **`list()` tolera arquivo órfão dos dois lados**: um `.wav` sem `.json` ainda aparece
   (duração = `(tamanho − 44) / (2 × sampleRate)` com a constante do store, o header não é lido — um `.wav` em outra taxa daria duração errada; `engine` cai no default `.model`); um `.json` sem
   `.wav` é lixo e é apagado na hora — sem isso, um crash exatamente entre escrever o `.wav`
   e escrever o `.json` (não atômico entre os dois arquivos, só dentro de cada um)
   deixaria um estado inconsistente permanente.
7. **`finishedFrames()` também zera `rawSamples`** (`lock.withLock { let r = rawSamples;
   rawSamples = []; return r }`) — um take de 2 minutos a 48 kHz são ~23 MB; sem isso o
   buffer bruto ficaria retido depois de já ter virado `frames` de 16 kHz.

### 3.5 Como portar para OpenWebUI-iOS

**Estado atual do alvo** (verificado, não do handoff):
- `App/Features/Voice/VoiceInputManager.swift` (467 linhas) ainda importa `SwiftWhisper` e
  usa `Whisper(fromFileURL:)` com `cachedWhisper`/`cachedModelID` — é literalmente o código
  que a rodada 9 removeu do Odysseus. Não tem `STTEngine` enum: usa dois booleans lidos de
  `UserDefaults` (`useModel`, `useServer`) direto de `voice.stt.engine`; não existe motor
  `.endpoint` (endpoint próprio do usuário) no alvo.
- Dois donos do `VoiceInputManager()`, não três: `App/Features/Chat/ChatScreen.swift:12`
  (`@StateObject`) e `App/Features/Voice/VoiceConversation.swift:39` (`private let`). Ainda
  assim é o mesmo risco: dois contextos Whisper simultâneos se ambos os caminhos carregarem
  um modelo grande ao mesmo tempo.
- `App/Features/Voice/VoiceSettingsView.swift` (428 linhas) já tem `coreMLControl(_:)` com o
  botão ⚡ (`bolt`/`bolt.fill`), mas sem checagem de memória nenhuma — sempre habilitado.
  Nenhum "Carregando modelo…"; o `VoiceSettingsView` do alvo não tem linha de teste de STT nem referencia `VoiceInputManager`; `processing`/`isRecording` só aparecem no botão de mic do `ChatScreen` (`App/Features/Chat/ChatScreen.swift:413-425`).
- Não existe `PendingAudioStore.swift`, `OnDeviceSTT.swift` nem `STTRunner` no alvo — nada
  disso foi portado ainda.
- `App/Features/Voice/ModelDownloadManager.swift` existe e já tem `excludeFromBackup(_:)` com a
  mesma assinatura (`nonisolated static func`, linha 38) e `coreMLAvailable`/`hasCoreML`/`coreMLProgress`/`isDownloadingCoreML`.
  **`coreMLBytes(_:)` não existe no alvo** (só no Odysseus, `ModelDownloadManager.swift:97`): o cálculo de "cabe na memória" exige portar essa função junto.

**Ordem sugerida** (menor fatia primeiro, por `scope-smallest-first`):

1. **Portar `PendingAudioStore.swift` e o `enum WAV` inteiros, sem alteração de lógica**,
   para `App/Features/Voice/PendingAudioStore.swift`. É autocontido — só depende de
   `Foundation` e de `ModelDownloadManager.excludeFromBackup` (existe igual no alvo; a chamada compila sem adaptação). Trazer `OdysseusTests/PendingAudioStoreTests.swift` verbatim — não depende de
   `VoiceInputManager`, roda isolado.
2. **Adaptar `VoiceInputManager.stop()`** para gravar antes de transcrever. Como o alvo não
   tem `STTEngine` enum, decidir primeiro se o porte introduz o enum (recomendado — mais
   fácil de portar o resto do Odysseus depois) ou mantém os dois booleans e grava
   `engine: useServer ? "server" : "model"` como string solta. Recomendado introduzir o
   enum agora: menos divergência para o próximo porte, e o `Pending.engine` já é uma
   `String` (rawValue), então o formato em disco não muda.
3. Trocar `transcribeWithWhisper()`/`transcribeWithServer()` (privadas, sem parâmetros) por
   versões que recebem `frames:`/`language:`/`modelID:` explícitos, e adicionar o
   dispatcher público `transcribe(frames:engine:modelID:language:)` +
   `transcribe(pending:)` — copiando a forma do Odysseus. Como o alvo ainda usa
   `SwiftWhisper` (não migrou para `STTRunner`), o corpo de `transcribeWithWhisper` continua
   usando `cachedWhisper` por enquanto; `loadingModel` pode ser ligado/desligado ao redor do
   `Whisper(fromFileURL:)` + `whisper.transcribe(audioFrames:)` mesmo sem o `STTRunner` —
   já vale como sinal pra UI, mesmo que a causa raiz (MainActor bloqueado, load síncrono)
   só se resolva quando o motor for trocado por whisper.cpp/STTRunner numa rodada futura.
4. Achar (ou criar) o ponto equivalente a `RootView` no alvo — é
   `App/App/OpenWebUIApp.swift` (`@main` na linha 4, `WindowGroup` na 15) — e portar o `.alert` de recuperação +
   `pendingAudio`/`recovered`/`recoverPending`, chamando `PendingAudioStore.purge()` no
   boot e `.list().last` em `scenePhase == .active`, igual ao Odysseus.
5. Portar as duas peças de UI em `VoiceSettingsView.swift`: o texto "Carregando modelo… A
   primeira vez pode levar minutos." condicionado a `voice.loadingModel`, e (só depois que
   houver algum cálculo de memória disponível no alvo — hoje não há `MemoryBudget` nem
   `STTRunner.fits`) o aviso "Não cabe na memória deste aparelho" no `modelRow` e no botão
   ⚡. Sem uma fonte de "quanto RAM isso vai usar", esse último item fica bloqueado — não
   inventar um número; portar só quando `STTRunner`/`MemoryBudget` também forem portados.
6. Conferir os outros dois chamadores de `VoiceInputManager()` (`ChatScreen.swift`,
   `VoiceConversation.swift`): o `pending`/`lastTranscriptionFailed` do manager agora
   importam — decidir se cada chamador expõe algum feedback próprio de "há uma gravação
   pendente" ou se a app-level alert cobre os dois casos (como no Odysseus, onde o alerta é
   global em `RootView`, não por tela).

**Divergência handoff × código**: o handoff (`HANDOFF-ARQUITETURA.md`) fala em "três
`VoiceInputManager` (chat, folha de voz, bancada de Ajustes)" no Odysseus antes da correção
— confirmado batendo com o texto, não há divergência aí. No alvo (OpenWebUI-iOS) são só
dois chamadores confirmados por grep; o texto da tarefa pedia para contar isso e o código
manda: **dois**, não três.

### 3.6 Testes que cobrem

`OdysseusTests/PendingAudioStoreTests.swift` (4 testes, todos operando sobre um `dir`
temporário passado explicitamente — nenhum toca o `Application Support` real):

- `testWAVRoundTrip` — `WAV.encode`/`decode` preservam contagem de frames e sample rate;
  amostrado a cada 997 frames com tolerância de `1.0 / 32767 + 0.0001`; `decode` de dado não-WAV
  retorna `nil`.
- `testSaveListFramesDelete` — `save` grava com `attempts == 0`; `list` devolve exatamente
  o que foi salvo; nenhum `.part` sobra (a escrita é atômica); os únicos dois arquivos no
  diretório são `<id>.wav` e `<id>.json`; `bumpAttempts` incrementa e persiste (confirmado
  relendo via `list`, não só o retorno da função); `delete` limpa os dois arquivos e o
  diretório fica vazio.
- `testOrphansAreHandledWithoutABook` — um `.wav` sem sidecar ainda aparece em `list` com
  duração calculada do tamanho do arquivo; um `.json` sem `.wav` correspondente é removido pelo
  próprio `list()`.
- `testPurgeKeepsNewestFiveAndDropsOldTakes` — 7 arquivos com timestamps forjados de hora
  em hora mais 1 arquivo com 8 dias de idade; após `purge`, sobram exatamente 5 e o mais
  velho (fora da janela de 7 dias) não está entre eles.

Nenhum teste cobre `VoiceInputManager.transcribe(pending:)` nem o `.alert` em
`OdysseusApp.swift` diretamente — essa integração (dispatcher + UI) não tem teste automatizado
no Odysseus; o porte deve considerar se vale escrever um teste de integração equivalente
(por exemplo, injetando um `STTEngine` fake e conferindo que `attempts` incrementa e o
arquivo some só quando `lastTranscriptionFailed == false`) já que o alvo herdará o mesmo
gap de cobertura se copiar só o que existe.

## 4. Diagnóstico local e "Reportar bug" por e-mail (sem telemetria de servidor)

### 4.1 O que mudou e por quê

Na 1.11 o Odysseus ganhou um sistema de diagnóstico que roda **sempre**, guarda tudo
**localmente**, e só sai do aparelho quando o próprio usuário manda — por e-mail, à mão.
Motivação direta: a Rodada 9b encontrou três formas silenciosas de morte (Core ML com nome
errado, jetsam por f16 sem entitlement, `load()` travando a UI na main thread) que não
deixavam nenhum rastro utilizável — nem crash report (jetsam é `SIGKILL`, sem exceção), nem
log (o processo já morreu), nem Organizer da Apple (só chega para quem ligou "Compartilhar
com desenvolvedores de apps" e só para crash de verdade, nunca para jetsam; MetricKit entrega
ao próprio app, não a um painel).

A primeira versão do sistema (commits `ff599c1`, `9d732b6`) tinha um `DiagnosticsUploader`
opt-in com `installId` e endpoint próprio (`POST /v1/ingest`, `X-App-Id`/`X-App-Token`),
pensado para caber no Zão Hub (telemetry-server multi-app, fork do coletor do ZaoPrompt).
**O dono decidiu contra isso na noite de 13/09** (ver §4.4): não quer o app que anuncia
"Dados não coletados" com um coletor por trás, nem mexer na ficha de privacidade do App Store
Connect. O uploader, o toggle "Enviar diagnósticos anônimos" e o `installId` saíram
(`ab6a29e`; `473b599` só trocou o `recipient` para o endereço de suporte); entrou "Reportar bug", que abre o app de e-mail do próprio usuário com
o relatório anexado. Zão Hub fica no disco (`~/Projetos/ZaoHub`) para outro app, mas não é
usado aqui.

Resultado: a captura continua 100% local e sempre ligada (é o que faz a tela Ajustes ›
Diagnóstico funcionar no aparelho do dono), o e-mail é a única saída possível, e é sempre uma
ação explícita do usuário — nunca automática.

Não há divergência entre o handoff (`HANDOFF-ARQUITETURA.md`, trecho da Rodada 9/9b/decisão do
dono) e o código lido nesta seção.

### 4.2 Arquivos e símbolos no Odysseus

Tudo em `Odysseus/Features/Diagnostics/`:

- `DiagnosticsStore.swift` — o spool NDJSON, spans, âncora de sessão, anel do log do motor,
  export JSON. Singleton `DiagnosticsStore.shared`, mas o inicializador aceita `directory:`
  para testes (injeção de dependência simples, sem protocolo).
- `MemoryBudget.swift` — `availableBytes` (`os_proc_available_memory()`, só iOS — no Mac é
  `nil`, API indisponível), `physicalBytes`, `freeDiskBytes`
  (`volumeAvailableCapacityForImportantUsageKey`), `mb(_:)`/`human(_:)` para formatação.
- `MetricKitCollector.swift` — assina `MXMetricManagerSubscriber`; nunca roda no simulador
  (MetricKit também não roda lá).
- `DiagnosticsSection.swift` — a tela Ajustes › Diagnóstico (`SettingsScroll` + `SettingsCard`,
  o padrão de tela de Ajustes do Odysseus).
- `BugReport.swift` — monta o pacote (assunto, corpo, JSON) que vai no e-mail.
- `BugReportSheet.swift` — a folha com o campo de texto + botões "Enviar por e-mail" /
  "Compartilhar arquivo", `MailComposer` (iOS, `MFMailComposeViewController`) e
  `MailComposerMac` (macOS, `NSSharingService(.composeEmail)`).

Ganchos fora da pasta:

- `Odysseus/App/OdysseusApp.swift` (`RootView`): chama `DiagnosticsStore.shared.startSession`
  e `MetricKitCollector.shared.start()` no `.task` do launch; `endSession()` quando
  `scenePhase` vira `.background`; `resumeSession()` quando volta a `.active`.
- `Odysseus/Features/Settings/SettingsView.swift`: novo caso `.diagnostics` no enum
  `SettingsSection`, título "Diagnóstico", ícone `waveform.path.ecg`, entra no grupo
  `[.voice, .diagnostics, .appearance, .language, .account, .server]`; o `switch` de destino
  liga `.diagnostics` a `DiagnosticsSection()`.
- `Odysseus/Features/Settings/SettingsSections.swift` (`AccountSection`): um segundo botão
  "Reportar bug" (ícone `ladybug`) depois de um separador, abrindo o mesmo `BugReportSheet`
  — ou seja, o botão existe em **dois** lugares (Diagnóstico e Conta), ambos abrindo a mesma
  sheet.
- `Odysseus/Features/Shared/SettingsUI.swift`: ganhou `copyToClipboard(_:)` (usado pelo alerta
  de transcrição recuperada de áudio pendente, não por este recurso diretamente); `saveJSON`
  já existia e é reaproveitado por "Compartilhar arquivo" e "Exportar diagnóstico".
- `Odysseus/Resources/PrivacyInfo.xcprivacy`: comentário atualizado explicando o diagnóstico;
  `NSPrivacyCollectedDataTypes` continua **vazio** (não mudou de estado, só o comentário).
- `Odysseus/Resources/Odysseus.entitlements`: **arquivo novo**, só
  `com.apple.developer.kernel.increased-memory-limit`. Não nasceu para o diagnóstico — é
  para o modelo Whisper/Parakeet caber na memória sem jetsam (Rodada 9b) — mas
  `MemoryBudget`/`DiagnosticsStore` são o que permite *detectar e explicar* o jetsam quando
  a entitlement não é suficiente (aparelho com pouca RAM, dois modelos grandes ao mesmo tempo
  etc.).

### 4.3 Trechos de código que o porte precisa

**`DiagEvent`** (o formato de linha do NDJSON, igual ao shape que um coletor de servidor
esperaria — mas aqui nunca sai do aparelho):

```swift
struct DiagEvent: Codable, Identifiable, Sendable {
    var name: String
    var ts: Double
    var props: [String: String]
    var id: String { "\(ts)-\(name)" }
    var date: Date { Date(timeIntervalSince1970: ts) }
}
```

**API pública de `DiagnosticsStore`** (assinaturas, sem corpo):

```swift
final class DiagnosticsStore: @unchecked Sendable {
    static let shared = DiagnosticsStore()
    init(directory: URL? = nil)

    static var appID: String   // "odysseus-ios" / "odysseus-macos"

    func event(_ name: String, _ props: [String: String] = [:])
    func recentEvents(limit: Int = 200) -> [DiagEvent]
    func drop(upTo ts: Double)

    func beginSpan(_ name: String, _ props: [String: String] = [:])
    func endSpan(_ name: String, _ extra: [String: String] = [:])
    func failSpan(_ name: String, _ error: String)
    func openSpans() -> [String: [String: String]]

    func startSession(version: String, build: String)
    func endSession()
    func resumeSession()
    func lastSuspectedDeath() -> DiagEvent?

    func appendEngineLog(_ line: String)
    func engineLogTail(_ n: Int = 120) -> [String]

    func exportJSON() -> Data
}
```

Constantes internas relevantes para o porte (limites de tamanho, não são segredo):
`spoolLimit = 512 * 1024` bytes (rotaciona `spool.ndjson` → `spool.1.ndjson`),
`logRingLimit = 400` linhas de log do motor.

**A regra de "morte suspeita"** (o coração do recurso — `startSession`, chamado uma vez no
launch):

```swift
func startSession(version: String, build: String) {
    let leftovers = openSpans()
    for (name, props) in leftovers {
        var p = props; p["span"] = name
        event("death.suspected", p)
    }
    // ...remove spans, persiste...
    let abnormal = FileManager.default.fileExists(atPath: sessionURL.path)
    try? Data("1".utf8).write(to: sessionURL)
    // ...
    if abnormal && leftovers.isEmpty { event("session.abnormal_end") }
    event("session.begin", ["version": version, "build": build, "physMB": MemoryBudget.mb(MemoryBudget.physicalBytes)])
}
```

Ou seja: um `span` aberto (gravado com fsync ANTES da operação arriscada) que ainda está lá
no próximo launch vira `death.suspected` com todas as props do span (`model`, `availMB` etc.);
se não havia span aberto mas o arquivo `session.open` já existia (processo nunca chamou
`endSession()`), vira `session.abnormal_end` — mais fraco (não sabe o que estava rodando, mas
sabe que morreu fora do ciclo normal).

**Uso típico de span** (o padrão que o porte deve replicar ao redor de `load()`/`decode()` do
motor de voz):

```swift
DiagnosticsStore.shared.beginSpan("stt.load", ["model": modelId, "availMB": MemoryBudget.mb(MemoryBudget.availableBytes)])
// ...trabalho arriscado (ler .bin, compilar Metal, carregar Core ML)...
DiagnosticsStore.shared.endSpan("stt.load", ["availMB": "...", "coreml": "..."])   // `ms` é calculado pelo próprio endSpan a partir do `at` do span; ou failSpan(_:_:) num catch
```

**`DiagnosticsSection.describe(_:)`** — o texto em linguagem de gente a partir do nome do span
(usado tanto na tela quanto no corpo do e-mail):

```swift
static func describe(_ e: DiagEvent) -> String {
    let span = e.props["span"] ?? ""
    switch span {
    case "stt.load":    return L("O app foi encerrado pelo sistema enquanto carregava o modelo %@ (havia %@ disponíveis). Provável falta de memória.", model, avail)
    case "stt.decode":  return L("O app foi encerrado durante a transcrição com o modelo %@.", model)
    case "coreml.unpack": return L("O app foi encerrado enquanto descompactava o encoder Core ML de %@.", model)
    case "":            return L("O app não foi encerrado normalmente na última vez (sem operação de voz em andamento).")
    default:            return L("O app foi encerrado durante “%@”.", span)
    }
}
```

Os nomes de span (`stt.load`, `stt.decode`, `coreml.unpack`) são específicos do Odysseus (STT
com Whisper/Parakeet + Core ML). No OpenWebUI-iOS o equivalente é onde o `SwiftWhisper`
antigo carrega/decodifica — os nomes de span devem virar os que fizerem sentido lá
(`stt.load`/`stt.decode` e também `coreml.unpack`: o `ModelDownloadManager` do alvo já
baixa o encoder Core ML como zip e descompacta em `unpackCoreML`, linhas 193-238; a FluidAudio
é toda Core ML).

**`BugReport`** — constantes e assinatura:

```swift
enum BugReport {
    static let recipient = "joaozao@macrozao.online"   // troca no porte (ver pergunta aberta)
    static let window: TimeInterval = 60 * 60
    static let minimumEvents = 50

    struct Package: Equatable {
        var subject: String
        var body: String
        var filename: String
        var json: Data
    }

    static func make(description: String, store: DiagnosticsStore = .shared, now: Date = Date()) -> Package
    static var osLabel: String        // "iOS 27.0" / "macOS 27.0"
    static var deviceModel: String    // "iPhone16,2" via utsname; "Mac15,6" via sysctlbyname no Mac
}
```

Regra de janela: pega eventos da última hora (`window`); se a última hora tiver menos que
`minimumEvents` (50), usa os últimos 50 eventos do spool inteiro (`Array(all.suffix(minimumEvents))`)
— nunca manda um relatório vazio só porque o app estava quieto. `id` do relatório é
`UUID().uuidString.lowercased()`, gerado a cada `make()` — nunca um id de instalação estável.

Assunto do e-mail (formato exato):
`"Bug report Odysseus \(version) (\(build)) · \(osLabel) · \(deviceModel)"`.

Nome do anexo: `"odysseus-bug-\(yyyyMMdd-HHmm).json"` (formatter com
`Locale(identifier: "en_US_POSIX")`, para não variar por idioma do sistema).

**Envio** (`BugReportSheet.swift`) — iOS usa `MFMailComposeViewController` com
`MailComposer.canSend` checando `MFMailComposeViewController.canSendMail()`; se não houver
conta de e-mail configurada, o botão "Enviar por e-mail" dá lugar a um texto explicativo;
"Compartilhar arquivo" é incondicional, sempre aparece (via `SettingsUI.saveJSON`, que já
existe no Odysseus e cobre share sheet/painel de salvar). No Mac,
`NSSharingService(named: .composeEmail)` grava o JSON num arquivo temporário e chama
`service.perform(withItems:)`.

**Manifesto de privacidade final** — trecho relevante (`PrivacyInfo.xcprivacy`):

```xml
<key>NSPrivacyTracking</key><false/>
<key>NSPrivacyTrackingDomains</key><array/>
<key>NSPrivacyCollectedDataTypes</key><array/>
<key>NSPrivacyAccessedAPITypes</key>
<array>
  <dict><key>NSPrivacyAccessedAPIType</key><string>NSPrivacyAccessedAPICategoryUserDefaults</string>
        <key>NSPrivacyAccessedAPITypeReasons</key><array><string>CA92.1</string></array></dict>
  <dict><key>NSPrivacyAccessedAPIType</key><string>NSPrivacyAccessedAPICategoryDiskSpace</string>
        <key>NSPrivacyAccessedAPITypeReasons</key><array><string>85F4.1</string></array></dict>
</array>
```

`CA92.1` cobre leitura de `UserDefaults` (tema, escolha de motor, URLs de endpoint) só para
uso do próprio app; `85F4.1` cobre checar espaço livre em disco antes de baixar um modelo
(`ModelDownloadManager`). O bug report também usa a segunda: `MemoryBudget.freeDiskBytes` lê
`volumeAvailableCapacityForImportantUsageKey` (85F4.1). Nenhuma API de motivo nova entrou;
por isso não precisou de terceira entrada.

**Entitlement** (`Odysseus.entitlements`, arquivo inteiro é pequeno):

```xml
<key>com.apple.developer.kernel.increased-memory-limit</key>
<true/>
```

### 4.4 Armadilhas verificadas

1. **A telemetria de servidor foi construída, testada e depois totalmente removida.** Três
   commits: `ff599c1` implementou `DiagnosticsUploader` com `installId`,
   endpoint `POST /v1/ingest`, headers `X-App-Id`/`X-App-Token`, backoff persistido;
   `9d732b6` corrigiu um bug nela (upload sem token dava 400 no hub); e o terceiro
   (`ab6a29e`) removeu tudo. **Não portar o uploader** — ele nunca foi ao ar e o dono decidiu
   explicitamente contra essa forma de diagnóstico. Portar só o que sobrou: spool local +
   bug report por e-mail.

2. **O manifesto de privacidade saiu malformado no primeiro archive da 1.11.** O patch que
   esvaziou `NSPrivacyCollectedDataTypes` fechou a tag `<array>` interna errado (o array de um
   `dict` específico, não o array-mãe), e isso só foi pego rodando `plutil -lint` no arquivo
   dentro do `.xcarchive` — o Xcode não acusa no build normal. Causa: edição manual de XML sem
   revalidar a estrutura aninhada. Consertado em `ceeed9a`, e `PrivacyManifestTests` agora lê
   o arquivo real do bundle (`Bundle(for: AppState.self).url(forResource:withExtension:)`) e
   garante `NSPrivacyCollectedDataTypes` com `count == 0` e as duas APIs certas — teste que
   roda todo archive, não só uma vez. **Ao portar, gerar/editar o `.xcprivacy` do
   OpenWebUI-iOS com o mesmo cuidado e rodar `plutil -lint` no arquivo final antes de
   confiar nele.**

3. **A entitlement nova invalidou o perfil de distribuição do iOS** (não é bug do
   diagnóstico, mas trava exatamente pelo entitlement que o acompanha): o archive passa (Xcode
   registra a capability no App ID automaticamente), mas o `-exportArchive` morre com "Cloud
   signing permission error" porque a chave de API (App Manager) não regenera perfis geridos
   pelo Xcode. Correção: apagar o perfil auto gerado (fica INVALID), criar um novo via API
   (`POST /v1/profiles`, tipo `IOS_APP_STORE`) e exportar com `signingStyle: manual`. **Se o
   OpenWebUI-iOS ainda não tem nenhuma entitlement no alvo iOS, adicionar
   `increased-memory-limit` (se portada) vai disparar o mesmo problema na primeira
   exportação** — não é específico do diagnóstico, mas é uma armadilha que qualquer entitlement
   nova aciona.

4. **Por que não usar o canal de crash da Apple**: registrado explicitamente como decisão, não
   como bug, mas vale para o porte não reinventar: Organizer só recebe crash de verdade (não
   jetsam) e só de usuários que ligaram "Compartilhar com desenvolvedores de apps"; MetricKit
   entrega ao próprio processo, não a um painel do dono. Não há atalho — o app precisa
   registrar e mostrar isso sozinho.

5. **`os_proc_available_memory()` é uma leitura instantânea, nunca cache.** O comentário em
   `MemoryBudget.swift` é explícito: ler direto antes de qualquer alocação grande, nunca
   guardar o valor. Um valor cacheado teria sido exatamente o tipo de erro que mascarou o
   "f16 crashava sem erro" por tanto tempo.

### 4.5 Como portar para OpenWebUI-iOS

**Estado do alvo hoje** (conferido por leitura direta, não pelo handoff):

- `OpenWebUI-iOS/PRIVACY.md` existe e já diz "não coleta, não armazena, não compartilha" —
  compatível com adicionar diagnóstico local + bug report por e-mail, contanto que a política
  ganhe uma frase equivalente à do Odysseus explicando que o relatório é opcional e iniciado
  pelo usuário.
- **Não existe `PrivacyInfo.xcprivacy` do próprio app** — só o de dependências de terceiros
  (`ZIPFoundation`) aparecem em `build-device/` (não versionado, gerado). Isso significa que o
  porte cria esse arquivo do zero, não edita um existente. O app já usa as duas APIs de motivo
  sem declarar: `UserDefaults` em dezenas de sítios (AppState, ServerConfig, Theme,
  VoiceModels, SpeechManager) e espaço em disco em `ModelDownloadManager.swift:177-178`; declarar as
  mesmas duas entradas (`CA92.1`, `85F4.1`) se for o caso.
- **Não existe nenhuma entitlement no alvo iOS** (só há `.entitlements` de macOS:
  `App/Resources/OpenWebUI-macOS.entitlements` e um `Odysseus-macOS.entitlements` residual).
  Se o porte também endereçar o jetsam do Whisper/FluidAudio (fora do escopo desta seção, mas
  relacionado), o `increased-memory-limit` no iOS vai precisar de um arquivo novo e vai acionar
  a mesma armadilha de perfil de distribuição (§4.4 item 3) na primeira exportação — avisar o
  dono com antecedência.
- **`App/Features/Settings/SettingsView.swift`** usa `List` + `Section` (não o padrão
  `SettingsScroll`/`SettingsCard` do Odysseus) — os componentes de UI do Odysseus
  (`DiagnosticsSection`, `BugReportSheet`) não colam direto; a estrutura (textos, regras,
  telas) porta, o container visual (`List`/`Section` com `.listRowBackground(theme.panel)`)
  precisa ser reescrito no estilo local. A seção `"CONTA"` do mesmo `SettingsView.swift` (linhas 69-81) já tem o botão
  "Sair" (`Button(role: .destructive) { await app.logout() }`); "Reportar bug" entra ali, como no Odysseus.
- **Não existe nenhum `MFMailComposeViewController`/`NSSharingService` no projeto** — o porte
  cria `BugReportSheet.swift`/`MailComposer` do zero, copiando a estrutura do Odysseus quase
  verbatim (é código de plataforma, não de domínio).
- **`SettingsUI`-equivalente**: `saveJSON` não existe no alvo; `copyToClipboard(_:)` existe, mas privado
  em `App/Features/Chat/MessageBubble.swift:367-374` (os dois ramos UIPasteboard/NSPasteboard); `App/Config/PlatformCompat.swift` é o lugar mais provável de abrigar
  utilitários cross-platform — conferir se já existe uma função de salvar arquivo (painel
  macOS / share sheet iOS) antes de duplicar; senão, portar `saveJSON` do Odysseus para lá.
- **Como o app é iPhone-only** para efeito deste porte (a instrução do time trata a parte
  macOS como fora de escopo, mesmo havendo um target macOS real no `project.yml`): implementar
  só o caminho `MFMailComposeViewController`; pode-se pular `MailComposerMac`/`NSSharingService`
  ou portá-los depois, sem bloquear a entrega principal.

**Ordem sugerida:**

1. `DiagnosticsStore.swift` + `MemoryBudget.swift` — copiar quase verbatim (não dependem de
   nada específico de voz; `MemoryBudget` é plataforma pura). Adaptar `appID` para
   `"openwebui-ios"`/`"openwebui-macos"` e o subsystem do `Logger`.
2. Instrumentar o carregamento/decodificação do motor de voz atual (SwiftWhisper 2023 +
   FluidAudio) com `beginSpan`/`endSpan`/`failSpan` — é aqui que o porte precisa decidir os
   nomes de span equivalentes a `stt.load`/`stt.decode` (sem `coreml.unpack`, a menos que o
   FluidAudio também tenha uma etapa de descompactação de modelo Core ML — conferir o código
   do FluidAudio antes de assumir que não).
3. `MetricKitCollector.swift` — copiar verbatim; só precisa existir e ser chamado uma vez no
   launch.
4. Ganchos de sessão em `OpenWebUIApp.swift` (`RootView`): hoje o `.onChange(of: scenePhase)`
   só chama `app.refreshModelsIfNeeded()` em `.active` — adicionar
   `DiagnosticsStore.shared.startSession(...)`/`MetricKitCollector.shared.start()` no `.task`
   de bootstrap, e `endSession()`/`resumeSession()` no `.onChange(of: scenePhase)` existente
   (não criar um segundo).
5. `BugReport.swift` — copiar a lógica (janela, piso de eventos, formato do assunto/nome de
   arquivo); mudar `recipient` (ver pergunta aberta abaixo) e ajustar `osLabel`/strings para
   "OpenWebUI" em vez de "Odysseus".
6. `DiagnosticsSection.swift` — reescrever a tela usando o padrão de UI do alvo (`List`/
   `Section`, não `SettingsScroll`/`SettingsCard`); manter o mesmo conteúdo (último
   encerramento anormal, memória agora, botão Reportar bug, botão Exportar diagnóstico,
   eventos recentes, log do motor).
7. `BugReportSheet.swift` + `MailComposer` (só o ramo iOS, ver acima) — copiar estrutura,
   adaptar tema/estilo.
8. Adicionar a entrada de menu em `SettingsView.swift` (seção nova "DIAGNÓSTICO" com
   `NavigationLink` para a tela, no padrão das seções existentes) e o botão extra em "CONTA"
   se o dono do OpenWebUI-iOS quiser o mesmo padrão de dois lugares.
9. Criar `PrivacyInfo.xcprivacy` do zero (checar `NSPrivacyAccessedAPITypes` reais do projeto
   antes de copiar as mesmas duas entradas do Odysseus — podem não ser as mesmas APIs) e
   rodar `plutil -lint` nele.
10. Atualizar `PRIVACY.md` com uma seção equivalente sobre o bug report opcional.
11. Portar os três arquivos de teste (§4.6), adaptando para o pacote/alvo do OpenWebUI-iOS
    (provavelmente dentro de `OpenWebUIKit` ou de um alvo de testes próprio — conferir a
    estrutura de testes do alvo antes de decidir onde entram).

### 4.6 Testes que cobrem

- `OdysseusTests/DiagnosticsStoreTests.swift` (5 testes):
  - `testEventsAreAppendedAndReadBackInOrder` — eventos voltam na ordem gravada; `drop(upTo:)`
    remove só os antigos.
  - `testOpenSpanBecomesASuspectedDeathOnTheNextLaunch` — um span aberto por uma instância
    sobrevive no disco e uma segunda instância (simulando o próximo launch) o lê, gera
    `death.suspected` com as props do span, e consome o span (`openSpans()` fica vazio depois).
  - `testCleanSessionEndLeavesNoAbnormalMark` — `endSession()` chamado a tempo não deixa
    `lastSuspectedDeath()`; `endSpan` grava `.ok` com `ms` calculado e as props extras.
  - `testAbnormalEndWithoutSpanIsStillRecorded` — sessão que nunca chamou `endSession()`, sem
    span aberto, ainda vira `session.abnormal_end` na próxima.
  - `testEngineLogTailIsKept` — 500 linhas escritas, `engineLogTail(3)` devolve as 3 últimas;
    `exportJSON()` nunca fica vazio.

- `OdysseusTests/BugReportTests.swift` (4 testes):
  - `testTheDescriptionTravelsAndNothingIdentifiesTheInstall` — a descrição do usuário chega
    aparada no JSON e no corpo; **não há chave `installId`** no JSON; assunto começa com
    `"Bug report Odysseus "`; nome de arquivo no formato certo; corpo cita o nome do anexo.
  - `testOnlyTheLastHourGoesUnlessItWasQuiet` — 80 eventos recentes: todos os 80 entram
    (dentro da hora); pedindo o relatório 2h no futuro, cai para exatamente `minimumEvents`
    (50), pegando os últimos 50 do spool inteiro (não os primeiros).
  - `testEachReportHasItsOwnIdAndTheExportHasNone` — dois `make()` seguidos geram `id`s
    diferentes; `exportJSON()` (usado pela tela, não pelo e-mail) não tem `installId`.
  - `testTheLastAbnormalExitIsSpelledOutInTheBody` — um span `stt.load` deixado aberto por uma
    instância aparece no corpo do e-mail (`"w-large"`) e como `lastAbnormalExit.props.span` no
    JSON da segunda instância.

- `OdysseusTests/PrivacyManifestTests.swift` (1 teste):
  - `testTheManifestParsesAndDeclaresNoCollectedDataAndNoTracking` — lê o
    `PrivacyInfo.xcprivacy` real do bundle de teste, garante `NSPrivacyTracking == false`,
    `NSPrivacyTrackingDomains` vazio, `NSPrivacyCollectedDataTypes` com `count == 0`, e o
    conjunto de `NSPrivacyAccessedAPIType` é exatamente
    `{UserDefaults, DiskSpace}`. Este teste roda contra o arquivo empacotado de verdade, não
    uma cópia — é o que teria pego o `<array>` malformado antes do upload (armadilha §4.4.2).

### 4.7 Perguntas para o dono

- Qual endereço de e-mail recebe os bug reports do OpenWebUI-iOS? No Odysseus é
  `joaozao@macrozao.online`; pode ser o mesmo ou outro (o `PRIVACY.md` do OpenWebUI-iOS já
  lista `privacidade@macrozao.online` para dúvidas de privacidade — não necessariamente o
  mesmo endereço para bug report).
- O OpenWebUI-iOS deve declarar o mesmo par de `NSPrivacyAccessedAPITypes`
  (UserDefaults CA92.1, DiskSpace 85F4.1), ou o app usa alguma outra "required-reason API"
  que também precisa entrar no manifesto? Precisa de uma varredura própria do projeto antes de
  copiar as entradas do Odysseus.
- Vale portar `increased-memory-limit` (Odysseus.entitlements) junto, dado que o
  OpenWebUI-iOS ainda está no SwiftWhisper de 2023 + FluidAudio (modelos podem ser grandes o
  suficiente para jetsam)? Isso está fora do escopo desta seção (é da fatia de voz/memória),
  mas decide se o porte cria a primeira entitlement iOS do projeto e aciona a armadilha de
  perfil de distribuição (§4.4.3) antes do esperado.

## 5. Strings novas (45 chaves) e o método de tradução por workflow

### 5.1 O que mudou e por quê

A rodada 1.11 mexeu duas vezes no catálogo de strings, nos mesmos 43 `.lproj` do Odysseus:

1. **`ff599c1`** (fix de voz + Diagnóstico) acrescentou **32 chaves novas** nos 43 catálogos de uma vez (valor = texto pt-BR nos 41 não traduzidos; só en foi traduzido nesse commit — comentário do próprio commit: "en translated; others pending"). Cobrem: gate de memória do modelo, tela "Diagnóstico" (últimos eventos, encerramento anormal, memória, log do motor), o toggle "Enviar diagnósticos anônimos" + "Token do app", e o fluxo de recuperação de gravação pendente (voice-pending).
2. **`ab6a29e`** (bug report por e-mail) fechou o assunto diagnóstico de um jeito diferente do que a primeira leva projetava: em vez de um uploader anônimo com toggle, o dono decidiu que nada sai do aparelho sem o usuário compor e mandar um e-mail. Isso **removeu 3 das 32 chaves** (o toggle inteiro) e **acrescentou 13 chaves novas** da tela `BugReportSheet`. Motivo declarado no commit: "the owner does not want a collector behind an app that says it collects nothing, nor a change to the App Store privacy label" — mantém o `PrivacyInfo.xcprivacy` declarando zero coleta (a regra de "divulgação opcional" da Apple cobre um envio visível, iniciado pelo usuário e pouco frequente).
3. **`eb9a236`** entre os dois: traduziu as 32 chaves do passo 1 para as outras 41 línguas (antes de o passo 2 apagar 3 delas — por isso o diff final por idioma mostra 42 linhas adicionadas líquidas, não 45).

Total bruto do round: **32 + 13 = 45 chaves novas escritas em algum momento**; **3 removidas** depois (o toggle); saldo líquido final por catálogo: **42 chaves a mais**, **0 removidas do estado final** (as 3 do toggle chegaram a ser traduzidas nas 41 línguas em `eb9a236` e saíram de todos os catálogos em `ab6a29e`). Cada `.lproj` termina com **875 chaves** (linhas variam de 912 a 922 por comentários) — confira com `grep -c '^"'`.

### 5.2 Chaves REMOVIDAS (toggle de diagnóstico anônimo)

Existiram só entre os commits `ff599c1` e `ab6a29e` (traduzidas nas 41 línguas em `eb9a236`, removidas de todos os 43 catálogos em `ab6a29e`):

| Chave (pt-BR = chave) | en (quando existiu) |
|---|---|
| `"Enviar diagnósticos anônimos"` | "Send anonymous diagnostics" |
| `"Desligado por padrão. Envia só travamentos, tempos de carga e memória — nunca áudio, texto ou o endereço do seu servidor."` | "Off by default. Sends only crashes, load times and memory — never audio, text or your server address." |
| `"Token do app"` | "App token" |

Junto com o texto foram embora `DiagnosticsUploader` e `installId` (ver seção 2/3 do handoff geral). **Não portar essas 3 — são código morto no próprio Odysseus.**

### 5.3 Chaves NOVAS (42 vivas no HEAD, pt-BR = chave / en = tradução)

Bloco 1 — `/* 1.11 — Diagnóstico, memória e gravação pendente */` (29 chaves vivas, das 32 originais menos as 3 removidas):

| Chave (pt-BR) | en |
|---|---|
| `Este modelo não cabe na memória deste aparelho (precisa de %@, há %@ livres). Use um q5 ou o Parakeet.` | This model does not fit in this device's memory (needs %@, %@ free). Use a q5 or Parakeet. |
| `Baixa o encoder Core ML (%@). A primeira carga compila para o Neural Engine e pode levar minutos.` | Downloads the Core ML encoder (%@). The first load compiles it for the Neural Engine and can take minutes. |
| `Não cabe na memória deste aparelho` | Does not fit in this device's memory |
| `Carregando modelo… A primeira vez pode levar minutos.` | Loading model… The first time can take minutes. |
| `Diagnóstico` | Diagnostics |
| `O que o app registrou sobre travamentos, memória e o motor de voz. Fica no aparelho; enviar é opcional.` | What the app recorded about crashes, memory and the speech engine. It stays on the device; sending is optional. |
| `Último encerramento anormal` | Last abnormal exit |
| `Nenhum registro.` | Nothing recorded. |
| `Memória agora` | Memory now |
| `Disponível para o app: %@` | Available to the app: %@ |
| `Física: %@` | Physical: %@ |
| `No Mac o limite por app não é exposto pelo sistema.` | On the Mac the per-app limit is not exposed by the system. |
| `É quanto o app ainda pode usar antes de o sistema encerrá-lo. Um modelo precisa caber aqui com folga.` | How much the app can still use before the system terminates it. A model has to fit here with room to spare. |
| `Exportar diagnóstico` | Export diagnostics |
| `Exportado` | Exported |
| `Eventos recentes` | Recent events |
| `Log do motor de voz` | Speech engine log |
| `O app foi encerrado pelo sistema enquanto carregava o modelo %@ (havia %@ disponíveis). Provável falta de memória.` | The system terminated the app while it was loading the model %@ (%@ were available). Probably out of memory. |
| `O app foi encerrado durante a transcrição com o modelo %@.` | The app was terminated during transcription with the model %@. |
| `O app foi encerrado enquanto descompactava o encoder Core ML de %@.` | The app was terminated while unpacking the Core ML encoder for %@. |
| `O app não foi encerrado normalmente na última vez (sem operação de voz em andamento).` | The app did not exit normally last time (no speech operation was in progress). |
| `O app foi encerrado durante “%@”.` (aspas curvas, iguais no arquivo) | The app was terminated during “%@”. |
| `Há uma gravação de %@ que não foi transcrita.` | There is a %@ recording that was not transcribed. |
| `Transcrever` | Transcribe |
| `Descartar` | Discard |
| `Depois` | Later |
| `Duas tentativas de transcrever com este modelo terminaram com o app fechado. Troque o modelo em Ajustes › Voz e modelos antes de tentar de novo.` | Two attempts to transcribe with this model ended with the app closed. Change the model in Settings › Voice and models before trying again. |
| `Motor: %@` | Engine: %@ |
| `Transcrição recuperada` | Recovered transcript |

Bloco 2 — `/* Rodada 9c — 1.11: relatório de bug por e-mail */` (13 chaves, todas vivas):

| Chave (pt-BR) | en |
|---|---|
| `Reportar bug` | Report a bug |
| `Relatório de bug` | Bug report |
| `O que aconteceu?` | What happened? |
| `Enviar por e-mail` | Send by email |
| `Compartilhar arquivo` | Share the file |
| `Vai junto: aparelho, versão do app e do sistema, memória e a última hora de registros (tempos de carga, travamentos, log do motor de voz). Nunca áudio, texto ou o endereço do seu servidor. Nada sai sem você tocar em enviar.` | What goes: device, app and system version, memory and the last hour of records (load times, crashes, speech engine log). Never audio, text or your server address. Nothing leaves until you tap send. |
| `Nenhum app de e-mail configurado neste aparelho. Compartilhe o arquivo por outro caminho.` | No mail app is set up on this device. Share the file another way. |
| `Abre um e-mail para o desenvolvedor com a última hora de registros. Você vê tudo antes de enviar.` | Opens an email to the developer with the last hour of records. You see everything before sending. |
| `Enviado` | Sent |
| `Memória disponível: %@ · Física: %@ · Disco livre: %@` | Memory available: %@ · Physical: %@ · Free disk: %@ |
| `Último encerramento anormal: %@` | Last abnormal exit: %@ |
| `Eventos anexados: %@` | Events attached: %@ |
| `Anexo: %@` | Attachment: %@ |

Nota de divergência: o handoff pede grep por "Rodada 9" e diz que o bloco é "os últimos do arquivo" — confirmado, o bloco `Rodada 9c` é literalmente o final do arquivo em ambos os idiomas (linha 900+ de 913 em pt-BR). Já o bloco `1.11 — Diagnóstico…` **não** tem "Rodada" no comentário — é preciso pegar os dois blocos (grep por "Rodada 9" só acha o segundo).

### 5.4 Método de tradução para as outras 41 línguas

Duas levas. `eb9a236` (32 chaves) rodou **opus, tradutor + revisor por locale** (82 agentes) — foi ANTES da regra do dono; ele reclamou da quota e a leva seguinte, `ab6a29e` (13 chaves do bug report), rodou **sonnet, um agente por locale, passada única** (41 agentes; workflow `wf_edab476c-47f` desta sessão). Nas duas, a saída do agente é forçada por schema JSON pela ferramenta Workflow e um script Python aplica o resultado nos catálogos. **Daqui em diante: sonnet, passada única.**

**Script**: `apply_translations.py`, achado em `/private/tmp/claude-501/-Users-joaozao-Projetos/aae19c9d-e660-4976-b539-7f0d405bd454/scratchpad/tts/pipeline/apply_translations.py` (o caminho leva "tts/pipeline" por reaproveitamento de scratchpad de outra tarefa — o conteúdo é genérico, não é código de TTS). Ainda existe no disco nesta sessão.

Interface do script (verbatim, resumida):
```python
"""Apply workflow translation results ([{code, translations:{pt_key: text}}]) to Localizable.strings files.
Usage: apply_translations.py <result.json-or-task-output> [...]  — replaces the value of each key in <code>.lproj."""
root='/Users/joaozao/Projetos/Odysseus-iOS/Odysseus/Resources'
```
- **Entrada**: um ou mais arquivos (path via `argv`) contendo JSON — ou bruto (`json.loads` direto) ou embutido em texto de saída de tarefa (`load()` cai no `except` e faz `raw.find('[{"code"')` / `raw.rfind('}]')` para extrair o array de dentro de qualquer prosa em volta). Formato do array:
  ```json
  [{"code": "fr", "translations": {"<chave pt-BR>": "<tradução>", "...": "..."}}, ...]
  ```
  `code` é o nome do `.lproj` (ex.: `fr`, `zh-Hans`, `de-CH`). `translations` mapeia a chave pt-BR (literal, com `%@` etc.) para o texto traduzido.
- **Processamento por chave**: pula valor vazio ou não-string; **descarta a tradução inteira se a contagem de `%@` não bater** entre chave e valor (`print('placeholder mismatch', code, k[:40])` e segue sem tocar naquela linha — protege contra um agente que troca ou remove um placeholder printf); localiza a linha `"chave" = "...";` por regex ancorada em início de linha e faz substituição in-place, escapando `\`, `"` e `\n` (`esc()`).
- **Saída**: reescreve cada `<root>/<code>.lproj/Localizable.strings` inteiro (não é append — reescreve o arquivo com as linhas substituídas) e imprime `{code: quantidade_de_chaves_trocadas}` no final. Não cria arquivo novo, não valida UTF-8 além do que Python já faz, não roda em paralelo.
- **Se um catálogo não existir** (`code` sem pasta `.lproj` correspondente), imprime `missing catalog <code>` e pula — não falha o lote inteiro.

O workflow que gera o JSON de entrada não está mais neste scratchpad (não achei o script/prompt do lançador de sub-agentes, só o aplicador). Pelo commit message ("translate the 32 diagnostics/memory/pending-recording strings into the other 41 languages") e pelo padrão de todo o projeto (memória: "Novidades em 55 localizações", "Novidades em 30 locales" nas rodadas 1.10/1.11 do próprio Odysseus), o método (o que esta sessão fez em `ab6a29e`) é: lançar um agente sonnet por idioma-alvo (41 tarefas), cada um recebendo a lista fixa das 32 chaves pt-BR + já o texto en como referência, devolvendo `{code, translations}` por saída estruturada (schema forçado, evita prosa em volta atrapalhar o parser — embora o parser tenha um fallback pra prosa mesmo assim); depois um agrega os 41 resultados (ou um por arquivo) e roda `apply_translations.py` neles.

### 5.5 Como portar para OpenWebUI-iOS

**Catálogos existentes no alvo**: `ls /Users/joaozao/Projetos/OpenWebUI-iOS/App/Resources | grep -c lproj` → **44 pastas** (o `find` sem `-prune` em `build-device/` devolve 45, um `Base.lproj` de exemplo do whisper.cpp), contra 43 no Odysseus — o alvo tem `de-AT` e `mn` a mais e **não tem `zh-HK`** (43 + 2 − 1 = 44). Todos os 44 catálogos do OpenWebUI-iOS têm hoje **254 chaves** cada (`grep -c '^"' App/Resources/<lang>.lproj/Localizable.strings`), simétricos entre si — não há chave nova pendente de tradução no momento.

**`L(_:)` no alvo**: existe, em `OpenWebUIKit/Sources/OpenWebUIKit/Localization.swift:290` (`public func L(_ key: String, _ args: CVarArg...) -> String`). A regra "a chave é o texto pt-BR" é a mesma: `LanguageManager.snapshotBundle.localizedString(forKey: key, value: key, table: nil)` usa a própria chave como `value` de fallback. **Diferença de mecanismo** (registrar, não é bug): o Odysseus resolve via *swizzle* de `Bundle.main` (subclasse `LocalizedBundle` instalada com `object_setClass`, documentado como obrigatório porque `String(localized:)` do Foundation não passa por aí); o OpenWebUI-iOS já usa um `LanguageManager` com `snapshotBundle` guardado por lock, sem precisar trocar a classe de `Bundle.main`. Os dois evitam `String(localized:)` puro pelo mesmo motivo (ele resolve contra `Locale.current`, não contra o idioma escolhido no app) — **confirmar que nenhum código novo do porte usa `String(localized:)` diretamente**, só `L(_:)` ou `Text("chave")` normal do SwiftUI.

**Nenhuma das 42 chaves de diagnóstico/bug-report existe hoje no OpenWebUI-iOS** (`grep -in "diagnóstico\|bug\|encoder"` no `pt-BR.lproj` do alvo não bateu nada) — é tudo texto novo a acrescentar, não um merge.

**Ordem sugerida do porte de strings**:
1. Portar primeiro **só as chaves ligadas a features que o porte de código vai mesmo trazer** — releia a seção 2/3 deste documento para saber quais pedaços de `STTRunner`, `Diagnostics` e `BugReportSheet` entram no OpenWebUI-iOS. Não copiar as 3 chaves do toggle removido (§5.2) nem qualquer string cujo símbolo Swift correspondente não for portado.
2. Adicionar as chaves novas primeiro em `en.lproj` e `pt-BR.lproj` (chave = valor em pt-BR, tradução manual/real em en), do jeito que o Odysseus fez no `ff599c1`/`ab6a29e` — não confiar em tradução automática para o idioma de referência.
3. Rodar o mesmo padrão de `apply_translations.py` apontando `root` para `OpenWebUI-iOS/App/Resources` (o script é genérico o bastante — só a constante `root` no topo do arquivo precisa mudar) contra os outros 42 idiomas (44 catálogos do alvo menos en/pt-BR), lançando um agente sonnet por locale como no Odysseus (memória do time: "Sub-agentes: sonnet por padrão... quota semanal e de 5h; opus só a pedido"). Cobrir também `de-AT` e `mn`, que o Odysseus nem tem — não há como copiar tradução pronta de lá para esses dois, precisam de tradução própria. O `zh-HK` do Odysseus não tem par no alvo; nada a fazer.
4. Depois de aplicar, checar contagem de chaves igual em todos os 44 catálogos (`grep -c '^"'`) e placeholder-count igual por chave (o próprio script já filtra isso, mas vale um `grep -o '%@'` de conferência pós-hoc).

### 5.6 Testes que cobrem

Não existe um teste unitário dedicado a "as strings novas existem/traduzidas" no Odysseus — a cobertura de i18n nesse round é indireta:
- `OdysseusTests/PrivacyManifestTests.swift` (criado em `ceeed9a`): carrega o `PrivacyInfo.xcprivacy` real do bundle e verifica que ele não declara *tracking* nem tipos de dado coletados — teste de regressão do bug em que a regex que esvaziava `NSPrivacyCollectedDataTypes` fechava a tag errada (fecha no purpose interno, deixando o manifest malformado). Não testa as `.strings` em si, mas é o teste que teria pegado a consequência de deixar o toggle "morto" declarado no manifest.
- `BugReportTests` (mencionado no commit `ab6a29e`, suíte chegando a 351 testes): 4 testes sobre `BugReport.make`: a descrição viaja e não há `installId`; janela de 1 h com piso `minimumEvents = 50`; id novo por relatório; último encerramento anormal / span aberto no corpo. Não há assert sobre `engineLog`, memória, disco ou versões (esses campos existem em `BugReport.swift:51-59`, sem teste). Indiretamente exercita as chaves de resumo em texto (`Memória disponível: %@ · Física: %@ · Disco livre: %@` etc.) porque o corpo do e-mail é montado a partir dos mesmos números, mas não faz assert sobre o texto localizado literal.
- Nenhum teste no Odysseus faz round-trip pelas 41 traduções (não há verificação automática de que `apply_translations.py` rodou para todos os catálogos ou que a contagem bate) — isso ficou manual/observacional (o commit message é a única prova: "translate the 32... into the other 41 languages"). **Recomendação para o porte**: se for portar essa infra de i18n em lote, vale escrever um teste simples que carregue todos os `.lproj` do alvo e compare o conjunto de chaves contra `en.lproj`, coisa que nem o Odysseus tem hoje.

## 6. Publicação (archive → export → altool → ASC API) e o pipeline de conversão GGML

### (1) O fluxo de publicação passo a passo

Toda a infraestrutura de release da 1.11 mora fora do repo do app, em
`/Users/joaozao/Projetos/_backups/BACKUPS-IOS/odysseus-appstore-deliver/`. Isso é
deliberado: nada aqui é código versionado do Odysseus-iOS, é ferramenta de release que
lê o `.xcodeproj` e escreve na App Store Connect (ASC). O fluxo é dois scripts separados,
nunca um só, para poder rodar checagens entre archive e export:

`release/archive_all.sh` só arquiva, nas duas plataformas, assinatura automática via
chave de API (a etapa de archive é a que faz o Xcode registrar a capability nova no App
ID, mesmo que o perfil de distribuição não seja regenerado):

```sh
cd /Users/joaozao/Projetos/Odysseus-iOS
xcodebuild archive -project Odysseus.xcodeproj -scheme Odysseus -configuration Release \
  -destination 'generic/platform=iOS' -archivePath $R/Odysseus-iOS.xcarchive \
  -derivedDataPath $R/dd -allowProvisioningUpdates \
  -authenticationKeyPath $KEY -authenticationKeyID $KID -authenticationKeyIssuerID $ISS
```
(o mesmo comando roda de novo com `-scheme Odysseus-macOS -destination 'generic/platform=macOS'`
para a build do Mac). `$KEY`/`$KID`/`$ISS` apontam para a chave de API App Manager: o
arquivo `.p8` fica em `~/.appstoreconnect/private_keys/`, o id da chave e o issuer id
ficam hardcoded no topo do script — nenhum dos dois é reproduzido aqui.

`tools/ship.sh ios|mac` faz export → validate → upload, nunca chama submit:

```sh
xcodebuild -exportArchive -archivePath $ARCH -exportOptionsPlist $S/ExportOptions.plist \
  -exportPath $OUT -allowProvisioningUpdates \
  -authenticationKeyPath $KEY -authenticationKeyID $KID -authenticationKeyIssuerID $ISS
xcrun altool --validate-app -f "$F" -t $TYPE --apiKey $KID --apiIssuer $ISS
xcrun altool --upload-app  -f "$F" -t $TYPE --apiKey $KID --apiIssuer $ISS
```
`$TYPE` é `ios`/`macos`, `$F` é o `.ipa`/`.pkg` gerado no export. O script sai cedo e
imprime as primeiras linhas de erro do log se qualquer etapa falhar (`grep -E 'error'`).

Depois do upload, metadado de versão não passa por `altool` — isso é feito por três
scripts finos sobre a API REST, descritos em (3). Na ordem real usada na 1.11:
`create_versions()` cria a versão 1.11 em `IOS` e `MAC_OS` (idempotente); `copy_promo()`
copia o texto promocional da 1.10 porque uma versão criada pela API nasce com
`promotionalText` vazio; `set_whatsnew_per_platform()` escreve "Novidades" por locale a
partir de `whatsnew3/final.json`; `attach(plat, number)` liga o build já `VALID` à versão
via `PATCH .../relationships/build`. Nenhum desses scripts chama o endpoint de submissão —
"Submit for Review" fica sempre para o dono apertar manualmente no ASC.

### (2) As duas lições verificadas

**(a) Entitlement nova invalida o perfil gerido pelo Xcode, e a chave de API não conserta
sozinha.** A 1.11 acrescentou `com.apple.developer.kernel.increased-memory-limit` ao
`Odysseus/Resources/Odysseus.entitlements` (linha 10, por causa do whisper.cpp 1.9.4
carregando f16/q8 grandes em RAM). O archive passou — o Xcode registrou a capability no
App ID durante a assinatura automática do archive. O export falhou com "Cloud signing
permission error": o perfil `Odysseus App Store (auto)` ficou `INVALID` porque uma chave
de API tipo App Manager não tem permissão para regenerar um perfil "managed by Xcode".
Saída, sem o dono:
1. Apagar o perfil `INVALID` pela API/portal.
2. Criar um novo via `POST /v1/profiles` (`profileType: IOS_APP_STORE`), relacionado ao
   App ID já com a capability e ao certificado `DISTRIBUTION` do keychain local (o mesmo
   "Apple Distribution" já usado nas exportações anteriores — achar com
   `security find-identity -v -p codesigning`).
3. Instalar o `.mobileprovision` baixado em **dois** diretórios (Xcode e
   `xcodebuild -exportArchive` procuram em lugares diferentes conforme a versão):
```sh
cp perfil.mobileprovision "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/"
cp perfil.mobileprovision "$HOME/Library/MobileDevice/Provisioning Profiles/"
```
4. Exportar com `signingStyle: manual`, citando o perfil pelo nome exato — é
   `release/ExportOptions-ios.plist`, que diverge de `tools/ExportOptions.plist`
   (`automatic`, que deixou de servir):
```xml
<key>signingStyle</key><string>manual</string>
<key>signingCertificate</key><string>Apple Distribution</string>
<key>provisioningProfiles</key>
<dict><key>com.zao.odysseus</key><string>Odysseus App Store 2026-09 (increased memory)</string></dict>
<key>teamID</key><string>(DEVELOPMENT_TEAM do Local.xcconfig, gitignored)</string>
```
`release/profile-name.txt` guarda só o nome do perfil, texto que precisa bater caractere
por caractere com a chave do plist. Conferir a entitlement antes de exportar/subir:
```sh
codesign -d --entitlements :- "$ARCH/Products/Applications/Odysseus.app"
```
Isso não é um problema de uma vez só: **toda entitlement nova no iOS repete o mesmo
sintoma**, porque o gatilho é "capability nova no App ID + perfil managed", não algo
específico do `increased-memory-limit`.

**(b) `plutil -lint` no manifesto de privacidade dentro do `.xcarchive`, antes do
upload.** O patch que zerou `NSPrivacyCollectedDataTypes` (decisão de não ter telemetria
de servidor) fechou um `<array>` interno no lugar errado. O `.xcarchive` "arquivou" com
sucesso mesmo assim — um plist malformado não quebra o archive, só o processamento de
Privacy Manifest da Apple depois do upload (ou pior, seria aceito silenciosamente com a
ficha errada). A checagem que fecha esse buraco roda sobre o artefato exportado, não
sobre a fonte do repo:
```sh
plutil -lint "$ARCH/Products/Applications/Odysseus.app/PrivacyInfo.xcprivacy"
```
`PrivacyManifestTests` no repo carrega o `PrivacyInfo.xcprivacy`-fonte e garante sem
rastreio, sem tipos coletados, só as duas Required Reason APIs declaradas — mas roda
sobre o arquivo do repo, não sobre a cópia dentro do `.xcarchive`, então não substitui o
`plutil -lint` manual pós-archive.

**(c) Disco: archive universal + DerivedData de teste levaram o Mac a 165 MB livres** no
meio do processo (Mac + iOS no mesmo `-derivedDataPath $R/dd`). Rotina, não exceção:
apagar `release/dd` e simuladores antigos (o handoff cita especificamente o simulador
iOS 17) antes de exportar.

### (3) Pipeline GGML (`stt-ggml/`)

Não é código do app — é a fábrica externa que produz os `.bin` que
`Odysseus/Features/Voice/VoiceModels.swift` referencia por URL, porque o catálogo passou
a apontar para espelhos próprios (`huggingface.co/JoaoZaokk/*`) em vez de repositórios de
terceiros. A versão corrente vive em
`odysseus-appstore-deliver/stt-ggml/pipeline/` (datada 13/09 19:17, com `dlwatch` e
`withtimeout` já cabeados). **Achado ao comparar os dois diretórios**: existe uma cópia
mais antiga em `stt-ggml/run_whisper.sh` e `stt-ggml/run_all.sh` (datada 12/09 21:48, sem
`dlwatch`/`withtimeout` nenhum) que ficou para trás quando o trabalho foi movido para
`pipeline/`; essa cópia de raiz também não teria como achar `env.sh` (`dirname "$0"` dela
aponta pra `stt-ggml/`, onde não existe `env.sh` — só existe dentro de `pipeline/`). Para
o porte, a referência é sempre `pipeline/`, nunca a raiz de `stt-ggml/`.

`pipeline/env.sh` centraliza paths (`WCPP`, `BIN`, `PCPP`, `PY`, `WORK`, `SAMPLES`,
`HF_USER=JoaoZaokk`) e duas funções de robustez de rede aprendidas na marra:
- `withtimeout() { perl -e 'alarm shift @ARGV; exec @ARGV' "$@"; }` — o macOS não tem
  `timeout(1)`; criada depois que um `hf upload` ficou 19 h pendurado sem erro.
- `dlwatch <stall_secs> <tries> <watch_dir> <hf download args...>` — roda `hf download`
  em background, mede `du -sk` do diretório a cada 30 s, mata o processo se não crescer
  por `stall_secs` (ou passar de 2 h numa tentativa) e tenta de novo até `<tries>` vezes
  (`hf download` retoma `.incomplete` sozinho); criada depois de duas quedas de DNS terem
  derrubado 7 downloads numa noite.

`pipeline/run_whisper.sh <slug>` é o caminho de pouco disco, usado para `kind: whisper` e
`kind: ggml-mirror` de `models.json`. Antes de baixar qualquer coisa, calcula
`need = max(source, f16 × 1,55) + 600 MB` e compara com `df -k /`; se não couber, sai com
código 5 (`SKIP-DISK`) sem tocar em nada. A conversão roda com
`GGML_DELETE_SOURCE_WEIGHTS=1`, que faz `convert-h5-to-ggml.py` apagar os safetensors da
fonte assim que os tensores estão materializados em RAM — o pico de disco fica em
`max(fonte, f16 + uma quantização)`. Cada quantização (`q8_0`, `q5_0`, `q4_0`) segue o
ciclo quantiza → verifica (`whisper-cli` transcreve `pt.wav`/`en.wav`, grava em
`VERIFY.txt`) → sobe (`hf upload`, sob `withtimeout 1800`) → apaga o `.bin` local antes
da próxima; o f16 intermediário é apagado no final. Resolve tokenizer faltante caindo
para o vocabulário de `openai/whisper-large-v3(-turbo)` e faz cast de `bf16` para `f32`
antes de converter (o conversor não aceita `BFloat16`).

`pipeline/run_one.sh <slug>` é o pipeline "peso cheio", chamado pelo `run_all.sh` para
`kind: parakeet` (e historicamente para os outros antes de `run_whisper.sh` existir):
despacha para `convert_whisper.sh`/`mirror_ggml.sh`/`convert_parakeet.sh` conforme o
`kind`, roda `verify_whisper.sh`/`verify_parakeet.sh`, monta o card com `make_card.py` e
só sobe com `upload.sh` se `hf auth whoami` responder — senão deixa a saída em
`$WORK/out-$SLUG` para upload manual. Seu guard de disco é mais grosseiro: estima
`need = fonte × 2 + 600 MB`, sem o refinamento de `f16 × 1,55` do `run_whisper.sh`.
`kind: parakeet.cpp` fica de fora do laço automático (`run_all.sh` filtra
`kind!='parakeet.cpp'`; dentro de `run_one.sh` esse `kind` cai no `*) … exit 4` de "tratar
manualmente").

`models.json` (271 linhas, mesmo conteúdo em `stt-ggml/models.json` e no scratchpad da
sessão) é o catálogo declarativo: `slug`, `kind`, `repo` de origem, `lang`, `license`,
`author`, `hf` (nome do repo de destino em `JoaoZaokk/*`), `verified`/`done` como flags de
progresso. `run_all.sh` itera nele pulando slugs cujo repo HF já tem `q5_0`.

`pipeline/patch_catalog_sizes.py` roda depois que os 24 repositórios sobem: varre
`VoiceModels.swift` procurando `bytes: <n>, url: mine("<repo>", "<file>")`, pergunta ao
Hugging Face (`HfApi().model_info(..., files_metadata=True)`) o tamanho LFS real de cada
arquivo e reescreve `bytes:` quando diverge, listando os que dão 404. É a única peça deste
pipeline que escreve em código do app — e mesmo assim só um literal numérico.

O toolchain que os scripts esperam (`wcpp-build` com `whisper-quantize`/
`parakeet-quantize`, `pcpp`, um `venv` Python com `huggingface_hub`+`transformers`) **foi
apagado do scratchpad em 13/09** — conferido agora: `wcpp-build`, `pcpp` e `venv` não
existem mais ali. Isso é esperado: o toolchain é volumoso e se recria sob demanda a partir
dos passos descritos em `env.sh` e nos scripts de conversão, não fica persistido entre
sessões.

### (4) Como portar para o OpenWebUI-iOS

O bundle de produção é `com.zao.openwebui`; o `project.yml` do OpenWebUI-iOS usa
`com.example.openwebui` como id de dev/simulador nas duas configurações (linhas 55 e 184)
e tem um comentário próprio avisando: "pass `PRODUCT_BUNDLE_IDENTIFIER=com.zao.openwebui`
on the archive command, or the export fails with 'No profiles for
com.example.openwebui'". Isso confirma a nota da memória do time — nada novo a decidir
aqui, só repetir a rotina no runbook de release. Como o app é iPhone-only nesta rodada de
porte, `archive_all.sh` perde a metade `-destination 'generic/platform=macOS'` (o
`project.yml` ainda define um target `OpenWebUI-macOS`, herdado do scaffold, mas ele fica
fora do fluxo de publicação tratado aqui).

**Reaproveitável quase tal qual:**
- `tools/ship.sh` — troca só `$S` (pasta de release própria), o `-project`/`-scheme` do
  `xcodebuild archive` (conferir o nome exato do `.xcodeproj`/scheme gerado pelo
  XcodeGen do OpenWebUI-iOS) e mantém `EXT=ipa` (não há alvo `.pkg` sem macOS).
- O padrão de dois scripts (`archive_all.sh` nunca exporta/sobe; `ship.sh` nunca arquiva)
  vale igual — é o que permite encaixar `plutil -lint` no meio.
- `tools/ExportOptions.plist` com `signingStyle: automatic` deve continuar funcionando
  **enquanto nenhuma entitlement nova entrar** — não copiar o modo manual
  preventivamente, só ter o runbook de (2)(a) pronto para quando acontecer (mesmo
  sintoma: "Cloud signing permission error" no export).
- `asc.py` (o par `get()`/`send()` sobre JWT ES256) serve para qualquer app da mesma
  conta ASC quase sem mudança; só troca o `APP` (o Odysseus usa `6783977350`, o
  OpenWebUI-iOS tem outro id numérico) e o path do `key.json`.
- **Achado relevante**: a conta já tem uma pasta de entrega própria para este app,
  `_backups/BACKUPS-IOS/openwebui-appstore-deliver/`, e o `key.json` de lá carrega o
  **mesmo** id de chave e o **mesmo** issuer id que o `key.json` do Odysseus — é a mesma
  chave de API App Manager, de conta, reaproveitada entre apps, não uma chave por app.
  Na prática isso simplifica o porte de `asc.py`/`ship.sh`: só o `APP` (app id na ASC)
  muda, a chave e o `$KID`/`$ISS` podem ser copiados como estão.
- `compose_111.py` como *padrão* de composição de "Novidades" (fonte pt-BR/en-US +
  traduções por sub-agentes + validação de forma) — as regras de validação são
  específicas da 1.11 (o caso "1/100", 8+1 itens) e precisam ser reescritas para o
  changelog real do OpenWebUI-iOS.

**O que muda ou não se aplica ainda:**
- A entrega do OpenWebUI-iOS hoje passa por **fastlane `deliver`**
  (`openwebui-appstore-deliver/Deliverfile`, com `app_identifier("com.zao.openwebui")`,
  `submit_for_review(false)`, `force(true)`), não pelo par `xcodebuild`+`altool` que o
  Odysseus usa. Portar `ship.sh`/`archive_all.sh` para lá é introduzir um segundo caminho
  de publicação, não substituir um já idêntico — vale decidir se o `deliver` fica só para
  metadado/screenshots e o `ship.sh` assume archive+upload de binário, espelhando o que o
  Odysseus já faz.
- Se e quando o OpenWebUI-iOS ganhar uma entitlement nova que o perfil gerido não cubra
  (ex.: também precisar de `increased-memory-limit` ao trocar o motor de voz), **o perfil
  vai invalidar do mesmo jeito** — mesmo sintoma, mesmo runbook de (2)(a): apagar,
  recriar via `POST /v1/profiles` com o certificado de distribuição da conta, instalar o
  `.mobileprovision` nos dois diretórios, exportar com `signingStyle: manual`.
- O pipeline GGML inteiro (`stt-ggml/`) não se aplica ainda: `patch_catalog_sizes.py`
  aponta hardcoded para `Odysseus/Features/Voice/VoiceModels.swift`, e o motor de voz do
  Odysseus (whisper.cpp 1.9.4 + Parakeet) é o que consome esse catálogo — o OpenWebUI-iOS
  precisaria primeiro trocar de motor de STT (assunto de outra seção deste documento) para
  este pipeline fazer sentido; só depois caberia adaptar `models.json`/`run_whisper.sh`/
  `patch_catalog_sizes.py` para o arquivo de catálogo equivalente do OpenWebUI-iOS.
- `AuthKey_*.p8`, `key.json` e o app id numérico na ASC continuam por-arquivo/por-app:
  só o *formato* dos scripts que os usam é copiável, não os arquivos em si.

## 7. Ordem sugerida do porte (menor primeiro, cada fatia fecha sozinha)

Regra da casa: "todos" é a sequência inteira, não a maior fatia de uma vez. Entregue e
feche a menor antes de abrir a próxima. Cada fatia abaixo compila, testa e commita sozinha.

1. **Pasta do encoder Core ML.** Bug existe verbatim no `ModelDownloadManager` do
   OpenWebUI-iOS (seção 2.4). Troca de uma função + `refresh()` renomeando pastas legadas +
   um teste de nome. Ganho imediato: o turbo quantizado passa a usar o Neural Engine.
2. **Um dono do motor.** `STTRunner` (fila serial fora do MainActor, contexto em cache,
   solta em memory warning/background) e o gate de memória com `MemoryBudget`. Dá para
   fazer ainda em cima do SwiftWhisper se a troca do motor for adiada; o jetsam vem de
   contextos duplicados e de load sem checar memória, não do wrapper.
3. **Áudio salvo antes de transcrever.** `PendingAudioStore` + alerta no launch +
   `attempts` antes do load. Independente do motor.
4. **Motor whisper.cpp 1.9.4 + Parakeet.** `Vendor/WhisperCPP` (pacote local com
   binaryTarget), `OnDeviceSTT.swift`, saída do SwiftWhisper de todos os arquivos que o
   importam (`VoiceInputManager`, `BargeInMonitor`, `NeuralVoiceStore`, `SpeechManager`).
   Decidir antes o que fica do FluidAudio (o OpenWebUI-iOS usa para quê? conferir no código).
5. **Catálogo por idioma.** `VoiceLang` com 21 casos (15 novos), prefixo `p-`, os 23 espelhos,
   `bytes` reais. Ids antigos não mudam; quem tinha os 4 modelos de terceiros baixa de novo.
6. **Diagnóstico local + Reportar bug.** `DiagnosticsStore`, `MetricKitCollector`,
   `BugReport` + `BugReportSheet` (só a parte iOS), `PrivacyInfo.xcprivacy` novo com tipos
   coletados vazio, botão em Ajustes. Sem uploader, sem toggle, sem installId.
7. **Strings.** As 42 chaves (seção 5) em pt-BR/en à mão, as outras 42 línguas por
   workflow sonnet, um agente por locale, saída por schema, gravadas por script.
8. **Publicação.** Se a entitlement `increased-memory-limit` entrar, o perfil App Store
   gerido pelo Xcode invalida: recriar pela API antes de exportar (seção 6). `plutil -lint`
   no manifesto dentro do `.xcarchive` antes de subir.

## 8. O que depende do dono e o que a sessão do porte levanta sozinha

### Decisões do dono (perguntar antes de codar)

- E-mail que recebe os bug reports do OpenWebUI-iOS: o mesmo `joaozao@macrozao.online`
  do Odysseus ou outro. O assunto já separa os apps ("Bug report <App> <versão> (<build>)").
- Escopo desta rodada no OpenWebUI-iOS: só o motor + memória (fatias 1 a 4) ou também o
  catálogo por idioma e o diagnóstico (5 a 7).
- FluidAudio: fica (para o que quer que faça hoje) ou sai junto com o SwiftWhisper.
- Entitlement `increased-memory-limit` no OpenWebUI-iOS: entra (e o perfil de
  distribuição precisa ser recriado) ou fica de fora até um relato de jetsam.

### Fatos que a sessão do porte confere no código, sem perguntar

- Quantos `VoiceInputManager` coexistem no OpenWebUI-iOS (`grep -rn "VoiceInputManager(" App/`).
  Cada instância com contexto próprio é um motor a mais na memória.
- Se existe chave `app.language` em UserDefaults (o rótulo de `VoiceLang` lê essa chave).
- Se existe `L(_:)` igual ao do Odysseus (é a função que passa pelo swizzle;
  `String(localized:)` fura).
- Quais required-reason APIs o app usa (`UserDefaults`, `DiskSpace`, `FileTimestamp`,
  `SystemBootTime`) antes de copiar o `PrivacyInfo.xcprivacy`.
- Onde o target iOS assina hoje (`CODE_SIGN_ENTITLEMENTS` no `project.yml`) antes de
  criar o primeiro `.entitlements` do projeto.
