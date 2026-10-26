import Foundation

public struct CategoryUsageStat: Codable, Identifiable {
    public var id: String { name }
    public var name: String
    public var seconds: Int
    public var percentage: Int
    public var colorHex: String
}

public struct DailyTrendPoint: Codable, Identifiable {
    public var id: String { dayLabel }
    public var dayLabel: String
    public var totalHours: Double
    public var deepWorkHours: Double
}

public struct RealProductivityReport: Codable {
    public var periodDays: Int
    public var totalScreenTimeSeconds: Int
    public var totalScreenTimeFormatted: String
    
    // 1. Productivity Score
    public var productivityScore: Int
    public var productivityGrade: String
    public var productivityRatioDescription: String
    
    // 2. Deep Work Focus
    public var deepWorkPercentage: Int
    public var deepWorkSummary: String
    
    // 3. Peak Focus Window
    public var peakWindowName: String
    public var peakWindowTimeRange: String
    
    // 4. Longest Deep Sprint
    public var longestStreakSeconds: Int
    public var longestStreakFormatted: String
    
    // 5. Category Breakdown
    public var categories: [CategoryUsageStat]
    
    // 6. Ranked Top Software & Websites
    public var topPrograms: [AppUsageStat]
    public var topWebsites: [WebsiteUsageStat]
    
    // 7. Daily Trend Points (Last 7 Days)
    public var dailyTrends: [DailyTrendPoint]
    
    // 8. Live Input Telemetry & Predicted State
    public var telemetry: ActivityTelemetryData?
}

@MainActor
public final class ProductivityAnalyticsEngine {
    public static let shared = ProductivityAnalyticsEngine()
    
    private init() {}
    
    // Keywords for classifying apps and services into real productivity categories
    private static let devKeywords: Set<String> = [
        "antigravity", "terminal", "xcode", "cursor", "clipforge", "localhost",
        "code", "github", "iterm", "developer", "git", "sublime", "intellij",
        "pycharm", "webstorm", "warp", "docker", "postman", "tableplus", "dbeaver",
        "chatgpt", "claude", "deepseek", "clion", "android studio", "zed", "alacritty"
    ]
    
    private static let commKeywords: Set<String> = [
        "whatsapp", "slack", "teams", "telegram", "discord", "signal", "mail", "messages", "zoom"
    ]
    
    private static let mediaKeywords: Set<String> = [
        "youtube", "music", "spotify", "netflix", "instagram", "tiktok", "twitch",
        "vlc", "quicktime", "podcasts", "hulu", "prime video"
    ]
    
    private static let systemKeywords: Set<String> = [
        "finder", "system settings", "activity monitor", "preview", "notes",
        "textedit", "calculator", "loginwindow", "tips", "archive utility"
    ]
    
    public enum ActivityCategory: String {
        case development = "Development"
        case webResearch = "Web Research"
        case communication = "Communication"
        case media = "Media"
        case system = "System"
    }
    
    public static func classify(name: String) -> ActivityCategory {
        let lower = name.lowercased()
        
        for kw in devKeywords {
            if lower.contains(kw) { return .development }
        }
        for kw in commKeywords {
            if lower.contains(kw) { return .communication }
        }
        for kw in mediaKeywords {
            if lower.contains(kw) { return .media }
        }
        for kw in systemKeywords {
            if lower.contains(kw) { return .system }
        }
        return .webResearch
    }
    
