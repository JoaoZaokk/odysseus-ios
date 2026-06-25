# ENDPOINTS.md — Odysseus server + ComfyUI

All reverse-engineered and (where noted) verified live. Auth is **cookie-session**
(`HTTPCookieStorage`) against the user's HTTPS server. Base default: `https://odysseus.macrozao.online`.

## Discovery aid
`GET /openapi.json` (FastAPI, served with the session cookie) lists every path + method +
request-body schema authoritatively. Use it instead of guessing bodies.

---

## Odysseus server API (verified live)

### Settings
- `GET /api/auth/settings` → flat key/value object (the settings bag).
- `POST /api/auth/settings` JSON partial → server merges. Used by AI Defaults, Search, Deep
  Research, Reminders, Agent execution limits, Sistema URL, etc.

### Agent tools
- `GET /api/tools` → `{tools:[{id, enabled}]}` (68 built-ins; no category — grouping is client-side).
- `POST /api/tools` JSON `{disabled:[ids]}` → **inverse list**; tools not listed are enabled.

### Diagnostics / system (verified live)
- `GET /api/diagnostics/logs?limit=N` → `{status:"success", logs:[String]}`; each line
  `"TS - module - LEVEL - msg"` (INFO/WARNING/ERROR/CRITICAL/DEBUG). Only param: `limit`.
- `GET /api/diagnostics/services`, `GET /api/hwfit/system` (status/host info — not yet wired).

### Integrations
- `GET /api/auth/integrations` → `{integrations:[{id,name,base_url,auth_type,enabled}]}`.
- `POST /api/auth/integrations` JSON, type-discriminated:
  - CalDAV/CardDAV: `{type:"caldav"|"carddav", name, base_url, username, password}` (**`base_url`**, not `url`).
  - API service: `{type:"api", name, base_url, auth_type, auth_header?, api_key?}`.
  - Claude/Codex agent: `{type:"claude"|"codex", name}` (returns a token).
- `DELETE /api/auth/integrations/{id}`, `POST /api/auth/integrations/{id}/test`.
- MCP servers (separate): `GET /api/mcp/servers`, `POST /api/mcp/servers` `{name,transport:"stdio",command,args[],env{}}`, `POST /api/mcp/servers/{id}/reconnect`.

### Model endpoints (LLM)
- `GET /api/model-endpoints` → list; `POST` = **form-urlencoded** (`name,base_url,model_type,endpoint_kind,category,api_key?`) — NOT JSON; `PATCH /{id}` (is_enabled); `DELETE /{id}`.

### Users / admin
- `GET /api/auth/users`; `POST /api/auth/users` `{username,password,is_admin}`; `PUT/DELETE /{username}`.
- `GET /api/auth/policy` (signup); `POST /api/auth/signup-toggle`.
- `GET /api/export` (backup JSON); `DELETE /api/admin/wipe/{cat}` (danger — not auto).

### Deep Research
- `POST` start, SSE stream, `GET` active, library, `GET` report (Accept: text/html → parsed native).

### Email (Settings → Contas)
- `GET /api/email/accounts` (list), add/delete/set-default; inbox list/read/reply/send/archive.
  TODO: confirm exact paths against `/openapi.json` and document error/timeout/loading states.

### TTS / STT (Voice)
- STT: on-device **Whisper** (SwiftWhisper) — no server endpoint; needs mic permission
  (`device.audio-input` entitlement). TTS: server `/api/tts/*` (seen in settings.js) and/or
  on-device `AVSpeechSynthesizer`. TODO: document provider matrix + fallback + formats per platform.

---

## ComfyUI — `http://192.168.3.133:8190` (VERIFIED LIVE 2026-06-24)

> Read-only GETs only. `POST /prompt` (real generation) intentionally NOT exercised.

| Method | Path | Status | Response (real) |
|--------|------|--------|-----------------|
| GET | `/system_stats` | ✅ 200 (37 ms) | OS win32; RAM 68 GB (35 free); ComfyUI 0.22.0; Python 3.13.12; PyTorch 2.12.1+cu126; `devices[]` below |
| GET | `/object_info` | ✅ 200 | **2548 nodes**; per-node input specs incl. available model filenames |
| GET | `/queue` | ✅ 200 | `{queue_running:[], queue_pending:[]}` (empty) |
| GET | `/history` | ✅ 200 | `{}` (0 entries) |
| GET | `/embeddings` | ✅ 200 | `[]` (0) |
| GET | `/object_info/{node}` | ✅ 200 | single-node spec (lighter than full `/object_info`) |
| POST | `/prompt` | ⛔ not tested | enqueues a real workflow — left for a deliberate generation phase |
| POST | `/interrupt`, `/queue` (clear) | ⛔ not tested | mutating |
| GET | `/view?filename=…` | n/a | fetch an output image (used after a real run) |

### GPUs (from `/system_stats.devices`)
| Device | GPU | VRAM total | VRAM free |
|--------|-----|-----------|-----------|
| cuda:0 | NVIDIA RTX **3090** | 25.8 GB | 24.4 GB |
| cuda:1 | NVIDIA RTX **3080 Ti** | 12.9 GB | 11.6 GB |

→ **Dual-GPU**, ~38.7 GB total / ~36 GB free. Enables single-GPU and dual/multi-GPU patterns.

### Model inventory (from `/object_info`, real)
- **Checkpoints (10)**: `sd_xl_base_1.0`, `hidream_o1_image_bf16`, `ltx-2.3-22b-dev-fp8`, `hunyuan3d-dit-v2-mv-turbo_fp16`, `sam3.1_multiplex_fp16`, …
- **UNET/diffusion (17)**: `flux-2-klein-base-4b-fp8`, `qwen_image_edit_2509_fp8_e4m3fn`, `hunyuanvideo1.5_720p_t2v_fp16`, `lotus-depth-d-v1-1`, `capybara_v0.1`, …
- **LoRA (17)**: many `Qwen-Image-Edit-2509/2511-Lightning-{4,8}steps`, Relight, Anything2Real, …
- **VAE (11)**: `ae`, `LTX23_video_vae`, `hunyuanvideo15_vae_fp16`, `cogvideox_vae`, …
- **CLIP/text encoders (13)**: `gemma_3_12B_it_heretic(_fp8)`, `gemma4_e4b_it_fp8_scaled`, `byt5_small_glyphxl`, …
- **ControlNet (3)**: `Depth-Anything-V2-Small`, `Z-Image-Turbo-Fun-Controlnet-Union-2.1`, `DA3NESTED-GIANT-LARGE`.
- No `UpscaleModelLoader` node registered (upscale via model-specific nodes; document during the diffusion phase).

### Capacity heuristic (documented; see DIFFUSION_COMFYUI_PLAN.md)
`/system_stats.devices[*].vram_free` → estimate which checkpoints/UNETs fit: fp8 ~ bytes≈params×1;
bf16/fp16 ~ params×2; + working set (latents/VAE) headroom ~2–4 GB. A 22B fp8 (~22 GB) fits the
3090 alone; small fp8 (4B Flux-2 Klein ~4 GB) fits either GPU comfortably.
