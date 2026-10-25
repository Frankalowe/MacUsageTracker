import Foundation

public struct UsageSession: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let startTime: Date             // When the Mac turned on or woke up
    public var endTime: Date               // When the Mac slept or shut down
    public var durationSeconds: Int        // Total duration in seconds

    public init(
        id: UUID = UUID(),
        startTime: Date = Date(),
        endTime: Date = Date(),
        durationSeconds: Int = 0
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.durationSeconds = durationSeconds
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
