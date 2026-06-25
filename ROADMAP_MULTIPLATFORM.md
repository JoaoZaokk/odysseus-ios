# ROADMAP_MULTIPLATFORM.md — Odysseus

Documentation only — no Part 2 code changes applied. Decisions for the user/CEO to approve.

## Guiding principle
Odysseus is **native SwiftUI** today (best-in-class on Apple platforms). Keep that as the
flagship. For Windows, do **not** force the SwiftUI codebase onto Windows; instead share the
*contracts* (API shapes, endpoints, config) and build a genuinely native-feeling Windows client.
A monorepo with a shared `core`/`api` contract layer keeps the two in sync without coupling UI.

---

## 1. macOS
- **Min target:** macOS 14 (Sonoma). **Recommended floor for ship:** macOS 14; test on 15/26.
- **Best target:** Apple Silicon native (arm64); also builds for Intel (universal) — keep universal until telemetry says otherwise.
- **Distribution:** (a) Developer-ID + notarization for direct download (most flexible, no sandbox
  friction for LAN); (b) Mac App Store (sandboxed — already sandboxed; resolve S1/S2/S6 first).
- **Permissions in play:** App Sandbox, `network.client`, `device.audio-input`, user-selected files, **Local Network** (the -1009 lesson — keep the retry).
- **Local network / ComfyUI:** works today via `NSAllowsLocalNetworking`; for MAS, justify or
  narrow `NSAllowsArbitraryLoads` (S6).
- **Limitations:** MAS sandbox makes arbitrary self-hosted HTTP servers a review topic; direct
  download avoids it.

## 2. iPadOS
- **Min target:** iPadOS 17 (matches the iOS target). The shared SwiftUI source already compiles for iOS.
- **Approach:** the existing iOS app **is** the iPad app (SwiftUI universal) — no Catalyst needed.
  Invest in iPad-specific layout: multi-column `NavigationSplitView` (already used), keyboard
  shortcuts, pointer/trackpad, drag-drop, Stage Manager sizing.
- **Filesystem:** sandboxed; use document picker / share sheet. Local network same caveats as iOS
  (Local Network permission + usage string — already present).
- **TTS/STT:** on-device Whisper works; mic permission via `NSMicrophoneUsageDescription` (present).
- **App Store Review:** the LAN/self-hosted-server model needs clear review notes; ATS `NSAllowsArbitraryLoads` is the same flag to justify.
- **Reuse:** ~100% of the SwiftUI source. **Rewrite:** only platform-conditional bits (`#if os(macOS)` chrome) — already factored.

## 3. Windows (11 / 10 / 8.1 / 7)

| OS | Viability | Notes |
|----|-----------|-------|
| **Windows 11** | ✅ full | WebView2 present; modern WinUI/Tauri/.NET all fine. Primary target. |
| **Windows 10** (1809+) | ✅ full | WebView2 supported (Evergreen runtime). Co-primary target. |
| **Windows 8.1** | ⚠️ limited | No official WebView2/.NET 8+; use .NET Framework 4.8 + WinForms/WPF + a packaged legacy WebView (CEF) or a pure-native UI. Best-effort. |
| **Windows 7** | ⚠️ legacy/risky | EOL, no WebView2, no .NET 8. Only feasible via .NET Framework 4.8 (last supported) or native Win32/CEF. High maintenance, security-discouraged. Document as "best-effort, unsupported." |

### Stack comparison for the Windows client
| Stack | Native feel | 7/8.1 support | Size | Effort | Notes |
|-------|-------------|---------------|------|--------|-------|
| **Tauri (Rust + WebView2)** | good | ❌ (WebView2 = 10+) | tiny | low-med | Lean, fast, secure; **recommended for 10/11**. Needs a fallback for 7/8.1. |
| **.NET 8 + WinUI 3** | excellent | ❌ (10+) | med | med | Most native on modern Windows; no legacy. |
| **.NET Framework 4.8 + WPF** | very good | ✅ (down to 7) | small | med | **Recommended legacy fallback** for 8.1/7. Mature, no WebView2 dependency. |
| **Electron** | mediocre | ❌ (10+) | large | low | Bloated; against the "no bloatware" goal. Avoid. |
| **Qt (C++/PySide)** | good | ✅ (with effort) | med | high | Cross-platform, can hit 7; heavier dev. |
| **Native Win32/C++** | excellent | ✅ | tiny | very high | Max effort; only if absolutely needed for 7. |

