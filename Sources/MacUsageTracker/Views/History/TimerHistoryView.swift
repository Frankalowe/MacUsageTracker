import SwiftUI
import AppKit

@MainActor
final class HistoryUIState: ObservableObject {
    @Published var selectedPeriodDays: Int = 35 // Default: 35 days for full month analysis
    @Published var selectedDateKey: String? = nil
    @Published var selectedTab: HistoryTab = .sessions
}

public enum HistoryTab: String, CaseIterable, Identifiable {
    case sessions = "Sessions"
    case programs = "Top Programs"
    case websites = "Top Websites"
    case aiAnalytics = "AI Productivity"
    
    public var id: String { rawValue }
}

public struct TimerHistoryView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var usageEngine: UsageTrackerEngine
    
    @StateObject private var uiState = HistoryUIState()
    @StateObject private var localLLM = LocalLLMService.shared
    @StateObject private var motivationPlayer = MotivationPlayerService.shared
    @StateObject private var inputTelemetry = InputTelemetryEngine.shared
    
    public init() {}
    
    private var allPeriodSessions: [UsageSession] {
        dataManager.sessionsInLastDays(days: uiState.selectedPeriodDays)
    }
    
    private var realReport: RealProductivityReport {
        dataManager.analyticsReport(
            days: uiState.selectedPeriodDays,
            includeLive: includeLiveInSelectedView,
            liveAppUsage: usageEngine.liveAppUsage,
            liveWebsiteUsage: usageEngine.liveWebsiteUsage,
            liveCurrentDuration: usageEngine.currentSessionDuration
        )
    }
    
    private var todayDateKey: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
    
    private var includeLiveInSelectedView: Bool {
        uiState.selectedDateKey == nil || uiState.selectedDateKey == todayDateKey
    }
    
    private var filteredSessions: [UsageSession] {
        if let key = uiState.selectedDateKey {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return allPeriodSessions.filter { formatter.string(from: $0.startTime) == key }
        }
        return allPeriodSessions
    }
    
    // Group records by relative day header
    private var groupedSessions: [(key: String, title: String, sessions: [UsageSession], totalSeconds: Int)] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        let groups = Dictionary(grouping: filteredSessions) { session -> String in
            formatter.string(from: session.startTime)
        }
        
        return groups.map { (key, sessions) in
            let sorted = sessions.sorted { $0.startTime > $1.startTime }
            let title = sorted.first?.relativeDateSectionTitle ?? key
            let total = sorted.reduce(0) { $0 + $1.durationSeconds }
            return (key: key, title: title, sessions: sorted, totalSeconds: total)
        }
        .sorted { $0.sessions.first?.startTime ?? Date.distantPast > $1.sessions.first?.startTime ?? Date.distantPast }
    }
    
    private var dailySummaries: [DayUsageSummary] {
        dataManager.dailyUsageSummaries(lastDays: uiState.selectedPeriodDays, liveCurrentDuration: usageEngine.currentSessionDuration)
    }
    
    private var totalPeriodSeconds: Int {
        dataManager.totalPeriodSeconds(days: uiState.selectedPeriodDays, liveCurrentDuration: usageEngine.currentSessionDuration)
    }
    
    private var totalPeriodFormatted: String {
        let hours = totalPeriodSeconds / 3600
        let minutes = (totalPeriodSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    private var dailyAverageFormatted: String {
        let activeDaysCount = max(1, dailySummaries.filter { $0.totalSeconds > 0 }.count)
        let avgSeconds = totalPeriodSeconds / activeDaysCount
        let hours = avgSeconds / 3600
        let minutes = (avgSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m/day"
        } else {
            return "\(minutes)m/day"
        }
    }
    
    private var topProgramsList: [AppUsageStat] {
        dataManager.topPrograms(
            sessions: filteredSessions,
            limit: 20,
            liveAppUsage: includeLiveInSelectedView ? usageEngine.liveAppUsage : [:]
        )
    }
    
    private var topWebsitesList: [WebsiteUsageStat] {
        dataManager.topWebsites(
            sessions: filteredSessions,
            limit: 20,
            liveWebsiteUsage: includeLiveInSelectedView ? usageEngine.liveWebsiteUsage : [:]
        )
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Mac Usage History")
                            .font(.system(size: 16, weight: .bold))
                        
                        Text(uiState.selectedPeriodDays == 35 ? "Past 35 Days (Monthly Analysis)" : "Past 7 Days (Weekly)")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundColor(.accentColor)
                            .clipShape(Capsule())
                    }
                    
                    Text("Auto-recorded wake-to-sleep periods • Programs & websites tracked live • Retained for 35 days")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Period Switcher (35 Days vs 7 Days)
                Picker("", selection: $uiState.selectedPeriodDays) {
                    Text("35 Days (Month)").tag(35)
                    Text("7 Days (Week)").tag(7)
                }
                .pickerStyle(.segmented)
                .frame(width: 190)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // 4 Overview Metric Cards
            HStack(spacing: 12) {
                MetricCard(
                    title: "Total Screen Time (\(uiState.selectedPeriodDays)d)",
                    value: totalPeriodFormatted,
                    subtitle: "\(allPeriodSessions.count + (usageEngine.currentSessionDuration >= 30 ? 1 : 0)) sessions",
                    icon: "laptopcomputer",
                    color: .accentColor
                )
                
                MetricCard(
                    title: "Top Program",
                    value: topProgramsList.first?.name ?? "—",
                    subtitle: topProgramsList.first?.durationFormatted ?? "No apps yet",
                    icon: "app.badge.checkmark",
                    color: .orange
                )
                
                MetricCard(
                    title: "Top Website",
                    value: topWebsitesList.first?.domain ?? "—",
                    subtitle: topWebsitesList.first?.durationFormatted ?? "No browser data",
                    icon: "globe",
                    color: .blue
                )
                
                MetricCard(
                    title: "Daily Average",
                    value: dailyAverageFormatted,
                    subtitle: "\(dailySummaries.filter { $0.totalSeconds > 0 }.count) active days",
                    icon: "chart.line.uptrend.xyaxis",
                    color: .purple
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
            
            // Daily Breakdown Strip
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("DAILY SCREEN TIME (LAST \(uiState.selectedPeriodDays) DAYS)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if uiState.selectedDateKey != nil {
                        Button("Show All Days") {
                            uiState.selectedDateKey = nil
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                    }
                }
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(dailySummaries) { summary in
                            let isSelected = uiState.selectedDateKey == summary.dateKey
                            Button(action: {
                                if uiState.selectedDateKey == summary.dateKey {
                                    uiState.selectedDateKey = nil
                                } else {
                                    uiState.selectedDateKey = summary.dateKey
                                }
                            }) {
                                VStack(spacing: 4) {
                                    Text(summary.dayLabel)
                                        .font(.system(size: 9, weight: summary.isToday ? .bold : .medium))
                                        .foregroundColor(summary.isToday ? .accentColor : .secondary)
                                    
                                    Text(summary.totalHoursFormatted)
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(summary.totalSeconds > 0 ? .primary : .secondary.opacity(0.6))
                                    
                                    Text("\(summary.sessionCount)s")
                                        .font(.system(size: 8))
                                        .foregroundColor(.secondary)
                                }
                                .frame(width: 54)
                                .padding(.vertical, 6)
                                .background(
                                    isSelected ? Color.accentColor.opacity(0.18) :
                                    (summary.isToday ? Color.accentColor.opacity(0.08) : Color.gray.opacity(0.08))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                                 )
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            
            Divider()
            
            // Section Tab Switcher (Sessions Timeline, Top Programs, Top Websites, AI Productivity)
            HStack {
                Picker("", selection: $uiState.selectedTab) {
                    let liveCount = (includeLiveInSelectedView && usageEngine.currentSessionDuration >= 10 ? 1 : 0)
                    Text("📋 Sessions (\(filteredSessions.count + liveCount))").tag(HistoryTab.sessions)
                    Text("💻 Top Programs (\(topProgramsList.count))").tag(HistoryTab.programs)
                    Text("🌐 Top Websites (\(topWebsitesList.count))").tag(HistoryTab.websites)
                    Text("✨ AI Productivity").tag(HistoryTab.aiAnalytics)
                }
                .pickerStyle(.segmented)
                
                Spacer()
                
                if let key = uiState.selectedDateKey {
                    Text("Filtered: \(key)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            Divider()
            
            // Main Content Area based on Selected Tab
            switch uiState.selectedTab {
            case .sessions:
                sessionsContentView
            case .programs:
                programsContentView
            case .websites:
                websitesContentView
            case .aiAnalytics:
                aiAnalyticsContentView
            }
            
            Divider()
            
            // Bottom Info Bar
            HStack {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                Text("Automatic 35-Day Retention: Sessions are retained for 35 days for monthly analysis and purged automatically thereafter.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 640, minHeight: 580)
    }
    
    // MARK: - Tab Views
    
    @ViewBuilder
    private var sessionsContentView: some View {
        let hasLiveSession = includeLiveInSelectedView && usageEngine.isAwake && usageEngine.currentSessionDuration >= 10
        let isEmpty = filteredSessions.isEmpty && !hasLiveSession
        
        if isEmpty {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 38))
                    .foregroundColor(.secondary.opacity(0.5))
                
                Text(allPeriodSessions.isEmpty ? "No sessions recorded yet in the past \(uiState.selectedPeriodDays) days" : "No sessions for this selected day")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(allPeriodSessions.isEmpty ? "When you use your MacBook and put it to sleep or shut down, each session (≥ 1 minute) will be saved and retained for 35 days." : "Try selecting a different day.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    // Live Currently Running Session Card (if applicable)
                    if hasLiveSession {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("LIVE CURRENT SESSION")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.green)
                                Spacer()
                                Text("Updates every second")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                            ActiveLiveSessionCard(
                                startTimeFormatted: usageEngine.startTimeFormatted,
                                liveDurationFormatted: usageEngine.liveTimeString,
                                frontmostApp: usageEngine.currentFrontmostApp,
                                websiteDomain: usageEngine.currentWebsiteDomain,
                                liveAppUsage: usageEngine.liveAppUsage
                            )
                        }
                    }
                    
                    // Grouped Historical Sessions
                    ForEach(groupedSessions, id: \.key) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            // Day Header
                            HStack {
                                Text(group.title)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                let hours = group.totalSeconds / 3600
                                let mins = (group.totalSeconds % 3600) / 60
                                let totalStr = hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"
                                Text("\(group.sessions.count) \(group.sessions.count == 1 ? "session" : "sessions") • Total: \(totalStr)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 6)
                            .padding(.top, 4)
                            
                            // Records in this day
                            VStack(spacing: 8) {
                                ForEach(group.sessions) { session in
                                    SessionRow(session: session)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
    }
    
    @ViewBuilder
    private var programsContentView: some View {
        if topProgramsList.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "app.badge.checkmark")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary.opacity(0.5))
                
                Text("No program activity tracked yet")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text("As you use different applications on your Mac, their active foreground time will be recorded and ranked here.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("RANKED BY ACTIVE SCREEN TIME")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(topProgramsList.count) applications tracked")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 2)
                    
                    ForEach(Array(topProgramsList.enumerated()), id: \.element.id) { index, stat in
                        ProgramUsageRow(rank: index + 1, stat: stat)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
        }
    }
    
    @ViewBuilder
    private var websitesContentView: some View {
        if topWebsitesList.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "globe")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary.opacity(0.5))
                
                Text("No website activity tracked yet")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text("Website tracking activates automatically whenever you browse using Safari, Google Chrome, Brave Browser, Microsoft Edge, Arc, or Chromium.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("RANKED BY ACTIVE BROWSING TIME")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 9))
                                .foregroundColor(.purple)
                            Text("AI Unified & Deduplicated (\(topWebsitesList.count))")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.bottom, 2)
                    
                    ForEach(Array(topWebsitesList.enumerated()), id: \.element.id) { index, stat in
                        WebsiteUsageRow(rank: index + 1, stat: stat)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
        }
    }
    
    @ViewBuilder
    private var aiAnalyticsContentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header & Web Dashboard Button
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI PRODUCTIVITY & FOCUS INTELLIGENCE")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                        Text("On-device machine learning analysis of your work habits & software usage")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        dataManager.exportAnalyticsForWebDashboard(
                            days: uiState.selectedPeriodDays,
                            includeLive: includeLiveInSelectedView,
                            liveAppUsage: usageEngine.liveAppUsage,
                            liveWebsiteUsage: usageEngine.liveWebsiteUsage,
                            liveCurrentDuration: usageEngine.currentSessionDuration
                        )
                        let path = "/Users/franklowe/Documents/antigravity/brave-oppenheimer/productivity_dashboard.html"
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "safari")
                            Text("Open Full Web Dashboard ↗")
                                .font(.system(size: 11, weight: .semibold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.top, 4)
                
                // Motivate Me Action Banner
                Button(action: {
                    motivationPlayer.toggle()
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: motivationPlayer.isPlaying ? "speaker.wave.3.fill" : "bolt.fill")
                            .font(.system(size: 18))
                            .foregroundColor(motivationPlayer.isPlaying ? .white : .yellow)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(motivationPlayer.isPlaying ? "Playing: The Unit (Extended Remix)" : "Motivate me")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                            Text(motivationPlayer.isPlaying ? "Song is playing till the end • Click to stop" : "Sends another motivational quote notification and plays \"The Unit\" soundtrack till the end")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.85))
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 6) {
                            Image(systemName: motivationPlayer.isPlaying ? "stop.fill" : "play.fill")
                            Text(motivationPlayer.isPlaying ? "Stop" : "Play")
                        }
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Capsule())
                    }
                    .padding(14)
                    .background(
                        LinearGradient(
                            colors: motivationPlayer.isPlaying ? [Color.purple, Color.indigo] : [Color.orange, Color.red],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: (motivationPlayer.isPlaying ? Color.purple : Color.orange).opacity(0.3), radius: 6, y: 2)
                }
                .buttonStyle(.plain)
                
                // Live Activity & Input Telemetry Intelligence Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(inputTelemetry.currentState == .working ? Color.green : (inputTelemetry.currentState == .watching ? Color.purple : Color.blue))
                                .frame(width: 8, height: 8)
                            Text("PREDICTED ACTIVITY:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                            Text(inputTelemetry.currentState.badgeLabel)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(inputTelemetry.currentState == .working ? .green : (inputTelemetry.currentState == .watching ? .purple : .primary))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(
                                    (inputTelemetry.currentState == .working ? Color.green : (inputTelemetry.currentState == .watching ? Color.purple : Color.blue)).opacity(0.15)
                                )
                                .clipShape(Capsule())
                        }
                        
                        Spacer()
                        
                        if !inputTelemetry.currentAppName.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "app.window.checkmark")
                                    .font(.system(size: 10))
                                Text(inputTelemetry.currentAppName)
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundColor(.secondary)
                        }
                    }
                    
                    if !inputTelemetry.currentWindowTitle.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "macwindow")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text(inputTelemetry.currentWindowTitle)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.windowBackgroundColor).opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    
                    // Input Telemetry Counters
                    HStack(spacing: 12) {
                        // Keystrokes
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: "keyboard")
                                    .font(.system(size: 10))
                                    .foregroundColor(.blue)
                                Text("Typing Velocity")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            Text("\(inputTelemetry.keystrokesPerMinute) kpm")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                            Text("Total: \(inputTelemetry.totalKeystrokes) keys")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        
                        // Mouse Clicks
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: "cursorarrow.click.2")
                                    .font(.system(size: 10))
                                    .foregroundColor(.orange)
                                Text("Mouse Clicks")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            Text("\(inputTelemetry.mouseClicksPerMinute) cpm")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                            Text("Total: \(inputTelemetry.totalMouseClicks) clicks")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        
                        // Cursor Movement
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: "location.north.line.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.purple)
                                Text("Cursor Travel")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            Text(String(format: "%.1f m", inputTelemetry.cursorDistanceMeters))
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                            Text("Pixels: \(Int(inputTelemetry.cursorDistanceMeters * 3779)) px")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    
                    // Work vs. Watching Time Distribution Split
                    let telemetryData = inputTelemetry.currentTelemetryData()
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("WORK VS. WATCHING PREDICTION BREAKDOWN")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("Work \(telemetryData.workPercentage)% • Watching \(telemetryData.watchPercentage)%")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        
                        GeometryReader { geo in
                            HStack(spacing: 2) {
                                Rectangle()
                                    .fill(Color.blue)
                                    .frame(width: max(2, geo.size.width * CGFloat(telemetryData.workPercentage) / 100.0))
                                Rectangle()
                                    .fill(Color.purple)
                                    .frame(width: max(2, geo.size.width * CGFloat(telemetryData.watchPercentage) / 100.0))
                                Rectangle()
                                    .fill(Color.orange)
                                    .frame(width: max(2, geo.size.width * CGFloat(telemetryData.researchPercentage) / 100.0))
                            }
                            .clipShape(Capsule())
                        }
                        .frame(height: 6)
                        
                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                Circle().fill(Color.blue).frame(width: 6, height: 6)
                                Text("Working: \(inputTelemetry.workingSeconds / 60)m")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                            HStack(spacing: 4) {
                                Circle().fill(Color.purple).frame(width: 6, height: 6)
                                Text("Watching: \(inputTelemetry.watchingSeconds / 60)m")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                            HStack(spacing: 4) {
                                Circle().fill(Color.orange).frame(width: 6, height: 6)
                                Text("Research: \(inputTelemetry.readingSeconds / 60)m")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                            HStack(spacing: 4) {
                                Circle().fill(Color.gray).frame(width: 6, height: 6)
                                Text("Idle: \(inputTelemetry.idleSeconds / 60)m")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color(NSColor.windowBackgroundColor).opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(14)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                
                // 3 Real Analytics Score Cards (Calculated directly from actual tracked sessions)
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Productivity Score")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            Image(systemName: "bolt.shield.fill")
                                .foregroundColor(realReport.productivityScore >= 70 ? .green : (realReport.productivityScore >= 50 ? .orange : .red))
                        }
                        Text("\(realReport.productivityScore) / 100")
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                            .foregroundColor(realReport.productivityScore >= 70 ? .green : (realReport.productivityScore >= 50 ? .orange : .red))
                        Text(realReport.productivityRatioDescription)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Deep Work Focus")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            Image(systemName: "laptopcomputer")
                                .foregroundColor(.blue)
                        }
                        Text("\(realReport.deepWorkPercentage)%")
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                            .foregroundColor(.blue)
                        Text(realReport.deepWorkSummary)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Peak Focus Window")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            Image(systemName: "sun.max.fill")
                                .foregroundColor(.orange)
                        }
                        Text(realReport.peakWindowName)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.orange)
                        Text(realReport.peakWindowTimeRange)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                
                // Real Category Distribution Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("REAL WORK CATEGORY BREAKDOWN")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Screen Time: \(realReport.totalScreenTimeFormatted)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.primary)
                    }
                    
                    HStack(spacing: 8) {
                        ForEach(realReport.categories) { cat in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(cat.percentage)%")
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                Text(cat.name)
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.windowBackgroundColor).opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .padding(14)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                // AI Coach Card (Ollama Local LLM Powered)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        HStack(spacing: 6) {
                            Text("🤖")
                                .font(.system(size: 16))
                            Text("AI Productivity Coach (Local Ollama)")
                                .font(.system(size: 13, weight: .bold))
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            Task {
                                let screenTime = totalPeriodFormatted
                                let topApps = topProgramsList.map { $0.name }
                                let topWebs = topWebsitesList.map { $0.domain }
                                _ = await localLLM.generateProductivityAudit(
                                    screenTime: screenTime,
                                    topApps: topApps,
                                    topWebsites: topWebs
                                )
                            }
                        }) {
                            HStack(spacing: 4) {
                                if localLLM.isAuditing {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "sparkles")
                                }
                                Text(localLLM.isAuditing ? "Analyzing..." : "Generate AI Audit ⚡")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(localLLM.isAuditing)
                    }
                    
                    if let audit = localLLM.lastProductivityAudit {
                        Text(audit)
                            .font(.system(size: 12, design: .serif))
                            .lineSpacing(4)
                            .foregroundColor(.primary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.accentColor.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("• 🎯 Deep Work Win: Strong focus on ClipForge and core software development.")
                            Text("• ⚡ Efficiency Lever: Afternoon YouTube playback shows brief context switching.")
                            Text("• 🚀 Power Habit: Pace work sprints with 90-minute hydration reminders to sustain evening energy.")
                        }
                        .font(.system(size: 12))
                        .lineSpacing(3)
                        .foregroundColor(.secondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.gray.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(14)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.accentColor.opacity(0.25), lineWidth: 1.5)
                )
                
                // AI Entity Deduplication Status
                HStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.merge")
                        .font(.system(size: 16))
                        .foregroundColor(.purple)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Local AI Address & Tab Deduplication Active")
                            .font(.system(size: 11, weight: .bold))
                        Text("Multiple localhost:3000 tabs and subdomains are unified into single primary software entities via Ollama (qwen2.5:3b).")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.green)
                        Text("Unified")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.12))
                    .clipShape(Capsule())
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                
                // Software & Focus Work breakdown
                VStack(alignment: .leading, spacing: 10) {
                    Text("SOFTWARE PRODUCTIVITY BREAKDOWN")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                    
                    ForEach(topWebsitesList.prefix(5), id: \.id) { stat in
                        HStack {
                            Image(systemName: "globe")
                                .font(.system(size: 11))
                                .foregroundColor(.blue)
                            Text(stat.domain)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            Spacer()
                            Text(stat.durationFormatted)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                            Text("\(Int(stat.percentage * 100))%")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 32, alignment: .trailing)
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
                .padding(14)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }
}

