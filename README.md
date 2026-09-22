<p align="center">
  <img src="Tempo-icon.png" width="128" height="128" alt="Tempo icon">
</p>

<h1 align="center">Tempo</h1>

<p align="center">
  A local-first focus timer, kanban board, and private work history for macOS.
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README-ZH.md">简体中文</a>
</p>

<p align="center">
  <img alt="macOS 26+" src="https://img.shields.io/badge/macOS-26%2B-000000?logo=apple&logoColor=white">
  <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple%20Silicon-arm64-555555">
  <img alt="SwiftUI" src="https://img.shields.io/badge/SwiftUI-native-F05138?logo=swift&logoColor=white">
  <a href="LICENSE"><img alt="License: CC BY-NC 4.0" src="https://img.shields.io/badge/License-CC%20BY--NC%204.0-lightgrey.svg"></a>
</p>

Tempo is a native macOS productivity app. The pomodoro clock, task boards, session history, and statistics stay on this Mac. Nothing is uploaded.

It is built by **[Crows-Storm](https://github.com/Crows-Storm)** as a clean-room native rewrite inspired by [Pomodoro Logger](https://github.com/zxch3n/PomodoroLogger). Tempo is not a fork, does not reuse that project’s Electron UI or GPL source, and ships under a different license.

## Features

**Focus**
- Classic pomodoro cycle: 25-minute focus, 5-minute short break, 15-minute long break every 4 focus sessions (all adjustable)
- Start, pause, switch phase, complete, cancel, and extend by 5 or 10 minutes
- Bind a running session to a board, a card, or neither; hours attach only to the selected card
- Immersive session: Tempo hides its own sidebar chrome while you work and restores it when idle
- Mini timer window and a menu-bar timer (template glyph, not the colorful app icon)
- A session counts as a pomodoro if it finishes naturally **or** you complete it after at least 10 minutes; shorter manual completes are kept as history but marked rotten

**Tasks**
- Kanban boards with custom columns, In Progress and Done roles, pin, archive, and search
- Cards with title, estimated hours, actual hours, and Markdown notes
- Drag cards between columns; boards archive when every card is done

**History and statistics**
- History is a calendar of sessions: heatmap, pomodoro counts, and a Sankey of app / window flow
- Statistics is trend and application mix, not the same view as History
- Overview is a separate home for boards and recent work

**Privacy**
- SwiftData library and activity log live under Application Support on this Mac
- App Sandbox is on; hardened runtime is on
- During a running focus, Tempo samples the frontmost app name. Window titles are read only if Accessibility is already granted. Tempo never auto-prompts for Accessibility; Settings can open System Settings so you can grant it yourself
- Optional distraction rules feed an efficiency score (share of samples that did not match the list)

**System**
- Languages: follow the system, English, Simplified Chinese, Japanese
- Appearance: system, light, or dark
- Launch at login, notifications, and sounds are optional
- First launch can merge an existing Pomodoro Logger or older Tempo library without deleting the original folders

## Requirements

- macOS 26.0 or later
- Apple Silicon
- Xcode 26 or later to build from source
- Bundle identifier: `app.tempo.macos`

## Build

```sh
git clone git@github.com:Crows-Storm/Tempo.git
cd Tempo
open Tempo.xcodeproj
```

In Xcode, select the **Tempo** scheme and Run (`⌘R`).

From the command line:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project Tempo.xcodeproj -scheme Tempo \
  -destination 'platform=macOS,arch=arm64' build
```

Run tests:

```sh
xcodebuild -project Tempo.xcodeproj -scheme Tempo \
  -destination 'platform=macOS,arch=arm64' test
```

## Package a DMG

Build a Release app and wrap it in a drag-to-Applications disk image:

```sh
chmod +x scripts/make-dmg.sh
./scripts/make-dmg.sh
```

The image is written to `build/dmg/Tempo-1.0.0.dmg` (version follows `CFBundleShortVersionString`). Double-click it: **Tempo** is on the left, **Applications** on the right. Drag the app onto the folder, then eject.

This project uses **ad-hoc signing** (`CODE_SIGN_IDENTITY = "-"`). The disk image does not contain an Apple Developer name, Team ID, or Apple ID. Recipients will see Gatekeeper’s unidentified-developer warning and can right-click the app and choose **Open**.

Notarizing with a Developer ID would attach *your* identity to the binary and upload a hash to Apple. Skip that if you want the opposite of a public developer identity.

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| Start or pause | Space |
| Switch focus or break (idle) | ⌥⌘S |
| Complete | ⇧⌘S |
| Cancel session | ⇧⌘. |
| New card | ⌘N |
| New board | ⇧⌘N |
| Find | ⌘F |
| Settings | ⌘, |
| Overview / Focus / Tasks / History / Statistics | ⌘1 … ⌘5 |
| Keyboard shortcuts sheet | ⇧⌘? |

## Data

| What | Where |
| --- | --- |
| Boards, cards, sessions | `~/Library/Application Support/Tempo/Tempo.store` |
| Activity samples | `~/Library/Application Support/Tempo/activity.sqlite` |
| Settings and clock | UserDefaults (`tempo.settings`, `tempo.clock`) |

Closing the last window does not quit Tempo (menu-bar app). Clicking the Dock icon reopens the main window.

### Import

On first launch Tempo looks for:

- `~/Library/Preferences/PomodoroLogger/db`
- `~/Library/Application Support/Tempo/db`

Matching records are merged in. Source directories are not deleted. A marker file records that import already ran.

## Project layout

```
App/                 Windows, app model, icon, entitlements
Core/                Timer, settings, analytics, import, domain rules
Features/            Overview, Focus, Tasks, History, Statistics, Settings, menu bar
Infrastructure/      SwiftData, activity probe, macOS chrome, notifications
Shared/              Design system, localization
TempoTests/          XCTest coverage for timer, import, charts, and session rules
scripts/             Icon Composer asset helper
```

AppKit is used only where SwiftUI cannot reach native macOS behavior (menu bar extra, settings window, Accessibility, Dock / activation policy). The rest of the UI is SwiftUI.

## License

Copyright © 2026 **Crows-Storm**.

This project is licensed under [Creative Commons Attribution-NonCommercial 4.0 International](https://creativecommons.org/licenses/by-nc/4.0/) (CC BY-NC 4.0). See [LICENSE](LICENSE).

In short:

- You may copy, share, and adapt Tempo **for non-commercial purposes**
- You must give appropriate credit to Crows-Storm
- You may **not** use the material for commercial advantage or monetary compensation without a separate permission
- Patent and trademark rights are not licensed

## Credits

- **Crows-Storm** — design and development of Tempo
- [zxch3n/PomodoroLogger](https://github.com/zxch3n/PomodoroLogger) — the project Tempo pays tribute to. Pomodoro Logger remains its own GPL-licensed Electron app; Tempo is a separate native implementation
- Apple Human Interface Guidelines — layout, settings, motion, and macOS chrome

## Repository

https://github.com/Crows-Storm/Tempo
