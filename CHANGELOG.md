# Changelog

## [1.1] — 2026-06-28

### Added
- **Deep Research, rebuilt**: live step-by-step graph, configurable search modes, a visual
  report that opens side by side, and history of past research (save and resume).
- **Cookbook**: browse and install packages and engines, with live status.
- **Compare**: ask the same question to two models side by side, streaming at once.
- **Tasks**: scheduled agents (cron/event) — view status, run now, pause, and resume.
- **Add models from the phone**: connect endpoints and enable, disable, or remove models
  without a computer.
- **Localization**: Portuguese, English, Japanese, Hindi, and Bengali, with automatic
  device-language detection (Settings › Language).

### Fixed
- **Session not persisting**: the session cookie was silently dropped (a non-shared
  `HTTPCookieStorage` instance), so the app asked to log in on every launch and
  authenticated screens failed with "session expired". Switched to
  `HTTPCookieStorage.shared` and persist the session across launches — sessions now stick
  and authenticated data loads correctly.
- **Theming in menus/sheets**: every theme is now applied consistently (no more dark menus
  on light themes or mismatched system selectors).
- Various stability and polish fixes.

### Release
- iOS app bumped to **1.1 (build 3)**.

## [1.0] — 2026-06

Initial release.

- Native SwiftUI client for a self-hosted Odysseus AI server — iPhone, iPad, and Mac
  from one codebase (no WebView).
- Login (username/password + optional 2FA), server switching, persistent session.
- Native streaming chat (Markdown, code blocks, reasoning blocks), Web/Deep/Agent toggles,
  attachments & vision.
- Spaces: Brain, Notes, Calendar, Gallery, Email (IMAP/SMTP), Tasks, Library (RAG),
  Compare, Cookbook.
- On-device voice: native STT + Whisper (Neural Engine), native TTS + neural PocketTTS.
- Native admin Settings (models, AI defaults, search, integrations, image generation,
  appearance with 17 themes, account, server).
