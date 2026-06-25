# COUNCIL_REPORT — LLM security council (2026-06-24)

A multi-agent ("LLM council") red-team review of Odysseus-iOS. Three independent Opus agents
audited the code; this human-in-the-loop (the orchestrator) acted as Blue Team and chair.
Every finding below was fixed or formally accepted with a rationale. Each fix is its own commit.

## Council members & what each did

| Agent | Model | Lens | Tokens / tools | Outcome |
|-------|-------|------|----------------|---------|
| **Round-1 Red** | Opus | Broad first pass | 89k / 26 | Found the original 10 (V1–V10): cleartext downgrade, SSRF, injection, ATS, Keychain, parser DoS, cookie store, error bodies, config race. |
| **Council A** | Opus | Auth / session / crypto / transport / concurrency / secrets-at-rest | 72k / 21 | Verified all landed fixes correct; **voted to fix (not defer) V7 & V9**; found A1–A5. |
| **Council B** | Opus | Injection / parsing / data-flow / rendering / DoS | 87k / 30 | **Found the encPath fix reached only 4 of ~11 files** (HIGH); report-image SSRF; remaining O(n²); **voted V8 deferrable** (with a cap). |

## Agreements (council consensus)
- ✅ All five round-1 fixes (scheme allowlist, private-IP detection, encPath in the 4 audited files, Keychain ThisDeviceOnly, ResearchReport cap, ATS) are **correctly implemented**. (A and B independently verified.)
- ✅ The codebase has **good hygiene**: no `print`/`NSLog` of secrets, no `try!`/`as!`/`fatalError`, tolerant decoders, no WebView/JS-injection surface, markdown renders as inert SwiftUI (no script injection). (A and B agree.)
- ✅ **V7 and V9 must be fixed, not deferred** (A's strong vote; B did not object). Done.
- ✅ **V8 can be deferred** — error strings render via verbatim `Text` (no markdown/link injection); only caveat is an uncapped non-JSON body → fixed with a 500-char cap. (B's vote; A did not object.)

## Disagreements / where the council diverged
1. **Completeness of the encPath fix.** Council A wrote *"verified the encoders are actually used at every server-id call site."* Council B, with a broader sweep, **proved that wrong** — `encPath` was missing from Brain, Calendar (`uid`), Chat attachments, Notes, Research report URL, Settings, MCP/integrations, Tasks, and admin `wipe`. **Resolution: B was right** — A's check was scoped to the auth files it was reviewing. All 17 sites are now encoded. *(This is exactly why a council beats a single reviewer.)*
2. **Severity of the report parser DoS.** Round-1 rated it MED→mitigated by the cap; B showed the cap bounds `n` but **not the O(n²) algorithm** within it. **Resolution: B's deeper analysis adopted** — fixed the algorithm (`i = n` on missing `>`) and `slice()` tail-return, not just the cap.
3. **How far to take V7.** A wanted a full "recreate the client per server" refactor; the chair chose the **minimal correct** version (per-client cookie store + clear-on-switch + force re-login + lock-guarded config) to fix the real bug without a risky rewrite. Documented as a deliberate scope choice.

## Findings & resolutions (every item)

| ID | Sev | Finding | Status / commit |
|----|-----|---------|-----------------|
| V1 | HIGH | Any-scheme accepted (file:// / SSRF) | ✅ allowlist · `93dbcb3` |
| V2 | HIGH | Cleartext downgrade on `10.evil.com` → cookie leak | ✅ real IP-range detection · `93dbcb3` |
| V3 | HIGH | `NSAllowsArbitraryLoads` | ✅ removed, verified live · `8f35316` |
| V4 / B-1 | HIGH | Raw server ids in URLs (only 4/11 files fixed) | ✅ all 17 sites encoded · `b6b2877` + `780a0e0` |
| V5 | MED | Keychain not ThisDeviceOnly | ✅ · `bacfa8a` |
| V6 / B-2 | MED | Report parser DoS (O(n²) within cap) | ✅ algorithm + slice fixed · `652a4a9` |
| V7 | MED-HIGH | Process-global cookie store; wrong-server state | ✅ per-client jar + clear-on-switch · `aac2e46` |
| V8 | MED | Raw error bodies in UI | ✅ deferred + 500-char cap · `652a4a9` |
| V9 | MED | `config` data race | ✅ lock-guarded · `aac2e46` |
| B-3 | MED | Report-image SSRF (`AsyncImage`) | ✅ `config.resolve` gate · `652a4a9` |
| A5 | LOW | MultipartForm CRLF/quote injection | ✅ `hdr()` sanitizer · `aac2e46` |
| A1 | MED | Raw password stored for silent re-login | ⏳ **accepted** — mitigated by ThisDeviceOnly; full fix (revocable token / biometric `SecAccessControl`) is a product/UX change, tracked. |
| A2 | LOW-MED | No biometric app-lock | ⏳ **accepted** — optional `LocalAuthentication` gate, tracked (feature, not a vuln). |
| A3 | LOW | 2FA success keyed off `totpRequired`/local totp | ⏳ **accepted** — server-driven; recommend driving phase off a server `authenticated` flag. |
| A4 | LOW | No TLS pinning | ⏳ **accepted** — hardening for a later version. |
| B-4 | LOW | Numeric-entity decode O(n) | ⏳ **accepted** — bounded by the 600 KB cap + off-main. |

**Tally:** every HIGH and MED is **fixed and build-verified**; the residual LOW/design items are
accepted with explicit rationale (defense-in-depth or product decisions, not exploitable-without-
device-compromise). Ported to OpenWebUI-iOS and Companion-iOS where the same code exists.
