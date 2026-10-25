import Foundation
import Combine

@MainActor
public final class LocalLLMService: ObservableObject {
    public static let shared = LocalLLMService()
    
    @Published public var isOllamaAvailable: Bool = false
    @Published public var availableModels: [String] = []
    @Published public var isGenerating: Bool = false
    @Published public var lastGeneratedQuote: (quote: String, author: String)? = nil
    
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
        
        // Pick best model: prefer fast models (qwen2.5:3b, qwen2.5:7b, gemma4:e2b) or user selection
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
}