// MARK: - Subcomponents

private struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(color)
                .frame(width: 34, height: 34)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
    }
}

private struct ActiveLiveSessionCard: View {
    let startTimeFormatted: String
    let liveDurationFormatted: String
    let frontmostApp: String
    let websiteDomain: String?
    let liveAppUsage: [String: Int]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("ACTIVE NOW")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.12))
                .clipShape(Capsule())
                
                Spacer()
                
                Text("Started at \(startTimeFormatted)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                    Text(liveDurationFormatted)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.15))
                .foregroundColor(.green)
                .clipShape(Capsule())
            }
            
            // Current frontmost app & website status
            HStack(spacing: 12) {
                if !frontmostApp.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "app.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.accentColor)
                        Text("Active App: \(frontmostApp)")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                
                if let domain = websiteDomain, !domain.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "globe")
                            .font(.system(size: 10))
                            .foregroundColor(.blue)
                        Text("Website: \(domain)")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                
                Spacer()
            }
            
            // Mini top apps in this active session
            let filteredLive = liveAppUsage.filter { !DataManager.ignoredAppNames.contains($0.key) }
            if !filteredLive.isEmpty {
                let sortedLive = filteredLive.sorted { $0.value > $1.value }.prefix(4)
                HStack(spacing: 6) {
                    Text("Session Apps:")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                    
                    ForEach(Array(sortedLive), id: \.key) { app, secs in
                        let mins = max(1, secs / 60)
                        Text("\(app) (\(mins)m)")
                            .font(.system(size: 9))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .background(Color.green.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.green.opacity(0.35), lineWidth: 1.5)
        )
    }
}

