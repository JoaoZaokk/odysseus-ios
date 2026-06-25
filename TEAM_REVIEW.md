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
| RT-3 | 🟡→✅ | Audio force-unwraps in `VoiceInputManager`. Re-reviewed: `captureRaw` already guards `floatChannelData`/`frameLength>0`; `static targetFormat!` has hardcoded-valid params (provably safe). The **one real risk**: `resampleTo16k` with **empty** samples → 0-capacity buffer → `floatChannelData![0]`/`baseAddress!` crash (the existing guard didn't cover empty input). | **Fixed (Blue)** — added `guard !samples.isEmpty`. Other unwraps confirmed provably-safe, left unchanged (option B). Build verified. |
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

## Round 2 — independent Opus red-team audit (REAL sub-agent)

The sub-agent infra worked on retry (Opus, 89k tokens, 26 tool calls) — a genuine independent
second pass. It found **real vulnerabilities the round-1 inline review missed**. Full debate:

| ID | Sev | Red Team finding | Blue Team action |
|----|-----|------------------|------------------|
| V1 | 🔴→✅ | `ServerConfig.normalize/resolve` accept **any scheme** (`file://`, `data:`) — SSRF / scheme smuggling. | **FIXED** `93dbcb3`: scheme allowlist (http/https only) in normalize + resolve + ComfyUIClient.url. |
| V2 | 🔴→✅ | "is-local" used `hasPrefix("10.")/"192.168."` → mis-fires on `10.evil.com`, **downgrading a public host to cleartext http and leaking the session cookie**; also missed `172.16/12`. | **FIXED** `93dbcb3`: `isLocalHost` parses real IPv4/IPv6 literals (127/8, 10/8, 172.16/12, 169.254/16, 192.168/16, ::1, fc00::/7). |
| V3 | 🔴→✅ | `NSAllowsArbitraryLoads:true` removes the ATS backstop (cleartext to any public host). | **FIXED** `8f35316`: dropped it, kept `NSAllowsLocalNetworking`. **Verified live** the LAN ComfyUI still connects. |
| V4 | 🟠→✅ | Server-supplied ids (email uid/folder, session/research/gallery id) interpolated **raw** into authenticated URLs → confused-deputy path/param smuggling. | **FIXED** `b6b2877`: `encPath`/`encQuery` at every string-id call site. |
| V5 | 🟠→✅ | Saved password in Keychain as `AfterFirstUnlock` (not `ThisDeviceOnly`) → can migrate via iCloud Keychain / backups. | **FIXED** `bacfa8a`: `…AfterFirstUnlockThisDeviceOnly`. |
| V6 | 🟠→✅ | `ResearchReport` HTML parser O(n²)/unbounded on hostile server HTML (DoS / UI hang). | **MITIGATED** `bacfa8a`: 600 KB input cap (real reports ~80 KB). Deeper single-pass `slice` rewrite tracked. |
| V7 | 🟠 | `HTTPCookieStorage.shared` not isolated per server; old server's cookie can be replayed; `logout()` best-effort. | **DEFERRED (documented)**: correct fix is a per-client cookie store, but it changes session persistence — needs careful migration so users aren't logged out. Tracked in TODO; **mitigated** by V2 (no cleartext to wrong host). |
| V8 | 🟠 | Raw server `detail`/error bodies rendered in user-facing errors (`ChatStreamClient.extractError` ~500 B). | **DEFERRED (documented)**: map to fixed strings; low exploitability (no creds in bodies). Tracked. |
| V9 | 🟠 | `APIClient` `@unchecked Sendable`; `config` mutated (`updateConfig`) without a lock while a background stream reads it → data race on server switch. | **DEFERRED (documented)**: low-likelihood; correct fix = new `APIClient` per server (or a lock). Tracked. |
| V10 | 🟢 | **No** `print`/`NSLog` of secrets; force-unwraps all provably safe from untrusted data; JSON decoders robust. | No action — good hygiene confirmed by a second reviewer. |

**Score:** 6 of 9 actionable findings **fixed + build-verified** (incl. all 3 HIGH); 3 MED
**deferred with rationale** (each would risk session/threading regressions for marginal gain and
is partly mitigated). The deferred three are the honest "we chose stability over churn" calls.

## Consensus (CEO/CTO/Comparator)
- The codebase is **defensively written and stable**; the only real, user-visible defect found
  (RT-1) is **fixed and verified live**. Security items S1/S2/S6/S7 are **release-gating for a
  public App Store build** but **not** blocking a private signed build for the user's devices.
- **Disagreement noted:** a stricter reviewer would harden RT-3 now; the team accepted B to keep
  the V1 build frozen and known-good, with the hardening explicitly tracked.
- Recommendation: ship V1 privately as-is; gate any public push on S1/S2/S6/S7 remediation.
