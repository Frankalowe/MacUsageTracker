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
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, _ in
            guard let data = data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            
            Task { @MainActor in
                self?.processRequest(request, connection: connection)
            }
        }
    }
    
    private func sendResponse(
        status: String = "200 OK",
        contentType: String = "text/plain; charset=utf-8",
        body: String,
        connection: NWConnection
    ) {
        let bodyData = body.data(using: .utf8) ?? Data()
        let headers = """
        HTTP/1.1 \(status)\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Methods: GET, POST, OPTIONS\r
        Access-Control-Allow-Headers: Content-Type, Authorization\r
        Content-Type: \(contentType)\r
        Content-Length: \(bodyData.count)\r
        Connection: close\r
        \r
        
        """
        guard let headerData = headers.data(using: .utf8) else {
            connection.cancel()
            return
        }
        var fullData = Data()
        fullData.append(headerData)
        fullData.append(bodyData)
        
        connection.send(content: fullData, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }
    
    private func processRequest(_ request: String, connection: NWConnection) {
        guard let firstLine = request.components(separatedBy: "\r\n").first else {
            sendResponse(status: "400 Bad Request", body: "Invalid Request", connection: connection)
            return
        }
        
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            sendResponse(status: "400 Bad Request", body: "Invalid Request", connection: connection)
            return
        }
        
        let method = parts[0]
        let path = parts[1]
        
        // Handle CORS preflight
        if method == "OPTIONS" {
            sendResponse(status: "204 No Content", body: "", connection: connection)
            return
        }
        
        // Handle HTML dashboard serving
        if path == "/dashboard" || path.hasPrefix("/dashboard?") {
            let htmlPath = "/Users/franklowe/Documents/antigravity/brave-oppenheimer/productivity_dashboard.html"
            if let html = try? String(contentsOfFile: htmlPath, encoding: .utf8) {
                sendResponse(contentType: "text/html; charset=utf-8", body: html, connection: connection)
                return
            }
        }
        
        // Handle Analytics API (supports ?days=1|7|14|30)
        if path.hasPrefix("/api/analytics") {
            var days = 7
            if let urlComponents = URLComponents(string: "http://127.0.0.1" + path),
               let daysStr = urlComponents.queryItems?.first(where: { $0.name == "days" })?.value,
               let parsedDays = Int(daysStr) {
                days = parsedDays
            }
            
            var report = DataManager.shared.analyticsReport(
                days: days,
                includeLive: true,
                liveAppUsage: UsageTrackerEngine.shared.liveAppUsage,
                liveWebsiteUsage: UsageTrackerEngine.shared.liveWebsiteUsage,
                liveCurrentDuration: UsageTrackerEngine.shared.currentSessionDuration
            )
            
            // Include multi-period precomputations
            let p1 = DataManager.shared.analyticsReport(days: 1, includeLive: true, liveAppUsage: UsageTrackerEngine.shared.liveAppUsage, liveWebsiteUsage: UsageTrackerEngine.shared.liveWebsiteUsage, liveCurrentDuration: UsageTrackerEngine.shared.currentSessionDuration)
            let p7 = (days == 7) ? report : DataManager.shared.analyticsReport(days: 7, includeLive: true, liveAppUsage: UsageTrackerEngine.shared.liveAppUsage, liveWebsiteUsage: UsageTrackerEngine.shared.liveWebsiteUsage, liveCurrentDuration: UsageTrackerEngine.shared.currentSessionDuration)
            let p14 = (days == 14) ? report : DataManager.shared.analyticsReport(days: 14, includeLive: true, liveAppUsage: UsageTrackerEngine.shared.liveAppUsage, liveWebsiteUsage: UsageTrackerEngine.shared.liveWebsiteUsage, liveCurrentDuration: UsageTrackerEngine.shared.currentSessionDuration)
            let p30 = (days == 30) ? report : DataManager.shared.analyticsReport(days: 30, includeLive: true, liveAppUsage: UsageTrackerEngine.shared.liveAppUsage, liveWebsiteUsage: UsageTrackerEngine.shared.liveWebsiteUsage, liveCurrentDuration: UsageTrackerEngine.shared.currentSessionDuration)
            
            report.periods = ["1": p1, "7": p7, "14": p14, "30": p30]
            
            if let data = try? JSONEncoder().encode(report), let jsonStr = String(data: data, encoding: .utf8) {
                sendResponse(contentType: "application/json; charset=utf-8", body: jsonStr, connection: connection)
                return
            }
        }
        
        // Handle AI Audit API
        if path.hasPrefix("/api/audit") {
            Task { @MainActor in
                let report = DataManager.shared.analyticsReport(
                    days: 7,
                    includeLive: true,
                    liveAppUsage: UsageTrackerEngine.shared.liveAppUsage,
                    liveWebsiteUsage: UsageTrackerEngine.shared.liveWebsiteUsage,
                    liveCurrentDuration: UsageTrackerEngine.shared.currentSessionDuration
                )
                let topApps = report.topPrograms.map { $0.name }
                let topWebs = report.topWebsites.map { $0.domain }
                
                let rawAudit = await LocalLLMService.shared.generateProductivityAudit(
                    screenTime: report.totalScreenTimeFormatted,
                    topApps: topApps,
                    topWebsites: topWebs
                )
                
                let synth = ProductivityAnalyticsEngine.synthesizeAIAudit(
                    screenTime: report.totalScreenTimeFormatted,
                    deepWorkPct: report.deepWorkPercentage,
                    deepWorkSummary: report.deepWorkSummary,
                    productivityGrade: report.productivityGrade,
                    peakWindow: report.peakWindowName,
                    peakRange: report.peakWindowTimeRange,
                    topPrograms: report.topPrograms,
                    topWebsites: report.topWebsites
                )
                
                let auditDict: [String: Any] = [
                    "win": synth.win,
                    "lever": synth.lever,
                    "habit": synth.habit,
                    "model": synth.model,
                    "raw": rawAudit
                ]
                
                if let jsonData = try? JSONSerialization.data(withJSONObject: auditDict),
                   let jsonStr = String(data: jsonData, encoding: .utf8) {
                    self.sendResponse(contentType: "application/json; charset=utf-8", body: jsonStr, connection: connection)
                } else {
                    self.sendResponse(status: "500 Internal Server Error", body: "{}", connection: connection)
                }
            }
            return
        }
        
        // Existing Notification testing
        if path.contains("/test-notification") || path.contains("/notify") {
            NotificationService.shared.sendTestNotification()
        }
        
        // Existing Chrome Extension Domain Reporting
        var domain: String? = nil
        var title: String? = nil
        if let urlComponents = URLComponents(string: "http://127.0.0.1" + path) {
            domain = urlComponents.queryItems?.first(where: { $0.name == "name" || $0.name == "domain" })?.value
            title = urlComponents.queryItems?.first(where: { $0.name == "title" })?.value
        }
        
        if let domain = domain, !domain.isEmpty {
            self.lastReportedDomain = domain
            self.lastReportTime = Date()
            UsageTrackerEngine.shared.handleDomainReportedFromExtension(rawDomain: domain, tabTitle: title)
        }
        
        sendResponse(body: "OK", connection: connection)
    }
}
