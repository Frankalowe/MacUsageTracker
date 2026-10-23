.PHONY: build release bundle run install uninstall clean

build:
	swift build

release:
	swift build -c release

bundle:
	./scripts/bundle.sh release

run: bundle
	open PomodoroTimetable.app

install: bundle
	rm -rf /Applications/PomodoroTimetable.app
	cp -R PomodoroTimetable.app /Applications/
	@echo "✅ Installed PomodoroTimetable.app to /Applications"

uninstall:
	rm -rf /Applications/PomodoroTimetable.app
	@echo "🗑️ Removed PomodoroTimetable.app from /Applications"

clean:
	rm -rf .build PomodoroTimetable.app
