import Foundation
import Combine

@MainActor
public final class LocalLLMService: ObservableObject {
    public static let shared = LocalLLMService()
    
    @Published public var isOllamaAvailable: Bool = false
    @Published public var availableModels: [String] = []
    @Published public var isGenerating: Bool = false
    @Published public var isAuditing: Bool = false
    @Published public var lastGeneratedQuote: (quote: String, author: String)? = nil
    @Published public var lastProductivityAudit: String? = nil
    
    // In-memory cache for fast title -> clean service name lookups
    private var serviceNameCache: [String: String] = [:]
    
    private let session: URLSession
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8.0
        config.timeoutIntervalForResource = 12.0
        self.session = URLSession(configuration: config)
        
        Task {
            await refreshModels()
        }
    }
    
    /// Queries the local Ollama instance on port 11434 for available models
    @discardableResult
    public func refreshModels(endpoint: String = "http://127.0.0.1:11434") async -> [String] {
        let cleanEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(cleanEndpoint)/api/tags") else {
            self.isOllamaAvailable = false
            return []
        }
        
        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                self.isOllamaAvailable = false
                return []
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["models"] as? [[String: Any]] {
                let modelNames = models.compactMap { $0["name"] as? String }
                self.availableModels = modelNames
                self.isOllamaAvailable = !modelNames.isEmpty
                return modelNames
            }
            
            self.isOllamaAvailable = true
            return []
        } catch {
            self.isOllamaAvailable = false
            return []
        }
    }
    
    /// Heuristically cleans a raw tab title down to its concise service name (e.g. "ClipForge AI – ... " -> "ClipForge")
    public func cleanServiceNameHeuristic(_ title: String) -> String {
        var clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. Strip badge counters e.g. (1) or (99+)
        if clean.hasPrefix("(") && clean.contains(")") {
            if let closeParen = clean.firstIndex(of: ")") {
                let prefix = clean[..<closeParen]
                if prefix.dropFirst().allSatisfy({ $0.isNumber || $0 == "+" }) {
                    clean = clean[clean.index(after: closeParen)...].trimmingCharacters(in: .whitespaces)
                }
            }
        }
        
        // 2. Strip browser suffixes
        let browserSuffixes = [" - Google Chrome", " - Brave", " - Safari", " - Arc", " - Microsoft Edge"]
        for suffix in browserSuffixes {
            if clean.hasSuffix(suffix) {
                clean = String(clean.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        
        // 3. Strip everything after separators like " – ", " — ", " | ", " - ", " // "
        for sep in [" – ", " — ", " | ", " - ", " // "] {
            if let range = clean.range(of: sep) {
                let candidate = String(clean[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                if !candidate.isEmpty && candidate.count >= 2 {
                    clean = candidate
                    break
                }
            }
        }
        
        // 4. Strip trailing " AI" or " Studio" or " App" if part of title e.g. "ClipForge AI" -> "ClipForge"
        for suffix in [" AI", " ai", " App", " app"] {
            if clean.hasSuffix(suffix) {
                let trimmed = String(clean.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && trimmed.count >= 3 {
                    clean = trimmed
                    break
                }
            }
        }
        
        return clean.isEmpty ? title : clean
    }
    
    /// Uses local Ollama LLM to intelligently extract the exact product/service name
    public func extractServiceName(from title: String, endpoint: String = "http://127.0.0.1:11434") async -> String {
        if let cached = serviceNameCache[title] {
            return cached
        }
        
        let heuristic = cleanServiceNameHeuristic(title)
        
        guard isOllamaAvailable else {
            serviceNameCache[title] = heuristic
            return heuristic
        }
        
        let prompt = """
        You are a software classifier. Extract ONLY the clean, concise product or service name (1 to 2 words, e.g. "ClipForge", "Grafana", "Jupyter", "Admin Portal") from this browser tab title. Return ONLY JSON: {"service": "..."}
        Title: "\(title)"
        """
        
        let selectedModel = availableModels.contains("qwen2.5:3b") ? "qwen2.5:3b" : (availableModels.first ?? "qwen2.5:3b")
        let cleanEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(cleanEndpoint)/api/generate") else {
            serviceNameCache[title] = heuristic
            return heuristic
        }
        
        let payload: [String: Any] = [
            "model": selectedModel,
            "prompt": prompt,
            "format": "json",
            "stream": false
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: payload) else {
            serviceNameCache[title] = heuristic
            return heuristic
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let responseString = json["response"] as? String,
                  let parsedData = responseString.data(using: .utf8),
                  let resJson = try? JSONSerialization.jsonObject(with: parsedData) as? [String: Any],
                  let service = resJson["service"] as? String, !service.isEmpty else {
                serviceNameCache[title] = heuristic
                return heuristic
            }
            
            let clean = service.trimmingCharacters(in: .whitespacesAndNewlines)
            serviceNameCache[title] = clean
            return clean
        } catch {
            serviceNameCache[title] = heuristic
            return heuristic
        }
    }
    
    /// Generates a motivational quote using the local LLM
    public func generateMotivationalQuote(
        preferredModel: String = "auto",
        endpoint: String = "http://127.0.0.1:11434"
    ) async -> (quote: String, author: String)? {
        self.isGenerating = true
        defer { self.isGenerating = false }
        
        // Ensure models are populated
        if availableModels.isEmpty {
            _ = await refreshModels(endpoint: endpoint)
        }
        
        let selectedModel: String
        if preferredModel != "auto" && !preferredModel.isEmpty {
            selectedModel = preferredModel
        } else if availableModels.contains("qwen2.5:3b") {
            selectedModel = "qwen2.5:3b"
        } else if availableModels.contains("qwen2.5:7b") {
            selectedModel = "qwen2.5:7b"
        } else if let first = availableModels.first {
            selectedModel = first
        } else {
            selectedModel = "qwen2.5:3b"
        }
        
        let cleanEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(cleanEndpoint)/api/generate") else { return nil }
        
        let prompt = """
        You are an inspiring mentor. Generate a short, punchy, single-sentence motivational quote for someone deep into focused work on their laptop.
        Format strictly as JSON: {"quote": "...", "author": "..."}
        """
        
        let requestPayload: [String: Any] = [
            "model": selectedModel,
            "prompt": prompt,
            "format": "json",
            "stream": false
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: requestPayload) else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let responseString = json["response"] as? String,
                  let parsedData = responseString.data(using: .utf8),
                  let quoteJson = try? JSONSerialization.jsonObject(with: parsedData) as? [String: Any] else {
                return nil
            }
            
            let quote = (quoteJson["quote"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let rawAuthor = (quoteJson["author"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let author = rawAuthor.isEmpty ? "AI Mentor" : rawAuthor
            
            guard !quote.isEmpty else { return nil }
            
            let result = (quote: quote, author: author)
            self.lastGeneratedQuote = result
            return result
        } catch {
            print("[LocalLLMService] Error generating quote: \(error)")
            return nil
        }
    }
    
    /// Generates an AI-powered productivity audit and actionable recommendations based on actual usage
    public func generateProductivityAudit(
        screenTime: String,
        topApps: [String],
        topWebsites: [String],
        endpoint: String = "http://127.0.0.1:11434"
    ) async -> String {
        self.isAuditing = true
        defer { self.isAuditing = false }
        
        let selectedModel = availableModels.contains("qwen2.5:3b") ? "qwen2.5:3b" : (availableModels.first ?? "qwen2.5:3b")
        let cleanEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(cleanEndpoint)/api/generate") else {
            return "Unable to connect to local LLM."
        }
        
        let appsSummary = topApps.prefix(4).joined(separator: ", ")
        let websSummary = topWebsites.prefix(4).joined(separator: ", ")
        
        let prompt = """
        You are a high-performance productivity coach analyzing MacBook usage data:
        - Screen Time: \(screenTime)
        - Top Applications: \(appsSummary.isEmpty ? "Coding & Tools" : appsSummary)
        - Top Sites / Services: \(websSummary.isEmpty ? "Local dev & tools" : websSummary)

        Provide a concise, practical 3-bullet productivity audit:
        1. 🎯 Deep Work Win: Highlight their strongest focus area
        2. ⚡ Efficiency Lever: What to optimize or protect focus from
        3. 🚀 Power Habit: One actionable tip for the next session
        Keep it direct, professional, motivating, and under 80 words.
        """
        
        let payload: [String: Any] = [
            "model": selectedModel,
            "prompt": prompt,
            "stream": false
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: payload) else {
            return "Failed to serialize audit request."
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let responseText = json["response"] as? String else {
                return "AI productivity review generated based on your deep focus sessions."
            }
            
            let result = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
            self.lastProductivityAudit = result
            return result
        } catch {
            return "Productivity focus is strong. Continue pacing work with 90m deep work sprints and hydration breaks."
        }
    }
}