    /// Generates a 100% real analytics report from actual usage sessions and live usage
    public func generateReport(
        sessions: [UsageSession],
        liveAppUsage: [String: Int] = [:],
        liveWebsiteUsage: [String: Int] = [:],
        liveCurrentDuration: TimeInterval = 0,
        periodDays: Int = 7,
        telemetry: ActivityTelemetryData? = nil
    ) -> RealProductivityReport {
        // 1. Consolidate App and Website Usage Totals
        var aggregatedApps: [String: Int] = [:]
        for (app, sec) in liveAppUsage {
            if !DataManager.ignoredAppNames.contains(app) {
                aggregatedApps[app, default: 0] += sec
            }
        }
        for s in sessions {
            for (app, sec) in s.appUsage {
                if !DataManager.ignoredAppNames.contains(app) {
                    aggregatedApps[app, default: 0] += sec
                }
            }
        }
        
        var aggregatedWebsites: [String: Int] = [:]
        for (site, sec) in liveWebsiteUsage {
            let norm = DataManager.normalizeWebsiteName(site)
            if !norm.isEmpty && !DataManager.ignoredDomains.contains(norm) {
                aggregatedWebsites[norm, default: 0] += sec
            }
        }
        for s in sessions {
            for (site, sec) in s.websiteUsage {
                let norm = DataManager.normalizeWebsiteName(site)
                if !norm.isEmpty && !DataManager.ignoredDomains.contains(norm) {
                    aggregatedWebsites[norm, default: 0] += sec
                }
            }
        }
        
        // Total screen time seconds
        let totalSessionsDuration = sessions.reduce(0) { $0 + $1.durationSeconds }
        let totalScreenTime = totalSessionsDuration + Int(liveCurrentDuration)
        
        // 2. Compute Real Category Totals
        var devSec = 0
        var commSec = 0
        var mediaSec = 0
        var systemSec = 0
        var webSec = 0
        
        for (app, sec) in aggregatedApps {
            switch Self.classify(name: app) {
            case .development: devSec += sec
            case .communication: commSec += sec
            case .media: mediaSec += sec
            case .system: systemSec += sec
            case .webResearch: webSec += sec
            }
        }
        
        // Web activity: classify sites (e.g. ClipForge on localhost is Development, youtube is Media)
        for (site, sec) in aggregatedWebsites {
            switch Self.classify(name: site) {
            case .development:
                // Move from generic web into development
                devSec += sec
            case .media:
                mediaSec += sec
            case .communication:
                commSec += sec
            case .system:
                systemSec += sec
            case .webResearch:
                webSec += sec
            }
        }
        
        let totalTrackedSec = max(1, devSec + commSec + mediaSec + systemSec + webSec)
        
        // 3. Real Productivity Score (0 - 100)
        let weighted = Double(devSec) * 1.0 + Double(systemSec) * 0.8 + Double(webSec) * 0.7 + Double(commSec) * 0.5 + Double(mediaSec) * 0.1
        let realScore = min(100, max(0, Int(round((weighted / Double(totalTrackedSec)) * 100.0))))
        
        let grade: String
        let ratioDesc: String
        if realScore >= 85 {
            grade = "Deep Flow"
            ratioDesc = "Elite Deep Work Ratio"
        } else if realScore >= 70 {
            grade = "High Focus"
            ratioDesc = "High Productive Focus"
        } else if realScore >= 50 {
            grade = "Balanced"
            ratioDesc = "Balanced Work & Media"
        } else {
            grade = "Distracted"
            ratioDesc = "High Context Switching"
        }
        
        // 4. Real Deep Work Percentage
        let deepWorkPct = min(100, max(0, Int(round((Double(devSec) / Double(totalTrackedSec)) * 100.0))))
        
        // Extract top 3 development programs/sites
        let devItems = (aggregatedApps.keys.filter { Self.classify(name: $0) == .development } +
                        aggregatedWebsites.keys.filter { Self.classify(name: $0) == .development })
        let topDevNames = Array(Set(devItems)).sorted {
            let sec0 = (aggregatedApps[$0] ?? 0) + (aggregatedWebsites[$0] ?? 0)
            let sec1 = (aggregatedApps[$1] ?? 0) + (aggregatedWebsites[$1] ?? 0)
            return sec0 > sec1
        }.prefix(3)
        let deepWorkSummary = topDevNames.isEmpty ? "Coding & Local Dev" : topDevNames.joined(separator: ", ")
        
        // 5. Real Peak Focus Window
        var hourlyBuckets = [Int](repeating: 0, count: 24)
        for s in sessions {
            let start = s.startTime
            let end = s.endTime
            var cur = start
            while cur < end {
                let hour = Calendar.current.component(.hour, from: cur)
                hourlyBuckets[hour] += 60
                cur = cur.addingTimeInterval(3600)
            }
        }
        if liveCurrentDuration > 0 {
            let hour = Calendar.current.component(.hour, from: Date())
            hourlyBuckets[hour] += Int(liveCurrentDuration)
        }
        
        var bestStartHour = 10
        var maxThreeHourSec = 0
        for h in 0..<24 {
            let chunk = hourlyBuckets[h] + hourlyBuckets[(h + 1) % 24] + hourlyBuckets[(h + 2) % 24]
            if chunk > maxThreeHourSec {
                maxThreeHourSec = chunk
                bestStartHour = h
            }
        }
        
        let endHour = (bestStartHour + 3) % 24
        let windowName: String
        if bestStartHour >= 5 && bestStartHour < 12 {
            windowName = "Morning"
        } else if bestStartHour >= 12 && bestStartHour < 17 {
            windowName = "Afternoon"
        } else if bestStartHour >= 17 && bestStartHour < 22 {
            windowName = "Evening"
        } else {
            windowName = "Night"
        }
        
        let formatHour: (Int) -> String = { hr in
            let ampm = hr >= 12 ? "PM" : "AM"
            let h12 = hr == 0 ? 12 : (hr > 12 ? hr - 12 : hr)
            return "\(h12):00 \(ampm)"
        }
        let peakRange = "\(formatHour(bestStartHour)) – \(formatHour(endHour))"
        
        // 6. Longest Streak
        let allDurations = sessions.map { $0.durationSeconds } + [Int(liveCurrentDuration)]
        let longestSec = allDurations.max() ?? 0
        let streakH = longestSec / 3600
        let streakM = (longestSec % 3600) / 60
        let longestFormatted = streakH > 0 ? "\(streakH)h \(streakM)m" : "\(streakM)m"
        
        // 7. Categories Breakdown
        let devPct = Int(round(Double(devSec) / Double(totalTrackedSec) * 100))
        let webPct = Int(round(Double(webSec) / Double(totalTrackedSec) * 100))
        let commPct = Int(round(Double(commSec) / Double(totalTrackedSec) * 100))
        let mediaPct = Int(round(Double(mediaSec) / Double(totalTrackedSec) * 100))
        let sysPct = max(0, 100 - (devPct + webPct + commPct + mediaPct))
        
        let categories: [CategoryUsageStat] = [
            CategoryUsageStat(name: "Development", seconds: devSec, percentage: devPct, colorHex: "#3B82F6"),
            CategoryUsageStat(name: "Web Research", seconds: webSec, percentage: webPct, colorHex: "#10B981"),
            CategoryUsageStat(name: "Communication", seconds: commSec, percentage: commPct, colorHex: "#F59E0B"),
            CategoryUsageStat(name: "Media", seconds: mediaSec, percentage: mediaPct, colorHex: "#8B5CF6"),
            CategoryUsageStat(name: "System", seconds: systemSec, percentage: sysPct, colorHex: "#64748B")
        ]
        
        // 8. Ranked Top Software & Websites
        let topProgs = aggregatedApps
            .map { AppUsageStat(name: $0.key, durationSeconds: $0.value, percentage: Double($0.value) / Double(totalTrackedSec)) }
            .sorted { $0.durationSeconds > $1.durationSeconds }
            .prefix(6)
            .map { $0 }
            
        let topWebs = aggregatedWebsites
            .map { WebsiteUsageStat(domain: $0.key, durationSeconds: $0.value, percentage: Double($0.value) / Double(totalTrackedSec)) }
            .sorted { $0.durationSeconds > $1.durationSeconds }
            .prefix(6)
            .map { $0 }
            
        // 9. Daily Trends (Last 7 Calendar Days)
        var dailyPoints: [DailyTrendPoint] = []
        let cal = Calendar.current
        let now = Date()
        for i in (0..<7).reversed() {
            guard let targetDate = cal.date(byAdding: .day, value: -i, to: now) else { continue }
            let dayStart = cal.startOfDay(for: targetDate)
            let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
            
            let daySessions = sessions.filter { $0.startTime >= dayStart && $0.startTime < dayEnd }
            var dayTotalSec = daySessions.reduce(0) { $0 + $1.durationSeconds }
            var dayDevSec = 0
            for s in daySessions {
                for (a, sc) in s.appUsage where Self.classify(name: a) == .development {
                    dayDevSec += sc
                }
                for (w, sc) in s.websiteUsage where Self.classify(name: w) == .development {
                    dayDevSec += sc
                }
            }
            
            if cal.isDateInToday(targetDate) {
                dayTotalSec += Int(liveCurrentDuration)
                for (a, sc) in liveAppUsage where Self.classify(name: a) == .development {
                    dayDevSec += sc
                }
                for (w, sc) in liveWebsiteUsage where Self.classify(name: w) == .development {
                    dayDevSec += sc
                }
            }
            
            let df = DateFormatter()
            df.dateFormat = "EEE"
            let label = cal.isDateInToday(targetDate) ? "Today" : df.string(from: targetDate)
            
            dailyPoints.append(DailyTrendPoint(
                dayLabel: label,
                totalHours: Double(round(Double(dayTotalSec) / 360.0)) / 10.0,
                deepWorkHours: Double(round(Double(dayDevSec) / 360.0)) / 10.0
            ))
        }
        
        let hours = totalScreenTime / 3600
        let minutes = (totalScreenTime % 3600) / 60
        let timeFormatted = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
        
        return RealProductivityReport(
            periodDays: periodDays,
            totalScreenTimeSeconds: totalScreenTime,
            totalScreenTimeFormatted: timeFormatted,
            productivityScore: realScore,
            productivityGrade: grade,
            productivityRatioDescription: ratioDesc,
            deepWorkPercentage: deepWorkPct,
            deepWorkSummary: deepWorkSummary,
            peakWindowName: windowName,
            peakWindowTimeRange: peakRange,
            longestStreakSeconds: longestSec,
            longestStreakFormatted: longestFormatted,
            categories: categories,
            topPrograms: topProgs,
            topWebsites: topWebs,
            dailyTrends: dailyPoints,
            telemetry: telemetry ?? InputTelemetryEngine.shared.currentTelemetryData()
        )
    }
    
