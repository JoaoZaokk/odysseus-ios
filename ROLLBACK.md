# ROLLBACK — Odysseus V1 macOS finalization

This file is the safety anchor created by **REGRA ZERO** before the V1 finalization work began.
If anything goes wrong, you can return the project to the exact pre-work state.

## Snapshot facts (2026-06-24)

| Item | Value |
|------|-------|
| Repo | `/Users/joaozao/Projetos/Odysseus-iOS` |
| Remote | `origin` → `github.com/JoaoZaokk/odysseus-ios.git` (sanitized public mirror — **do not push without sanitization**) |
| Branch before work | `main` |
| Snapshot commit | `738d1a2` — *chore: snapshot current project state before V1 finalization* |
| Previous commit | `377cf9c` — *Odysseus iOS — cliente nativo SwiftUI (PolyForm Noncommercial)* |
| Rollback tag | `pre-v1-finalization-snapshot` |
| Work branch | `v1-macos-finalization` |
| Folder backup | `/Users/joaozao/Projetos/_backups/Odysseus-iOS-pre-v1-20260624/` (160 MB, source + `.git`, build artifacts excluded) |
| Full-history bundle | `/Users/joaozao/Projetos/_backups/Odysseus-iOS-pre-v1-20260624.bundle` (872 KB) |

## How to roll back

### Option A — reset `main` to the snapshot (discards all V1 work)
```bash
cd /Users/joaozao/Projetos/Odysseus-iOS
git checkout main
git reset --hard pre-v1-finalization-snapshot
git branch -D v1-macos-finalization   # optional: drop the work branch
```

### Option B — just abandon the work branch, keep main untouched
```bash
cd /Users/joaozao/Projetos/Odysseus-iOS
git checkout main          # main was never moved past the snapshot
```
(`main` still points at `738d1a2`; the work happened only on `v1-macos-finalization`.)

### Option C — restore from the folder backup (if the repo itself is damaged)
```bash
rm -rf /Users/joaozao/Projetos/Odysseus-iOS-broken
mv /Users/joaozao/Projetos/Odysseus-iOS /Users/joaozao/Projetos/Odysseus-iOS-broken
cp -a /Users/joaozao/Projetos/_backups/Odysseus-iOS-pre-v1-20260624 /Users/joaozao/Projetos/Odysseus-iOS
cd /Users/joaozao/Projetos/Odysseus-iOS && xcodegen generate
```

### Option D — restore full history from the bundle
```bash
git clone /Users/joaozao/Projetos/_backups/Odysseus-iOS-pre-v1-20260624.bundle Odysseus-iOS-restored
```

## After any rollback
Regenerate the Xcode project (it is gitignored):
```bash
cd /Users/joaozao/Projetos/Odysseus-iOS && xcodegen generate
```

## Notes
- `.gitignore` was updated in the snapshot commit to exclude `build-*/` (3.9 GB of local
  build artifacts that must never be committed).
- The work branch commits each fix/feature/doc separately (REGRA ABSOLUTA DE COMMITS).
