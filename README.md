# Odysseus iOS

Cliente **nativo** (SwiftUI) para o seu servidor Odysseus — *Self-hosted AI chat
with memory, documents, and tools*. Não é um WebView embrulhado: fala direto com
a API REST/SSE do Odysseus e renderiza tudo nativo (markdown, code blocks,
streaming token a token, blocos de raciocínio, modo agente, busca na web).

O endereço do servidor é configurável em **Ajustes › Servidor** (e na tela de
login) — aponte para o seu servidor local (`http://meu-servidor:porta`) ou, quando
expuser o Odysseus na web, para `https://seu-dominio`.

---

## Como rodar

Pré-requisitos: Xcode 26+, `xcodegen` (`brew install xcodegen`).

```bash
cd Odysseus-iOS
xcodegen generate          # gera Odysseus.xcodeproj a partir de project.yml
open Odysseus.xcodeproj     # ou use a linha de comando abaixo
```

Build + simulador via CLI:

```bash
xcodebuild -project Odysseus.xcodeproj -scheme Odysseus \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -derivedDataPath build build

xcrun simctl install "iPhone 16 Pro" \
  build/Build/Products/Debug-iphonesimulator/Odysseus.app
xcrun simctl launch "iPhone 16 Pro" com.zao.odysseus
```

> O projeto (`Odysseus.xcodeproj`) é gerado — não fica no git. Edite
> `project.yml` e rode `xcodegen generate` ao adicionar arquivos/dependências.

---

## Arquitetura

```
Odysseus/
  App/            OdysseusApp (entry), AppState (auth + config + roteamento)
  Config/         ServerConfig (URL persistida), Theme (paleta Odysseus)
  Networking/     APIClient (sessão por cookie), ChatStreamClient (SSE),
                  StreamEvent, Keychain, MultipartForm
  Models/         Codable tolerante: AuthStatus, ChatSession, Message,
                  ChatModel, DefaultChat, Features...
  Features/
    Auth/         LoginView (usuário/senha/2FA, troca de servidor)
    Sessions/     MainView (NavigationSplitView), SessionListView, SessionStore
    Chat/         ChatScreen, ChatViewModel, MessageBubble (markdown + thinking)
    Settings/     SettingsView, ServerSheet
```

### Mapa da API do Odysseus usado pelo app

| O quê | Endpoint | Detalhe |
|---|---|---|
| Status de sessão | `GET /api/auth/status` | `{configured, authenticated, username, is_admin}` |
| Login | `POST /api/auth/login` | JSON `{username, password, remember, totp_code?}` → cookie de sessão |
| Recursos | `GET /api/auth/features` | flags: web_search, rag, memory, gallery... |
| Modelo padrão | `GET /api/default-chat` | `{endpoint_url, model, endpoint_id}` |
| Listar conversas | `GET /api/sessions` | título no campo `name` |
| Histórico | `GET /api/history/{id}` | `{history:[...], model}` |
| Criar conversa | `POST /api/session` | FormData `name, endpoint_url, model, skip_validation, endpoint_id?` |
| Renomear | `PATCH /api/session/{id}` | FormData `name` |
| Apagar | `DELETE /api/session/{id}` | |
| **Chat (stream)** | `POST /api/chat_stream` | FormData `message, session, mode` (+ flags) → **SSE** |
| Parar geração | `POST /api/chat/stop/{id}` | |

**Protocolo de streaming:** SSE, linhas `data: {json}` terminadas por
`data: [DONE]`. Frames principais: `{"delta": "..."}` (token de texto),
`{"delta":"...","thinking":true}` (raciocínio), e eventos estruturados por
`type` (`tool_start`, `model_info`, etc.). Auth é por **cookie de sessão**,
persistido pelo `URLSession`/`HTTPCookieStorage` entre execuções.

---

## Status

**Núcleo**
- [x] Login (usuário/senha + 2FA opcional), troca de servidor, sessão persistida
- [x] **Hub de navegação** — landing na sidebar com todos os espaços + conversas
- [x] Lista de conversas (buscar, renomear, apagar, fixadas no topo)
- [x] Chat com streaming nativo, markdown, blocos de raciocínio colapsáveis
- [x] Toggles de **Web**, **Deep** (pesquisa profunda) e **Agente**

