import Foundation
import UserNotifications
import AppKit

@MainActor
public final class NotificationManager {
    public static let shared = NotificationManager()
    
    private var chimeTask: Task<Void, Never>?
    private var activeSound: NSSound?
    
    private init() {
        requestAuthorization()
    }
    
    public func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
            }
        }
    }
    
    public func sendNotification(title: String, subtitle: String? = nil, body: String, playSound: Bool = true) {
        let content = UNMutableNotificationContent()
        content.title = title
        if let subtitle = subtitle {
            content.subtitle = subtitle
        }
        content.body = body
        if playSound {
            content.sound = .default
        }
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // deliver immediately
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to deliver notification: \(error)")
            }
        }
    }
    
    public func stopChime() {
        chimeTask?.cancel()
        chimeTask = nil
        activeSound?.stop()
        activeSound = nil
    }
    
    /// Plays the notification chime for at least the specified minimum duration (default: 3 seconds)
    public func playChime(minimumDuration: TimeInterval = 3.0) {
        stopChime()
        
        chimeTask = Task { @MainActor [weak self] in
            guard let sound = NSSound(named: "Glass") ?? NSSound(named: "Ping") else {
                // Fallback: beep repeatedly for at least minimumDuration
                let iterations = max(1, Int(ceil(minimumDuration)))
                for _ in 0..<iterations {
                    if Task.isCancelled { break }
                    NSSound.beep()
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
                return
            }
            
            self?.activeSound = sound
            let duration = sound.duration > 0 ? sound.duration : 1.65
            let repeatCount = max(1, Int(ceil(minimumDuration / duration)))
            
            for _ in 0..<repeatCount {
                if Task.isCancelled { break }
                sound.stop()
                sound.play()
                let sleepNanos = UInt64(duration * 1_000_000_000)
                try? await Task.sleep(nanoseconds: sleepNanos)
            }
            
            self?.activeSound = nil
        }
    }
}
