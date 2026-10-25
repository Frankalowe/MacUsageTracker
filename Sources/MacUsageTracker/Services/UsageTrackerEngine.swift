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
    private var lastStateSaveTime: TimeInterval = 0
    private var lastExtensionReportTime: TimeInterval = 0
    private var extensionReportedDomain: String? = nil
    
    private let recognizedBrowserBundleIDs: [String: String] = [
        "com.brave.Browser": "Brave Browser",
        "com.google.Chrome": "Google Chrome",
        "com.apple.Safari": "Safari",
        "company.thebrowser.Browser": "Arc",
        "com.microsoft.edgemac": "Microsoft Edge",
        "org.chromium.Chromium": "Chromium",
        "com.vivaldi.Vivaldi": "Vivaldi",
        "com.kagi.kagimacOS": "Orion"
    ]
    
    // Notification interval milestones
    public var lastQuoteIntervalIndex: Int = 0       // 60-minute interval tracker
    public var lastStretchIntervalIndex: Int = 0     // 90-minute interval tracker
    public var last10HourNotifiedDateKey: String?    // Prevents duplicate 10h alerts on same calendar day
    
    private var timerCancellable: AnyCancellable?
    private var observers: [Any] = []
    
    public init() {
        let now = Date()
        self.currentSessionStart = now
        
        // Restore running session seamlessly if recovering from app update/restart
        restoreActiveSessionIfAvailable(fallbackNow: now)
        
        // Start local receiver for optional browser companion extension
        BrowserExtensionServer.shared.start()
        
        startTimer()
        setupSystemObservers()
    }
    
    /// Called when the companion browser extension reports the active tab domain and title
    public func handleDomainReportedFromExtension(rawDomain: String, tabTitle: String?) {
        guard isAwake else { return }
        let urlString = rawDomain.contains("://") ? rawDomain : "http://" + rawDomain
        let url = URL(string: urlString)
        let host = url?.host ?? rawDomain
        let port = url?.port
        guard let formatted = Self.formatWebsiteIdentifier(host: host, port: port, title: tabTitle) else {
            self.currentWebsiteDomain = nil
            return
        }
        
        self.extensionReportedDomain = formatted
        self.lastExtensionReportTime = Date().timeIntervalSince1970
        self.currentWebsiteDomain = formatted
        self.liveWebsiteUsage[formatted, default: 0] += 1
    }
    
    /// Formats a website identifier, extracting software name from tab title on localhost / local servers.
    public static func formatWebsiteIdentifier(host: String, port: Int?, title: String?) -> String? {
        let cleanHost = host.lowercased().hasPrefix("www.") ? String(host.dropFirst(4)) : host.lowercased()
        
        // Ignore internal browser pages (new tab, settings, etc.)
        let internalPages: Set<String> = ["newtab", "new-tab-page", "extensions", "settings", "about", "blank", "downloads", "history"]
        if internalPages.contains(cleanHost) || cleanHost.isEmpty {
            return nil
        }
        
        // Identify local software development and internal server hosts
        let isLocal = cleanHost == "localhost" ||
                      cleanHost == "127.0.0.1" ||
                      cleanHost == "0.0.0.0" ||
                      cleanHost == "::1" ||
                      cleanHost.hasPrefix("192.168.") ||
                      cleanHost.hasPrefix("10.") ||
                      cleanHost.hasSuffix(".local") ||
                      cleanHost.hasSuffix(".test") ||
                      cleanHost.hasSuffix(".internal")
        
        if isLocal {
            let p = port ?? 3000
            let canon = LocalLLMService.shared.canonicalLocalhostIdentifier(port: p, title: title)
            return canon.isEmpty ? nil : canon
        }
        
        let canon = LocalLLMService.shared.canonicalWebsiteIdentifier(raw: cleanHost)
        return canon.isEmpty ? nil : canon
    }
    
    private func restoreActiveSessionIfAvailable(fallbackNow: Date) {
        let fileURL = DataManager.shared.activeSessionFileURL
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder().decode(ActiveSessionState.self, from: data) else {
            persistActiveSessionState()
            return
        }
        
        let now = Date()
        let timeSinceHeartbeat = now.timeIntervalSince(state.lastHeartbeat)
        let bootTime = systemBootTime()
        let didReboot = (bootTime != nil && bootTime! > state.lastHeartbeat)
        
        // Normalize any fragmented keys in active session usage
        var normalizedWeb: [String: Int] = [:]
        for (k, v) in state.liveWebsiteUsage {
            let norm = LocalLLMService.shared.canonicalWebsiteIdentifier(raw: k)
            if !norm.isEmpty {
                normalizedWeb[norm, default: 0] += v
            }
        }
        
        // If the app was restarted/updated recently (within 15 mins) and Mac didn't reboot in between:
        // Seamlessly continue the active session with ZERO lost progress!
        if timeSinceHeartbeat < 15 * 60 && !didReboot {
            self.currentSessionStart = state.sessionStartTime
            self.liveAppUsage = state.liveAppUsage
            self.liveWebsiteUsage = normalizedWeb
            self.lastQuoteIntervalIndex = state.lastQuoteIntervalIndex
            self.lastStretchIntervalIndex = state.lastStretchIntervalIndex
            self.last10HourNotifiedDateKey = state.last10HourNotifiedDateKey
            self.currentSessionDuration = max(0, now.timeIntervalSince(state.sessionStartTime))
            print("Seamlessly resumed active session across app update! Duration: \(Int(currentSessionDuration))s")
        } else {
            // App was closed for a prolonged time or Mac rebooted: finalize past progress into history!
            let duration = Int(state.lastHeartbeat.timeIntervalSince(state.sessionStartTime))
            if duration >= DataManager.shared.settings.minimumSessionSeconds {
                let session = UsageSession(
                    startTime: state.sessionStartTime,
                    endTime: state.lastHeartbeat,
                    durationSeconds: duration,
                    appUsage: state.liveAppUsage,
                    websiteUsage: normalizedWeb
                )
                DataManager.shared.addSession(session)
                print("Finalized previous session of \(duration)s into history before starting fresh session")
            }
            try? FileManager.default.removeItem(at: fileURL)
            self.currentSessionStart = fallbackNow
            self.currentSessionDuration = 0
        }
        
        persistActiveSessionState()
    }
    
    private func systemBootTime() -> Date? {
        var mib = [CTL_KERN, KERN_BOOTTIME]
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.size
        if sysctl(&mib, 2, &bootTime, &size, nil, 0) == 0 {
            return Date(timeIntervalSince1970: TimeInterval(bootTime.tv_sec))
        }
        return nil
    }
    
    public func persistActiveSessionState() {
        guard isAwake else { return }
        let state = ActiveSessionState(
            sessionStartTime: currentSessionStart,
            lastHeartbeat: Date(),
            liveAppUsage: liveAppUsage,
            liveWebsiteUsage: liveWebsiteUsage,
            lastQuoteIntervalIndex: lastQuoteIntervalIndex,
            lastStretchIntervalIndex: lastStretchIntervalIndex,
            last10HourNotifiedDateKey: last10HourNotifiedDateKey
        )
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: DataManager.shared.activeSessionFileURL, options: .atomic)
        }
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
    
    private func isSelfApplication(name: String) -> Bool {
        let selfNames = ["Mac Usage Tracker", "MacUsageTracker", ProcessInfo.processInfo.processName]
        if selfNames.contains(name) { return true }
        if let bundleId = Bundle.main.bundleIdentifier,
           let frontBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           frontBundleId == bundleId {
            return true
        }
        return false
    }

    private func tick() {
        guard isAwake else { return }
        currentSessionDuration = Date().timeIntervalSince(currentSessionStart)
        
        // Track active frontmost program (ignoring Mac Usage Tracker itself)
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           let frontApp = frontmost.localizedName,
           !isSelfApplication(name: frontApp) {
            self.currentFrontmostApp = frontApp
            liveAppUsage[frontApp, default: 0] += 1
            
            // Check if frontmost application is a recognized browser
            let bundleId = frontmost.bundleIdentifier ?? ""
            let isBrowser = recognizedBrowserBundleIDs.keys.contains(bundleId) ||
                ["Google Chrome", "Safari", "Brave Browser", "Microsoft Edge", "Arc", "Chromium", "Brave", "Chrome"].contains(frontApp)
            
            if isBrowser {
                let now = Date().timeIntervalSince1970
                // 1. If companion browser extension reported domain recently, use it
                if now - lastExtensionReportTime < 2.0, let extDomain = extensionReportedDomain {
                    self.currentWebsiteDomain = extDomain
                } else if let domain = sampleBrowserDomain(bundleId: bundleId, appName: frontApp) {
                    // 2. Otherwise query via native AppleScript
                    self.currentWebsiteDomain = domain
                    liveWebsiteUsage[domain, default: 0] += 1
                } else {
                    self.currentWebsiteDomain = nil
                }
            } else {
                self.currentWebsiteDomain = nil
            }
        }
        
        checkNotificationTriggers()
        
        // Persist active session state every 5 seconds so updates or restarts never lose progress
        let now = Date().timeIntervalSince1970
        if now - lastStateSaveTime >= 5.0 {
            lastStateSaveTime = now
            persistActiveSessionState()
        }
    }
    
    /// Queries the active tab domain and title when a browser is in focus, sampling every 2s for zero overhead.
    private func sampleBrowserDomain(bundleId: String, appName: String) -> String? {
        let now = Date().timeIntervalSince1970
        if now - lastBrowserDomainCheckTime < 2.0 {
            return cachedBrowserDomain
        }
        lastBrowserDomainCheckTime = now
        
        let scriptSource: String
        if bundleId == "com.apple.Safari" || appName == "Safari" {
            scriptSource = "tell application id \"com.apple.Safari\" to return {URL of front document, name of front document}"
        } else {
            let target = bundleId.isEmpty ? "application \"\(appName)\"" : "application id \"\(bundleId)\""
            scriptSource = "tell \(target) to return {URL of active tab of front window, title of active tab of front window}"
        }
        
        guard let script = NSAppleScript(source: scriptSource) else {
            cachedBrowserDomain = nil
            return nil
        }
        
        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)
        
        var rawUrl: String? = nil
        var tabTitle: String? = nil
        
        if errorInfo == nil {
            if descriptor.numberOfItems >= 2 {
                rawUrl = descriptor.atIndex(1)?.stringValue
                tabTitle = descriptor.atIndex(2)?.stringValue
            } else if descriptor.numberOfItems == 1 {
                rawUrl = descriptor.atIndex(1)?.stringValue
            } else {
                rawUrl = descriptor.stringValue
            }
        }
        
        guard let raw = rawUrl, !raw.isEmpty else {
            cachedBrowserDomain = nil
            return nil
        }
        
        let urlString = raw.contains("://") ? raw : "https://" + raw
        guard let url = URL(string: urlString), let host = url.host, !host.isEmpty else {
            cachedBrowserDomain = nil
            return nil
        }
        
        guard let formatted = Self.formatWebsiteIdentifier(host: host, port: url.port, title: tabTitle) else {
            cachedBrowserDomain = nil
            return nil
        }
        cachedBrowserDomain = formatted
        return formatted
    }
    
    public func checkNotificationTriggers() {
        let settings = DataManager.shared.settings
        let duration = Int(currentSessionDuration)
        
        // 1. Every 60 minutes: Motivational quote
        if settings.enableMotivationalQuotes {
            let quoteInterval = duration / 3600
            if quoteInterval > lastQuoteIntervalIndex && quoteInterval > 0 {
                lastQuoteIntervalIndex = quoteInterval
                Task {
                    let item = await NotificationService.shared.getMotivationalQuote()
                    NotificationService.shared.sendNotification(
                        title: "⚡ Hour \(quoteInterval) Milestone",
                        subtitle: "Keep Going Strong",
                        body: "\"\(item.quote)\" — \(item.author)"
                    )
                }
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
        persistActiveSessionState()
        startTimer()
    }
    
    public func handleSystemWillTerminate() {
        // Save current active state before process terminates so that upon update/relaunch it resumes seamlessly
        persistActiveSessionState()
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
        
        // Remove active session file since session was officially finalized
        try? FileManager.default.removeItem(at: DataManager.shared.activeSessionFileURL)
    }
}
