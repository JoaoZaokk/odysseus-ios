# DIFFUSION_COMFYUI_PLAN.md

Image-generation architecture for Odysseus: **OpenWebUI Gen**, **ComfyUI**, and a generic
**Diffusion API**, with fallback, configuration, live status, and capacity estimation.
This phase delivers **architecture + config + live status**; deep workflow generation
(txt2img/upscale/inpaint/outpaint, multi-GPU) is **documented here, not yet executed** — no
heavy model downloads, no real `POST /prompt` runs.

## What is implemented (this phase)
- `ImageGenProvider` enum (openwebui / comfyui / generic) + persisted config
  (`DiffusionConfigKeys`, `@AppStorage`): provider URLs, default provider, automatic fallback,
  timeout. UI: **Settings → Geração de imagem** (`DiffusionServersView`).
- `ComfyUIClient` (read-only): `/system_stats`, `/object_info`, `/queue`. Models for
  GPUs/VRAM/RAM/version and the model inventory. **Verified live** vs ComfyUI 0.22.0.
- `ComfyCapacity`: per-GPU "will it fit?" estimate from filename precision hints.
- Blue-Team fix: retry once on macOS Local-Network `-1009` (see MB_ERRORS_SOLUTIONS).

## Fallback architecture (target)
```
ImageGenerationProvider (protocol)
├── OpenWebUIGenProvider   // uses the main Odysseus session (default URL = main server)
├── ComfyUIProvider        // direct to user ComfyUI (workflow JSON via /prompt)  ← read-only today
└── GenericDiffusionProvider // any OpenAI-image-style / A1111-style endpoint

generate(request):
  providers = [default] + (fallbackEnabled ? others-in-order : [])
  for p in providers:
     try p.generate(request)  → return on success
  → all failed: surface a clear error; log without sensitive data
```
The settings screen already shows the resolved fallback order live
(`ComfyUI → OpenWebUI Gen → Diffusion API`, reordered by the chosen default).

## ComfyUI endpoints (tested — see ENDPOINTS.md)
Read-only used today: `/system_stats`, `/object_info`, `/object_info/{node}`, `/queue`,
`/history`, `/embeddings`. Generation (future phase): `POST /prompt` (enqueue workflow),
`GET /history/{prompt_id}` (poll), `GET /view?filename=…&subfolder=…&type=output` (fetch image),
`POST /interrupt`, websocket `/ws?clientId=…` (live progress).

## Live server snapshot (user's rig, 2026-06-24)
- Host: Windows, ComfyUI 0.22.0, Python 3.13.12, PyTorch 2.12.1+cu126, 68 GB RAM.
- **GPU0 RTX 3090 (24.4 GB free / 25.8)**, **GPU1 RTX 3080 Ti (11.6 / 12.9)** → dual-GPU, ~36 GB free.
- Inventory: 10 checkpoints, 17 UNET/diffusion, 17 LoRA, 11 VAE, 13 CLIP/text-encoders, 3 ControlNet.
- Notable models present: `flux-2-klein-base-4b-fp8`, `qwen_image_edit_2509_fp8`, `sd_xl_base_1.0`,
  `hidream_o1_image`, `ltx-2.3-22b`, `hunyuanvideo1.5_720p`, `Z-Image-Turbo` ControlNet, gemma text encoders.

## Capacity estimation (implemented heuristic)
- Read `system_stats.devices[*].vram_free`. For each checkpoint/UNET, estimate weight size from
  the filename: `fp8` ≈ 1 byte/param, `fp16`/`bf16` ≈ 2 bytes/param; param count from a `NNb`
  token (e.g. `22b`). Add **~3 GB** working-set headroom (latents, VAE decode, attention).
- Fit vs best single GPU free VRAM: `fits` (≤85%), `tight` (≤100%), `tooBig` (>100%),
  `unknown` (no hint). Validated live: `ltx-2.3-22b-dev-fp8` → **não cabe**;
  `sd_xl_base_1.0` → **cabe**.
- **Limitations / TODO**: ComfyUI does not expose param counts, so models without a size token
  and outside known families (SDXL/Flux) show `—`. Improve by (a) a small name→size table for
  common bases, (b) reading file sizes if a models-listing endpoint exposes them, (c) factoring
  resolution/batch into the working-set estimate.

## GPU patterns to document (future generation phase — examples only, no model downloads)
| Pattern | Approach on this rig |
|---------|----------------------|
| txt2img single-GPU | Standard graph on GPU0 (3090, 24 GB) for SDXL/Flux-fp8/Qwen-Edit. |
| txt2img multi-GPU | Per-device pipelines or MultiGPU custom nodes; assign UNET→GPU0, VAE/CLIP→GPU1 to free VRAM; or run two independent jobs (one per GPU) for throughput. |
| Upscale single-GPU | Tiled upscale (e.g. UltimateSDUpscale) on GPU0; no `UpscaleModelLoader` node present → add an upscale model or use latent upscale. |
| Upscale dual-GPU | Split tiles across GPUs, or run the upscaler on GPU1 while GPU0 generates. |
| Inpaint | Inpaint checkpoint/conditioning + mask; Qwt-Image-Edit LoRAs present (Relight, Anything2Real). |
| Outpaint | Pad + mask the canvas, feed as inpaint with edge conditioning. |
| API workflow | Export the ComfyUI graph as **API-format JSON**, parameterize seed/prompt/model, `POST /prompt`, poll `/history`, fetch `/view`. |
| Queue / history | `/queue` for running+pending; `/history` for finished outputs and their files. |
| Fallback / timeout / offline / OOM | Provider chain above; surface VRAM/OOM hints from capacity estimate before submitting. |

## Local & network paths (external dependencies — documented, not wired)
The user's model/source tree lives on the Windows/LAN side, not on this Mac:
```
Rede local → DOCS IA → IA LINUX
Rede local → pipeline → disco F:  →  F:\ComfyUI Portable
```
These are **not mounted** in this environment, so they are recorded as external deps. ComfyUI
already exposes its model inventory over HTTP (`/object_info`), which is what the app uses — it
does not need direct filesystem access to those paths for status/capacity. Direct path browsing
(if ever wanted) would require an SMB mount or a small agent on the ComfyUI host.

## Security notes
- The ComfyUI URL is user-supplied; the client validates scheme/host and only issues GETs.
  No `POST /prompt` from settings. ATS: app permits local HTTP (`NSAllowsLocalNetworking`,
  `NSAllowsArbitraryLoads`) — see SECURITY_REVIEW S6.
- The real LAN IP is **not** hardcoded in shipped Swift (generic placeholder); it appears only
  in local docs. Scrub `*.md` before any public push (SECURITY_REVIEW).
