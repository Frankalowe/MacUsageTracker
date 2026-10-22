import SwiftUI

@MainActor
final class TimetableViewModel: ObservableObject {
    @Published var currentWeekStart: Date
    @Published var selectedCategoryId: UUID? = nil
    @Published var editingBlock: TimetableBlock? = nil
    @Published var isAddingBlock: Bool = false
    @Published var newBlockDate: Date = Date()
    @Published var newBlockMinute: Int = 9 * 60
    @Published var showingAutoPadAlert: Bool = false
    
    init() {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today) // 1 = Sun, 2 = Mon ...
        // Week starts on Monday (weekday 2)
        let daysToSubtract = (weekday == 1 ? 6 : weekday - 2)
        let monday = calendar.date(byAdding: .day, value: -daysToSubtract, to: calendar.startOfDay(for: today)) ?? today
        self.currentWeekStart = monday
    }
    
    func shiftWeek(by days: Int) {
        let calendar = Calendar.current
        if let newDate = calendar.date(byAdding: .day, value: days, to: currentWeekStart) {
            currentWeekStart = newDate
        }
    }
    
    func jumpToToday() {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        let daysToSubtract = (weekday == 1 ? 6 : weekday - 2)
        currentWeekStart = calendar.date(byAdding: .day, value: -daysToSubtract, to: calendar.startOfDay(for: today)) ?? today
    }
}

public struct TimetableMainView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var pomodoroEngine: PomodoroEngine
    
    @StateObject private var vm = TimetableViewModel()
    
    public init() {}
    
    private var weekRangeTitle: String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let startStr = formatter.string(from: vm.currentWeekStart)
        
        let sunday = calendar.date(byAdding: .day, value: 6, to: vm.currentWeekStart) ?? vm.currentWeekStart
        let yearFormatter = DateFormatter()
        yearFormatter.dateFormat = "MMM d, yyyy"
        let endStr = yearFormatter.string(from: sunday)
        
        return "\(startStr) – \(endStr)"
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Main Navigation & Filter Toolbar
            VStack(spacing: 12) {
                HStack(spacing: 16) {
                    // Title and Week Navigation
                    HStack(spacing: 8) {
                        Button(action: { vm.shiftWeek(by: -7) }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Today") {
                            vm.jumpToToday()
                        }
                        .buttonStyle(.bordered)
                        
                        Button(action: { vm.shiftWeek(by: 7) }) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .buttonStyle(.bordered)
                        
                        Text(weekRangeTitle)
                            .font(.system(size: 14, weight: .bold))
                            .padding(.leading, 8)
                    }
                    
                    Spacer()
                    
                    // Stats Pills
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Text("Planned:")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text("\(totalWeeklyTargetPomodoros) 🍅")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.05))
                        .clipShape(Capsule())
                        
                        HStack(spacing: 4) {
                            Text("Done:")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text("\(totalWeeklyCompletedPomodoros) 🍅")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.green)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.05))
                        .clipShape(Capsule())
                    }
                    
                    // Quick Action Buttons
                    HStack(spacing: 8) {
                        Button(action: {
                            vm.showingAutoPadAlert = true
                        }) {
                            Label("Auto-Pad Buffers", systemImage: "arrow.triangle.pull")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.bordered)
                        
                        Button(action: {
                            vm.newBlockDate = Date()
                            vm.newBlockMinute = 9 * 60
                            vm.isAddingBlock = true
                        }) {
                            Label("Add Block", systemImage: "plus")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                
                // Category Filter Pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        FilterPill(
                            title: "All Categories",
                            color: .accentColor,
                            isSelected: vm.selectedCategoryId == nil
                        ) {
                            vm.selectedCategoryId = nil
                        }
                        
                        ForEach(dataManager.categories) { category in
                            FilterPill(
                                title: category.name,
                                color: category.color,
                                isSelected: vm.selectedCategoryId == category.id
                            ) {
                                vm.selectedCategoryId = category.id
                            }
                        }
                    }
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Week Grid
            WeekGridView(
                weekStartDate: vm.currentWeekStart,
                selectedCategoryId: vm.selectedCategoryId,
                onSelectBlock: { block in
                    vm.editingBlock = block
                },
                onAddBlockAt: { date, minute in
                    vm.newBlockDate = date
                    vm.newBlockMinute = minute
                    vm.isAddingBlock = true
                }
            )
        }
        .frame(minWidth: 850, minHeight: 600)
        .sheet(item: $vm.editingBlock) { block in
            BlockEditSheet(
                blockToEdit: block,
                initialDate: block.date,
                initialStartMinute: block.startMinuteOfDay
            )
            .environmentObject(dataManager)
        }
        .sheet(isPresented: $vm.isAddingBlock) {
            BlockEditSheet(
                blockToEdit: nil,
                initialDate: vm.newBlockDate,
                initialStartMinute: vm.newBlockMinute
            )
            .environmentObject(dataManager)
        }
        .confirmationDialog(
            "Auto-Pad Buffers",
            isPresented: $vm.showingAutoPadAlert,
            titleVisibility: .visible
        ) {
            Button("Pad 10m gaps between today's blocks") {
                dataManager.autoPadBuffers(for: Date(), bufferMinutes: 10)
            }
            Button("Pad 15m gaps between today's blocks") {
                dataManager.autoPadBuffers(for: Date(), bufferMinutes: 15)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will automatically adjust overlapping or back-to-back blocks today to insert breathing room and buffer breaks.")
        }
    }
    
    private var totalWeeklyTargetPomodoros: Int {
        let calendar = Calendar.current
        var total = 0
        for i in 0..<7 {
            if let day = calendar.date(byAdding: .day, value: i, to: vm.currentWeekStart) {
                total += dataManager.blocks(for: day).reduce(0) { $0 + $1.targetPomodoros }
            }
        }
        return total
    }
    
    private var totalWeeklyCompletedPomodoros: Int {
        let calendar = Calendar.current
        var total = 0
        for i in 0..<7 {
            if let day = calendar.date(byAdding: .day, value: i, to: vm.currentWeekStart) {
                total += dataManager.blocks(for: day).reduce(0) { $0 + $1.completedPomodoros }
            }
        }
        return total
    }
}

// MARK: - Filter Pill

struct FilterPill: View {
    let title: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(isSelected ? color.opacity(0.18) : Color.gray.opacity(0.1))
            .foregroundColor(isSelected ? .primary : .secondary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? color : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
