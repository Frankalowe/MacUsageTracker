import Foundation
import AppKit
import Combine

@MainActor
public final class UsageTrackerEngine: ObservableObject {
    public static let shared = UsageTrackerEngine()
    
    @Published public var currentSessionStart: Date
    @Published public var currentSessionDuration: TimeInterval = 0
    @Published public var isAwake: Bool = true
    
    // Live program and website tracking
    @Published public var liveAppUsage: [String: Int] = [:]
    @Published public var liveWebsiteUsage: [String: Int] = [:]
    @Published public var currentFrontmostApp: String = ""
    @Published public var currentWebsiteDomain: String? = nil
    
    private var lastBrowserDomainCheckTime: TimeInterval = 0
    private var cachedBrowserDomain: String? = nil
    
    // Notification interval milestones
    public var lastQuoteIntervalIndex: Int = 0       // 60-minute interval tracker
    public var lastStretchIntervalIndex: Int = 0     // 90-minute interval tracker
    public var last10HourNotifiedDateKey: String?    // Prevents duplicate 10h alerts on same calendar day
    
    private var timerCancellable: AnyCancellable?
    private var observers: [Any] = []
    
    public init() {
        let now = Date()
        self.currentSessionStart = now
        startTimer()
        setupSystemObservers()
    }
    
    deinit {
        // NotificationCenter removes block-based observers when released
    }
    
    // MARK: - Menu Bar and Display Formatters
    
    public var menuBarTitle: String {
        guard isAwake else { return "💻 Asleep" }
        let total = Int(currentSessionDuration)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        
        if hours > 0 {
            return "💻 \(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "💻 \(minutes)m"
        } else {
            return "💻 <1m"
        }
    }
    
