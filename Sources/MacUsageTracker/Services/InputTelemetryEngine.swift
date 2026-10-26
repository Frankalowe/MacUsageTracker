import Foundation
import AppKit
import Combine

public enum UserActivityState: String, Codable, Sendable {
    case working = "Working"
    case watching = "Watching Something"
    case reading = "Active Research"
    case idle = "Idle / Away"
    
    public var badgeLabel: String {
        switch self {
        case .working: return "👨‍💻 Deep Working"
        case .watching: return "🎬 Watching Video / Stream"
        case .reading: return "📖 Active Research & Reading"
        case .idle: return "☕ Idle / Away"
        }
    }
    
    public var icon: String {
        switch self {
        case .working: return "laptopcomputer"
        case .watching: return "play.tv.fill"
        case .reading: return "book.fill"
        case .idle: return "moon.zzz.fill"
        }
    }
}

public struct ActivityTelemetryData: Codable, Sendable {
    public var currentState: UserActivityState
    public var currentAppName: String
    public var currentWindowTitle: String
    public var keystrokesPerMinute: Int
    public var mouseClicksPerMinute: Int
    public var cursorDistanceMeters: Double
    public var totalKeystrokes: Int
    public var totalMouseClicks: Int
    public var workingSeconds: Int
    public var watchingSeconds: Int
    public var readingSeconds: Int
    public var idleSeconds: Int
    
    public var workPercentage: Int {
        let total = workingSeconds + watchingSeconds + readingSeconds
        return total > 0 ? Int(round(Double(workingSeconds) / Double(total) * 100.0)) : 100
    }
    
    public var watchPercentage: Int {
        let total = workingSeconds + watchingSeconds + readingSeconds
        return total > 0 ? Int(round(Double(watchingSeconds) / Double(total) * 100.0)) : 0
    }
    
    public var researchPercentage: Int {
        let total = workingSeconds + watchingSeconds + readingSeconds
        return total > 0 ? max(0, 100 - (workPercentage + watchPercentage)) : 0
    }
}

@MainActor
public final class InputTelemetryEngine: ObservableObject {
    public static let shared = InputTelemetryEngine()
    
    @Published public private(set) var currentState: UserActivityState = .working
    @Published public private(set) var currentAppName: String = ""
    @Published public private(set) var currentWindowTitle: String = ""
    @Published public private(set) var currentBrowserURL: String = ""
    
    // Live input velocity
    @Published public private(set) var keystrokesPerMinute: Int = 0
    @Published public private(set) var mouseClicksPerMinute: Int = 0
    @Published public private(set) var cursorDistanceMeters: Double = 0.0
    
    // Cumulative counters for active session
    @Published public private(set) var totalKeystrokes: Int = 0
    @Published public private(set) var totalMouseClicks: Int = 0
    
    // Compiled time breakdown
    @Published public private(set) var workingSeconds: Int = 0
    @Published public private(set) var watchingSeconds: Int = 0
    @Published public private(set) var readingSeconds: Int = 0
    @Published public private(set) var idleSeconds: Int = 0
    
    private var lastMouseLocation: NSPoint? = nil
    private var keystrokeTimestamps: [TimeInterval] = []
    private var mouseClickTimestamps: [TimeInterval] = []
    private var lastWindowTitleCheckTime: TimeInterval = 0
    private var globalEventMonitors: [Any] = []
    
    private let telemetryFileURL: URL
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("MacUsageTracker", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.telemetryFileURL = appDir.appendingPathComponent("input_telemetry.json")
        
        loadSavedTelemetry()
        setupGlobalMonitors()
    }
    
