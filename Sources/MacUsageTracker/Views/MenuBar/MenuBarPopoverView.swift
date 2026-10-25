import SwiftUI

@MainActor
final class PopoverUIState: ObservableObject {
    // UI state helper
}

public struct MenuBarPopoverView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var usageEngine: UsageTrackerEngine
    
    @StateObject private var uiState = PopoverUIState()
    
    public init() {}
    
    private var todayTotalString: String {
        dataManager.todayTotalFormatted(liveCurrentDuration: usageEngine.currentSessionDuration)
    }
    
    private var todaySessionsCount: Int {
        let count = dataManager.todaySessions().count
        return usageEngine.currentSessionDuration >= Double(dataManager.settings.minimumSessionSeconds) ? count + 1 : count
    }
    
    private var dailySummaries: [DayUsageSummary] {
        dataManager.dailyUsageSummaries(lastDays: 7, liveCurrentDuration: usageEngine.currentSessionDuration)
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                HStack(spacing: 6) {
                    Text("💻")
                        .font(.system(size: 16))
                    Text("Mac Usage Tracker")
                        .font(.system(size: 13, weight: .bold))
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button(action: {
                        TimerHistoryWindowController.shared.showWindow()
                    }) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("7-Day Usage History")
                    
                    Button(action: {
                        SettingsWindowController.shared.showWindow()
                    }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Preferences")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)
            
            Divider()
            
            ScrollView {
                VStack(spacing: 14) {
                    // Active Session Card
                    VStack(spacing: 8) {
                        HStack {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(usageEngine.isAwake ? Color.green : Color.gray)
                                    .frame(width: 8, height: 8)
                                Text(usageEngine.isAwake ? "CURRENT MAC SESSION" : "SYSTEM ASLEEP")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text("Started at \(usageEngine.startTimeFormatted)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        
                        Text(usageEngine.liveTimeString)
                            .font(.system(size: 32, weight: .bold, design: .monospaced))
                            .foregroundColor(.primary)
                            .padding(.vertical, 4)
                        
                        HStack(spacing: 8) {
                            HStack(spacing: 3) {
                                Image(systemName: "drop.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(.blue)
                                let nextStretch = 90 - ((Int(usageEngine.currentSessionDuration) / 60) % 90)
                                Text("Stretch in \(nextStretch)m")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                            
                            Text("•")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                            
                            HStack(spacing: 3) {
                                Image(systemName: "quote.bubble.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(.orange)
                                let nextQuote = 60 - ((Int(usageEngine.currentSessionDuration) / 60) % 60)
                                Text("Quote in \(nextQuote)m")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                        }

                        if !usageEngine.currentFrontmostApp.isEmpty {
                            HStack(spacing: 6) {
                                HStack(spacing: 4) {
                                    Image(systemName: "app.fill")
                                        .font(.system(size: 8))
                                        .foregroundColor(.accentColor)
                                    Text(usageEngine.currentFrontmostApp)
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundColor(.primary)
                                }
                                
                                if let domain = usageEngine.currentWebsiteDomain, !domain.isEmpty {
                                    Text("•")
                                        .font(.system(size: 8))
                                        .foregroundColor(.secondary)
                                    HStack(spacing: 4) {
                                        Image(systemName: "globe")
                                            .font(.system(size: 8))
                                            .foregroundColor(.blue)
                                        Text(domain)
                                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                            .foregroundColor(.primary)
                                    }
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.gray.opacity(0.1))
                            .clipShape(Capsule())
                            .padding(.top, 2)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .background(Color.accentColor.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    
                    // Today's Cumulative Screen Time Card
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Image(systemName: "clock.badge.checkmark.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.accentColor)
                                .frame(width: 40, height: 40)
                                .background(Color.accentColor.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("TODAY'S SCREEN TIME")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.secondary)
                                
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(todayTotalString)
                                        .font(.system(size: 18, weight: .bold))
                                    
                                    Text("(\(todaySessionsCount) \(todaySessionsCount == 1 ? "period" : "periods"))")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                        }
                        
                        if dataManager.settings.enableTenHourReminder {
                            let todaySecs = dataManager.todayTotalSeconds(liveCurrentDuration: usageEngine.currentSessionDuration)
                            let progress = min(1.0, Double(todaySecs) / 36000.0)
                            VStack(alignment: .leading, spacing: 3) {
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule()
                                            .fill(Color.gray.opacity(0.15))
                                        Capsule()
                                            .fill(progress >= 1.0 ? Color.orange : Color.accentColor)
                                            .frame(width: geo.size.width * CGFloat(progress))
                                    }
                                }
                                .frame(height: 4)
                                
                                HStack {
                                    Text(progress >= 1.0 ? "🌙 10h Cap Reached (Time to rest)" : "10h Daily Cap Target")
                                        .font(.system(size: 8))
                                        .foregroundColor(progress >= 1.0 ? .orange : .secondary)
                                    Spacer()
                                    Text("\(Int(progress * 100))%")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(progress >= 1.0 ? .orange : .secondary)
                                }
                            }
                            .padding(.top, 2)
                        }
                    }
                    .padding(12)
                    .background(Color.gray.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 16)
                    
                    // 7-Day Mini Breakdown Strip
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("LAST 7 DAYS ACTIVITY")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("35-day retention")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        
                        HStack(spacing: 6) {
                            ForEach(dailySummaries) { summary in
                                VStack(spacing: 4) {
                                    Text(summary.dayLabel)
                                        .font(.system(size: 9, weight: summary.isToday ? .bold : .medium))
                                        .foregroundColor(summary.isToday ? .accentColor : .secondary)
                                    
                                    Text(summary.totalHoursFormatted)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(summary.totalSeconds > 0 ? .primary : .secondary.opacity(0.6))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(summary.isToday ? Color.accentColor.opacity(0.12) : Color.gray.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.gray.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 6)
            }
            
            Divider()
            
            // Bottom Action Bar
            HStack(spacing: 12) {
                Button(action: {
                    TimerHistoryWindowController.shared.showWindow()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 11))
                        Text("View Monthly History ↗")
                            .font(.system(size: 11, weight: .bold))
                    }
                }
                .buttonStyle(.borderedProminent)
                
                Spacer()
                
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 330, height: 450)
    }
}
