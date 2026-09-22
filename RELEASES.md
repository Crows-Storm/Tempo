# Releases

Copy the version section below into the GitHub Release body. Attach the local `build/dmg/Tempo-<version>.dmg` and tag `v<version>`.

Current version: **1.0.0** (build 2)  
Date: 22 September 2026  
Repository: https://github.com/Crows-Storm/Tempo

---

## Tempo 1.0.0

A local-first native macOS focus app: pomodoro timer, kanban boards, and private history. Nothing is uploaded.

Built by [Crows-Storm](https://github.com/Crows-Storm). Inspired by [Pomodoro Logger](https://github.com/zxch3n/PomodoroLogger); this is a separate SwiftUI app, not a fork and not GPL/Electron source.

### Install

1. Download `Tempo-1.0.0.dmg`
2. Open the image: **Tempo** on the left, **Applications** on the right
3. Drag Tempo into Applications and eject
4. First launch: **right-click → Open** (unidentified developer is expected; this build is ad-hoc signed and does not embed an Apple ID, Team ID, or developer name)

### Requirements

- macOS 26.0 or later
- Apple Silicon
- Bundle ID: `app.tempo.macos`

### In this release

- Pomodoro cycle with adjustable focus / short break / long break
- Start, pause, switch, complete, cancel, extend 5 or 10 minutes
- Bind a session to a board, a card, or neither; hours attach only to the selected card
- Immersive session hides Tempo chrome; idle restores it
- Menu bar timer and mini timer window
- Counts as a pomodoro on natural finish, or complete after at least 10 minutes
- Boards, custom columns, Markdown cards, drag and drop, pin, archive
- History heatmap, pomodoro counts, and app / window flow
- Statistics as a separate trend view
- Overview home
- English, Simplified Chinese, Japanese, or follow the system
- System / light / dark appearance
- Optional login item, notifications, sounds, distraction rules
- Optional import from Pomodoro Logger or an older Tempo library
- App Sandbox; frontmost app sampling; window titles only if Accessibility is already granted

### Asset

| File | Notes |
| --- | --- |
| `Tempo-1.0.0.dmg` | Drag-to-Applications image (ad-hoc signed) |

Build locally with `./scripts/make-dmg.sh` → `build/dmg/Tempo-1.0.0.dmg`.

### License

[CC BY-NC 4.0](LICENSE) · Copyright © 2026 Crows-Storm  
Non-commercial use with attribution.
