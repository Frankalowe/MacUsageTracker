import Foundation
import UserNotifications
import AppKit

@MainActor
public final class NotificationManager {
    public static let shared = NotificationManager()
    
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
            NSSound.beep()
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
    
    public func playChime() {
        if let sound = NSSound(named: "Glass") ?? NSSound(named: "Ping") {
            sound.play()
        } else {
            NSSound.beep()
        }
    }
}