**Recommendation:** **Tauri (Rust + WebView2)** for Windows 10/11 as the main fork (native chrome,
tiny, secure, configurable endpoints), with a **.NET Framework 4.8 WPF** thin client as the
optional legacy fallback for 8.1/7 (feature-reduced). Don't block 10/11 on 7/8.1.

### Cross-cutting Windows concerns
- **Runtimes:** WebView2 Evergreen (auto-updates) for Tauri; .NET FW 4.8 ships with 10/11, installable on 7/8.1.
- **Packaging/update:** MSIX (10/11) or NSIS/Inno + a Tauri/Squirrel updater; code-signing cert (EV recommended to avoid SmartScreen).
- **TTS/STT:** Windows `System.Speech` / SAPI for TTS; Whisper.cpp (native) or Azure/local STT for transcription. Document a provider matrix mirroring the Apple side.
- **Local network / ComfyUI:** no ATS equivalent; just firewall prompts. The `ComfyUIClient` logic ports cleanly to Rust/.NET (same read-only endpoints).

## 4. Windows fork plan (the "amigável, nativo, sem bloatware")
- Native window chrome (Mica/acrylic on 11, flat on 10, classic on 8.1/7), no Electron weight.
- Configurable endpoints (main server, ComfyUI, OpenWebUI Gen, Diffusion) — reuse the same config keys.
- Local-server support, emails, TTS/STT, future diffusion — same feature contracts as Apple.
- **Few, discreet ads** (Part 5) to cover store/infra cost — never in the chat flow, never pausing audio.
- **No context loss with macOS:** share an `openapi`-derived TypeScript/Rust contract package so
  both clients track the same server API. Suggested monorepo:
  ```
  /apps/macos      (this SwiftUI app)
  /apps/ipados     (same SwiftUI target)
  /apps/windows    (Tauri/.NET fork)
  /packages/api    (endpoint contracts generated from /openapi.json)
  /packages/core   (config keys, capacity heuristic, provider model)
  /docs
  ```

## 5. Ads (planning only — CFO)
- Few, discreet, never in the main flow, never pause audio, never invade chat UI.
- Opt-out / remove-ads IAP in the future. No sensitive data; consent where required (GDPR/ATT).
- Apple: respect ATT + App Store ad rules. Microsoft Store: respect their ad SDK rules.
- **Purpose:** cover store fees / infra only — not a revenue product. CFO to size expected fees
  vs. a one-time "remove ads" price; recommend ads **off by default in V1**, revisit post-launch.

## 6. Diffusion — future roadmap (after V1)
Build on the implemented provider/config/status layer:
- Real generation: `POST /prompt` with parameterized API-format workflows; poll `/history`; fetch `/view`; websocket progress.
- Providers: ComfyUI, OpenWebUI Gen, generic Diffusion API; later Automatic1111, InvokeAI, Fooocus (if demand).
- Features: workflow editor/templates, presets, queue/history UI, upscale, inpaint, outpaint,
  single/dual/multi-GPU routing, VRAM-aware model picker (extend the capacity heuristic), seed/batch controls.
- Servers: local + remote; the dual-GPU rig (3090+3080 Ti) is the reference target.
- **No model downloads** in-app; the server hosts models.

## Open decisions (for CEO/CTO/CFO)
- D1 Windows main stack: **Tauri** (recommended) vs WinUI vs WPF-only.
- D2 Legacy 7/8.1: support best-effort (WPF 4.8) vs drop (recommend best-effort, low priority).
- D3 Ads default: **off in V1** (recommended), revisit with CFO cost numbers.
- D4 Monorepo migration timing: after V1 ships (avoid destabilizing the flagship now).