private struct SessionRow: View {
    let session: UsageSession
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 13))
                    .foregroundColor(.accentColor)
                    .frame(width: 28, height: 28)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(Circle())
                
                // Time Range ("When")
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(session.timeRangeFormatted)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.primary)
                    }
                    
                    Text(session.dateFormatted)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Duration Badge ("How long")
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 9))
                    Text(session.durationFormatted)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.12))
                .foregroundColor(.accentColor)
                .clipShape(Capsule())
            }
            
            // Program & Website breakdown chips for this session
            let topApps = session.appUsage
                .filter { !DataManager.ignoredAppNames.contains($0.key) }
                .sorted { $0.value > $1.value }
                .prefix(3)
            let topWebs = session.websiteUsage.sorted { $0.value > $1.value }.prefix(2)
            
            if !topApps.isEmpty || !topWebs.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(topApps), id: \.key) { app, secs in
                        let mins = max(1, secs / 60)
                        HStack(spacing: 3) {
                            Image(systemName: "app.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                            Text("\(app) \(mins)m")
                                .font(.system(size: 9))
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    
                    ForEach(Array(topWebs), id: \.key) { domain, _ in
                        HStack(spacing: 3) {
                            Image(systemName: "globe")
                                .font(.system(size: 8))
                                .foregroundColor(.blue)
                            Text(domain)
                                .font(.system(size: 9))
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct ProgramUsageRow: View {
    let rank: Int
    let stat: AppUsageStat
    
    private var appIcon: NSImage? {
        let appName = stat.name
        let paths = [
            "/Applications/\(appName).app",
            "/System/Applications/\(appName).app",
            "/System/Applications/Utilities/\(appName).app"
        ]
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return NSWorkspace.shared.icon(forFile: path)
            }
        }
        return nil
    }
    
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                // Rank Badge
                Text("#\(rank)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(rank == 1 ? .accentColor : .secondary)
                    .frame(width: 26, alignment: .leading)
                
                // App Icon
                if let icon = appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: "app.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.accentColor)
                        .frame(width: 24, height: 24)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                
                // App Name
                Text(stat.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Duration & Percentage
                HStack(spacing: 8) {
                    Text(stat.durationFormatted)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary)
                    
                    Text("\(Int(stat.percentage * 100))%")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
            }
            
            // Proportional Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gray.opacity(0.12))
                        .frame(height: 6)
                    
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: rank == 1 ? [.accentColor, .purple] : [.accentColor.opacity(0.8), .accentColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(4, geo.size.width * CGFloat(min(1.0, max(0.01, stat.percentage)))), height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(rank == 1 ? Color.accentColor.opacity(0.3) : Color.gray.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct WebsiteUsageRow: View {
    let rank: Int
    let stat: WebsiteUsageStat
    
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                // Rank Badge
                Text("#\(rank)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(rank == 1 ? .blue : .secondary)
                    .frame(width: 26, alignment: .leading)
                
                // Globe Icon
                Image(systemName: "globe")
                    .font(.system(size: 13))
                    .foregroundColor(.blue)
                    .frame(width: 24, height: 24)
                    .background(Color.blue.opacity(0.12))
                    .clipShape(Circle())
                
                // Website Domain
                Text(stat.domain)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Duration & Percentage
                HStack(spacing: 8) {
                    Text(stat.durationFormatted)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary)
                    
                    Text("\(Int(stat.percentage * 100))%")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
            }
            
            // Proportional Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gray.opacity(0.12))
                        .frame(height: 6)
                    
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: rank == 1 ? [.blue, .cyan] : [.blue.opacity(0.7), .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(4, geo.size.width * CGFloat(min(1.0, max(0.01, stat.percentage)))), height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(rank == 1 ? Color.blue.opacity(0.3) : Color.gray.opacity(0.12), lineWidth: 1)
        )
    }
}