    private func setupGlobalMonitors() {
        // High-resolution global event monitoring (when allowed by system)
        let keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.recordKeystroke()
            }
        }
        let mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.recordMouseClick()
            }
        }
        if let km = keyMonitor { globalEventMonitors.append(km) }
        if let mm = mouseMonitor { globalEventMonitors.append(mm) }
    }
    
    public func recordKeystroke() {
        let now = Date().timeIntervalSince1970
        keystrokeTimestamps.append(now)
        totalKeystrokes += 1
    }
    
    public func recordMouseClick() {
        let now = Date().timeIntervalSince1970
        mouseClickTimestamps.append(now)
        totalMouseClicks += 1
    }
    
    /// Called every 1 second by the main usage engine tick
    public func tick(frontmostApp: String, currentDomain: String?) {
        let now = Date().timeIntervalSince1970
        self.currentAppName = frontmostApp
        
        // 1. Poll CGEventSource for global keystrokes/clicks (works even without Accessibility permissions)
        let keyIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
        if keyIdle < 1.1 {
            keystrokeTimestamps.append(now)
            totalKeystrokes += 1
        }
        
        let clickIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .leftMouseDown)
        if clickIdle < 1.1 {
            mouseClickTimestamps.append(now)
            totalMouseClicks += 1
        }
        
        // 2. Track Cursor Movement
        let currentLocation = NSEvent.mouseLocation
        if let last = lastMouseLocation {
            let dx = currentLocation.x - last.x
            let dy = currentLocation.y - last.y
            let dist = sqrt(dx * dx + dy * dy)
            if dist > 2.0 && dist < 3000.0 {
                // 1 screen pixel ≈ 0.00026 meters
                cursorDistanceMeters += dist * 0.000264
            }
        }
        lastMouseLocation = currentLocation
        
        // 3. Prune events older than 60 seconds to calculate per-minute velocities
        let oneMinuteAgo = now - 60.0
        keystrokeTimestamps.removeAll { $0 < oneMinuteAgo }
        mouseClickTimestamps.removeAll { $0 < oneMinuteAgo }
        
        self.keystrokesPerMinute = keystrokeTimestamps.count
        self.mouseClicksPerMinute = mouseClickTimestamps.count
        
        // 4. Sample Frontmost Window Title every 2 seconds
        if now - lastWindowTitleCheckTime >= 2.0 {
            lastWindowTitleCheckTime = now
            sampleWindowTitle(appName: frontmostApp)
        }
        
        // 5. Predict Activity State: Working vs. Watching vs. Reading vs. Idle
        predictActivity(
            appName: frontmostApp,
            domain: currentDomain,
            keyIdle: keyIdle,
            clickIdle: clickIdle
        )
        
        // 6. Accumulate Duration
        switch currentState {
        case .working: workingSeconds += 1
        case .watching: watchingSeconds += 1
        case .reading: readingSeconds += 1
        case .idle: idleSeconds += 1
        }
    }
    
    /// Analyzes multi-modal signals (window title, typing velocity, mouse movement, active app) to predict activity
    private func predictActivity(
        appName: String,
        domain: String?,
        keyIdle: TimeInterval,
        clickIdle: TimeInterval
    ) {
        let mouseMoveIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .mouseMoved)
        let overallInputIdle = min(keyIdle, mouseMoveIdle, clickIdle)
        
        // Signal A: Total inactivity for > 2.5 minutes -> Idle / Away
        if overallInputIdle > 150.0 {
            self.currentState = .idle
            return
        }
        
        let lowerTitle = currentWindowTitle.lowercased()
        let lowerApp = appName.lowercased()
        let lowerDomain = (domain ?? "").lowercased()
        
        // Media keywords in window title or URL
        let mediaKeywords = [
            "youtube", "netflix", "vlc", "movie", "video", "trailer",
            "episode", "season", "stream", "twitch", "hotstar", "disney+",
            "prime video", "hulu", "crunchyroll", ".mp4", ".mkv", ".avi",
            "1080p", "720p", "4k", "watch?v=", "watch party", "cinema"
        ]
        let hasMediaIndicator = mediaKeywords.contains { lowerTitle.contains($0) || lowerDomain.contains($0) }
        let isDedicatedMediaPlayer = ["quicktime player", "vlc", "iina", "infuse", "mpv", "netflix", "youtube"].contains(lowerApp)
        
        // Signal B: WATCHING SOMETHING
        // Passive consumption criteria:
        // - Keyboard is idle (> 25s) AND mouse is largely stationary (> 10s)
        // - AND media app is active OR window title/URL indicates video/movie playback
        if (hasMediaIndicator || isDedicatedMediaPlayer) && keyIdle > 25.0 && mouseMoveIdle > 10.0 {
            self.currentState = .watching
            return
        }
        
        // Signal C: DEEP WORKING
        // Active creation & engineering criteria:
        // - Coding tools / IDEs / Local dev / Terminal
        let devApps = [
            "antigravity", "xcode", "cursor", "visual studio code", "code",
            "terminal", "iterm", "iterm2", "intellij", "pycharm", "webstorm",
            "warp", "docker", "postman", "tableplus", "dbeaver", "sublime", "zed"
        ]
        let isDevApp = devApps.contains { lowerApp.contains($0) }
        let isLocalDevSite = lowerDomain.contains("localhost") || lowerDomain.contains("clipforge") || lowerDomain.contains("127.0.0.1")
        let isCodingSite = lowerDomain.contains("github") || lowerDomain.contains("stackoverflow") || lowerDomain.contains("claude") || lowerDomain.contains("chatgpt")
        
        // Active typing (> 6 keys/min) or working inside a dev tool
        if isDevApp || isLocalDevSite || (keystrokesPerMinute >= 6) || (isCodingSite && clickIdle < 15.0) {
            self.currentState = .working
            return
        }
        
        // Signal D: READING / RESEARCH
        // User is browsing documents/articles with active mouse scrolling but low typing
        if mouseMoveIdle < 12.0 && clickIdle < 30.0 {
            self.currentState = .reading
            return
        }
        
        // Default to working if recent inputs detected
        self.currentState = .working
    }
    
    private func sampleWindowTitle(appName: String) {
        // 1. Browsers: Query active tab URL & title
        let browsers = ["Google Chrome", "Brave Browser", "Safari", "Microsoft Edge", "Arc", "Chromium"]
        if browsers.contains(appName) {
            let scriptSource: String
            if appName == "Safari" {
                scriptSource = "tell application \"Safari\" to return {URL of front document, name of front document}"
            } else {
                scriptSource = "tell application \"\(appName)\" to return {URL of active tab of front window, title of active tab of front window}"
            }
            if let script = NSAppleScript(source: scriptSource) {
                var errorInfo: NSDictionary?
                let desc = script.executeAndReturnError(&errorInfo)
                if errorInfo == nil && desc.numberOfItems >= 2 {
                    self.currentBrowserURL = desc.atIndex(1)?.stringValue ?? ""
                    let title = desc.atIndex(2)?.stringValue ?? ""
                    if !title.isEmpty {
                        self.currentWindowTitle = title
                        return
                    }
                }
            }
        }
        
        // 2. Generic Applications: Query window title via System Events
        let scriptSource = """
        tell application "System Events"
            try
                set frontProc to first application process whose frontmost is true
                return name of front window of frontProc
            on error
                return ""
            end try
        end tell
        """
        if let script = NSAppleScript(source: scriptSource) {
            var errorInfo: NSDictionary?
            let desc = script.executeAndReturnError(&errorInfo)
            if errorInfo == nil, let title = desc.stringValue, !title.isEmpty {
                self.currentWindowTitle = title
            }
        }
    }
    
    // MARK: - Persistence & Report
    
    public func currentTelemetryData() -> ActivityTelemetryData {
        ActivityTelemetryData(
            currentState: currentState,
            currentAppName: currentAppName,
            currentWindowTitle: currentWindowTitle,
            keystrokesPerMinute: keystrokesPerMinute,
            mouseClicksPerMinute: mouseClicksPerMinute,
            cursorDistanceMeters: Double(round(cursorDistanceMeters * 10.0)) / 10.0,
            totalKeystrokes: totalKeystrokes,
            totalMouseClicks: totalMouseClicks,
            workingSeconds: workingSeconds,
            watchingSeconds: watchingSeconds,
            readingSeconds: readingSeconds,
            idleSeconds: idleSeconds
        )
    }
    
    public func saveTelemetry() {
        let data = currentTelemetryData()
        if let encoded = try? JSONEncoder().encode(data) {
            try? encoded.write(to: telemetryFileURL, options: .atomic)
        }
    }
    
    private func loadSavedTelemetry() {
        guard FileManager.default.fileExists(atPath: telemetryFileURL.path),
              let data = try? Data(contentsOf: telemetryFileURL),
              let decoded = try? JSONDecoder().decode(ActivityTelemetryData.self, from: data) else {
            return
        }
        self.workingSeconds = decoded.workingSeconds
        self.watchingSeconds = decoded.watchingSeconds
        self.readingSeconds = decoded.readingSeconds
        self.idleSeconds = decoded.idleSeconds
        self.totalKeystrokes = decoded.totalKeystrokes
        self.totalMouseClicks = decoded.totalMouseClicks
        self.cursorDistanceMeters = decoded.cursorDistanceMeters
    }
}
