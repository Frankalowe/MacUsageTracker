import SwiftUI

@MainActor
final class PopoverUIState: ObservableObject {
    @Published var showingSettings: Bool = false
    @Published var showingAddBlock: Bool = false
}

public struct MenuBarPopoverView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var pomodoroEngine: PomodoroEngine
    
    @StateObject private var uiState = PopoverUIState()
    
    public init() {}
    
    private var currentOrActiveBlock: TimetableBlock? {
        pomodoroEngine.activeBlock ?? dataManager.currentBlock()
    }
    
    private var nextBlock: TimetableBlock? {
        dataManager.nextUpcomingBlock()
    }
    
    private var todayBlocks: [TimetableBlock] {
        dataManager.blocks(for: Date())
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                HStack(spacing: 6) {
                    Text("🍅")
                        .font(.system(size: 16))
                    Text("Focus & Timetable")
                        .font(.system(size: 13, weight: .bold))
                }
                
                Spacer()
                
                Button(action: {
                    uiState.showingSettings = true
                }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)
            
            Divider()
            
            ScrollView {
                VStack(spacing: 14) {
                    // Mode Segment Switcher
                    HStack(spacing: 4) {
                        ForEach(PomodoroMode.allCases, id: \.self) { mode in
                            let isSelected = pomodoroEngine.mode == mode
                            Button(action: {
                                pomodoroEngine.startSession(mode: mode, block: currentOrActiveBlock)
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: mode.icon)
                                        .font(.system(size: 10))
                                    Text(mode.rawValue)
                                        .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .frame(maxWidth: .infinity)
                                .background(isSelected ? Color.accentColor : Color.gray.opacity(0.12))
                                .foregroundColor(isSelected ? .white : .primary)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    
                    // Main Timer Display
                    VStack(spacing: 10) {
                        ZStack {
                            // Background track
                            Circle()
                                .stroke(Color.gray.opacity(0.2), lineWidth: 6)
                                .frame(width: 130, height: 130)
                            
                            // Animated progress fill
                            Circle()
                                .trim(from: 0, to: CGFloat(pomodoroEngine.progress))
                                .stroke(
                                    pomodoroEngine.mode == .work ? Color.accentColor : Color.green,
                                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                                )
                                .frame(width: 130, height: 130)
                                .rotationEffect(.degrees(-90))
                                .animation(.linear(duration: 0.5), value: pomodoroEngine.progress)
                            
                            // Center Countdown
                            VStack(spacing: 2) {
                                Text(pomodoroEngine.timeString)
                                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                                
                                Text(pomodoroEngine.mode.rawValue)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // Timer Control Buttons
                        HStack(spacing: 12) {
                            // Reset button
                            Button(action: {
                                pomodoroEngine.reset()
                            }) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 12))
                                    .frame(width: 30, height: 30)
                                    .background(Color.gray.opacity(0.15))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .help("Reset Timer")
                            
                            // Play / Pause Primary Button
                            Button(action: {
                                pomodoroEngine.togglePlayPause()
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: pomodoroEngine.state == .running ? "pause.fill" : "play.fill")
                                        .font(.system(size: 14))
                                    Text(pomodoroEngine.state == .running ? "Pause" : (pomodoroEngine.state == .paused ? "Resume" : "Start Focus"))
                                        .font(.system(size: 13, weight: .bold))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(pomodoroEngine.mode == .work ? Color.accentColor : Color.green)
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            
                            // Skip button
                            Button(action: {
                                pomodoroEngine.skip()
                            }) {
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 11))
                                    .frame(width: 30, height: 30)
                                    .background(Color.gray.opacity(0.15))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .help("Skip to next")
                        }
                    }
                    .padding(.vertical, 4)
                    
                    // Smart Context Card (Current / Linked Block)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("ACTIVE TIME BLOCK")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.secondary)
                            Spacer()
                            if currentOrActiveBlock != nil {
                                Text("Linked")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.accentColor)
                            }
                        }
                        
                        if let block = currentOrActiveBlock {
                            let category = dataManager.category(for: block.categoryId)
                            HStack(alignment: .center, spacing: 8) {
                                Circle()
                                    .fill(category.color)
                                    .frame(width: 10, height: 10)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(block.title)
                                        .font(.system(size: 12, weight: .semibold))
                                        .lineLimit(1)
                                    
                                    HStack(spacing: 6) {
                                        Text(block.timeRangeFormatted)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.secondary)
                                        
                                        HStack(spacing: 2) {
                                            Text("🍅")
                                                .font(.system(size: 8))
                                            Text("\(block.completedPomodoros)/\(block.targetPomodoros)")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    dataManager.toggleBlockCompletion(withId: block.id)
                                }) {
                                    Image(systemName: block.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 16))
                                        .foregroundColor(block.isCompleted ? .green : .secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(8)
                            .background(category.color.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else if let next = nextBlock {
                            HStack(spacing: 8) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Upcoming: \(next.title)")
                                        .font(.system(size: 11, weight: .medium))
                                        .lineLimit(1)
                                    Text("Starts at \(next.startTimeFormatted)")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(8)
                            .background(Color.gray.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            HStack {
                                Text("No scheduled block right now")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(8)
                            .background(Color.gray.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(.horizontal, 16)
                    
                    // Today's Agenda Preview
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("TODAY'S SCHEDULE")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(todayBlocks.count) blocks")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        
                        VStack(spacing: 4) {
                            ForEach(todayBlocks.prefix(4)) { block in
                                let cat = dataManager.category(for: block.categoryId)
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(cat.color)
                                        .frame(width: 6, height: 6)
                                    
                                    Text(block.title)
                                        .font(.system(size: 11))
                                        .lineLimit(1)
                                        .strikethrough(block.isCompleted)
                                        .foregroundColor(block.isCompleted ? .secondary : .primary)
                                    
                                    Spacer()
                                    
                                    Text(block.startTimeFormatted)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 3)
                                .padding(.horizontal, 6)
                                .background(Color.gray.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 8)
            }
            
            Divider()
            
            // Bottom Action Bar
            HStack(spacing: 12) {
                Button(action: {
                    TimetableWindowController.shared.showWindow()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 11))
                        Text("Open Timetable Planner ↗")
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
        .frame(width: 320, height: 500)
        .sheet(isPresented: $uiState.showingSettings) {
            SettingsView()
                .environmentObject(dataManager)
        }
    }
}
