# Mac Usage Tracker for macOS 💻⏱️

A native macOS status bar menu application that automatically tracks your active MacBook work time by detecting when your Mac wakes up or boots and when it sleeps or shuts down. No manual timers, no periodic resets, and zero configuration needed.

---

## 🌟 Key Features

### 💻 Automatic Wake & Sleep Tracking
* **Zero-Intervention Counting:** Automatically starts counting uptime when your Mac turns on or wakes up (`didWakeNotification`), and records the period when your Mac goes to sleep (`willSleepNotification`) or shuts down.
* **Live Status Bar Counter:** Displays live uptime in the macOS menu bar (e.g. `💻 1h 24m`), counting up continuously while your Mac is awake.
* **1-Minute Filter:** Automatically filters out accidental lid opens or brief wake glitches under 60 seconds.

### 🕒 7-Day Usage Retention & Auto-Purge
* **Strict 7-Day Storage:** Stores all wake-to-sleep usage periods locally for exactly 7 days.
* **Automatic Purging:** Any session older than 7 days is automatically deleted on launch and hourly.
* **Interactive 7-Day History Window:**
  * Total 7-day screen time, session count, and daily average.
  * Day-by-day interactive bar chart.
  * Chronological session timelines showing exact start & end times (e.g., `09:15 AM – 11:42 AM`) and duration (`2h 27m`).
  * Day filtering to isolate any day's sessions.

### 🔔 Smart Reminders & Motivators
* **🧘 90-Minute Stretch & Hydrate:** Every 90 minutes of active continuous work, sends a notification reminder to stretch, look away from the display, and hydrate.
* **⚡ 60-Minute Motivational Quotes:** Every 60 minutes of active work, sends a curated quote from leaders and authors to inspire and keep your momentum going forwards.
* **🌙 10-Hour End of Day Reminder:** When your daily screen time hits 10 hours, sends a reminder to wrap up and rest. If 10 hours is not met, no notification is sent.

### 🚀 Launch at Login
* Automatically registers with macOS (`SMAppService`) to launch upon Mac startup/login so your work hours are tracked effortlessly from the moment you turn on your laptop.

---

## 🚀 Quick Start

### Run the App
To compile and launch the application directly:
```bash
make run
```
or launch the prebuilt app bundle:
```bash
open MacUsageTracker.app
```

The `💻` icon with live uptime will appear in your macOS status menu bar.

---

## 🛠️ Build Commands

| Command | Description |
| :--- | :--- |
| `make build` | Builds the debug binary with Swift Package Manager |
| `make release` | Builds an optimized release binary |
| `make bundle` | Packages the application into `MacUsageTracker.app` (`LSUIElement = YES`) |
| `make run` | Builds the release app bundle and launches it |
| `make clean` | Removes build artifacts and bundle |
