import Foundation
import UserNotifications

@MainActor
public final class NotificationService {
    public static let shared = NotificationService()
    
    private init() {
        if Bundle.main.bundleIdentifier != nil {
            requestAuthorization()
        }
    }
    
    public func requestAuthorization() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission notice: \(error.localizedDescription)")
            }
        }
    }
    
    public func sendNotification(title: String, subtitle: String? = nil, body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        
        let content = UNMutableNotificationContent()
        content.title = title
        if let subtitle = subtitle {
            content.subtitle = subtitle
        }
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to deliver notification: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Curated Motivational Quotes
    
    public static let motivationalQuotes: [(quote: String, author: String)] = [
        ("Small daily improvements over time lead to stunning results.", "Robin Sharma"),
        ("Focus on being productive instead of busy.", "Tim Ferriss"),
        ("The secret of getting ahead is getting started.", "Mark Twain"),
        ("Success is the sum of small efforts, repeated day in and day out.", "Robert Collier"),
        ("Energy flows where attention goes.", "Tony Robbins"),
        ("Deep work is the superpower of the 21st century.", "Cal Newport"),
        ("It always seems impossible until it's done.", "Nelson Mandela"),
        ("Discipline is choosing between what you want now and what you want most.", "Abraham Lincoln"),
        ("Great things are done by a series of small things brought together.", "Vincent van Gogh"),
        ("One hour of deep focus beats a whole day of divided attention.", "James Clear"),
        ("You don't have to be extreme, just consistent.", "Anonymous"),
        ("Action is the foundational key to all success.", "Pablo Picasso"),
        ("Do what you can, with what you have, where you are.", "Theodore Roosevelt"),
        ("Continuous effort, not strength or intelligence, is the key to unlocking our potential.", "Winston Churchill"),
        ("Focus is a muscle. The more you practice, the stronger it gets.", "Anonymous")
    ]
    
    public func getRandomMotivationalQuote() -> (quote: String, author: String) {
        Self.motivationalQuotes.randomElement() ?? ("Focus on progress, not perfection.", "Anonymous")
    }
    
    /// Gets a motivational quote, sourcing from the local LLM if enabled, with fallback to curated library
    public func getMotivationalQuote() async -> (quote: String, author: String) {
        let settings = DataManager.shared.settings
        if settings.useLocalLLMForQuotes {
            if let llmQuote = await LocalLLMService.shared.generateMotivationalQuote(
                preferredModel: settings.localLLMModel,
                endpoint: settings.localLLMEndpoint
            ) {
                return llmQuote
            }
        }
        return getRandomMotivationalQuote()
    }
}
