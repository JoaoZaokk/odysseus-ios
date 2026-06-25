# SECURITY_REVIEW.md — Odysseus iOS/macOS

Scope: source-level + supply-chain + platform review for V1. Updated as the Red Team pass runs.
Severity: 🔴 high · 🟠 medium · 🟡 low · 🟢 ok.

## Static scan (2026-06-24, initial)

| # | Severity | Finding | Location | Status / recommendation |
|---|----------|---------|----------|--------------------------|
| S1 | 🟠→✅ | Real Apple `DEVELOPMENT_TEAM` was committed in `project.yml`. `origin` is a **public** GitHub mirror → would leak on push. | `project.yml` | **FIXED**: team id moved to gitignored `Local.xcconfig` (via committed `Signing.xcconfig` + `#include?`). `project.yml` no longer contains it; build + signing verified. Fresh clones copy `Local.xcconfig.example`. |
| S2 | 🟡 (accepted) | Default server host `odysseus.macrozao.online` is hardcoded. | `ServerConfig.swift:9`, `SettingsSections.swift:15` | **Accepted per the user's sanitization policy** (which forbids team id / LAN IP / cookies / emails — not the public hostname). It's a resolvable DNS name, not a credential, and is the user's daily-use default. For a fully-generic open-source release, optionally blank it + onboarding. Not changed (would hurt daily UX). |
| S3 | 🟡→✅ | Example LAN IP used as a placeholder in source. | `ServerConfig.swift`, `SettingsView.swift`, `README.md` | **FIXED**: genericized to `meu-servidor:porta`. No LAN IP left in source. |
| S4 | 🟢 | No hardcoded passwords / API keys / bearer tokens / cookies in source. The `password` matches are SwiftUI `@State` input fields (correct). | — | OK. Secrets live in `HTTPCookieStorage` (session) and Keychain. |
| S5 | 🟢 | Auth is cookie-session over the user's HTTPS server; `api_key` for model endpoints is write-only server-side (stored as fingerprint). | `APIClient`, `SettingsAPI` | OK. |
| S6 | 🟠 | `NSAllowsArbitraryLoads: true` (blanket ATS exception) in **both** Info.plists. Justifiable (generic client for user self-hosted HTTP servers), but Apple review scrutinizes it. | `Info.plist:29`, `Info-macOS.plist:31` | For App Store: prefer `NSAllowsLocalNetworking` + per-domain exceptions, or provide a clear review-notes justification. Keep for private builds. Tracked in TODO. |
| S7 | 🟡→✅ | Local docs (`*.md`) contained the user's ComfyUI LAN IP. | doc set | **FIXED**: scrubbed to `<comfyui-host>` across all docs. The real IP lives only in the agent's out-of-repo memory. |
| S8 | 🟡 | `PRIVACY.md` contains a personal contact email (`jogosxd9@gmail.com`). | `PRIVACY.md:44` | **Deliberate** — a privacy policy needs a support contact (App Store requires one). **Left as-is for your decision**: keep, or swap for a dedicated support alias before a public release. Not auto-changed. |

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
