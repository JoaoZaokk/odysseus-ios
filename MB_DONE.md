# MB_DONE — completed work (memory bank)

> Accrues as work lands. Each entry: what, commit, files, test/validation.

## 2026-06-24

### REGRA ZERO — freeze & rollback
- Snapshot commit `738d1a2` on `main`; tag `pre-v1-finalization-snapshot`; work branch `v1-macos-finalization`.
- `.gitignore` updated to exclude `build-*/` (3.9 GB artifacts kept out of the snapshot).
- Folder backup (160 MB) + git bundle (872 KB) in `/Users/joaozao/Projetos/_backups/`.
- `ROLLBACK.md` written with 4 rollback options. **Validation:** `git status` clean of artifacts; backup `du -sh` confirmed.

### Audit + documentation scaffold
- Structure audit: 17 modules, 62 Swift files, ~10.1k LOC.
- Security static scan → `SECURITY_REVIEW.md` (S1 team id, S2 default host, S3 placeholder IP; S4/S5 ok — no hardcoded secrets).
- Wrote `CLAUDE.md`, `MB_START.md`, `TODO.md`, `MB_DONE.md`, `MB_ERRORS_SOLUTIONS.md`.
- ComfyUI `192.168.3.133:8190` reachability confirmed (HTTP 200, 37 ms) for the diffusion phase.

### Build verification (commit `c992ed2`)
- macOS + iOS both **BUILD SUCCEEDED** on the work branch (Xcode 26.4 / Swift 6.3). → `BUILD_MACOS.md`.

### ComfyUI live endpoint test (commit `c992ed2`)
- Read-only probe of `system_stats`/`object_info`/`queue`/`history`/`embeddings` (all 200).
  Dual-GPU (RTX 3090 24.4 GB free + 3080 Ti 11.6 GB), 2548 nodes, full model inventory. → `ENDPOINTS.md`.

### Diffusion feature (commit `81e5de7`)
- New **Settings → Geração de imagem**: provider config (ComfyUI/OpenWebUI-Gen/Diffusion URLs,
  default provider, fallback, timeout) + live ComfyUI status + per-GPU capacity ("cabe/não cabe").
- `ComfyUIClient` (read-only) + `ComfyCapacity`. **Tested live**: status "online", correct fit
  flags (ltx-22b → não cabe; sdxl → cabe). Blue-Team retry fix for macOS `-1009`. → `DIFFUSION_COMFYUI_PLAN.md`.
- Files: `Odysseus/Features/Diffusion/{ComfyUIClient,DiffusionServersView}.swift`, `SettingsView.swift` wiring.
