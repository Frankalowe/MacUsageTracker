import AppKit
import SwiftUI

@MainActor
public final class TimerHistoryWindowController: NSObject, NSWindowDelegate {
    public static let shared = TimerHistoryWindowController()
    
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
        
        let contentView = TimerHistoryView()
            .environmentObject(DataManager.shared)
            .environmentObject(UsageTrackerEngine.shared)
        
        let hostingController = NSHostingController(rootView: contentView)
        
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        newWindow.title = "Mac Usage History (Monthly Analysis)"
        newWindow.minSize = NSSize(width: 580, height: 520)
        newWindow.contentViewController = hostingController
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        
        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    public func closeWindow() {
        window?.close()
        window = nil
    }
    
    public func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
