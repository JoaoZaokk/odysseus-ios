# CLAUDE.md — Odysseus iOS/macOS

Native SwiftUI client (shared `Odysseus/` source) for the self-hosted **Odysseus** AI chat
server (`odysseus.macrozao.online`). Two targets: **Odysseus** (iOS 17+) and **Odysseus-macOS**
(macOS 14+). Built with **XcodeGen** — `Odysseus.xcodeproj` is generated (gitignored); run
`xcodegen generate` after adding/removing files.

## Build
```bash
xcodegen generate
# macOS
xcodebuild -project Odysseus.xcodeproj -scheme Odysseus-macOS -configuration Debug -destination 'platform=macOS' build
# iOS
xcodebuild -project Odysseus.xcodeproj -scheme Odysseus     -configuration Debug -destination 'generic/platform=iOS' build
```
Run the built macOS app:
`open ~/Library/Developer/Xcode/DerivedData/Odysseus-*/Build/Products/Debug/Odysseus.app`

## Architecture
- `App/` — entry point, `AppState` (holds `APIClient`, session), root view.
- `Config/` — `ServerConfig` (URL normalization, default `odysseus.macrozao.online`), themes,
  `Backgrounds` (animated stars/aurora), `ScreenChrome` (macOS custom headers, not `.toolbar`).
- `Networking/` — `APIClient` (cookie-session auth via `HTTPCookieStorage`, SSE via
  `session.bytes(for:)`, FastAPI 422-array error surfacing).
- `Features/` — 17 modules: Auth, Brain, Calendar, Chat, Compare, Cookbook, Email, Gallery,
  Library, Navigation, Notes, Research (Deep Research graph + native report), Sessions,
  Settings (+ admin sections), Shared, Tasks, Voice (TTS/STT).
- `Models/`, `Resources/` (assets, Info.plist, entitlements).

## Conventions
- macOS: global `.buttonStyle(.plain)`; full-row hit areas via
  `.frame(maxWidth:.infinity).contentShape(Rectangle())`; themed cards with labels-above-fields
  (macOS `Form` overflows left-labels). `\.theme` env, `Color(hex:)`.
- Font helper `.ody(...)`: **the `size:` variant needs `weight:` BEFORE `design:`**
  (`.ody(size:12, weight:.medium, design:.monospaced)`) — common compile gotcha.
- Backend is FastAPI: 422 `detail` is an **array** of `{loc,msg}`; `POST /api/model-endpoints`
  is **form-urlencoded**, not JSON; most settings live under `/api/auth/settings`.

## Key API contracts (reverse-engineered, all verified live)
See `ENDPOINTS.md`. Highlights: `GET/POST /api/auth/settings`, `/api/tools` (GET list +
`POST {disabled:[…]}`), `/api/diagnostics/logs?limit=N`, `/api/auth/integrations`
(CalDAV/CardDAV use `base_url`), `/api/mcp/servers`, Deep Research start/stream/library/report.

## Operating constraints (DO NOT VIOLATE)
- The macOS target is **sandboxed** (`app-sandbox=true`). In-app `NSLog`/`os_log`/`/tmp` shape
  dumps do NOT surface — render to a temp on-screen `Text` + screenshot, or fetch `/openapi.json`.
- **No push without sanitization**: `origin` is a public mirror. `project.yml` carries the real
  `DEVELOPMENT_TEAM`. See `SECURITY_REVIEW.md`.
- Never auto-trigger heavy/destructive real-infra actions: Cookbook model *serve/launch*,
  Danger-Zone wipes, ComfyUI `POST /prompt`. Read-only probing is fine.
- Do not enter passwords or run `sudo` (the user does that).
- The separate **MacrozaoHQ (QG)** app is out of scope — do not touch.

## V1 finalization (this effort)
Branch `v1-macos-finalization`, anchored at tag `pre-v1-finalization-snapshot`. See
`ROLLBACK.md`, `TODO.md`, `MB_START.md`, `MB_DONE.md`, `MB_ERRORS_SOLUTIONS.md`, `FINAL_HANDOFF.md`.
