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
        // 1. In-App Floating Toast Window (Always displays on screen, bypasses Do Not Disturb & permission blocks)
        ToastNotificationWindowController.shared.showToast(
            title: title,
            subtitle: subtitle,
            body: body,
            icon: title.contains("Stretch") ? "drop.fill" : "bolt.fill"
        )
        
        // 2. Native System Events dispatch via osascript (Bypasses ad-hoc sandbox restrictions)
        deliverViaSystemEvents(title: title, subtitle: subtitle, body: body)
        
        // 3. Standard UNUserNotificationCenter dispatch (with Time-Sensitive priority to break through Do Not Disturb)
        let content = UNMutableNotificationContent()
        content.title = title
        if let subtitle = subtitle, !subtitle.isEmpty {
            content.subtitle = subtitle
        }
        content.body = body
        content.sound = .default
        if #available(macOS 12.0, *) {
            content.interruptionLevel = .timeSensitive
            content.relevanceScore = 1.0
        }
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("UNUserNotificationCenter note: \(error.localizedDescription)")
            }
        }
    }
    
    public func deliverViaSystemEvents(title: String, subtitle: String?, body: String) {
        let escapedTitle = title.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let escapedSub = (subtitle ?? "").replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let escapedBody = body.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        
        let scriptSource: String
        if !escapedSub.isEmpty {
            scriptSource = "tell application \"System Events\" to display notification \"\(escapedBody)\" with title \"\(escapedTitle)\" subtitle \"\(escapedSub)\" sound name \"default\""
        } else {
            scriptSource = "tell application \"System Events\" to display notification \"\(escapedBody)\" with title \"\(escapedTitle)\" sound name \"default\""
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", scriptSource]
            try? process.run()
        }
    }
    
    /// Sends an immediate test notification with quote and sound to verify alerts work
    public func sendTestNotification() {
        Task {
            let quote = await getMotivationalQuote()
            sendNotification(
                title: "⚡ Motivational Insight",
                subtitle: "— \(quote.author)",
                body: "\"\(quote.quote)\""
            )
        }
    }
    
    // MARK: - Curated Motivational Quotes from Real Famous Figures
    
    public static let motivationalQuotes: [(quote: String, author: String)] = [
        ("The only way to do great work is to love what you do.", "Steve Jobs"),
        ("It's not that I'm so smart, it's just that I stay with problems longer.", "Albert Einstein"),
        ("At dawn, when you have trouble getting out of bed, tell yourself: 'I have to go to work — as a human being.'", "Marcus Aurelius"),
        ("Iron rusts from disuse; stagnant water loses its purity; even so does inaction sap the vigors of the mind.", "Leonardo da Vinci"),
        ("The present is theirs; the future, for which I really worked, is mine.", "Nikola Tesla"),
        ("Life is not easy for any of us. But what of that? We must have perseverance and above all confidence in ourselves.", "Marie Curie"),
        ("Sometimes it is the people no one imagines anything of who do the things that no one can imagine.", "Alan Turing"),
        ("It is not because things are difficult that we do not dare; it is because we do not dare that they are difficult.", "Seneca"),
        ("Genius is one percent inspiration and ninety-nine percent perspiration.", "Thomas Edison"),
        ("Believe you can and you're halfway there.", "Theodore Roosevelt"),
        ("Success is not final, failure is not fatal: it is the courage to continue that counts.", "Winston Churchill"),
        ("We are what we repeatedly do. Excellence, then, is not an act, but a habit.", "Aristotle"),
        ("Whether you think you can, or you think you can't — you're right.", "Henry Ford"),
        ("You can't use up creativity. The more you use, the more you have.", "Maya Angelou"),
        ("It always seems impossible until it's done.", "Nelson Mandela"),
        ("I fear not the man who has practiced 10,000 kicks once, but I fear the man who has practiced one kick 10,000 times.", "Bruce Lee"),
        ("Study hard what interests you the most in the most undisciplined, irreverent and original manner possible.", "Richard Feynman"),
        ("Do not go where the path may lead, go instead where there is no path and leave a trail.", "Ralph Waldo Emerson"),
        ("He who has a why to live can bear almost any how.", "Friedrich Nietzsche"),
        ("No great thing is created suddenly.", "Epictetus"),
        ("It is not the strongest of the species that survives, nor the most intelligent, but the one most responsive to change.", "Charles Darwin"),
        ("Give me six hours to chop down a tree and I will spend the first four sharpening the axe.", "Abraham Lincoln"),
        ("Mystery creates wonder and wonder is the basis of man's desire to understand.", "Neil Armstrong"),
        ("Look up at the stars and not down at your feet. Try to make sense of what you see.", "Stephen Hawking"),
        ("Energy and persistence conquer all things.", "Benjamin Franklin"),
        ("I've failed over and over and over again in my life. And that is why I succeed.", "Michael Jordan"),
        ("Don't count the days, make the days count.", "Muhammad Ali"),
        ("Dedication sees dreams come true.", "Kobe Bryant"),
        ("A champion is defined not by their wins but by how they can recover when they fall.", "Serena Williams"),
        ("The way to get started is to quit talking and begin doing.", "Walt Disney"),
        ("There is nothing like a dream to create the future.", "Victor Hugo"),
        ("The secret of getting ahead is getting started.", "Mark Twain"),
        ("Knowing is not enough; we must apply. Willing is not enough; we must do.", "Johann Wolfgang von Goethe"),
        ("Optimism is the faith that leads to achievement. Nothing can be done without hope and confidence.", "Helen Keller"),
        ("The journey of a thousand miles begins with a single step.", "Lao Tzu"),
        ("Action is the foundational key to all success.", "Pablo Picasso"),
        ("There is nothing impossible to him who will try.", "Alexander the Great"),
        ("If people do not believe that mathematics is simple, it is only because they do not realize how complicated life is.", "John von Neumann"),
        ("I just wondered how things were put together.", "Claude Shannon"),
        ("Talk is cheap. Show me the code.", "Linus Torvalds"),
        ("The most dangerous phrase in the language is: 'We've always done it this way.'", "Grace Hopper"),
        ("That brain of mine is something more than merely mortal; as time will show.", "Ada Lovelace"),
        ("Let your joy be in your journey — not in some distant goal.", "Tim Cook"),
        ("If you double the number of experiments you do per year you're going to double your inventiveness.", "Jeff Bezos"),
        ("Great things start with a craft, relentless focus, and suffering through hard problems.", "Jensen Huang"),
        ("Our industry does not respect tradition — it only respects innovation.", "Satya Nadella"),
        ("Somewhere, something incredible is waiting to be known.", "Carl Sagan"),
        ("If I have seen further it is by standing on the shoulders of Giants.", "Isaac Newton"),
        ("You cannot teach a man anything; you can only help him find it within himself.", "Galileo Galilei"),
        ("It does not matter how slowly you go as long as you do not stop.", "Confucius"),
        ("In the midst of chaos, there is also opportunity.", "Sun Tzu"),
        ("Two roads diverged in a wood, and I took the one less traveled by, and that has made all the difference.", "Robert Frost"),
        ("It has long been an axiom of mine that the little things are infinitely the most important.", "Arthur Conan Doyle"),
        ("Small minds are concerned with the extraordinary, great minds with the commonplace.", "Blaise Pascal"),
        ("It is not enough to have a good mind; the main thing is to use it well.", "Rene Descartes"),
        ("You are in danger of living a life so comfortable and soft, that you will die without ever realizing your true potential.", "David Goggins"),
        ("It is our choices that show what we truly are, far more than our abilities.", "J.K. Rowling"),
        ("Talent hits a target no one else can hit; Genius hits a target no one else can see.", "Arthur Schopenhauer"),
        ("You do not rise to the level of your goals. You fall to the level of your systems.", "James Clear"),
        ("Clarity about what matters provides clarity about what does not.", "Cal Newport"),
        ("Focus on being productive instead of busy.", "Tim Ferriss"),
        ("Small daily improvements over time lead to stunning results.", "Robin Sharma"),
        ("Success is the sum of small efforts, repeated day in and day out.", "Robert Collier"),
        ("The path to success is to take massive, determined action.", "Tony Robbins"),
        ("Great things are done by a series of small things brought together.", "Vincent van Gogh"),
        ("Before anything else, preparation is the key to success.", "Alexander Graham Bell"),
        ("Chance favors the prepared mind.", "Louis Pasteur"),
        ("High achievement always takes place in the framework of high expectation.", "Charles Kettering"),
        ("Believe in life! Always human beings will live and progress to greater, broader, and fuller life.", "W.E.B. Du Bois"),
        ("The future belongs to those who believe in the beauty of their dreams.", "Eleanor Roosevelt")
    ]
    
    // Non-repeating shuffle deck so every notification brings a new real quote
    private var quoteDeck: [Int] = []
    private var lastUsedQuoteIndex: Int = -1
    
    // De-duplication history buffer across ALL quote sources (LLM and curated)
    private var recentlyShownQuoteHashes: Set<String> = []
    private var recentQuoteQueue: [String] = []
    
    public func recordShownQuote(_ text: String) {
        let key = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        recentlyShownQuoteHashes.insert(key)
        recentQuoteQueue.append(key)
        if recentQuoteQueue.count > 60 {
            let oldest = recentQuoteQueue.removeFirst()
            recentlyShownQuoteHashes.remove(oldest)
        }
    }
    
    public func isRecentlyShown(_ text: String) -> Bool {
        let key = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return recentlyShownQuoteHashes.contains(key)
    }
    
    public func getRandomMotivationalQuote() -> (quote: String, author: String) {
        if quoteDeck.isEmpty {
            quoteDeck = Array(0..<Self.motivationalQuotes.count).shuffled()
            if quoteDeck.first == lastUsedQuoteIndex && quoteDeck.count > 1 {
                quoteDeck.swapAt(0, quoteDeck.count - 1)
            }
        }
        let nextIndex = quoteDeck.removeFirst()
        lastUsedQuoteIndex = nextIndex
        return Self.motivationalQuotes[nextIndex]
    }
    
    /// Gets a motivational quote, sourcing from the local LLM if enabled, strictly enforcing NO REPEATS
    public func getMotivationalQuote() async -> (quote: String, author: String) {
        let settings = DataManager.shared.settings
        if settings.useLocalLLMForQuotes {
            // Attempt up to 3 times to get a fresh, non-repeated quote from the local LLM
            for _ in 0..<3 {
                if let llmQuote = await LocalLLMService.shared.generateMotivationalQuote(
                    preferredModel: settings.localLLMModel,
                    endpoint: settings.localLLMEndpoint
                ) {
                    if !isRecentlyShown(llmQuote.quote) {
                        recordShownQuote(llmQuote.quote)
                        return llmQuote
                    }
                }
            }
        }
        
        // Fallback: Pick a non-repeated quote from our verified real-people collection
        for _ in 0..<Self.motivationalQuotes.count {
            let quote = getRandomMotivationalQuote()
            if !isRecentlyShown(quote.quote) {
                recordShownQuote(quote.quote)
                return quote
            }
        }
        
        let fallback = getRandomMotivationalQuote()
        recordShownQuote(fallback.quote)
        return fallback
    }
}
