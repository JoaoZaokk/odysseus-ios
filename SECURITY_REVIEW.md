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
| S6 | 🟠→✅ | `NSAllowsArbitraryLoads: true` (blanket ATS exception). | `project.yml` (generates both plists) | **FIXED** (`8f35316`): removed; kept `NSAllowsLocalNetworking`. Public hosts now require HTTPS (also enforced by `ServerConfig.normalize`). Verified live: LAN ComfyUI still connects. |
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

## Red-team round 2 (independent Opus sub-agent) — see TEAM_REVIEW.md for the full debate
Found real issues the first pass missed. Fixed + build-verified: scheme allowlist & private-IP
detection (SSRF / cleartext-downgrade, `93dbcb3`), percent-encoded server ids (`b6b2877`),
Keychain `ThisDeviceOnly` + ResearchReport input cap (`bacfa8a`), ATS hardening (`8f35316`).
Deferred-with-rationale (stability over churn): per-server cookie store (V7), error-string
redaction (V8), `APIClient` config-race lock (V9).

## Red-team round 3 — LLM council (2 more Opus agents) — see COUNCIL_REPORT.md
Full multi-agent audit. **Every HIGH and MED fixed + build-verified:** encPath propagated to all
17 server-id sites (`780a0e0`), report-parser O(n²) + slice tail (`652a4a9`), report-image SSRF
(`652a4a9`), error-body cap (`652a4a9`), per-client cookie store + server-switch reset + config
lock (`aac2e46`), MultipartForm CRLF (`aac2e46`). **Accepted LOW/design (tracked, with rationale):**
A1 password-at-rest (mitigated ThisDeviceOnly; full fix = revocable token/biometric, product change),
A2 biometric app-lock, A3 2FA-off-server-flag, A4 TLS pinning, B4 entity-decode O(n) (capped+off-main).
Ported the shared URL/injection/ATS fixes to **OpenWebUI-iOS** and **Companion-iOS**.

## Decisions
- S1/S2 are **release-gating for a public App Store build** but **not** blocking for a private
  signed build for the user's own devices. Documented as TODO, not auto-changed (would break the
  local signed build). CEO/CTO sign-off required before any public push.
