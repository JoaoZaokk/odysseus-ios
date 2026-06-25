# TODO — Odysseus V1 macOS finalization

Status: ✅ done · 🟡 in progress · ⏳ pending · 🚫 blocked (needs user/external) · 📝 doc-only this phase

> **Finalize snapshot (2026-06-24):** all 15 markdown docs + 3 memory banks written; both targets
> build clean; ComfyUI live-tested; new image-gen screen verified; red/blue done inline; tag
> `v1-macos-ready` created. Remaining = security remediation, per-screen manual QA, deep diffusion
> phase, App Store submission (manual), sibling SPM (sudo). See FINAL_HANDOFF.md / POST_VALIDATION.md.

## REGRA ZERO — freeze & rollback
- ✅ Snapshot commit (`738d1a2`) + tag `pre-v1-finalization-snapshot` + branch `v1-macos-finalization`
- ✅ Folder backup + git bundle in `_backups/`
- ✅ `ROLLBACK.md`
- ✅ `.gitignore` excludes `build-*/` (3.9 GB artifacts)

## Documentation scaffold
- ✅ `CLAUDE.md`, `SECURITY_REVIEW.md`, `MB_START.md`, this `TODO.md`
- 🟡 `MB_DONE.md`, `MB_ERRORS_SOLUTIONS.md` (accrue as work lands)
- ⏳ `BUILD_MACOS.md`, `TEST_REPORT.md`, `ENDPOINTS.md`, `CHANGELOG.md`
- ⏳ `ROADMAP_MULTIPLATFORM.md`, `DIFFUSION_COMFYUI_PLAN.md`, `TEAM_REVIEW.md`
- ⏳ `POST_VALIDATION.md`, `FINAL_HANDOFF.md`

## Part 1 — V1 macOS finalization
- 🟡 Re-verify clean build (macOS + iOS) on work branch → `BUILD_MACOS.md`
- ⏳ Functional review of every screen (open/nav/config/persistence/loading/empty/error states)
- ⏳ Email: validate flows + document endpoints + pendências → `ENDPOINTS.md`
- ⏳ TTS/STT: document providers, endpoints, formats, fallback, mic perms → `ENDPOINTS.md`
- ⏳ Timeout / offline-server / slow-response handling audit (no infinite spinners)
- ✅ Security S1/S3/S7 remediation (team id → gitignored xcconfig; LAN IPs scrubbed) — **repo push-safe**; S2 accepted; S8 flagged; S6 = App Store decision
- ✅ RT-3 audio empty-samples guard
- ✅ Navigation smoke pass (all main sections open, no crash)

## Part 1.5 — Diffusion / OpenWebUI Gen / ComfyUI (architecture + config + docs only)
- 🟡 Test ComfyUI live: `GET /system_stats`, `/object_info`, `/queue`, `/history`, `/embeddings`
- ⏳ `ImageGenerationProvider` abstraction (OpenWebUI Gen / ComfyUI / generic) + fallback chain
- ⏳ AI-servers settings: editable ComfyUI/Diffusion/OpenWebUI URLs, default provider, fallback toggle, timeout, "Test connection", "Refresh models/workflows"
- ⏳ New screen: server status / latency / loaded+available models / queue / VRAM / "what fits"
- 📝 Capacity logic (VRAM/RAM → which models likely fit; single/dual/multi GPU) — document, derive from `/system_stats`
- 📝 ComfyUI patterns: txt2img, upscale (single/dual GPU), inpaint, outpaint, API workflow, queue/history, fallback/timeout/offline — examples only, **no model downloads**
- 📝 Local/network paths (`DOCS IA > IA LINUX`, `pipeline > F:\ComfyUI Portable`) documented as external deps

## Testing
- ⏳ build / smoke / open / nav / config / endpoints / email / TTS / STT / HTTPS / timeout / offline / slow / logs / perms → `TEST_REPORT.md`

## Red Team / Blue Team (sandbox copy)
- ⏳ Sandbox copy; Red Team probes (invalid endpoint, offline, timeout, malformed payload, ATS/HTTP, path traversal, secrets in logs, perms)
- ⏳ Blue Team fixes + tests; `TEAM_REVIEW.md` with consensus + disagreements + recommendation

## Build final + archive
- ⏳ Final build, fix, test, commit, tag `v1-macos-ready`
- 🚫 **App Store submission** — agent cannot do (Apple creds + outward action). Handoff steps in `FINAL_HANDOFF.md`.
- ⏳ Final backup + temporary archive → `FINAL_HANDOFF.md`, `POST_VALIDATION.md`

## Part 2 — multiplatform roadmap (docs only, after Part 1)
- ⏳ macOS / iPadOS target versions + distribution → `ROADMAP_MULTIPLATFORM.md`
- ⏳ Windows 11/10/8.1/7 viability + stack comparison (Tauri/.NET/WinUI/Electron/Qt) + legacy fallback
- ⏳ Windows fork plan (native, lean, configurable endpoints, few discreet ads — CFO risk notes)
- ⏳ Diffusion future roadmap (ComfyUI/OpenWebUI/A1111/Invoke/Fooocus, workflow editor, presets, GPU tiers)

## Accepted LOW / hardening backlog (from the LLM council — COUNCIL_REPORT.md)
- ⏳ A1 — persist a revocable session token instead of the password, or gate the saved password behind biometrics (`SecAccessControl`/`.userPresence`). Currently mitigated by `ThisDeviceOnly`.
- ⏳ A2 — optional `LocalAuthentication` app-lock before showing chat history.
- ⏳ A3 — drive login phase off a server-confirmed `authenticated` flag, not local `totpRequired`/totp emptiness.
- ⏳ A4 — TLS certificate pinning via `URLSessionDelegate`.
- ⏳ B4 — single-pass numeric-entity decode in `ResearchReport.decode` (currently bounded by the 600 KB cap + off-main).

## Blocked (need user / external)
- 🚫 Sibling SPM (OpenWebUI-iOS / Companion-iOS / github-odysseus): DNS flush needs `sudo`
- 🚫 App Store / TestFlight submission (Apple credentials)
- 🚫 Cookbook serve/launch & Danger-Zone wipes (heavy/destructive real infra — never auto)
