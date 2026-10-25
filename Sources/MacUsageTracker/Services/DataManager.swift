import Foundation
import SwiftUI
import Combine

public struct AppData: Codable {
    public var settings: AppSettings
    public var sessions: [UsageSession]
    
    // Backwards compatibility with previous versions
    enum CodingKeys: String, CodingKey {
        case settings
        case sessions
        case timerRecords
    }
    
    public init(settings: AppSettings, sessions: [UsageSession]) {
        self.settings = settings
        self.sessions = sessions
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.settings = (try? container.decode(AppSettings.self, forKey: .settings)) ?? .default
        
        if let decodedSessions = try? container.decode([UsageSession].self, forKey: .sessions) {
            self.sessions = decodedSessions
        } else {
            self.sessions = []
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(settings, forKey: .settings)
        try container.encode(sessions, forKey: .sessions)
    }
}

@MainActor
public final class DataManager: ObservableObject {
    public static let shared = DataManager()
    
    // 7-day retention policy: 7 days in seconds
    public static let retentionDays: Int = 7
    public static let retentionSeconds: TimeInterval = 7 * 24 * 60 * 60
    
    @Published public var sessions: [UsageSession] = []
    @Published public var settings: AppSettings = .default
    
    private let fileURL: URL
    private var pruneCancellable: AnyCancellable?
    
    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("MacUsageTracker", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.fileURL = appDir.appendingPathComponent("data.json")
        
        load()
        
        // Setup recurring hourly check to purge any usage sessions older than 7 days
        pruneCancellable = Timer.publish(every: 3600, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.pruneOldSessions()
            }
    }
    
    public func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            self.sessions = []
            self.settings = .default
            return
        }
        
        do {
            let decoded = try JSONDecoder().decode(AppData.self, from: data)
            self.settings = decoded.settings
            self.sessions = decoded.sessions
            pruneOldSessions()
        } catch {
            print("Failed to decode data, using defaults: \(error)")
            self.sessions = []
            self.settings = .default
        }
    }
    
    public func save() {
        pruneOldSessions()
        let appData = AppData(settings: settings, sessions: sessions)
        do {
            let data = try JSONEncoder().encode(appData)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save data: \(error)")
        }
    }
    
    // MARK: - 7-Day Retention Management
    
    /// Prunes any session records older than 7 days from the reference date.
    /// Returns the number of records pruned.
    @discardableResult
    public func pruneOldSessions(referenceDate: Date = Date()) -> Int {
        let cutoff = referenceDate.addingTimeInterval(-Self.retentionSeconds)
        let beforeCount = sessions.count
        sessions.removeAll { $0.startTime < cutoff }
        let removed = beforeCount - sessions.count
        if removed > 0 {
            let appData = AppData(settings: settings, sessions: sessions)
            if let data = try? JSONEncoder().encode(appData) {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
        return removed
    }
    
    /// Adds a completed MacBook usage session to persistent storage.
    public func addSession(_ session: UsageSession) {
        pruneOldSessions()
        sessions.append(session)
        save()
    }
    
    // MARK: - Queries
    
    /// Returns all sessions recorded for today.
    public func todaySessions(referenceDate: Date = Date()) -> [UsageSession] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: referenceDate)
        guard let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday) else {
            return []
        }
        return sessions
            .filter { $0.startTime >= startOfToday && $0.startTime < endOfToday }
            .sorted { $0.startTime > $1.startTime }
    }
    
    /// Total seconds of Mac screen time today, including currently running active session uptime.
    public func todayTotalSeconds(referenceDate: Date = Date(), liveCurrentDuration: TimeInterval = 0) -> Int {
        let completedToday = todaySessions(referenceDate: referenceDate).reduce(0) { $0 + $1.durationSeconds }
        return completedToday + Int(liveCurrentDuration)
    }
    
    /// Formatted total screen time for today (e.g. "3h 45m" or "42m").
    public func todayTotalFormatted(referenceDate: Date = Date(), liveCurrentDuration: TimeInterval = 0) -> String {
        let total = todayTotalSeconds(referenceDate: referenceDate, liveCurrentDuration: liveCurrentDuration)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    /// Returns all sessions stored for the last 7 days, sorted newest first.
    public func sessionsInLast7Days(referenceDate: Date = Date()) -> [UsageSession] {
        let cutoff = referenceDate.addingTimeInterval(-Self.retentionSeconds)
        return sessions
            .filter { $0.startTime >= cutoff }
            .sorted { $0.startTime > $1.startTime }
    }
    
    /// Total seconds of Mac screen time over the last 7 days.
    public func total7DaySeconds(referenceDate: Date = Date(), liveCurrentDuration: TimeInterval = 0) -> Int {
        let completed = sessionsInLast7Days(referenceDate: referenceDate).reduce(0) { $0 + $1.durationSeconds }
        return completed + Int(liveCurrentDuration)
    }
    
    /// Returns day-by-day summary for each of the last N days (default 7 days).
    public func dailyUsageSummaries(lastDays: Int = 7, referenceDate: Date = Date(), liveCurrentDuration: TimeInterval = 0) -> [DayUsageSummary] {
        let calendar = Calendar.current
        var summaries: [DayUsageSummary] = []
        let startOfRefDay = calendar.startOfDay(for: referenceDate)
        
        for dayOffset in (0..<lastDays).reversed() {
            guard let dayDate = calendar.date(byAdding: .day, value: -dayOffset, to: startOfRefDay),
                  let nextDayDate = calendar.date(byAdding: .day, value: 1, to: dayDate) else {
                continue
            }
            
            let isToday = calendar.isDateInToday(dayDate)
            let daySessions = sessions.filter { $0.startTime >= dayDate && $0.startTime < nextDayDate }
            var totalSeconds = daySessions.reduce(0) { $0 + $1.durationSeconds }
            
            if isToday {
                totalSeconds += Int(liveCurrentDuration)
            }
            
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "EEE"
            let label = isToday ? "Today" : dayFormatter.string(from: dayDate)
            
            summaries.append(DayUsageSummary(
                date: dayDate,
                dayLabel: label,
                isToday: isToday,
                sessionCount: daySessions.count + (isToday && liveCurrentDuration > 0 ? 1 : 0),
                totalSeconds: totalSeconds
            ))
        }
        
        return summaries
    }
    
    /// Clears all stored sessions manually.
    public func clearAllSessions() {
        sessions.removeAll()
        save()
    }
}
