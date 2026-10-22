import Foundation

public struct TimetableBlock: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var notes: String
    public var categoryId: UUID
    
    /// Anchor date for single occurrences or creation baseline for recurring rules
    public var date: Date
    
    /// Minute of day from 0 to 1439 (e.g., 09:30 AM = 9 * 60 + 30 = 570)
    public var startMinuteOfDay: Int
    
    /// Duration in minutes (e.g., 45, 60, 90)
    public var durationMinutes: Int
    
    /// Target number of pomodoro sessions planned for this block
    public var targetPomodoros: Int
    
    /// Completed pomodoro sessions logged
    public var completedPomodoros: Int
    
    /// Manual completion flag
    public var isCompleted: Bool
    
    /// Recurrence rule (none, daily, weekdays, custom)
    public var recurrenceRule: RecurrenceRule
    
    /// Optional buffer gap after this block (e.g., 5, 10, 15 minutes)
    public var bufferAfterMinutes: Int

    public init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        categoryId: UUID,
        date: Date = Date(),
        startMinuteOfDay: Int = 540, // 9:00 AM
        durationMinutes: Int = 60,
        targetPomodoros: Int = 2,
        completedPomodoros: Int = 0,
        isCompleted: Bool = false,
        recurrenceRule: RecurrenceRule = .none,
        bufferAfterMinutes: Int = 0
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.categoryId = categoryId
        self.date = date
        self.startMinuteOfDay = startMinuteOfDay
        self.durationMinutes = max(15, durationMinutes)
        self.targetPomodoros = max(1, targetPomodoros)
        self.completedPomodoros = completedPomodoros
        self.isCompleted = isCompleted
        self.recurrenceRule = recurrenceRule
        self.bufferAfterMinutes = bufferAfterMinutes
    }

    public var endMinuteOfDay: Int {
        startMinuteOfDay + durationMinutes
    }

    public var startTimeFormatted: String {
        let hours = startMinuteOfDay / 60
        let minutes = startMinuteOfDay % 60
        return String(format: "%02d:%02d", hours, minutes)
    }

    public var endTimeFormatted: String {
        let total = endMinuteOfDay
        let hours = (total / 60) % 24
        let minutes = total % 60
        return String(format: "%02d:%02d", hours, minutes)
    }

    public var timeRangeFormatted: String {
        "\(startTimeFormatted) – \(endTimeFormatted)"
    }

    /// Determines if this block occurs on a given calendar date
    public func occursOn(date targetDate: Date, calendar: Calendar = .current) -> Bool {
        if recurrenceRule.frequency == .none {
            return calendar.isDate(date, inSameDayAs: targetDate)
        } else {
            return recurrenceRule.matches(date: targetDate, calendar: calendar)
        }
    }
}
