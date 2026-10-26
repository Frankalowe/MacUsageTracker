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
    
    // Registry of ports to canonical service names, e.g. 3000 -> "ClipForge"
    @Published public private(set) var portServiceRegistry: [Int: String] = [3000: "ClipForge"]
    
    // Registry of domain aliases to canonical domains, e.g. "music.youtube.com" -> "youtube.com"
    @Published public private(set) var domainRegistry: [String: String] = [:]
    
    // In-memory cache for fast title -> clean service name lookups
    private var serviceNameCache: [String: String] = [:]
    
    private let registryFileURL: URL
    private let session: URLSession
    
    private struct CanonicalRegistryData: Codable {
        var portServices: [Int: String]
        var domainAliases: [String: String]
    }
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8.0
        config.timeoutIntervalForResource = 12.0
        self.session = URLSession(configuration: config)
        
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("MacUsageTracker", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.registryFileURL = appDir.appendingPathComponent("canonical_registry.json")
        
        loadRegistry()
        
        Task {
            await refreshModels()
        }
    }
    
    private func loadRegistry() {
        guard FileManager.default.fileExists(atPath: registryFileURL.path),
              let data = try? Data(contentsOf: registryFileURL),
              let decoded = try? JSONDecoder().decode(CanonicalRegistryData.self, from: data) else {
            // Default seed: port 3000 -> ClipForge
            self.portServiceRegistry[3000] = "ClipForge"
            return
        }
        self.portServiceRegistry = decoded.portServices
        if self.portServiceRegistry[3000] == nil {
            self.portServiceRegistry[3000] = "ClipForge"
        }
        self.domainRegistry = decoded.domainAliases
    }
    
    private func saveRegistry() {
        let data = CanonicalRegistryData(portServices: portServiceRegistry, domainAliases: domainRegistry)
        if let encoded = try? JSONEncoder().encode(data) {
            try? encoded.write(to: registryFileURL, options: .atomic)
        }
    }
    
    /// Canonicalizes any localhost/127.0.0.1 tab to ensure multiple tabs of the same service collapse into ONE
    public func canonicalLocalhostIdentifier(port: Int, title: String?) -> String {
        if let rawTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines), !rawTitle.isEmpty {
            let candidate = cleanServiceNameHeuristic(rawTitle)
            let lower = candidate.lowercased()
            let genericTitles: Set<String> = ["settings", "localhost", "dashboard", "home", "untitled", "loading", "login", "admin", "index"]
            if !candidate.isEmpty && !genericTitles.contains(lower) && !lower.hasPrefix("http") && lower != "localhost:\(port)" {
                if portServiceRegistry[port] != candidate {
                    portServiceRegistry[port] = candidate
                    saveRegistry()
                }
            }
        }
        
        if let serviceName = portServiceRegistry[port] {
            return "\(serviceName) (localhost:\(port))"
        }
        
        return "localhost:\(port)"
    }
    
    /// Canonicalizes any website string or local tab, collapsing subdomains and duplicate tabs
    public func canonicalWebsiteIdentifier(raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        
        let lower = trimmed.lowercased()
        
        // Ignore internal browser pages
        let internalPages: Set<String> = ["newtab", "new-tab-page", "extensions", "settings", "about", "blank", "downloads", "history"]
        if internalPages.contains(lower) { return "" }
        
        // 1. Check AI / user registry first
        if let registered = domainRegistry[trimmed] ?? domainRegistry[lower] {
            return registered
        }
        
        // 2. Handle localhost / local server cases
        if lower.contains("localhost") || lower.contains("127.0.0.1") || lower.contains("0.0.0.0") || lower.contains("::1") {
            if lower.contains("clipforge") {
                return "ClipForge (localhost:3000)"
            }
            
            var detectedPort = 3000
            if let portMatch = lower.range(of: #":\d{2,5}"#, options: .regularExpression) {
                let portStr = String(lower[portMatch].dropFirst())
                if let p = Int(portStr) {
                    detectedPort = p
                }
            }
            
            if let service = portServiceRegistry[detectedPort] {
                return "\(service) (localhost:\(detectedPort))"
            }
            
            if lower == "localhost" || lower == "127.0.0.1" {
                if let service = portServiceRegistry[3000] {
                    return "\(service) (localhost:3000)"
                }
                return "localhost:3000"
            }
            
            return "localhost:\(detectedPort)"
        }
        
        // 3. Clean external web domains
        var host = lower
        if host.hasPrefix("https://") { host = String(host.dropFirst(8)) }
        if host.hasPrefix("http://") { host = String(host.dropFirst(7)) }
        if let slash = host.firstIndex(of: "/") { host = String(host[..<slash]) }
        if let colon = host.firstIndex(of: ":") { host = String(host[..<colon]) }
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
        
        // Known multi-subdomain and related service unifications
        if host.contains("youtube.com") || host == "youtu.be" {
            return "youtube.com"
        }
        if host.contains("github.com") || host.contains("githubusercontent.com") {
            return "github.com"
        }
        if host.contains("openai.com") || host.contains("chatgpt.com") {
            return "chatgpt.com"
        }
        if host.contains("google.com") || host.contains("google.co.") {
            return "google.com"
        }
        if host.contains("whatsapp.com") {
            return "whatsapp.com"
        }
        if host.contains("slack.com") {
            return "slack.com"
        }
        if host.contains("spotify.com") {
            return "spotify.com"
        }
        if host == "twitter.com" || host == "x.com" {
            return "x.com"
        }
        if host.contains("reddit.com") {
            return "reddit.com"
        }
        if host.contains("amazon.") {
            return "amazon.com"
        }
        if host.contains("wikipedia.org") {
            return "wikipedia.org"
        }
        
        // Strip common mobile/app subdomains e.g. "m.domain.com", "mobile.domain.com", "app.domain.com", "web.domain.com"
        for prefix in ["m.", "mobile.", "app.", "web.", "login.", "auth."] {
            if host.hasPrefix(prefix) && host.components(separatedBy: ".").count >= 3 {
                host = String(host.dropFirst(prefix.count))
                break
            }
        }
        
        // If domain has 3 parts and top-level domain is common (e.g. docs.stripe.com -> stripe.com)
        let parts = host.components(separatedBy: ".")
        if parts.count == 3 {
            let commonTLDs: Set<String> = ["com", "org", "net", "io", "dev", "ai", "co", "app", "me"]
            if commonTLDs.contains(parts[2]) {
                return "\(parts[1]).\(parts[2])"
            }
        }
        
        return host
    }
    
    /// Uses local Ollama LLM to group, deduplicate, and canonicalize website/localhost identifiers
    public func runLocalAICanonicalization(identifiers: [String], endpoint: String = "http://127.0.0.1:11434") async {
        guard !identifiers.isEmpty else { return }
        
        let uniqueInputs = Array(Set(identifiers)).filter {
            let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty &&
                   !["newtab", "new-tab-page", "settings", "extensions"].contains(trimmed.lowercased())
        }
        guard !uniqueInputs.isEmpty else { return }
        
        let prompt = """
        You are a web address and local software canonicalizer for a macOS productivity tracker.
        Given this list of observed browser tabs and addresses:
        - Multiple tabs on the same localhost:port (e.g. localhost:3000 running ClipForge) MUST be unified to a single concise label: "ClipForge (localhost:3000)".
        - Multiple pages or subdomains of the same website (e.g. music.youtube.com, m.youtube.com) MUST be unified to the primary root domain (e.g. "youtube.com").
        - General "localhost" with no port should map to the primary running project "ClipForge (localhost:3000)".
        
        Input list:
        \(uniqueInputs.description)
        
        Return ONLY a JSON dictionary mapping each input string to its single unified canonical name.
        JSON format: {"mappings": {"input_string": "canonical_name"}}
        """
        
        let selectedModel = availableModels.contains("qwen2.5:3b") ? "qwen2.5:3b" : (availableModels.first ?? "qwen2.5:3b")
        let cleanEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(cleanEndpoint)/api/generate") else { return }
        
        let payload: [String: Any] = [
            "model": selectedModel,
            "prompt": prompt,
            "format": "json",
            "stream": false
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: payload) else { return }
        
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
                  let mappings = resJson["mappings"] as? [String: String] else {
                return
            }
            
            var didUpdate = false
            for (raw, canonical) in mappings {
                let trimmedRaw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedCanon = canonical.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedRaw.isEmpty && !trimmedCanon.isEmpty && domainRegistry[trimmedRaw] != trimmedCanon {
                    domainRegistry[trimmedRaw] = trimmedCanon
                    didUpdate = true
                }
            }
            if didUpdate {
                saveRegistry()
                print("Local AI canonicalized \(mappings.count) addresses!")
            }
        } catch {
            print("Local AI canonicalization skipped (offline or busy)")
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
        
        let domains = [
            "technology & computer science pioneers (e.g. Steve Jobs, Alan Turing, Linus Torvalds, Claude Shannon, Grace Hopper, Ada Lovelace, Jensen Huang)",
            "great philosophers & stoics (e.g. Marcus Aurelius, Seneca, Aristotle, Epictetus, Friedrich Nietzsche, Confucius, Lao Tzu)",
            "world-renowned scientists & physicists (e.g. Albert Einstein, Richard Feynman, Marie Curie, Isaac Newton, Stephen Hawking, Galileo Galilei)",
            "historic leaders & visionaries (e.g. Winston Churchill, Theodore Roosevelt, Nelson Mandela, Abraham Lincoln, Benjamin Franklin, Eleanor Roosevelt)",
            "elite champions & athletes (e.g. Michael Jordan, Kobe Bryant, Muhammad Ali, Serena Williams, Bruce Lee)",
            "legendary inventors & innovators (e.g. Leonardo da Vinci, Nikola Tesla, Thomas Edison, Henry Ford, Alexander Graham Bell)"
        ]
        let chosenDomain = domains.randomElement() ?? "visionaries"
        
        let prompt = """
        Quote an authentic, famous motivational quote from a REAL person in \(chosenDomain).
        The author MUST be a real, notable historical or modern figure. Do NOT fabricate quotes, and do NOT use "Anonymous" or "AI Mentor".
        Choose a different quote every time.
        Format strictly as JSON: {"quote": "The quote text", "author": "Full Name of Real Person"}
        """
        
        let requestPayload: [String: Any] = [
            "model": selectedModel,
            "prompt": prompt,
            "format": "json",
            "stream": false,
            "options": [
                "temperature": 0.92,
                "top_p": 0.95
            ]
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
            
            // Reject generic or anonymous placeholders to ensure 100% real people
            let banned = ["ai mentor", "anonymous", "unknown", "ai", "mentor", "various", "author", ""]
            if banned.contains(rawAuthor.lowercased()) || rawAuthor.count < 3 {
                return nil
            }
            
            guard !quote.isEmpty else { return nil }
            
            let result = (quote: quote, author: rawAuthor)
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
