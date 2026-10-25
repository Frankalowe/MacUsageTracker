.PHONY: build release bundle run install uninstall clean

build:
	swift build

release:
	swift build -c release

bundle:
	./scripts/bundle.sh release

run: bundle
	open MacUsageTracker.app

install: bundle
	@pkill -f "PomodoroTimetable" 2>/dev/null || true
	@pkill -f "MacUsageTracker" 2>/dev/null || true
	rm -rf /Applications/PomodoroTimetable.app
	rm -rf /Applications/MacUsageTracker.app
	cp -R MacUsageTracker.app /Applications/
	@echo "✅ Installed MacUsageTracker.app to /Applications"
	open /Applications/MacUsageTracker.app
	@echo "🚀 Launched MacUsageTracker from /Applications"

uninstall:
	@pkill -f "PomodoroTimetable" 2>/dev/null || true
	@pkill -f "MacUsageTracker" 2>/dev/null || true
	rm -rf /Applications/PomodoroTimetable.app
	rm -rf /Applications/MacUsageTracker.app
	@echo "🗑️ Removed PomodoroTimetable.app and MacUsageTracker.app from /Applications"

clean:
	rm -rf .build PomodoroTimetable.app MacUsageTracker.app
