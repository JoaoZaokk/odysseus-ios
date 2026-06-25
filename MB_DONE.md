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
