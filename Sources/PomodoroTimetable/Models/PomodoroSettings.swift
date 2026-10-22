import Foundation

public struct PomodoroSettings: Codable, Sendable {
    public var workDurationMinutes: Int
    public var shortBreakDurationMinutes: Int
    public var longBreakDurationMinutes: Int
    public var longBreakInterval: Int
    public var playSoundChime: Bool
    public var sendNotifications: Bool
    public var defaultBufferMinutes: Int

    public init(
        workDurationMinutes: Int = 25,
        shortBreakDurationMinutes: Int = 5,
        longBreakDurationMinutes: Int = 15,
        longBreakInterval: Int = 4,
        playSoundChime: Bool = true,
        sendNotifications: Bool = true,
        defaultBufferMinutes: Int = 5
    ) {
        self.workDurationMinutes = workDurationMinutes
        self.shortBreakDurationMinutes = shortBreakDurationMinutes
        self.longBreakDurationMinutes = longBreakDurationMinutes
        self.longBreakInterval = longBreakInterval
        self.playSoundChime = playSoundChime
        self.sendNotifications = sendNotifications
        self.defaultBufferMinutes = defaultBufferMinutes
    }

    public static let `default` = PomodoroSettings()
}
