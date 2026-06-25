# Diagrams

Self-contained SVGs (render on GitHub and in any browser). Secrets are **masked** in the
"before" art (e.g. `FZ5•••`, `192.168.x.x`) so the diagrams never re-introduce them.

| File | Shows |
|------|-------|
| `security-before-after.svg` | Repo sanitization: team id + LAN IPs in tracked files → moved to gitignored `Local.xcconfig` + genericized → **push-safe** (S1/S3/S7). |
| `diffusion-architecture.svg` | Image-gen provider/fallback chain + `ComfyUIClient` read-only endpoints + `ComfyCapacity` "fits this machine?" estimate (real rig: RTX 3090 + 3080 Ti). |
