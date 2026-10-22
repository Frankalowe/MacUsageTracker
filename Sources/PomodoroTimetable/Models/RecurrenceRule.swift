import Foundation

public enum RecurrenceFrequency: String, Codable, CaseIterable, Sendable {
    case none = "None"
    case daily = "Every Day"
    case weekdays = "Weekdays (Mon-Fri)"
    case customWeekly = "Custom Days"
}

public struct RecurrenceRule: Codable, Hashable, Sendable {
    public var frequency: RecurrenceFrequency
    /// Days of week: 1 = Sunday, 2 = Monday, ..., 7 = Saturday (matching Calendar.current weekday components)
    public var daysOfWeek: [Int]

    public init(frequency: RecurrenceFrequency = .none, daysOfWeek: [Int] = []) {
        self.frequency = frequency
        self.daysOfWeek = daysOfWeek
    }

    public static let none = RecurrenceRule(frequency: .none)
    public static let daily = RecurrenceRule(frequency: .daily)
    public static let weekdays = RecurrenceRule(frequency: .weekdays, daysOfWeek: [2, 3, 4, 5, 6])

    /// Checks if this rule matches a specific calendar date
    public func matches(date: Date, calendar: Calendar = .current) -> Bool {
        switch frequency {
        case .none:
            return false // Checked by exact block date
        case .daily:
            return true
        case .weekdays:
            let weekday = calendar.component(.weekday, from: date)
            return weekday >= 2 && weekday <= 6 // Mon - Fri
        case .customWeekly:
            let weekday = calendar.component(.weekday, from: date)
            return daysOfWeek.contains(weekday)
        }
    }

    public var displayName: String {
        switch frequency {
        case .none:
            return "Does not repeat"
        case .daily:
            return "Daily"
        case .weekdays:
            return "Weekdays"
        case .customWeekly:
            let symbols = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            let dayNames = daysOfWeek.sorted().compactMap { index -> String? in
                guard index >= 1 && index <= 7 else { return nil }
                return symbols[index]
            }
            return dayNames.isEmpty ? "Custom Weekly" : "Every " + dayNames.joined(separator: ", ")
        }
    }
}
