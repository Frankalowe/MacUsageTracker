import Foundation
@preconcurrency import UserNotifications
import AppKit

@MainActor
public final class NotificationService: NSObject, UNUserNotificationCenterDelegate, ObservableObject {
    public static let shared = NotificationService()
    
    @Published public var authorizationStatus: UNAuthorizationStatus = .notDetermined
    
    private override init() {
        super.init()
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
            checkAndRequestAuthorization()
        }
    }
    
    public func checkAndRequestAuthorization() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        
        Task { @MainActor in
            let settings = await center.notificationSettings()
            self.authorizationStatus = settings.authorizationStatus
            if settings.authorizationStatus == .notDetermined {
                do {
                    let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                    self.authorizationStatus = granted ? .authorized : .denied
                } catch {
                    self.authorizationStatus = .denied
                    print("Notification authorization notice: \(error.localizedDescription)")
                }
            }
        }
    }
    
    public func requestAuthorization() {
        checkAndRequestAuthorization()
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Display banner, play sound, and update badge even when the app is active/focused
        completionHandler([.banner, .sound, .badge, .list])
    }
    
    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
    
    // MARK: - Notification Dispatch
    
    public func sendNotification(title: String, subtitle: String? = nil, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        if let subtitle = subtitle, !subtitle.isEmpty {
            content.subtitle = subtitle
        }
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )
        
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error = error {
                print("UNUserNotificationCenter delivery issue: \(error.localizedDescription), falling back to native alert")
                Task { @MainActor in
                    self?.deliverViaAppleScript(title: title, subtitle: subtitle, body: body)
                }
            }
        }
        
        // If UNUserNotificationCenter is not explicitly authorized yet, also guarantee delivery via AppleScript fallback
        if self.authorizationStatus != .authorized {
            deliverViaAppleScript(title: title, subtitle: subtitle, body: body)
        }
    }
    
    public func deliverViaAppleScript(title: String, subtitle: String?, body: String) {
        let escapedTitle = title.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let escapedSub = (subtitle ?? "").replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let escapedBody = body.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        
        let scriptSource: String
        if !escapedSub.isEmpty {
            scriptSource = "display notification \"\(escapedBody)\" with title \"\(escapedTitle)\" subtitle \"\(escapedSub)\" sound name \"default\""
        } else {
            scriptSource = "display notification \"\(escapedBody)\" with title \"\(escapedTitle)\" sound name \"default\""
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            var errorInfo: NSDictionary?
            if let script = NSAppleScript(source: scriptSource) {
                script.executeAndReturnError(&errorInfo)
            }
        }
    }
    
    /// Sends an immediate test notification with quote and sound to verify alerts work
    public func sendTestNotification() {
        Task {
            let quote = await getMotivationalQuote()
            sendNotification(
                title: "⚡ Test Motivational Quote",
                subtitle: "Keep Going Strong",
                body: "\"\(quote.quote)\" — \(quote.author)"
            )
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
