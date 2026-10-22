.PHONY: build release bundle run clean

build:
	swift build

release:
	swift build -c release

bundle:
	./scripts/bundle.sh release

run: bundle
	open PomodoroTimetable.app

clean:
	rm -rf .build PomodoroTimetable.app