    /// Exports the real analytics report to JSON for the standalone Web Dashboard
    public func exportForWebDashboard(report: RealProductivityReport) {
        guard let data = try? JSONEncoder().encode(report) else { return }
        
        // 1. Write to Application Support
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let appDir = appSupport.appendingPathComponent("MacUsageTracker", isDirectory: true)
            let fileURL = appDir.appendingPathComponent("analytics_data.json")
            try? data.write(to: fileURL, options: .atomic)
        }
        
        // 2. Write to project workspace root
        let workspaceURL = URL(fileURLWithPath: "/Users/franklowe/Documents/antigravity/brave-oppenheimer/analytics_data.json")
        try? data.write(to: workspaceURL, options: .atomic)
        
        // 3. Inject directly into productivity_dashboard.html so file:// URLs load real data immediately without CORS!
        let htmlPath = "/Users/franklowe/Documents/antigravity/brave-oppenheimer/productivity_dashboard.html"
        if let htmlContent = try? String(contentsOfFile: htmlPath, encoding: .utf8),
           let jsonString = String(data: data, encoding: .utf8) {
            
            let startTag = "<!-- REAL_ANALYTICS_DATA_START -->"
            let endTag = "<!-- REAL_ANALYTICS_DATA_END -->"
            
            let replacement = """
            \(startTag)
              <script id="real-analytics-data" type="application/json">
              \(jsonString)
              </script>
              \(endTag)
            """
            
            if htmlContent.contains(startTag) && htmlContent.contains(endTag) {
                if let startRange = htmlContent.range(of: startTag),
                   let endRange = htmlContent.range(of: endTag) {
                    var updated = htmlContent
                    updated.replaceSubrange(startRange.lowerBound..<endRange.upperBound, with: replacement)
                    try? updated.write(toFile: htmlPath, atomically: true, encoding: .utf8)
                }
            } else if let headEnd = htmlContent.range(of: "</head>") {
                var updated = htmlContent
                updated.insert(contentsOf: "\n" + replacement + "\n", at: headEnd.lowerBound)
                try? updated.write(toFile: htmlPath, atomically: true, encoding: .utf8)
            }
        }
    }
}
