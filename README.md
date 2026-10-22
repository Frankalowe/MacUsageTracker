# Pomodoro Timetable for macOS 🍅📅

A native macOS status menu application featuring an integrated Pomodoro timer in the status bar and an interactive weekly timetable planner for day-to-day focus and recurring weekly work.

---

## 🌟 Key Features

### 🍅 Status Menu & Pomodoro Timer
* **Dynamic Menu Bar Item:** Displays an idle icon `🍅` when inactive, and a countdown timer (`🍅 24:35` or `☕️ 04:50`) during active focus and break sessions.
* **Smart Context Tracking:** Automatically detects your currently scheduled timetable block and links your active Pomodoro session to it.
* **Interval Modes:** Support for **Focus (25m)**, **Short Break (5m)**, and **Long Break (15m)** with animated progress rings.
* **Semi-Automated Session Flow:** Plays an audio chime and sends native macOS notifications upon session completion, pausing to wait for you before beginning the next cycle.
* **Today's Agenda Snapshot:** Quick view of today's schedule directly from the menu bar popover.

### 📅 Advanced Weekly Timetable Planner
* **Dedicated Standalone Window:** Launches via *"Open Timetable Planner ↗"* without closing when you click away.
* **Visual Time-Blocking Grid:** 7-day visual calendar grid (Mon–Sun) with vertical hourly timeline (07:00 – 22:00) and current-time red indicator line.
* **Flexible Recurrence Engine:** Schedule blocks to repeat **Daily**, on **Weekdays (Mon–Fri)**, or on **Custom Selected Days** of the week.
* **Pomodoro Target Estimation & Progress:** Set estimated Pomodoros per block (e.g. 4 sessions) and track completion (`🍅 2/4`) with check-off status.
* **Color-Coded Categories & Tags:** Deep Work, Meetings, Study & Learning, Admin & Email, Wellness & Exercise, plus custom categories.
* **Auto-Pad Buffer & Breaks:** Automatically insert 10m or 15m buffer gaps between contiguous blocks to prevent burnout.
* **Quick Block Creation:** Double-click any hourly slot on the grid to create a time block snapped to that hour.

---

## 🚀 Quick Start

### Run the App
To compile and launch the application directly:
```bash
make run
```
or launch the prebuilt app bundle:
```bash
open PomodoroTimetable.app
```

The `🍅` icon will appear in your macOS status menu bar.

---

## 🛠️ Build Commands

| Command | Description |
| :--- | :--- |
| `make build` | Builds the debug binary with Swift Package Manager |
| `make release` | Builds an optimized release binary |
| `make bundle` | Packages the application into `PomodoroTimetable.app` with `LSUIElement = YES` (status bar accessory) |
| `make run` | Builds the release app bundle and launches it |
| `make clean` | Removes build artifacts and bundle |

---

## 🏗️ Architecture & Tech Stack

* **Language:** Swift 6.0
* **UI Framework:** SwiftUI & AppKit (`MenuBarExtra`, `NSWindowController`, `NSHostingController`)
* **Persistence:** Local JSON store in `~/Library/Application Support/PomodoroTimetable/data.json` with automatic fallback to rich default developer routines.
* **Notifications:** Native `UserNotifications` and `NSSound`.
* **State Management:** Reactive MVVM architecture with `ObservableObject` and `@Published` Combine pipelines.
