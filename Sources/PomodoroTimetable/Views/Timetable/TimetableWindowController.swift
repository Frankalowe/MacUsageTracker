import AppKit
import SwiftUI

@MainActor
public final class TimetableWindowController: NSObject, NSWindowDelegate {
    public static let shared = TimetableWindowController()
    
    private var window: NSWindow?
    
    public override init() {
        super.init()
    }
    
    public func showWindow() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let contentView = TimetableMainView()
            .environmentObject(DataManager.shared)
            .environmentObject(PomodoroEngine.shared)
        
        let hostingController = NSHostingController(rootView: contentView)
        
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1150, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        newWindow.title = "Weekly Timetable & Planner"
        newWindow.titlebarAppearsTransparent = false
        newWindow.titleVisibility = .visible
        newWindow.minSize = NSSize(width: 850, height: 550)
        newWindow.contentViewController = hostingController
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        
        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    public func windowWillClose(_ notification: Notification) {
        // Keep controller ready to reopen anytime
    }
}
