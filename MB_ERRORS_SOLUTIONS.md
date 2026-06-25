# MB_ERRORS_SOLUTIONS — errors → causes → fixes (memory bank)

> Each entry: error · probable cause · solution · related commit · validating test · status.

## Carried-over lessons (pre-V1, still relevant)
- **`POST /api/model-endpoints` → 422 "base_url: Field required"** · cause: sent JSON, endpoint
  uses FastAPI `Form(...)` · fix: send `application/x-www-form-urlencoded` · status: ✅ fixed previously.
- **Integration create → 422 "Integration base URL is required"** · cause: body used `url` ·
  fix: CalDAV/CardDAV use `base_url` · status: ✅ fixed previously.
- **`.ody(size:…)` → "argument 'weight' must precede 'design'"** · fix: order `size, weight, design` · status: ✅ pattern documented in CLAUDE.md.
- **macOS sandbox swallows in-app shape dumps** (no `/tmp`, no `log show`) · fix: render to a
  temp on-screen `Text` + screenshot, or GET `/openapi.json` · status: ✅ technique documented.

## V1 finalization (this effort)

- **ComfyUI status showed "offline" though `curl` reached it (37 ms)** · error `-1009`
  NSURLErrorNotConnectedToInternet on the **first** LAN connection · cause: macOS **Local
  Network privacy** — the OS returns -1009 on the first attempt to a private-range host while it
  evaluates/awaits the permission grant (the main internet server worked, only the LAN IP failed)
  · **fix:** `ComfyUIClient.getJSON` retries once (0.8 s delay) on
  `.notConnectedToInternet`/`.networkConnectionLost` · commit `81e5de7` · **validating test:**
  re-ran "Testar conexão" in-app → status flipped to "online" with full GPU/VRAM/model detail ·
  status: ✅ fixed + verified live.
- **`.ody(size:…, design:…, weight:…)` compile error** (twice) · order must be
  `size, weight, design` · fix applied in `DiffusionServersView` + `SettingsAdminSections` ·
  status: ✅ (pattern already in CLAUDE.md).
- **3.9 GB build dirs untracked, `git add .` would bloat the snapshot** · fix: `.gitignore`
  `build-*/` before staging · commit `738d1a2` · status: ✅.

### Red-team round 2 (independent Opus sub-agent) — real vulns fixed
- **Cleartext cookie leak** · `ServerConfig` "is-local" used string prefixes → `10.evil.com`
  downgraded to http, leaking the session cookie · fix: parse real IPv4/IPv6 private ranges +
  scheme allowlist (http/https only) · `93dbcb3` · ✅.
- **SSRF / file:// smuggling** · normalize/resolve accepted any scheme · fix: allowlist · `93dbcb3` · ✅.
- **Path/param smuggling via server ids** · raw interpolation of uid/session/research/gallery ids ·
  fix: `encPath`/`encQuery` · `b6b2877` · ✅.
- **Password migratable via iCloud Keychain** · fix: `…ThisDeviceOnly` · `bacfa8a` · ✅.
- **Report-parser DoS on hostile HTML** · fix: 600 KB input cap · `bacfa8a` · ✅.
- **ATS blanket cleartext** · fix: drop `NSAllowsArbitraryLoads`, keep `NSAllowsLocalNetworking`;
  **verified live** LAN ComfyUI still connects · `8f35316` · ✅.
- Deferred (documented, stability over churn): per-server cookie store (V7), error redaction (V8),
  APIClient config-race lock (V9). See TEAM_REVIEW.md.
