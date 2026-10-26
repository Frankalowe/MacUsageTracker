import Foundation

public struct UsageSession: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let startTime: Date             // When the Mac turned on or woke up
    public var endTime: Date               // When the Mac slept or shut down
    public var durationSeconds: Int        // Total duration in seconds
    public var appUsage: [String: Int]     // App name -> seconds spent
    public var websiteUsage: [String: Int] // Domain -> seconds spent

    public init(
        id: UUID = UUID(),
        startTime: Date = Date(),
        endTime: Date = Date(),
        durationSeconds: Int = 0,
        appUsage: [String: Int] = [:],
        websiteUsage: [String: Int] = [:]
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.durationSeconds = durationSeconds
        self.appUsage = appUsage
        self.websiteUsage = websiteUsage
    }
    
    // Backwards-compatible decoding
    enum CodingKeys: String, CodingKey {
        case id
        case startTime
        case endTime
        case durationSeconds
        case appUsage
        case websiteUsage
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.startTime = (try? container.decode(Date.self, forKey: .startTime)) ?? Date()
        self.endTime = (try? container.decode(Date.self, forKey: .endTime)) ?? Date()
        self.durationSeconds = (try? container.decode(Int.self, forKey: .durationSeconds)) ?? 0
        self.appUsage = (try? container.decode([String: Int].self, forKey: .appUsage)) ?? [:]
        self.websiteUsage = (try? container.decode([String: Int].self, forKey: .websiteUsage)) ?? [:]
    }

    // MARK: - Formatting Helpers

    public var timeRangeFormatted: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(formatter.string(from: startTime)) – \(formatter.string(from: endTime))"
    }

    public var startTimeFormatted: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: startTime)
    }

    public var endTimeFormatted: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: endTime)
    }

    public var dateFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: startTime)
    }

    public var relativeDateSectionTitle: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(startTime) {
            return "Today"
        } else if calendar.isDateInYesterday(startTime) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMM d"
            return formatter.string(from: startTime)
        }
    }

    public var durationFormatted: String {
        let hours = durationSeconds / 3600
        let minutes = (durationSeconds % 3600) / 60
        let seconds = durationSeconds % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }

    public func isWithinLast7Days(referenceDate: Date = Date()) -> Bool {
        isWithinRetentionPeriod(referenceDate: referenceDate, days: 7)
    }

    public func isWithinRetentionPeriod(referenceDate: Date = Date(), days: Int = 35) -> Bool {
        let retentionSeconds: TimeInterval = TimeInterval(days * 24 * 60 * 60)
        return startTime >= referenceDate.addingTimeInterval(-retentionSeconds)
    }
}

public struct DayUsageSummary: Identifiable, Sendable {
    public var id: String { dateKey }
    public let date: Date
    public let dateKey: String
    public let dayLabel: String
    public let isToday: Bool
    public let sessionCount: Int
    public let totalSeconds: Int

    public var totalHoursFormatted: String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "0m"
        }
    }

    public init(
        date: Date,
        dayLabel: String,
        isToday: Bool,
        sessionCount: Int,
        totalSeconds: Int
    ) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        self.dateKey = formatter.string(from: date)
        self.date = date
        self.dayLabel = dayLabel
        self.isToday = isToday
        self.sessionCount = sessionCount
        self.totalSeconds = totalSeconds
    }
}

public struct AppUsageStat: Identifiable, Sendable, Equatable, Codable {
    public var id: String { name }
    public let name: String
    public let durationSeconds: Int
    public let percentage: Double // 0.0 ... 1.0

    public var durationFormatted: String {
        let hours = durationSeconds / 3600
        let minutes = (durationSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "\(durationSeconds)s"
        }
    }

    public init(name: String, durationSeconds: Int, percentage: Double) {
        self.name = name
        self.durationSeconds = durationSeconds
        self.percentage = percentage
    }
}

public struct WebsiteUsageStat: Identifiable, Sendable, Equatable, Codable {
    public var id: String { domain }
    public let domain: String
    public let durationSeconds: Int
    public let percentage: Double // 0.0 ... 1.0

    public var durationFormatted: String {
        let hours = durationSeconds / 3600
        let minutes = (durationSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "\(durationSeconds)s"
        }
    }

    public init(domain: String, durationSeconds: Int, percentage: Double) {
        self.domain = domain
        self.durationSeconds = durationSeconds
        self.percentage = percentage
    }
}

public struct ActiveSessionState: Codable, Sendable {
    public var sessionStartTime: Date
    public var lastHeartbeat: Date
    public var liveAppUsage: [String: Int]
    public var liveWebsiteUsage: [String: Int]
    public var lastQuoteIntervalIndex: Int
    public var lastStretchIntervalIndex: Int
    public var last10HourNotifiedDateKey: String?
    
    public init(
        sessionStartTime: Date,
        lastHeartbeat: Date = Date(),
        liveAppUsage: [String: Int] = [:],
        liveWebsiteUsage: [String: Int] = [:],
        lastQuoteIntervalIndex: Int = 0,
        lastStretchIntervalIndex: Int = 0,
        last10HourNotifiedDateKey: String? = nil
    ) {
        self.sessionStartTime = sessionStartTime
        self.lastHeartbeat = lastHeartbeat
        self.liveAppUsage = liveAppUsage
        self.liveWebsiteUsage = liveWebsiteUsage
        self.lastQuoteIntervalIndex = lastQuoteIntervalIndex
        self.lastStretchIntervalIndex = lastStretchIntervalIndex
        self.last10HourNotifiedDateKey = last10HourNotifiedDateKey
    }
}
