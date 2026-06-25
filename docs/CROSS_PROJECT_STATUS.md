# CROSS_PROJECT_STATUS — Projetos/ review (2026-06-24)

Status of the "same treatment for the other projects" pass. Done = real, committed work.
Backups for anything touched live in `_backups/`.

## Git repos

| Project | State | What was done | Next |
|---------|-------|---------------|------|
| **Odysseus-iOS** | ✅ full | REGRA ZERO + 16 docs + diffusion feature (live-tested) + **red/blue: 6 real vulns fixed (3 HIGH)** + SVGs + **push-safe** + iOS/macOS parity verified. Branch `v1-macos-finalization`, tag `v1-macos-ready`. | App Store (manual), S6/S8 decisions done; deep e2e flows + diffusion phase later. |
| **OpenWebUI-iOS** | ✅ security port | Same fork → **same vulns**. Ported the URL scheme-allowlist + real private-IP detection (cleartext Bearer-token leak), `encPath` at all server-id sites, dropped `NSAllowsArbitraryLoads`. `OpenWebUIKit` package **builds clean**. Branch `security-url-hardening`, tag `pre-security-fix-snapshot`, `SECURITY_NOTES.md`. Team id already safe (`${DEVELOPMENT_TEAM}`). | Full-app build pending SPM/whisper DNS flush; per-server token isolation deferred. |
| **ZaoIMEKeyboard** | ⚠️ needs you | Only pending change is a **deletion of `Models/model.safetensors`** (LFS pointer, ~968 MB). Not mine; intent unknown. **Not committed.** | Confirm: intentional removal vs accidental? Then commit or `git restore`. |
| **ZaoSemanticIME** | ⚠️ needs you | Same: pending **deletion of `ios/.../model.safetensors`** (LFS pointer, ~869 MB). **Not committed.** | Same confirmation needed. |

## Not git repos (need REGRA ZERO = `git init` + curated `.gitignore` + first commit)
Doing this blindly risks committing big model files / secrets, so each needs a quick review
first (gitignore build artifacts + scan for team id / LAN IP / tokens, exactly like Odysseus).

| Project | Notes |
|---------|-------|
| **Companion-iOS** | Voice companion; fork of the Open WebUI iOS app → likely the **same URL vulns** to port once under git. |
| **Companion-Android** | Kotlin/Compose port. |
| **OpenWebUI-Android** | Kotlin/Compose multi-tab client. |
| **ZaoCast** | macOS scrcpy/adb GUI. |
| **ZhaoHub-Android** | Kotlin/Compose ERP client (cookie-sid auth — review auth handling). |
| **MacrozaoHQ** | ⛔ OUT OF SCOPE — do not touch (user rule). |

## Recommended order for a follow-up session
1. Confirm the two model-deletion intents (ZaoIME / ZaoSemantic) and commit accordingly.
2. REGRA ZERO + URL-vuln port for **Companion-iOS** (highest value — shares the Open WebUI core).
3. REGRA ZERO for the Android repos + ZaoCast; review auth (ZhaoHub cookie-sid) and secrets.
4. Push decisions per repo (each remote may be public — sanitize first, like Odysseus S1/S3/S7).
