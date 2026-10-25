import Foundation

public struct AppSettings: Codable, Sendable, Equatable {
    public var minimumSessionSeconds: Int // e.g. 60 seconds (1 minute threshold)
    public var launchAtLogin: Bool
    public var enableHydrateReminder: Bool // Every 90 mins: stretch & hydrate
    public var enableMotivationalQuotes: Bool // Every 60 mins: inspiring quote
    public var enableTenHourReminder: Bool // At 10 hours: end of day reminder

    public init(
        minimumSessionSeconds: Int = 60,
        launchAtLogin: Bool = true,
        enableHydrateReminder: Bool = true,
        enableMotivationalQuotes: Bool = true,
        enableTenHourReminder: Bool = true
    ) {
        self.minimumSessionSeconds = minimumSessionSeconds
        self.launchAtLogin = launchAtLogin
        self.enableHydrateReminder = enableHydrateReminder
        self.enableMotivationalQuotes = enableMotivationalQuotes
        self.enableTenHourReminder = enableTenHourReminder
    }

    public static let `default` = AppSettings()
    
    // Custom decoding for backward compatibility
    enum CodingKeys: String, CodingKey {
        case minimumSessionSeconds
        case launchAtLogin
        case enableHydrateReminder
        case enableMotivationalQuotes
        case enableTenHourReminder
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.minimumSessionSeconds = (try? container.decode(Int.self, forKey: .minimumSessionSeconds)) ?? 60
        self.launchAtLogin = (try? container.decode(Bool.self, forKey: .launchAtLogin)) ?? true
        self.enableHydrateReminder = (try? container.decode(Bool.self, forKey: .enableHydrateReminder)) ?? true
        self.enableMotivationalQuotes = (try? container.decode(Bool.self, forKey: .enableMotivationalQuotes)) ?? true
        self.enableTenHourReminder = (try? container.decode(Bool.self, forKey: .enableTenHourReminder)) ?? true
    }
}
