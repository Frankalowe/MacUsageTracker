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
        HStack(alignment: .top, spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color.orange, Color.red], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 36, height: 36)
                Image(systemName: data.icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(.top, 2)
            
            // Content
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(data.title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(4)
                            .background(Color.gray.opacity(0.15))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                
                if let sub = data.subtitle, !sub.isEmpty {
                    Text(sub)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
                
                Text(data.body)
                    .font(.system(size: 11, design: .serif))
                    .lineSpacing(2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(width: 340)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1.5)
        )
        .shadow(color: Color.black.opacity(0.25), radius: 16, x: 0, y: 6)
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
        hostingView.frame = NSRect(x: 0, y: 0, width: 340, height: 110)
        
        if panel == nil {
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 340, height: 110),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.isFloatingPanel = true
            p.level = .floating
            p.backgroundColor = .clear
            p.isOpaque = false
            p.hasShadow = false
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            self.panel = p
        }
        
        guard let p = panel else { return }
        p.contentView = hostingView
        
        // Position at top-right of main screen
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let x = screenRect.maxX - 360
            let y = screenRect.maxY - 130
            p.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        p.alphaValue = 0.0
        p.orderFrontRegardless()
        
        // Sound & Animation
        NSSound(named: "Glass")?.play()
        
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
