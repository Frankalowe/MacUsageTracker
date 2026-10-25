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
    
    // 35-day retention policy: 35 days in seconds (covers full month analysis)
    public static let retentionDays: Int = 35
    public static let retentionSeconds: TimeInterval = 35 * 24 * 60 * 60
    
    @Published public var sessions: [UsageSession] = []
    @Published public var settings: AppSettings = .default
    
    private let fileURL: URL
    public let activeSessionFileURL: URL
    private var pruneCancellable: AnyCancellable?
    
    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("MacUsageTracker", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.fileURL = appDir.appendingPathComponent("data.json")
        self.activeSessionFileURL = appDir.appendingPathComponent("active_session.json")
        
        load()
        
        // Setup recurring hourly check to purge any usage sessions older than 35 days
        pruneCancellable = Timer.publish(every: 3600, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.pruneOldSessions()
            }
    }
    
    public func load() {
        var loadedData: AppData?
        
        if FileManager.default.fileExists(atPath: fileURL.path),
           let data = try? Data(contentsOf: fileURL) {
            loadedData = try? JSONDecoder().decode(AppData.self, from: data)
        }
        
        // If primary file failed to decode or was missing, check automated backup file
        let backupURL = fileURL.deletingPathExtension().appendingPathExtension("bak")
        if loadedData == nil && FileManager.default.fileExists(atPath: backupURL.path),
           let backupData = try? Data(contentsOf: backupURL) {
            loadedData = try? JSONDecoder().decode(AppData.self, from: backupData)
            if loadedData != nil {
                print("Recovered AppData from backup file: \(backupURL.path)")
            }
        }
        
        if let decoded = loadedData {
            self.settings = decoded.settings
            self.sessions = decoded.sessions
            
            // Clean out any self-tracker app entries from existing historical sessions
            for i in 0..<self.sessions.count {
                for ignored in Self.ignoredAppNames {
                    self.sessions[i].appUsage.removeValue(forKey: ignored)
                }
            }
            
            pruneOldSessions()
        } else {
            self.settings = .default
            self.sessions = []
        }
        
        // Import legacy Pomodoro sessions if MacUsageTracker is brand new or empty
        if self.sessions.isEmpty {
            importLegacyPomodoroDataIfNeeded()
        }
    }
    
    public func save() {
        pruneOldSessions()
        let appData = AppData(settings: settings, sessions: sessions)
        do {
            let data = try JSONEncoder().encode(appData)
            
            // Create automated backup before overwriting
            let backupURL = fileURL.deletingPathExtension().appendingPathExtension("bak")
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try? FileManager.default.removeItem(at: backupURL)
                try? FileManager.default.copyItem(at: fileURL, to: backupURL)
            }
            
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save data: \(error)")
        }
    }
    
    private func importLegacyPomodoroDataIfNeeded() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let legacyDir = appSupport.appendingPathComponent("PomodoroTimetable", isDirectory: true)
        let legacyFile = legacyDir.appendingPathComponent("data.json")
        guard FileManager.default.fileExists(atPath: legacyFile.path),
              let data = try? Data(contentsOf: legacyFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let timerRecords = json["timerRecords"] as? [[String: Any]] else {
            return
        }
        
        var importedSessions: [UsageSession] = []
        for record in timerRecords {
            let idString = record["id"] as? String ?? UUID().uuidString
            let id = UUID(uuidString: idString) ?? UUID()
            let durationSeconds = record["durationSecondsUsed"] as? Int ?? ((record["durationMinutes"] as? Int ?? 25) * 60)
            guard durationSeconds >= 30 else { continue }
            
            let timestamp = record["timestamp"] as? TimeInterval ?? 0
            let completedAt = record["completedAt"] as? TimeInterval ?? (timestamp + Double(durationSeconds))
            let startTime = Date(timeIntervalSinceReferenceDate: timestamp)
            let endTime = Date(timeIntervalSinceReferenceDate: completedAt)
            
            importedSessions.append(UsageSession(
                id: id,
                startTime: startTime,
                endTime: endTime,
                durationSeconds: durationSeconds,
                appUsage: [:],
                websiteUsage: [:]
            ))
        }
        
        if !importedSessions.isEmpty {
            self.sessions.append(contentsOf: importedSessions)
            save()
            print("Successfully migrated \(importedSessions.count) legacy sessions from PomodoroTimetable")
        }
    }
    
    // MARK: - 35-Day Retention Management (Full Monthly Analysis)
    
    /// Prunes any session records older than 35 days from the reference date.
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
    
    /// Returns all sessions stored for the last N days (default 35 days for full month analysis).
    public func sessionsInLastDays(days: Int = 35, referenceDate: Date = Date()) -> [UsageSession] {
        let retention = TimeInterval(days * 24 * 60 * 60)
        let cutoff = referenceDate.addingTimeInterval(-retention)
        return sessions
            .filter { $0.startTime >= cutoff }
            .sorted { $0.startTime > $1.startTime }
    }
    
    /// Returns all sessions stored within the 35-day retention period.
    public func sessionsInRetentionPeriod(referenceDate: Date = Date()) -> [UsageSession] {
        return sessionsInLastDays(days: Self.retentionDays, referenceDate: referenceDate)
    }
    
    /// Convenience helper for 7-day query
    public func sessionsInLast7Days(referenceDate: Date = Date()) -> [UsageSession] {
        return sessionsInLastDays(days: 7, referenceDate: referenceDate)
    }
    
    /// Total seconds of Mac screen time over the specified number of days (default 35 days).
    public func totalPeriodSeconds(days: Int = 35, referenceDate: Date = Date(), liveCurrentDuration: TimeInterval = 0) -> Int {
        let completed = sessionsInLastDays(days: days, referenceDate: referenceDate).reduce(0) { $0 + $1.durationSeconds }
        return completed + Int(liveCurrentDuration)
    }
    
    /// Total seconds over the last 7 days.
    public func total7DaySeconds(referenceDate: Date = Date(), liveCurrentDuration: TimeInterval = 0) -> Int {
        return totalPeriodSeconds(days: 7, referenceDate: referenceDate, liveCurrentDuration: liveCurrentDuration)
    }
    
    /// Formatted total screen time for the specified number of days.
    public func totalPeriodFormatted(days: Int = 35, referenceDate: Date = Date(), liveCurrentDuration: TimeInterval = 0) -> String {
        let total = totalPeriodSeconds(days: days, referenceDate: referenceDate, liveCurrentDuration: liveCurrentDuration)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
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

    // MARK: - Top Programs & Websites Aggregation

    public static let ignoredAppNames: Set<String> = [
        "Mac Usage Tracker",
        "MacUsageTracker",
        "PomodoroTimetable",
        "Pomodoro Timetable"
    ]

    /// Aggregates program usage across the given sessions and optional live session, excluding the tracker itself.
    public func topPrograms(
        sessions: [UsageSession],
        limit: Int = 10,
        liveAppUsage: [String: Int] = [:]
    ) -> [AppUsageStat] {
        var totals = liveAppUsage
        for session in sessions {
            for (app, secs) in session.appUsage {
                totals[app, default: 0] += secs
            }
        }
        for ignored in Self.ignoredAppNames {
            totals.removeValue(forKey: ignored)
        }
        let totalSecs = max(1, totals.values.reduce(0, +))
        return totals
            .filter { !Self.ignoredAppNames.contains($0.key) && $0.value > 0 }
            .map { AppUsageStat(name: $0.key, durationSeconds: $0.value, percentage: Double($0.value) / Double(totalSecs)) }
            .sorted { $0.durationSeconds > $1.durationSeconds }
            .prefix(limit)
            .map { $0 }
    }

    /// Aggregates top programs over the last N days.
    public func topPrograms(
        days: Int = 35,
        limit: Int = 10,
        liveAppUsage: [String: Int] = [:]
    ) -> [AppUsageStat] {
        topPrograms(sessions: sessionsInLastDays(days: days), limit: limit, liveAppUsage: liveAppUsage)
    }

    /// Aggregates website domain usage across the given sessions and optional live session.
    public func topWebsites(
        sessions: [UsageSession],
        limit: Int = 10,
        liveWebsiteUsage: [String: Int] = [:]
    ) -> [WebsiteUsageStat] {
        var totals = liveWebsiteUsage
        for session in sessions {
            for (domain, secs) in session.websiteUsage {
                totals[domain, default: 0] += secs
            }
        }
        let totalSecs = max(1, totals.values.reduce(0, +))
        return totals
            .filter { $0.value > 0 }
            .map { WebsiteUsageStat(domain: $0.key, durationSeconds: $0.value, percentage: Double($0.value) / Double(totalSecs)) }
            .sorted { $0.durationSeconds > $1.durationSeconds }
            .prefix(limit)
            .map { $0 }
    }

    /// Aggregates top websites over the last N days.
    public func topWebsites(
        days: Int = 35,
        limit: Int = 10,
        liveWebsiteUsage: [String: Int] = [:]
    ) -> [WebsiteUsageStat] {
        topWebsites(sessions: sessionsInLastDays(days: days), limit: limit, liveWebsiteUsage: liveWebsiteUsage)
    }
    
    /// Clears all stored sessions manually.
    public func clearAllSessions() {
        sessions.removeAll()
        save()
    }
}
