# SECURITY_REVIEW.md — Odysseus iOS/macOS

Scope: source-level + supply-chain + platform review for V1. Updated as the Red Team pass runs.
Severity: 🔴 high · 🟠 medium · 🟡 low · 🟢 ok.

## Static scan (2026-06-24, initial)

| # | Severity | Finding | Location | Status / recommendation |
|---|----------|---------|----------|--------------------------|
| S1 | 🟠 | Real Apple `DEVELOPMENT_TEAM` (`FZ5A72S5DT`) committed in a tracked file. `origin` is a **public** GitHub mirror → leaks on push. | `project.yml:26` | NOT changed yet (needed for local signing). Recommend: move to a local-only `Local.xcconfig` (gitignored) or `$(DEVELOPMENT_TEAM)` env; keep an empty placeholder in `project.yml`. Tracked in TODO. |
| S2 | 🟡 | Hardcoded default server host `odysseus.macrozao.online` reveals user infra in a public repo. | `ServerConfig.swift:9`, `SettingsSections.swift:15` | Intentional default (the app's home server). For a public/App-Store build, recommend defaulting to empty + onboarding to enter the server. Tracked in TODO. |
| S3 | 🟡 | Example LAN IP `192.168.3.47:7000` appears as a placeholder. | `ServerConfig.swift:22` (comment), `SettingsView.swift:231` (placeholder) | Cosmetic; genericize placeholder to `https://your-server:port`. Not a secret (RFC1918 example). |
| S4 | 🟢 | No hardcoded passwords / API keys / bearer tokens / cookies in source. The `password` matches are SwiftUI `@State` input fields (correct). | — | OK. Secrets live in `HTTPCookieStorage` (session) and Keychain. |
| S5 | 🟢 | Auth is cookie-session over the user's HTTPS server; `api_key` for model endpoints is write-only server-side (stored as fingerprint). | `APIClient`, `SettingsAPI` | OK. |
| S6 | 🟠 | `NSAllowsArbitraryLoads: true` (blanket ATS exception) in **both** Info.plists. Justifiable (generic client for user self-hosted HTTP servers), but Apple review scrutinizes it. | `Info.plist:29`, `Info-macOS.plist:31` | For App Store: prefer `NSAllowsLocalNetworking` + per-domain exceptions, or provide a clear review-notes justification. Keep for private builds. Tracked in TODO. |
| S7 | 🟡 | Local docs (`*.md`) contain the user's LAN IP `192.168.3.133:8190`. The shipped Swift uses a **generic placeholder** (good), but the docs would leak the IP on a public push. | `ENDPOINTS.md`, `DIFFUSION_COMFYUI_PLAN.md` | Gitignore or scrub the LAN IP from docs before any public push. |

## Platform / sandbox
- macOS entitlements (`Odysseus-macOS.entitlements`): `app-sandbox`, `network.client`,
  `device.audio-input` (STT mic), `files.user-selected.read-write` (backup export panel). 🟢
  Minimal and appropriate — no broad filesystem, no JIT, no disabled library validation.
- No `NSAllowsArbitraryLoads` blanket ATS exception expected for the HTTPS default; **local
  HTTP servers** (LM Studio, ComfyUI on `http://192.168.x`) require an ATS exception or the
  user using `https`. → verify in Info.plist during Red Team (item RT-ATS).

## To verify during Red Team (see TEAM_REVIEW.md)
- [x] **RESOLVED** — ATS/local-HTTP: plain-HTTP LAN works (`NSAllowsLocalNetworking`+`NSAllowsArbitraryLoads`). BUT macOS **Local Network privacy** returns `-1009` on the *first* LAN connection while the OS evaluates permission → app showed a spurious "offline". **Blue Team fix applied** (retry once on `.notConnectedToInternet`/`.networkConnectionLost`). Verified live: retry → "online".
- [ ] Timeout / offline-server handling on every network call (no infinite spinners).
- [ ] Malformed / oversized API responses don't crash the decoders (tolerant `init(from:)` already used widely — confirm coverage).
- [ ] No sensitive data written to logs (`print`/`NSLog`) in release builds.
- [ ] Deep-link / URL handling (if any) rejects untrusted hosts.
- [ ] ComfyUI/diffusion endpoints: user-supplied URLs are validated; no SSRF-style blind follow.

## Decisions
- S1/S2 are **release-gating for a public App Store build** but **not** blocking for a private
  signed build for the user's own devices. Documented as TODO, not auto-changed (would break the
  local signed build). CEO/CTO sign-off required before any public push.
