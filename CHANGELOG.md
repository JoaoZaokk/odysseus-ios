# CHANGELOG

## [v1-macos-finalization] — 2026-06-24

### Added
- **Settings → Geração de imagem**: image-generation provider configuration (ComfyUI /
  OpenWebUI Gen / generic Diffusion URLs, default provider, automatic fallback, timeout).
- **Live ComfyUI status & capacity**: `ComfyUIClient` (read-only) pulls `system_stats` /
  `object_info` / `queue`; shows version, GPUs/VRAM, RAM, model inventory, and a per-GPU
  "cabe / não cabe / apertado" model-fit estimate (`ComfyCapacity`).
- `scripts/comfy-health.sh` — read-only ComfyUI health check.
- Full documentation set: CLAUDE, ROLLBACK, TODO, BUILD_MACOS, ENDPOINTS, SECURITY_REVIEW,
  DIFFUSION_COMFYUI_PLAN, TEAM_REVIEW, TEST_REPORT, ROADMAP_MULTIPLATFORM, MB_START/DONE/ERRORS,
  CHANGELOG, FINAL_HANDOFF, POST_VALIDATION.

### Fixed
- **macOS Local Network -1009**: first connection to a LAN host (ComfyUI) failed with
  `.notConnectedToInternet` while macOS evaluated Local Network permission → spurious "offline".
  `ComfyUIClient` now retries once; verified live (status flips to "online").

### Changed
- `.gitignore` excludes `build-*/` (3.9 GB of local build artifacts).

### Security (documented, not auto-changed — see SECURITY_REVIEW.md)
- S1 `DEVELOPMENT_TEAM` in tracked `project.yml` (public mirror leak risk).
- S2 hardcoded default server host. S3 placeholder LAN IP.
- S6 blanket `NSAllowsArbitraryLoads`. S7 LAN IP in local docs.
- No hardcoded passwords / API keys / cookies in source (S4/S5 OK).

### Notes
- Carried-over (pre-branch, in snapshot `738d1a2`): Integrações Add, Agent Tools built-in
  toggles, Terminal Logs, stars twinkle, email form redesign.
- **Not done by the agent:** App Store submission (Apple credentials + outward action) — see FINAL_HANDOFF.
