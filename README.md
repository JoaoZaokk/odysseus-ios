# Odysseus iOS

<p align="center">
  <a href="https://apps.apple.com/us/app/odysseus-mobile/id6783977350"><img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="Download on the App Store" height="48"></a>
</p>

<p align="center">
  <a href="https://apps.apple.com/us/app/odysseus-mobile/id6783977350"><img alt="App Store" src="https://img.shields.io/itunes/v/6783977350?label=App%20Store&logo=apple&color=0D96F6"></a>
  <img alt="Platforms" src="https://img.shields.io/badge/platform-iOS%2017%2B%20%C2%B7%20iPadOS%20%C2%B7%20macOS%2014%2B-lightgrey?logo=apple">
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/license-PolyForm%20Noncommercial-blue"></a>
</p>

> **Available on the App Store:** [Odysseus - Mobile](https://apps.apple.com/us/app/odysseus-mobile/id6783977350)
> — free, non-commercial. You still need your own Odysseus server (see below).

A **native** (SwiftUI) client for your self-hosted **Odysseus** AI server — *self-hosted
AI chat with memory, documents, and tools*. Not a wrapped WebView: it talks straight to
the Odysseus REST/SSE API and renders everything natively — markdown, syntax-highlighted
code, token-by-token streaming, reasoning blocks, agent mode, and web search.

> **Requires your own Odysseus server.** This app is only the client. Set the server
> address on first launch, or later in **Settings › Server** — point it at your local
> server (`http://my-server:port`) or, once exposed on the web, at `https://your-domain`.

Universal: **iPhone, iPad, and Mac** from one native codebase (iOS 17+ / macOS 14+).

---

## Features

**Chat**
- Native token-by-token streaming, Markdown + syntax-highlighted code, collapsible
  reasoning blocks.
- Web, Deep, and Agent toggles.
- Attachments & vision (send photos straight from the app).
- On-device voice: live dictation (native STT + Whisper with Neural Engine acceleration)
  and read-aloud (native TTS + neural PocketTTS) — audio never leaves the device.

**Spaces**
- **Brain** — assistant memories (search, categories, add, pin, organize with AI).
- **Notes** — notes & reminders.
- **Calendar** — events, created in natural language.
- **Gallery** — generated and uploaded images.
- **Email** — IMAP/SMTP inbox with multiple accounts.
- **Tasks** — scheduled agents (cron/event): run, pause, resume.
- **Library** — personal documents (RAG).
- **Compare** — the same question to two models side by side, streaming at once.
- **Cookbook** — browse and install packages and engines.
- **Deep Search** — deep research with a live step graph, search modes, a visual report,
  and history (save & resume).

**Settings (native admin panel)**
- AI defaults (chat/utility models, fallbacks, vision, research), Search, Integrations,
  Email, Reminders, Image generation, 17 themes + fonts + animated backgrounds +
  transparency, **Language**, Account (2FA, change password, tokens), Server, and admin
  tools (Agent Tools, Users, System/logs/backup).
- **Add and manage models right from the phone.**

**Languages**
- **34 languages** — including right-to-left (Arabic, Persian, Urdu, Pashto) — with
  **automatic device-language detection** (Settings › Language).

---

## Running it

Requirements: Xcode 26+, `xcodegen` (`brew install xcodegen`).

```bash
cd Odysseus-iOS
xcodegen generate          # generates Odysseus.xcodeproj from project.yml
open Odysseus.xcodeproj
```

> The `.xcodeproj` is generated and is not committed. Edit `project.yml` and run
> `xcodegen generate` when adding files or dependencies — do not hand-edit build settings
> in Xcode (they are overwritten on the next generation).

The real signing Team ID lives in `Local.xcconfig` (gitignored). Copy
`Local.xcconfig.example` → `Local.xcconfig` and fill in your own, or let Xcode use
automatic / personal-team signing.

---

## Architecture

```
Odysseus/
  App/            entry point, AppState (auth + config + routing)
  Config/         ServerConfig, themes, animated backgrounds, screen chrome
  Networking/     APIClient (cookie session), ChatStreamClient (SSE), Keychain
  Models/         tolerant Codable models
  Features/       Auth, Brain, Calendar, Chat, Compare, Cookbook, Diffusion, Email,
                  Gallery, Library, Localization, Navigation, Notes, Research
                  (Deep Research), Sessions, Settings, Shared, Tasks, Voice
  Resources/      assets, Info.plist, .lproj localizations
```

Auth is a **session cookie** (stored via `HTTPCookieStorage.shared` and persisted across
launches); chat streams over **SSE** (`data: {delta|thinking|type…}` … `[DONE]`).

---

## Privacy

Your data stays between your device and your server. The app has no servers of its own,
no analytics, no tracking, and no ads. Voice transcription happens locally, on the
device. See [`PRIVACY.md`](PRIVACY.md).

---

## License

**[PolyForm Noncommercial License 1.0.0](LICENSE)** — free for non-commercial use
(personal, research, education). For commercial use, app-store redistribution,
white-labeling, or any use outside the non-commercial license, see
[`COMMERCIAL-LICENSE.md`](COMMERCIAL-LICENSE.md).

© 2026 JoaoZaokk
