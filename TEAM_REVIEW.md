# TEAM_REVIEW.md — Red Team / Blue Team / Blind Comparator

> **Agent infrastructure note:** real sub-agent spawning failed in this environment — the
> harness forced model `mimo-v2.5-pro` (the user's own self-hosted model, inaccessible to
> sub-agents) and ignored the `sonnet` override (`subagent_tokens: 0`, immediate failure). Per
> the master prompt ("se o ambiente não suportar agentes reais, simulem os papéis e documentem"),
> the Red/Blue/Comparator roles were executed **inline** with full context and a real static
> audit. One finding was reproduced **live** against the user's ComfyUI server.

## Method
- Static pattern audit (`git grep`) for force-unwraps, `try!`, `as!`, `fatalError`, missing
  timeouts, unguarded indexing, stray logging.
- Live behavioral test of the new diffusion/ComfyUI path against `<comfyui-host>:8190`.
- Manual review of `APIClient`, `ServerConfig`, `ComfyUIClient`, Voice, Research, Settings.

## Red Team findings

| ID | Sev | Finding | Status |
|----|-----|---------|--------|
| RT-1 | 🔴→✅ | **Reproduced live**: ComfyUI showed "offline" though reachable — macOS Local Network privacy returns `-1009` on the first LAN connection. Spurious failure for *every* first LAN connect. | **Fixed (Blue)** — retry once on `-1009`/`-1005`; verified → "online". commit `81e5de7`. |
| RT-2 | 🟠 | `NSAllowsArbitraryLoads: true` in both Info.plists (SECURITY S6). | Documented; release-gating for App Store, accepted for private build. |
| RT-3 | 🟡 | Audio force-unwraps in `VoiceInputManager` (`AVAudioFormat(...)!`, `floatChannelData![0]`, `baseAddress!`). Standard AVAudioEngine pattern with hardcoded-valid params, but a format-creation failure would crash. | Accepted (low risk); flagged for defensive `guard` in a future hardening pass. |
| RT-4 | 🟡 | `ModelDownloadManager.swift:25` uses `urls(for:.applicationSupportDirectory…)[0]`. | Accepted — that API always returns ≥1 URL on Apple platforms. |
| RT-5 | 🟡 | `ResearchGraph.swift:247` preview animation assumes `rounds[0]` exists. | Accepted — `startPreview` pre-populates rounds; not reachable empty. |
| RT-6 | 🟢 | **No** `try!`, `as!`, `fatalError`/`preconditionFailure`, or stray `print`/`NSLog` in source. Every `URLSession` sets request+resource timeouts. Decoders are tolerant (`try?` + custom `init(from:)`). | Good hygiene — no action. |
| RT-7 | 🟡 | `ServerConfig`/`ComfyUIClient` accept user URLs. `ComfyUIClient` only issues GETs and validates scheme; no `POST /prompt` from settings. No SSRF amplification. | OK; keep GET-only in the status path. |

## Blue Team actions
- **RT-1 fixed** (commit `81e5de7`): `ComfyUIClient.getJSON` retries once after 0.8 s on
  `.notConnectedToInternet`/`.networkConnectionLost`. Live-validated.
- RT-2/S6, S7 (LAN IP in docs): documented in SECURITY_REVIEW + TODO; not auto-changed
  (would break local signed build / the user wants the IP in local docs).
- RT-3/4/5: assessed low-risk and **accepted with rationale** rather than churn provably-safe
  code. Recommended a future "defensive audio/IO guards" task (in TODO).

## Blind Comparator — "harden every force-unwrap now" vs "guard only the genuinely-unsafe"
| Criterion | A: fix all unwraps now | B: accept provably-safe, guard audio/IO later |
|-----------|------------------------|-----------------------------------------------|
| Risk reduction | marginal (most are safe) | targets the only realistic crash sites |
| Churn / regression risk | higher (touches stable Voice/Research code) | minimal |
| V1 stability | could destabilize before ship | preserves a known-good build |
| Maintainability | noisier diffs | focused, documented rationale |
| **Recommendation** | | **B (chosen)** — lowest risk to the V1 build; audio/IO guards tracked as a follow-up. |

## Consensus (CEO/CTO/Comparator)
- The codebase is **defensively written and stable**; the only real, user-visible defect found
  (RT-1) is **fixed and verified live**. Security items S1/S2/S6/S7 are **release-gating for a
  public App Store build** but **not** blocking a private signed build for the user's devices.
- **Disagreement noted:** a stricter reviewer would harden RT-3 now; the team accepted B to keep
  the V1 build frozen and known-good, with the hardening explicitly tracked.
- Recommendation: ship V1 privately as-is; gate any public push on S1/S2/S6/S7 remediation.
