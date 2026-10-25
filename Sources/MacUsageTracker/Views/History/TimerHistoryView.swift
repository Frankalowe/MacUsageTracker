import SwiftUI

@MainActor
final class HistoryUIState: ObservableObject {
    @Published var selectedPeriodDays: Int = 35 // Default: 35 days for full month analysis
    @Published var selectedDateKey: String? = nil
    @Published var showingClearConfirmation: Bool = false
}

public struct TimerHistoryView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var usageEngine: UsageTrackerEngine
    
    @StateObject private var uiState = HistoryUIState()
    
    public init() {}
    
    private var allPeriodSessions: [UsageSession] {
        dataManager.sessionsInLastDays(days: uiState.selectedPeriodDays)
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
                    
                    Text("Auto-recorded wake-to-sleep periods • Stored for 35 days for full monthly work analysis")
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
                
                if !allPeriodSessions.isEmpty {
                    Button(action: {
                        uiState.showingClearConfirmation = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                            Text("Clear")
                                .font(.system(size: 11))
                        }
                    }
                    .buttonStyle(.bordered)
                    .confirmationDialog("Clear all usage history?", isPresented: $uiState.showingClearConfirmation) {
                        Button("Delete All History", role: .destructive) {
                            dataManager.clearAllSessions()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will delete all stored session periods immediately.")
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Metrics Cards
            HStack(spacing: 14) {
                MetricCard(
                    title: "Total Screen Time (\(uiState.selectedPeriodDays)d)",
                    value: totalPeriodFormatted,
                    icon: "laptopcomputer",
                    color: .accentColor
                )
                
                MetricCard(
                    title: "Sessions Used (\(uiState.selectedPeriodDays)d)",
                    value: "\(allPeriodSessions.count)",
                    icon: "bolt.badge.clock.fill",
                    color: .green
                )
                
                MetricCard(
                    title: "Active Daily Average",
                    value: dailyAverageFormatted,
                    icon: "chart.line.uptrend.xyaxis",
                    color: .purple
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 10)
            
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
            
            // Sessions List or Empty State
            if filteredSessions.isEmpty {
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
                                VStack(spacing: 6) {
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
            
            Divider()
            
            // Bottom Info Bar
            HStack {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                Text("Automatic 35-Day Retention: Sessions are kept for 35 days (full monthly analysis) and purged automatically thereafter.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 640, minHeight: 650)
    }
}

// MARK: - Subcomponents

private struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)
            }
            Spacer()
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
    }
}

private struct SessionRow: View {
    let session: UsageSession
    
    var body: some View {
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.12), lineWidth: 1)
        )
    }
}