    public var liveTimeString: String {
        let total = Int(currentSessionDuration)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    
    public var startTimeFormatted: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: currentSessionStart)
    }
    
    // MARK: - Internal Lifecycle
    
    private func startTimer() {
        timerCancellable?.cancel()
        timerCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }
    
    private func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }
    
    private func tick() {
        guard isAwake else { return }
        currentSessionDuration = Date().timeIntervalSince(currentSessionStart)
        
        // Track active frontmost program
        let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Finder"
        self.currentFrontmostApp = frontApp
        liveAppUsage[frontApp, default: 0] += 1
        
        // Track active website domain if frontmost app is a recognized browser
        let browserNames = ["Google Chrome", "Safari", "Brave Browser", "Microsoft Edge", "Arc", "Chromium"]
        if browserNames.contains(frontApp) {
            if let domain = sampleBrowserDomain(appName: frontApp) {
                self.currentWebsiteDomain = domain
                liveWebsiteUsage[domain, default: 0] += 1
            } else {
                self.currentWebsiteDomain = nil
            }
        } else {
            self.currentWebsiteDomain = nil
        }
        
        checkNotificationTriggers()
    }
    
    /// Queries the active tab domain when a browser is in focus, sampling every 2s for zero overhead.
    private func sampleBrowserDomain(appName: String) -> String? {
        let now = Date().timeIntervalSince1970
        if now - lastBrowserDomainCheckTime < 2.0 {
            return cachedBrowserDomain
        }
        lastBrowserDomainCheckTime = now
        
        let scriptSource: String
        if appName == "Safari" {
            scriptSource = "if application \"Safari\" is running then tell application \"Safari\" to return URL of front document"
        } else if ["Google Chrome", "Brave Browser", "Microsoft Edge", "Arc", "Chromium"].contains(appName) {
            scriptSource = "if application \"\(appName)\" is running then tell application \"\(appName)\" to return URL of active tab of front window"
        } else {
            cachedBrowserDomain = nil
            return nil
        }
        
        guard let script = NSAppleScript(source: scriptSource) else {
            cachedBrowserDomain = nil
            return nil
        }
        
        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)
        if errorInfo == nil, let urlString = descriptor.stringValue, let url = URL(string: urlString), let host = url.host {
            let domain = host.lowercased().hasPrefix("www.") ? String(host.dropFirst(4)) : host.lowercased()
            cachedBrowserDomain = domain
            return domain
        }
        
        cachedBrowserDomain = nil
        return nil
    }
    
    public func checkNotificationTriggers() {
        let settings = DataManager.shared.settings
        let duration = Int(currentSessionDuration)
        
        // 1. Every 60 minutes: Motivational quote
        if settings.enableMotivationalQuotes {
            let quoteInterval = duration / 3600
            if quoteInterval > lastQuoteIntervalIndex && quoteInterval > 0 {
                lastQuoteIntervalIndex = quoteInterval
                let item = NotificationService.shared.getRandomMotivationalQuote()
                NotificationService.shared.sendNotification(
                    title: "⚡ Hour \(quoteInterval) Milestone",
                    subtitle: "Keep Going Strong",
                    body: "\"\(item.quote)\" — \(item.author)"
                )
            }
        }
        
        // 2. Every 90 minutes: Stretch & hydrate reminder
        if settings.enableHydrateReminder {
            let stretchInterval = duration / 5400
            if stretchInterval > lastStretchIntervalIndex && stretchInterval > 0 {
                lastStretchIntervalIndex = stretchInterval
                let minutesActive = stretchInterval * 90
                NotificationService.shared.sendNotification(
                    title: "🧘 Time to Stretch & Hydrate!",
                    subtitle: "\(minutesActive)m Continuous Mac Usage",
                    body: "You've been active for \(minutesActive) minutes straight. Roll your shoulders, look at something distant, and drink a glass of water!"
                )
            }
        }
        
        // 3. When time hits 10 hours today: Reminder to end the day (if not met, never sent)
        if settings.enableTenHourReminder {
            let todayTotal = DataManager.shared.todayTotalSeconds(liveCurrentDuration: currentSessionDuration)
            let tenHoursInSeconds = 10 * 3600 // 36,000s
            
            let todayFormatter = DateFormatter()
            todayFormatter.dateFormat = "yyyy-MM-dd"
            let todayKey = todayFormatter.string(from: Date())
            
            if todayTotal >= tenHoursInSeconds && last10HourNotifiedDateKey != todayKey {
                last10HourNotifiedDateKey = todayKey
                NotificationService.shared.sendNotification(
                    title: "🌙 Time to End the Day!",
                    subtitle: "10 Hours of Screen Time Reached",
                    body: "You've completed 10 hours of Mac work today. Outstanding dedication! Give yourself a well-deserved break and wrap up for the day."
                )
            }
        }
    }
    
    private func setupSystemObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        
        // When MacBook is about to sleep
        let sleepObs = workspaceCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleSystemWillSleep()
            }
        }
        observers.append(sleepObs)
        
        // When MacBook wakes up
        let wakeObs = workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleSystemDidWake()
            }
        }
        observers.append(wakeObs)
        
        // When App terminates or MacBook shuts down / restarts
        let termObs = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleSystemWillTerminate()
            }
        }
        observers.append(termObs)
    }
    
    public func handleSystemWillSleep() {
        finalizeCurrentSession()
        isAwake = false
        stopTimer()
    }
    
    public func handleSystemDidWake() {
        currentSessionStart = Date()
        currentSessionDuration = 0
        lastQuoteIntervalIndex = 0
        lastStretchIntervalIndex = 0
        liveAppUsage.removeAll()
        liveWebsiteUsage.removeAll()
        cachedBrowserDomain = nil
        isAwake = true
        startTimer()
    }
    
    public func handleSystemWillTerminate() {
        finalizeCurrentSession()
    }
    
    private func finalizeCurrentSession() {
        let now = Date()
        let duration = Int(now.timeIntervalSince(currentSessionStart))
        let minSeconds = DataManager.shared.settings.minimumSessionSeconds
        
        if duration >= minSeconds {
            let session = UsageSession(
                startTime: currentSessionStart,
                endTime: now,
                durationSeconds: duration,
                appUsage: liveAppUsage,
                websiteUsage: liveWebsiteUsage
            )
            DataManager.shared.addSession(session)
        }
        liveAppUsage.removeAll()
        liveWebsiteUsage.removeAll()
        cachedBrowserDomain = nil
    }
}
