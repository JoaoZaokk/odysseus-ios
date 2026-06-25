# MB_START — initial state (memory bank: what needs to start)

> One of three memory banks. See `MB_DONE.md` (completed) and `MB_ERRORS_SOLUTIONS.md` (errors→fixes).

## Starting point (2026-06-24)
- Branch before work: `main` @ `377cf9c`; snapshot `738d1a2`; tag `pre-v1-finalization-snapshot`;
  work branch `v1-macos-finalization`. Backup + bundle in `_backups/`. (See `ROLLBACK.md`.)
- App: 62 Swift files, ~10.1k LOC, 17 feature modules. iOS + macOS shared source via XcodeGen.
- Both targets built clean at the start of this effort (verified in the prior session).

## Architecture (current)
- Networking: single `APIClient`, cookie-session auth, SSE streaming, FastAPI-tolerant decoding.
- Settings: native sectioned panel incl. admin sections (Lembretes, Integrações + Add, Agent
  Tools + built-in tool toggles, Sistema + Terminal Logs, Usuários). All verified live.
- Deep Research: native animated node graph + native HTML→SwiftUI report renderer.
- Voice: TTS + STT (Whisper). Chat: SSE streaming, image paste (macOS ⌘V).

## Known risks at start
- R1 — App Store **submission** cannot be performed by the agent (needs Apple creds + outward
  action). Build/archive/handoff can. → handled as handoff, not a blocker.
- R2 — Security S1/S2 (team id + default host in tracked files) gate a *public* release.
- R3 — Diffusion/ComfyUI is **architecture + config + docs only** this phase (no heavy models,
  no deep workflows). ComfyUI at `192.168.3.133:8190` is reachable from this Mac (HTTP 200).
- R4 — Other 3 sibling projects' SPM is blocked on a DNS flush needing `sudo` (user action).
- R5 — macOS sandbox blocks in-app log/file shape dumps (use on-screen render or `/openapi.json`).

## Decisions pending (for CEO/CTO)
- D1 — Default server host for a public build: blank+onboarding vs keep current. (CFO/PR input.)
- D2 — Diffusion provider order of fallback (OpenWebUI Gen → ComfyUI → generic) — confirm default.
- D3 — Windows fork stack (Tauri vs .NET/WinUI vs Electron) — Part 2 roadmap, decide later.

## What needs to start (high level — see TODO.md for the itemized list)
1. Re-verify build on the work branch (macOS + iOS) → `BUILD_MACOS.md`.
2. Test ComfyUI endpoints live → `ENDPOINTS.md` / `DIFFUSION_COMFYUI_PLAN.md`.
3. Diffusion provider abstraction + AI-servers settings/config screen.
4. Red Team / Blue Team pass (sandbox copy) → `TEAM_REVIEW.md`.
5. Part 2 multiplatform roadmap docs.
6. Honest handoff + post-validation.
