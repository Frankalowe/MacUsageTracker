// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PomodoroTimetable",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "PomodoroTimetable",
            targets: ["PomodoroTimetable"]
        )
    ],
    targets: [
        .executableTarget(
            name: "PomodoroTimetable",
            path: "Sources/PomodoroTimetable"
        )
    ]
)