**Espaços** (10 seções do Odysseus)
- [x] **Brain** — memórias: listar/buscar/categorias/adicionar/fixar/apagar + tidy (IA)
- [x] **Notes** — notas: grid, criar/editar, arquivar, apagar
- [x] **Deep Search** — flag `use_research` no chat + eventos `research_*`
- [x] **Calendar** — agenda por dia, criar (form + quick-parse NL), apagar, horários TZ-corretos
- [x] **Gallery** — grid de imagens (AsyncImage com cookie), favoritos, detalhe
- [x] **Email** — inbox, ler, arquivar, apagar; detecta "não configurado" (sem IMAP)
- [x] **Contas de email** — listar/adicionar (IMAP+SMTP)/apagar/definir padrão (`/api/email/accounts`)
- [x] **Tasks** — agentes agendados: status, schedule/cron/evento, rodar/pausar/retomar
- [x] **Library** — documentos pessoais (RAG): listar, enviar (file picker), apagar
- [x] **Compare** — 2 modelos lado a lado, mesma pergunta, streaming simultâneo
- [x] **Cookbook** — catálogo de pacotes/engines por categoria, status de instalação

**Extras**
- [x] **Anexos/visão** — PhotosPicker no chat, upload (`/api/upload`), thumbnail,
  envio com `attachments`, render de imagem nos balões
- [x] **TTS on-device** — botão 🔊 nos balões da IA, `AVSpeechSynthesizer`
  (nativo, offline, voz pt-BR premium quando instalada)
- [x] **Voz e modelos (Ajustes)** — seletor de engine STT (nativo / modelo
  on-device) e TTS (nativo / Kokoro); **gerenciador de modelos**: catálogo
  Whisper + Kokoro agrupado por tamanho (≤500MB/1GB/2GB/3GB), filtro de idioma
  (PT/EN/bilíngue), **download direto no celular** com progresso, instalar,
  excluir, escolher ativo. (Download verificado: ggml-tiny 74MB no device.)
- [x] **STT on-device (Whisper)** — `SwiftWhisper`/whisper.cpp integrado;
  `VoiceInputManager` grava o mic (AVAudioEngine → 16kHz mono) e transcreve com
  o modelo GGUF ativo, OU usa o `SFSpeechRecognizer` nativo. **Botão de microfone
  no chat.** Compila e roda; gravação de mic **só no iPhone físico** (o simulador
  não tem áudio HAL — tratado com mensagem, sem crash). Transcrição real você
  valida no device.
- [ ] **TTS Kokoro (neural)** — o pedaço mais difícil: precisa de ONNX runtime +
  **fonemização** (text→fonemas, hoje sem solução Swift madura — espeak-ng).
  Esforço dedicado, só testável no device. Pendente.

**Pendente:** Kokoro TTS, ajuste fino de temas, push notifications.

> **Todas as 10 seções + anexos + TTS implementados e verificados ao vivo.**

> Todas as formas de JSON acima foram **verificadas contra o servidor ao vivo**
> (login, sessions, history, models, default-chat, memory, notes, calendar,
> gallery, email).

### Notas de implementação importantes
- **URLs com query string** usam resolução relativa (`URL(string:relativeTo:)`),
  não `appendingPathComponent` — senão o `?` é escapado e vira 404.
- **Datas do calendário** são *naive locais* ("2026-06-20T09:30:00", sem TZ) —
  parseadas como hora local, não UTC.
- Loads cancelados por transição de tela (`.task` teardown) são ignorados, não
  viram erro na UI.

---

## Expor na web com segurança (futuro)

Quando for tirar da LAN:

1. **HTTPS na frente** — Caddy/Traefik/nginx com TLS (Let's Encrypt). O Odysseus
   roda como `uvicorn`; deixe o proxy reverso terminar o TLS.
2. **Trocar a URL no app** para `https://...` (Ajustes › Servidor). Aí dá para
   apertar o ATS no `project.yml` (remover `NSAllowsArbitraryLoads`, manter só a
   exceção do seu domínio — ou nenhuma, já que HTTPS válido dispensa exceção).
3. **Cookie seguro** — garanta `Secure` + `HttpOnly` + `SameSite` no cookie de
   sessão do servidor.
4. **Não exponha sem auth forte** — 2FA já é suportado pelo app; considere
   também rate-limiting no proxy e, idealmente, um túnel (Tailscale/WireGuard)
   ou Cloudflare Tunnel em vez de abrir a porta direto.

---

## Licença

**[PolyForm Noncommercial License 1.0.0](LICENSE)** — uso livre para fins **não
comerciais** (pessoal, pesquisa, educação). Para uso comercial, veja
[`COMMERCIAL-LICENSE.md`](COMMERCIAL-LICENSE.md).

Privacidade: o app não coleta nada — todos os dados ficam entre o seu dispositivo
e o seu servidor. Detalhes em [`PRIVACY.md`](PRIVACY.md).

© 2026 JoaoZaokk
