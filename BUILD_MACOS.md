# BUILD_MACOS.md — Odysseus build

## Toolchain (2026-06-24, verified)
| Tool | Version |
|------|---------|
| Xcode | 26.4 (17E192) |
| Swift | 6.3 (swiftlang-6.3.0.123.5) |
| XcodeGen | 2.45.4 |
| Targets | `Odysseus` (iOS 17+), `Odysseus-macOS` (macOS 14+) |
| Signing team | from gitignored `Local.xcconfig` (not committed) — see SECURITY_REVIEW S1 |

## Generate project (required after add/remove files — `.xcodeproj` is gitignored)
```bash
cd /Users/joaozao/Projetos/Odysseus-iOS
xcodegen generate
```

## Build commands
```bash
# macOS
xcodebuild -project Odysseus.xcodeproj -scheme Odysseus-macOS -configuration Debug \
  -destination 'platform=macOS' build

# iOS (generic device; no simulator needed for compile-check)
xcodebuild -project Odysseus.xcodeproj -scheme Odysseus -configuration Debug \
  -destination 'generic/platform=iOS' build
```

## Results — work branch `v1-macos-finalization` @ `23e57a3`
| Target | Result |
|--------|--------|
| Odysseus-macOS (Debug) | ✅ **BUILD SUCCEEDED** |
| Odysseus (iOS, Debug) | ✅ **BUILD SUCCEEDED** |

No compile errors on either target. Build artifacts land in
`~/Library/Developer/Xcode/DerivedData/Odysseus-*/Build/Products/Debug/` (gitignored).

## Run the macOS app
```bash
open ~/Library/Developer/Xcode/DerivedData/Odysseus-*/Build/Products/Debug/Odysseus.app
```

## Release / archive (for handoff — see FINAL_HANDOFF.md)
```bash
xcodebuild -project Odysseus.xcodeproj -scheme Odysseus-macOS -configuration Release \
  -destination 'platform=macOS' -archivePath build/Odysseus-macOS.xcarchive archive
```
> App Store **submission** is a manual user step (Apple credentials + outward action) — the
> agent cannot perform it. Archive + export + upload steps are documented in FINAL_HANDOFF.md.

## Notes
- macOS target is sandboxed; entitlements in `Odysseus/Resources/Odysseus-macOS.entitlements`.
- Build directories `build-*/` are local artifacts (3.9 GB) and are gitignored.
