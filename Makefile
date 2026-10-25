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
	@pkill -TERM -f "MacUsageTracker" 2>/dev/null || true
	@sleep 0.3
	@pkill -9 -f "PomodoroTimetable" 2>/dev/null || true
	rm -rf /Applications/MacUsageTracker.app /Applications/PomodoroTimetable.app
	cp -R MacUsageTracker.app /Applications/
	@echo "✅ Installed MacUsageTracker.app to /Applications"
	open /Applications/MacUsageTracker.app
	@echo "🚀 Launched MacUsageTracker from /Applications"

uninstall:
	@pkill -f "MacUsageTracker" 2>/dev/null || true
	@pkill -f "PomodoroTimetable" 2>/dev/null || true
	rm -rf /Applications/MacUsageTracker.app /Applications/PomodoroTimetable.app
	@echo "🗑️ Removed MacUsageTracker.app from /Applications"

clean:
	rm -rf .build PomodoroTimetable.app MacUsageTracker.app
