import SwiftUI
import AppKit

public struct ToastNotificationData: Identifiable, Equatable {
    public let id = UUID()
    public let title: String
    public let subtitle: String?
    public let body: String
    public let icon: String
    
    public init(title: String, subtitle: String? = nil, body: String, icon: String = "bolt.fill") {
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.icon = icon
    }
}

public struct ToastNotificationView: View {
    let data: ToastNotificationData
    let onDismiss: () -> Void
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header Row: App Icon + App Name + "now" + Close Button (macOS native style)
            HStack(spacing: 6) {
                // Mini App Icon with Light Green Accent
                ZStack {
                    RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.25, green: 0.85, blue: 0.55), Color(red: 0.12, green: 0.68, blue: 0.4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 18, height: 18)
                    Image(systemName: data.icon)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                }
                
                Text("Mac Usage Tracker")
                    .font(.system(size: 12, weight: .semibold, design: .default))
                    .foregroundColor(.secondary)
                
                Text("• now")
                    .font(.system(size: 11, weight: .regular, design: .default))
                    .foregroundColor(.secondary.opacity(0.7))
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(4)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            
            // Notification Title (San Francisco 13pt semibold)
            Text(data.title)
                .font(.system(size: 13, weight: .semibold, design: .default))
                .foregroundColor(.primary)
                .lineLimit(1)
            
            // Subtitle (if available) with light green accent
            if let sub = data.subtitle, !sub.isEmpty {
                Text(sub)
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundColor(Color(red: 0.2, green: 0.78, blue: 0.48))
                    .lineLimit(1)
            }
            
            // Message Body (San Francisco 12pt regular - matches native macOS notifications)
            Text(data.body)
                .font(.system(size: 12, weight: .regular, design: .default))
                .foregroundColor(.primary.opacity(0.9))
                .lineSpacing(2.5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(width: 350)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(red: 0.25, green: 0.85, blue: 0.55).opacity(0.35), lineWidth: 1)
        )
        .shadow(color: Color(red: 0.15, green: 0.8, blue: 0.45).opacity(0.12), radius: 8, x: 0, y: 2)
        .shadow(color: Color.black.opacity(0.24), radius: 16, x: 0, y: 8)
    }
}

@MainActor
public final class ToastNotificationWindowController {
    public static let shared = ToastNotificationWindowController()
    
    private var panel: NSPanel?
    private var dismissTimer: Timer?
    
    private init() {}
    
    public func showToast(title: String, subtitle: String? = nil, body: String, icon: String = "bolt.fill") {
        dismissTimer?.invalidate()
        dismissTimer = nil
        
        let data = ToastNotificationData(title: title, subtitle: subtitle, body: body, icon: icon)
        
        let toastView = ToastNotificationView(data: data) { [weak self] in
            self?.dismissToast()
        }
        
        let hostingView = NSHostingView(rootView: toastView)
        let fittingSize = hostingView.fittingSize
        let toastWidth: CGFloat = 350
        let toastHeight: CGFloat = max(90, fittingSize.height)
        hostingView.frame = NSRect(x: 0, y: 0, width: toastWidth, height: toastHeight)
        
        if panel == nil {
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: toastWidth, height: toastHeight),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.isFloatingPanel = true
            // Elevated popup level to float above full screen apps, modal sheets, and menu bars
            p.level = .popUpMenu
            p.backgroundColor = .clear
            p.isOpaque = false
            p.hasShadow = false
            p.hidesOnDeactivate = false
            // .fullScreenAuxiliary allows displaying over native full-screen apps and Do Not Disturb sessions
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            self.panel = p
        }
        
        guard let p = panel else { return }
        p.contentView = hostingView
        p.setContentSize(NSSize(width: toastWidth, height: toastHeight))
        
        // Position at top-right of the active screen, immediately below menu bar (matching macOS system notification alignment)
        let mouseLoc = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) }) ?? NSScreen.main ?? NSScreen.screens.first
        if let screen = targetScreen {
            let screenRect = screen.visibleFrame
            let x = screenRect.maxX - toastWidth - 16
            let y = screenRect.maxY - toastHeight - 12
            p.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        p.alphaValue = 0.0
        p.orderFrontRegardless()
        
        // Sound & Animation (Direct CoreAudio sound bypasses DND muting)
        if !(NSSound(named: "Glass")?.play() ?? false) {
            NSSound.beep()
        }
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            p.animator().alphaValue = 1.0
        }
        
        // Auto-dismiss after 6 seconds
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.dismissToast()
            }
        }
    }
    
    public func dismissToast() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        
        guard let p = panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            p.animator().alphaValue = 0.0
        }, completionHandler: {
            DispatchQueue.main.async {
                p.orderOut(nil)
            }
        })
    }
}
