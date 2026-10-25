import Foundation

public struct AppSettings: Codable, Sendable, Equatable {
    public var minimumSessionSeconds: Int // e.g. 60 seconds (1 minute threshold)
    public var launchAtLogin: Bool
    public var enableHydrateReminder: Bool // Every 90 mins: stretch & hydrate
    public var enableMotivationalQuotes: Bool // Every 60 mins: inspiring quote
    public var enableTenHourReminder: Bool // At 10 hours: end of day reminder
    public var useLocalLLMForQuotes: Bool // Source quotes from local LLM (Ollama)
    public var localLLMEndpoint: String // e.g. "http://127.0.0.1:11434"
    public var localLLMModel: String // "auto" or specific model name

    public init(
        minimumSessionSeconds: Int = 60,
        launchAtLogin: Bool = true,
        enableHydrateReminder: Bool = true,
        enableMotivationalQuotes: Bool = true,
        enableTenHourReminder: Bool = true,
        useLocalLLMForQuotes: Bool = true,
        localLLMEndpoint: String = "http://127.0.0.1:11434",
        localLLMModel: String = "auto"
    ) {
        self.minimumSessionSeconds = minimumSessionSeconds
        self.launchAtLogin = launchAtLogin
        self.enableHydrateReminder = enableHydrateReminder
        self.enableMotivationalQuotes = enableMotivationalQuotes
        self.enableTenHourReminder = enableTenHourReminder
        self.useLocalLLMForQuotes = useLocalLLMForQuotes
        self.localLLMEndpoint = localLLMEndpoint
        self.localLLMModel = localLLMModel
    }

    public static let `default` = AppSettings()
    
    // Custom decoding for backward compatibility
    enum CodingKeys: String, CodingKey {
        case minimumSessionSeconds
        case launchAtLogin
        case enableHydrateReminder
        case enableMotivationalQuotes
        case enableTenHourReminder
        case useLocalLLMForQuotes
        case localLLMEndpoint
        case localLLMModel
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.minimumSessionSeconds = (try? container.decode(Int.self, forKey: .minimumSessionSeconds)) ?? 60
        self.launchAtLogin = (try? container.decode(Bool.self, forKey: .launchAtLogin)) ?? true
        self.enableHydrateReminder = (try? container.decode(Bool.self, forKey: .enableHydrateReminder)) ?? true
        self.enableMotivationalQuotes = (try? container.decode(Bool.self, forKey: .enableMotivationalQuotes)) ?? true
        self.enableTenHourReminder = (try? container.decode(Bool.self, forKey: .enableTenHourReminder)) ?? true
        self.useLocalLLMForQuotes = (try? container.decode(Bool.self, forKey: .useLocalLLMForQuotes)) ?? true
        self.localLLMEndpoint = (try? container.decode(String.self, forKey: .localLLMEndpoint)) ?? "http://127.0.0.1:11434"
        self.localLLMModel = (try? container.decode(String.self, forKey: .localLLMModel)) ?? "auto"
    }
}
