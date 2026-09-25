# Releases

Copy the version section below into the GitHub Release body. Attach the local `build/dmg/Tempo-<version>.dmg` and tag `v<version>`.

Current version: **1.0.4** (build 4)
Date: 25 September 2026
Repository: https://github.com/Crows-Storm/Tempo

---

## Tempo 1.0.4

Patch release on the V1 line. Overview, attention flow, permissions, and task cards.

### Install

1. Download `Tempo-1.0.4.dmg`
2. Open the image: **Tempo** on the left, **Applications** on the right
3. Drag Tempo into Applications and eject
4. First launch: **right-click → Open** (unidentified developer is expected; this build is ad-hoc signed and does not embed an Apple ID, Team ID, or developer name)

### Requirements

- macOS 26.0 or later
- Apple Silicon
- Bundle ID: `app.tempo.macos`

### Changes

- Overview: **Today's focus** replaces Recent — today's pomodoros concatenated into one app lane and one Sankey
- Sankey: hover a node or ribbon to isolate that flow
- Sankey: missing window titles use **Untitled** in the middle column (no app → Focused skip that covers other titles)
- Activity and Sankey ignore system chrome such as loginwindow, Dock, and Control Center
- Settings: On/Off for Accessibility, Screen Recording, and Notifications; Screen Recording is asked so window titles can be read
- Rebuilds re-prompt Accessibility / Screen Recording when the app binary path changes
- Tasks: Markdown checkboxes in the card preview can be toggled; clicking the rest of the card still opens the editor

### Asset

| File              | Notes                                      |
| ----------------- | ------------------------------------------ |
| `Tempo-1.0.4.dmg` | Drag-to-Applications image (ad-hoc signed) |

Build locally with `./scripts/make-dmg.sh` → `build/dmg/Tempo-1.0.4.dmg`.

### License

[CC BY-NC 4.0](LICENSE) · Copyright © 2026 Crows-Storm
Non-commercial use with attribution.

---

## Tempo 1.0.3

Patch release on the V1 line. Same local-first native macOS app; this build fixes History layout, permission prompts, and the session detail page.

### Install

1. Download `Tempo-1.0.3.dmg`
2. Open the image: **Tempo** on the left, **Applications** on the right
3. Drag Tempo into Applications and eject
4. First launch: **right-click → Open** (unidentified developer is expected; this build is ad-hoc signed and does not embed an Apple ID, Team ID, or developer name)

### Requirements

- macOS 26.0 or later
- Apple Silicon
- Bundle ID: `app.tempo.macos`

### Changes

- History: picking another day no longer resizes or recenters the calendar split
- History: session detail no longer lists window titles (apps, attention, and flow stay)
- Accessibility for window titles: system prompt once when a focus starts; if refused, Tempo does not ask again
- Notifications: system prompt once when a session ends; if refused, Tempo does not ask again
- After a refusal, Settings can jump to System Settings to turn the permission on
- README screenshots for the main screens

### Asset

| File              | Notes                                      |
| ----------------- | ------------------------------------------ |
| `Tempo-1.0.3.dmg` | Drag-to-Applications image (ad-hoc signed) |

Build locally with `./scripts/make-dmg.sh` → `build/dmg/Tempo-1.0.3.dmg`.

### License

[CC BY-NC 4.0](LICENSE) · Copyright © 2026 Crows-Storm
Non-commercial use with attribution.

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

| File              | Notes                                      |
| ----------------- | ------------------------------------------ |
| `Tempo-1.0.0.dmg` | Drag-to-Applications image (ad-hoc signed) |

### License

[CC BY-NC 4.0](LICENSE) · Copyright © 2026 Crows-Storm
Non-commercial use with attribution.
