import SwiftUI

public struct WeekGridView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var pomodoroEngine: PomodoroEngine
    
    let weekStartDate: Date
    let selectedCategoryId: UUID?
    let onSelectBlock: (TimetableBlock) -> Void
    let onAddBlockAt: (Date, Int) -> Void
    
    private let startHour = 7
    private let endHour = 22
    private let hourHeight: CGFloat = 58
    
    private var totalSpanMinutes: Int {
        (endHour - startHour) * 60
    }
    
    private var daysInWeek: [Date] {
        let calendar = Calendar.current
        return (0..<7).compactMap { dayOffset in
            calendar.date(byAdding: .day, value: dayOffset, to: weekStartDate)
        }
    }
    
    public init(
        weekStartDate: Date,
        selectedCategoryId: UUID?,
        onSelectBlock: @escaping (TimetableBlock) -> Void,
        onAddBlockAt: @escaping (Date, Int) -> Void
    ) {
        self.weekStartDate = weekStartDate
        self.selectedCategoryId = selectedCategoryId
        self.onSelectBlock = onSelectBlock
        self.onAddBlockAt = onAddBlockAt
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Day Header Bar
            HStack(spacing: 0) {
                // Time gutter offset
                Text("Time")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 55, alignment: .center)
                
                Divider()
                
                ForEach(daysInWeek, id: \.self) { day in
                    DayHeaderCell(day: day, blocks: dataManager.blocks(for: day))
                    if day != daysInWeek.last {
                        Divider()
                    }
                }
            }
            .frame(height: 52)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Scrollable Timeline Grid
            ScrollView(.vertical, showsIndicators: true) {
                HStack(alignment: .top, spacing: 0) {
                    // Time Labels Gutter
                    VStack(alignment: .trailing, spacing: 0) {
                        ForEach(startHour..<endHour, id: \.self) { hour in
                            HStack {
                                Text(String(format: "%02d:00", hour))
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 45, alignment: .trailing)
                                Spacer(minLength: 4)
                            }
                            .frame(height: hourHeight, alignment: .top)
                        }
                    }
                    .frame(width: 55)
                    .padding(.top, 2)
                    
                    Divider()
                    
                    // 7 Day Columns
                    HStack(spacing: 0) {
                        ForEach(daysInWeek, id: \.self) { day in
                            DayColumnView(
                                day: day,
                                startHour: startHour,
                                endHour: endHour,
                                hourHeight: hourHeight,
                                selectedCategoryId: selectedCategoryId,
                                onSelectBlock: onSelectBlock,
                                onAddBlockAt: onAddBlockAt
                            )
                            
                            if day != daysInWeek.last {
                                Divider()
                            }
                        }
                    }
                }
                .frame(height: CGFloat(endHour - startHour) * hourHeight)
            }
        }
    }
}

// MARK: - Day Header Cell

struct DayHeaderCell: View {
    let day: Date
    let blocks: [TimetableBlock]
    
    private var isToday: Bool {
        Calendar.current.isDateInToday(day)
    }
    
    private var dayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: day).uppercased()
    }
    
    private var dayNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: day)
    }
    
    private var completedPomodoros: Int {
        blocks.reduce(0) { $0 + $1.completedPomodoros }
    }
    
    private var targetPomodoros: Int {
        blocks.reduce(0) { $0 + $1.targetPomodoros }
    }
    
    var body: some View {
        VStack(spacing: 2) {
            Text(dayName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(isToday ? .accentColor : .secondary)
            
            HStack(spacing: 4) {
                Text(dayNumber)
                    .font(.system(size: 14, weight: isToday ? .bold : .medium))
                    .foregroundColor(isToday ? .white : .primary)
                    .frame(width: 24, height: 24)
                    .background(isToday ? Color.accentColor : Color.clear)
                    .clipShape(Circle())
                
                if targetPomodoros > 0 {
                    HStack(spacing: 2) {
                        Text("🍅")
                            .font(.system(size: 8))
                        Text("\(completedPomodoros)/\(targetPomodoros)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.black.opacity(0.06))
                    .clipShape(Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

// MARK: - Day Column View

struct DayColumnView: View {
    @EnvironmentObject var dataManager: DataManager
    
    let day: Date
    let startHour: Int
    let endHour: Int
    let hourHeight: CGFloat
    let selectedCategoryId: UUID?
    let onSelectBlock: (TimetableBlock) -> Void
    let onAddBlockAt: (Date, Int) -> Void
    
    private var dayBlocks: [TimetableBlock] {
        let all = dataManager.blocks(for: day)
        if let catId = selectedCategoryId {
            return all.filter { $0.categoryId == catId }
        }
        return all
    }
    
    private var isToday: Bool {
        Calendar.current.isDateInToday(day)
    }
    
    private var currentMinuteOfDay: Int {
        let cal = Calendar.current
        return cal.component(.hour, from: Date()) * 60 + cal.component(.minute, from: Date())
    }
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Background Hour Lines & Click-to-add slots
                VStack(spacing: 0) {
                    ForEach(startHour..<endHour, id: \.self) { hour in
                        Rectangle()
                            .fill(Color.clear)
                            .frame(height: hourHeight)
                            .overlay(
                                Divider()
                                    .opacity(0.4),
                                alignment: .top
                            )
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                onAddBlockAt(day, hour * 60)
                            }
                    }
                }
                
                // Blocks
                ForEach(dayBlocks) { block in
                    let topOffset = CGFloat(block.startMinuteOfDay - (startHour * 60)) * (hourHeight / 60.0)
                    let blockHeight = CGFloat(block.durationMinutes) * (hourHeight / 60.0)
                    
                    if topOffset + blockHeight > 0 && topOffset < CGFloat(endHour - startHour) * hourHeight {
                        BlockCardView(
                            block: block,
                            height: blockHeight - 2,
                            onEdit: {
                                onSelectBlock(block)
                            }
                        )
                        .frame(width: geo.size.width - 4)
                        .offset(x: 2, y: max(0, topOffset))
                    }
                }
                
                // Current Time Red Indicator
                if isToday {
                    let nowOffset = CGFloat(currentMinuteOfDay - (startHour * 60)) * (hourHeight / 60.0)
                    if nowOffset >= 0 && nowOffset <= CGFloat(endHour - startHour) * hourHeight {
                        HStack(spacing: 0) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 7, height: 7)
                            Rectangle()
                                .fill(Color.red)
                                .frame(height: 1.5)
                        }
                        .offset(y: nowOffset - 3.5)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isToday ? Color.accentColor.opacity(0.02) : Color.clear)
    }
}
