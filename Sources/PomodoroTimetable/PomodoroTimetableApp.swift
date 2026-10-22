import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as a status bar accessory app (no dock icon clutter)
        NSApp.setActivationPolicy(.accessory)
        NotificationManager.shared.requestAuthorization()
    }
}

@main
struct PomodoroTimetableApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var dataManager = DataManager.shared
    @StateObject private var pomodoroEngine = PomodoroEngine.shared
    
    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView()
                .environmentObject(dataManager)
                .environmentObject(pomodoroEngine)
        } label: {
            HStack(spacing: 4) {
                Text(pomodoroEngine.menuBarTitle)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
