import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as a status bar accessory app (no dock icon clutter)
        NSApp.setActivationPolicy(.accessory)
        
        // Request notification authorization for stretch, quotes, and 10h reminders
        NotificationService.shared.requestAuthorization()
        
        // Ensure launch at login preference is respected
        if DataManager.shared.settings.launchAtLogin {
            LaunchAtLoginManager.setEnabled(true)
        }
    }
}

@main
struct PomodoroTimetableApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var dataManager = DataManager.shared
    @StateObject private var usageEngine = UsageTrackerEngine.shared
    
    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView()
                .environmentObject(dataManager)
                .environmentObject(usageEngine)
        } label: {
            HStack(spacing: 4) {
                Text(usageEngine.menuBarTitle)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
