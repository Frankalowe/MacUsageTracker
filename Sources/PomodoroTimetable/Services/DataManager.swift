import Foundation
import SwiftUI
import Combine

public struct AppData: Codable {
    public var categories: [TaskCategory]
    public var blocks: [TimetableBlock]
    public var settings: PomodoroSettings
}

@MainActor
public final class DataManager: ObservableObject {
    public static let shared = DataManager()
    
    @Published public var categories: [TaskCategory] = []
    @Published public var blocks: [TimetableBlock] = []
    @Published public var settings: PomodoroSettings = .default
    
    private let fileURL: URL
    
    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("PomodoroTimetable", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.fileURL = appDir.appendingPathComponent("data.json")
        
        load()
    }
    
    public func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            loadDefaultData()
            return
        }
        
        do {
            let decoded = try JSONDecoder().decode(AppData.self, from: data)
            self.categories = decoded.categories.isEmpty ? TaskCategory.defaultCategories : decoded.categories
            self.blocks = decoded.blocks
            self.settings = decoded.settings
        } catch {
            print("Failed to decode data, loading defaults: \(error)")
            loadDefaultData()
        }
    }
    
    public func save() {
        let appData = AppData(categories: categories, blocks: blocks, settings: settings)
        do {
            let data = try JSONEncoder().encode(appData)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save data: \(error)")
        }
    }
    
    private func loadDefaultData() {
        self.categories = TaskCategory.defaultCategories
        self.settings = .default
        
        // Generate helpful initial timetable blocks for weekdays
        let deepWorkCat = categories[0]
        let meetingCat = categories[1]
        let learningCat = categories[2]
        let adminCat = categories[3]
        
        let now = Date()
        self.blocks = [
            // Morning Deep Work (Weekdays 09:00 - 11:30)
            TimetableBlock(
                title: "Core Deep Work",
                notes: "High-focus priority tasks & development",
                categoryId: deepWorkCat.id,
                date: now,
                startMinuteOfDay: 9 * 60, // 09:00
                durationMinutes: 150, // 2.5 hours
                targetPomodoros: 4,
                completedPomodoros: 1,
                recurrenceRule: .weekdays,
                bufferAfterMinutes: 15
            ),
            // Daily Team Standup (Weekdays 11:45 - 12:15)
            TimetableBlock(
                title: "Daily Standup & Sync",
                notes: "Team updates & blockers",
                categoryId: meetingCat.id,
                date: now,
                startMinuteOfDay: 11 * 60 + 45, // 11:45
                durationMinutes: 30,
                targetPomodoros: 1,
                completedPomodoros: 1,
                recurrenceRule: .weekdays,
                bufferAfterMinutes: 45 // Lunch break buffer
            ),
            // Afternoon Focus (Weekdays 13:30 - 15:30)
            TimetableBlock(
                title: "Feature Implementation",
                notes: "Building key deliverables",
                categoryId: deepWorkCat.id,
                date: now,
                startMinuteOfDay: 13 * 60 + 30, // 13:30
                durationMinutes: 120,
                targetPomodoros: 3,
                completedPomodoros: 0,
                recurrenceRule: .weekdays,
                bufferAfterMinutes: 15
            ),
            // Admin & Inbox Zero (Weekdays 16:00 - 17:00)
            TimetableBlock(
                title: "Admin, PRs & Inbox",
                notes: "Review pending PRs and organize tomorrow's goals",
                categoryId: adminCat.id,
                date: now,
                startMinuteOfDay: 16 * 60, // 16:00
                durationMinutes: 60,
                targetPomodoros: 2,
                completedPomodoros: 0,
                recurrenceRule: .weekdays,
                bufferAfterMinutes: 0
            ),
            // Weekend Learning (Saturday 10:00 - 12:00)
            TimetableBlock(
                title: "Weekend Project & Tech Reading",
                notes: "Explore new frameworks and research",
                categoryId: learningCat.id,
                date: now,
                startMinuteOfDay: 10 * 60,
                durationMinutes: 120,
                targetPomodoros: 3,
                completedPomodoros: 0,
                recurrenceRule: RecurrenceRule(frequency: .customWeekly, daysOfWeek: [7]), // Sat
                bufferAfterMinutes: 10
            )
        ]
        save()
    }
    
    // MARK: - Block Queries & Manipulation
    
    public func blocks(for date: Date) -> [TimetableBlock] {
        return blocks
            .filter { $0.occursOn(date: date) }
            .sorted { $0.startMinuteOfDay < $1.startMinuteOfDay }
    }
    
    public func currentBlock(at date: Date = Date()) -> TimetableBlock? {
        let calendar = Calendar.current
        let currentMinute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        
        let todayBlocks = blocks(for: date)
        return todayBlocks.first { block in
            currentMinute >= block.startMinuteOfDay && currentMinute < block.endMinuteOfDay
        }
    }
    
    public func nextUpcomingBlock(at date: Date = Date()) -> TimetableBlock? {
        let calendar = Calendar.current
        let currentMinute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        
        let todayBlocks = blocks(for: date)
        return todayBlocks.first { block in
            block.startMinuteOfDay > currentMinute
        }
    }
    
    public func addBlock(_ block: TimetableBlock) {
        blocks.append(block)
        save()
    }
    
    public func updateBlock(_ block: TimetableBlock) {
        if let index = blocks.firstIndex(where: { $0.id == block.id }) {
            blocks[index] = block
            save()
        }
    }
    
    public func deleteBlock(withId id: UUID) {
        blocks.removeAll { $0.id == id }
        save()
    }
    
    public func toggleBlockCompletion(withId id: UUID) {
        if let index = blocks.firstIndex(where: { $0.id == id }) {
            blocks[index].isCompleted.toggle()
            save()
        }
    }
    
    public func incrementPomodoro(forBlockId id: UUID) {
        if let index = blocks.firstIndex(where: { $0.id == id }) {
            blocks[index].completedPomodoros += 1
            if blocks[index].completedPomodoros >= blocks[index].targetPomodoros {
                blocks[index].isCompleted = true
            }
            save()
        }
    }
    
    public func category(for id: UUID) -> TaskCategory {
        return categories.first(where: { $0.id == id }) ?? categories.first ?? TaskCategory(name: "General", colorHex: "#4F46E5")
    }
    
    /// Auto-pads buffer time between adjacent or overlapping blocks for the chosen date
    public func autoPadBuffers(for date: Date, bufferMinutes: Int = 10) {
        let dayBlocks = blocks(for: date)
        guard dayBlocks.count > 1 else { return }
        
        var adjustedStart = dayBlocks[0].startMinuteOfDay
        for i in 0..<dayBlocks.count {
            var block = dayBlocks[i]
            if block.startMinuteOfDay < adjustedStart {
                block.startMinuteOfDay = adjustedStart
            }
            block.bufferAfterMinutes = bufferMinutes
            updateBlock(block)
            adjustedStart = block.endMinuteOfDay + bufferMinutes
        }
    }
}
