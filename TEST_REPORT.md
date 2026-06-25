# TEST_REPORT.md — Odysseus V1

Environment: macOS (Darwin 25.x), Xcode 26.4, Swift 6.3. Branch `v1-macos-finalization`.
Legend: ✅ verified live · 🟢 builds/compiles · ⚠️ partial · ⏳ not exercised this session.

## Build / compile
| Test | Result |
|------|--------|
| `xcodegen generate` | ✅ |
| macOS Debug build | ✅ BUILD SUCCEEDED |
| iOS Debug build (generic device) | ✅ BUILD SUCCEEDED |
| App launches (macOS, signed/sandboxed) | ✅ |

## Settings — verified live this/recent session
| Area | Result |
|------|--------|
| Padrões de IA / Busca / Deep Research | ✅ render + real data |
| Integrações + **Add** (CalDAV create→list→remove) | ✅ live round-trip (`base_url` fix) |
| Agent Tools — execution limits | ✅ |
| Agent Tools — **Built-in Tools** (68 tools, 11 categories, toggle + `POST {disabled}`) | ✅ save round-trip verified |
| Sistema — **Terminal Logs** (`/api/diagnostics/logs`, color/level filter) | ✅ filter ERROR → 20/100 |
| Usuários (signup toggle, list) | ✅ |
| **Geração de imagem** (new) — provider config, ComfyUI test, capacity | ✅ live "online" + correct fit flags |

## Diffusion / ComfyUI (live, read-only)
| Test | Result |
|------|--------|
| `GET /system_stats` (GPUs, VRAM, RAM, versions) | ✅ |
| `GET /object_info` (model inventory) | ✅ 2548 nodes parsed |
| `GET /queue`, `/history`, `/embeddings` | ✅ |
| Capacity estimate (`ltx-22b`→não cabe, `sdxl`→cabe) | ✅ matches reality |
| Local Network `-1009` first-connect retry fix | ✅ verified: retry → online |
| `POST /prompt` (real generation) | ⛔ intentionally not run (no model loads) |

## Network robustness
| Test | Result |
|------|--------|
| All `URLSession` set request+resource timeouts | 🟢 (grep-verified) |
| Tolerant decoders (no crash on missing/null fields) | 🟢 custom `init(from:)` widely used |
| FastAPI 422-array errors surfaced to UI | ✅ (e.g. integration "base URL required") |
| Offline/unreachable server → clear error, no infinite spinner | ✅ ComfyUI offline path shows error then recovers on retry |

## Not exhaustively exercised this session (honest gaps)
| Area | Why / next step |
|------|------------------|
| Every chat/voice/email/gallery/calendar flow end-to-end | ⏳ Settings + diffusion were the focus; smoke-level confidence from clean build + tolerant code. Recommend a manual pass per screen before public ship. |
| TTS/STT live capture (mic) | ⏳ documented (Whisper on-device); a real dictation round-trip not re-run this session. |
| Email send/receive against a live mailbox | ⏳ endpoints documented; needs a configured account to test send/receive. |
| iOS on-device/simulator runtime | ⏳ compiled for generic iOS; not run on a device/simulator this session. |
| Automated unit/smoke test scripts | ⏳ none in repo yet; recommend adding `xcodebuild test` targets + an endpoint health script. |

## Recommended test scripts to add (TODO)
- `scripts/comfy-health.sh` — curl the read-only ComfyUI endpoints + assert 200 (the manual probe used here, scripted).
- `xcodebuild test` target with a few decoder unit tests (malformed/empty JSON → no crash).
- A smoke checklist (open each section, assert no crash) for pre-ship manual QA.
