import Foundation
import Network

@MainActor
public final class BrowserExtensionServer: ObservableObject {
    public static let shared = BrowserExtensionServer()
    
    public static let port: UInt16 = 48123
    @Published public var isRunning: Bool = false
    @Published public var lastReportedDomain: String? = nil
    @Published public var lastReportTime: Date? = nil
    
    private var listener: NWListener?
    
    public init() {}
    
    public func start() {
        guard listener == nil else { return }
        
        do {
            let nwPort = NWEndpoint.Port(rawValue: Self.port)!
            let parameters = NWParameters.tcp
            let newListener = try NWListener(using: parameters, on: nwPort)
            
            newListener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handleConnection(connection)
                }
            }
            
            newListener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.isRunning = true
                    case .failed(let error):
                        print("[BrowserExtensionServer] Listener failed: \(error)")
                        self?.isRunning = false
                    case .cancelled:
                        self?.isRunning = false
                    default:
                        break
                    }
                }
            }
            
            newListener.start(queue: .main)
            self.listener = newListener
        } catch {
            print("[BrowserExtensionServer] Failed to bind to port \(Self.port): \(error)")
        }
    }
    
    public func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 2048) { [weak self] data, _, isComplete, _ in
            guard let data = data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            
            Task { @MainActor in
                self?.processRequest(request, connection: connection)
            }
        }
    }
    
    private func processRequest(_ request: String, connection: NWConnection) {
        // Extract domain from query: /domain?name=example.com or body
        var domain: String? = nil
        
        if let line = request.components(separatedBy: "\r\n").first {
            let parts = line.components(separatedBy: " ")
            if parts.count >= 2 {
                let path = parts[1]
                if let urlComponents = URLComponents(string: "http://127.0.0.1" + path) {
                    domain = urlComponents.queryItems?.first(where: { $0.name == "name" || $0.name == "domain" })?.value
                }
            }
        }
        
        if let domain = domain, !domain.isEmpty {
            let cleanDomain = domain.lowercased().hasPrefix("www.") ? String(domain.dropFirst(4)) : domain.lowercased()
            self.lastReportedDomain = cleanDomain
            self.lastReportTime = Date()
            UsageTrackerEngine.shared.handleDomainReportedFromExtension(cleanDomain)
        }
        
        let responseBody = "OK"
        let httpResponse = "HTTP/1.1 200 OK\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type\r\nContent-Type: text/plain\r\nContent-Length: \(responseBody.utf8.count)\r\nConnection: close\r\n\r\n\(responseBody)"
        
        connection.send(content: httpResponse.data(using: .utf8), completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }
}
