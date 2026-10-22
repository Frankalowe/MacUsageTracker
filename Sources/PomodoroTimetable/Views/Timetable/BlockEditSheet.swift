import SwiftUI

@MainActor
final class BlockEditViewModel: ObservableObject {
    @Published var title: String = ""
    @Published var notes: String = ""
    @Published var selectedCategoryId: UUID
    @Published var startHour: Int = 9
    @Published var startMinute: Int = 0
    @Published var durationMinutes: Int = 60
    @Published var targetPomodoros: Int = 2
    @Published var completedPomodoros: Int = 0
    @Published var bufferAfterMinutes: Int = 0
    @Published var recurrenceFrequency: RecurrenceFrequency = .none
    @Published var selectedDaysOfWeek: Set<Int> = [2, 3, 4, 5, 6]
    
    init(blockToEdit: TimetableBlock?, initialDate: Date, initialStartMinute: Int) {
        if let block = blockToEdit {
            self.title = block.title
            self.notes = block.notes
            self.selectedCategoryId = block.categoryId
            self.startHour = block.startMinuteOfDay / 60
            self.startMinute = block.startMinuteOfDay % 60
            self.durationMinutes = block.durationMinutes
            self.targetPomodoros = block.targetPomodoros
            self.completedPomodoros = block.completedPomodoros
            self.bufferAfterMinutes = block.bufferAfterMinutes
            self.recurrenceFrequency = block.recurrenceRule.frequency
            self.selectedDaysOfWeek = Set(block.recurrenceRule.daysOfWeek)
        } else {
            self.selectedCategoryId = DataManager.shared.categories.first?.id ?? UUID()
            self.startHour = initialStartMinute / 60
            self.startMinute = (initialStartMinute % 60) / 15 * 15
            self.durationMinutes = 60
            self.targetPomodoros = 2
            self.bufferAfterMinutes = DataManager.shared.settings.defaultBufferMinutes
            self.recurrenceFrequency = .none
        }
    }
}

public struct BlockEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataManager: DataManager
    
    let blockToEdit: TimetableBlock?
    let initialDate: Date
    let initialStartMinute: Int
    
    @StateObject private var vm: BlockEditViewModel
    
    public init(
        blockToEdit: TimetableBlock? = nil,
        initialDate: Date = Date(),
        initialStartMinute: Int = 540 // 09:00
    ) {
        self.blockToEdit = blockToEdit
        self.initialDate = initialDate
        self.initialStartMinute = initialStartMinute
        _vm = StateObject(wrappedValue: BlockEditViewModel(
            blockToEdit: blockToEdit,
            initialDate: initialDate,
            initialStartMinute: initialStartMinute
        ))
    }
    
    private let durationOptions = [15, 25, 30, 45, 60, 90, 120, 150, 180, 240]
    private let bufferOptions = [0, 5, 10, 15, 20, 30]
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(blockToEdit == nil ? "New Timetable Block" : "Edit Block")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Title & Notes
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Title & Details")
                            .font(.subheadline.bold())
                            .foregroundColor(.secondary)
                        
                        TextField("e.g., Deep Work: API Architecture", text: $vm.title)
                            .textFieldStyle(.roundedBorder)
                        
                        TextField("Notes / checklist / deliverables...", text: $vm.notes)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    // Category Selection
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Category")
                            .font(.subheadline.bold())
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 8) {
                            ForEach(dataManager.categories) { category in
                                Button(action: {
                                    vm.selectedCategoryId = category.id
                                }) {
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(category.color)
                                            .frame(width: 8, height: 8)
                                        Text(category.name)
                                            .font(.system(size: 11, weight: .medium))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        vm.selectedCategoryId == category.id
                                            ? category.color.opacity(0.2)
                                            : Color(NSColor.controlBackgroundColor)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(vm.selectedCategoryId == category.id ? category.color : Color.gray.opacity(0.3), lineWidth: 1)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    
                    // Timing & Duration
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Schedule Time")
                            .font(.subheadline.bold())
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 16) {
                            // Start Time
                            HStack(spacing: 4) {
                                Text("Starts:")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                
                                Picker("", selection: $vm.startHour) {
                                    ForEach(0..<24) { h in
                                        Text(String(format: "%02d", h)).tag(h)
                                    }
                                }
                                .frame(width: 65)
                                
                                Text(":")
                                
                                Picker("", selection: $vm.startMinute) {
                                    ForEach([0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55], id: \.self) { m in
                                        Text(String(format: "%02d", m)).tag(m)
                                    }
                                }
                                .frame(width: 65)
                            }
                            
                            // Duration
                            HStack(spacing: 4) {
                                Text("Duration:")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                
                                Picker("", selection: $vm.durationMinutes) {
                                    ForEach(durationOptions, id: \.self) { dur in
                                        let hours = dur / 60
                                        let mins = dur % 60
                                        let label = hours > 0 ? (mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h") : "\(mins)m"
                                        Text(label).tag(dur)
                                    }
                                }
                                .frame(width: 95)
                            }
                        }
                    }
                    
                    // Recurrence
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recurrence (Repeat Schedule)")
                            .font(.subheadline.bold())
                            .foregroundColor(.secondary)
                        
                        Picker("Repeat", selection: $vm.recurrenceFrequency) {
                            ForEach(RecurrenceFrequency.allCases, id: \.self) { freq in
                                Text(freq.rawValue).tag(freq)
                            }
                        }
                        .pickerStyle(.segmented)
                        
                        if vm.recurrenceFrequency == .customWeekly {
                            HStack(spacing: 6) {
                                ForEach([
                                    (2, "Mon"),
                                    (3, "Tue"),
                                    (4, "Wed"),
                                    (5, "Thu"),
                                    (6, "Fri"),
                                    (7, "Sat"),
                                    (1, "Sun")
                                ], id: \.0) { dayNum, dayName in
                                    let isSelected = vm.selectedDaysOfWeek.contains(dayNum)
                                    Button(action: {
                                        if isSelected {
                                            vm.selectedDaysOfWeek.remove(dayNum)
                                        } else {
                                            vm.selectedDaysOfWeek.insert(dayNum)
                                        }
                                    }) {
                                        Text(dayName)
                                            .font(.system(size: 11, weight: isSelected ? .bold : .regular))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(isSelected ? Color.accentColor : Color.gray.opacity(0.15))
                                            .foregroundColor(isSelected ? .white : .primary)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                    
                    // Pomodoro Targets & Buffer Auto-Padding
                    HStack(alignment: .top, spacing: 24) {
                        // Target Pomodoros
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Target Pomodoros")
                                .font(.subheadline.bold())
                                .foregroundColor(.secondary)
                            
                            Stepper(value: $vm.targetPomodoros, in: 1...16) {
                                HStack(spacing: 4) {
                                    Text("🍅")
                                    Text("\(vm.targetPomodoros) session\(vm.targetPomodoros > 1 ? "s" : "")")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("(\(vm.targetPomodoros * 25)m focus)")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        // Buffer padding after
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Buffer Gap After Block")
                                .font(.subheadline.bold())
                                .foregroundColor(.secondary)
                            
                            Picker("", selection: $vm.bufferAfterMinutes) {
                                ForEach(bufferOptions, id: \.self) { buf in
                                    Text(buf == 0 ? "No buffer" : "\(buf) min buffer").tag(buf)
                                }
                            }
                            .frame(width: 130)
                        }
                    }
                    
                    // Delete Block button if editing
                    if let block = blockToEdit {
                        Divider()
                            .padding(.vertical, 4)
                        
                        HStack {
                            Button(role: .destructive, action: {
                                dataManager.deleteBlock(withId: block.id)
                                dismiss()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "trash")
                                    Text("Delete Block")
                                }
                                .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                            
                            Spacer()
                        }
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Footer
            HStack {
                Spacer()
                Button("Save Block") {
                    saveBlock()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(vm.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 500, height: 560)
    }
    
    private func saveBlock() {
        let rule: RecurrenceRule
        switch vm.recurrenceFrequency {
        case .none:
            rule = .none
        case .daily:
            rule = .daily
        case .weekdays:
            rule = .weekdays
        case .customWeekly:
            rule = RecurrenceRule(frequency: .customWeekly, daysOfWeek: Array(vm.selectedDaysOfWeek))
        }
        
        let startMinuteTotal = vm.startHour * 60 + vm.startMinute
        
        if let existing = blockToEdit {
            var updated = existing
            updated.title = vm.title.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.notes = vm.notes
            updated.categoryId = vm.selectedCategoryId
            updated.startMinuteOfDay = startMinuteTotal
            updated.durationMinutes = vm.durationMinutes
            updated.targetPomodoros = vm.targetPomodoros
            updated.completedPomodoros = vm.completedPomodoros
            updated.bufferAfterMinutes = vm.bufferAfterMinutes
            updated.recurrenceRule = rule
            dataManager.updateBlock(updated)
        } else {
            let newBlock = TimetableBlock(
                title: vm.title.trimmingCharacters(in: .whitespacesAndNewlines),
                notes: vm.notes,
                categoryId: vm.selectedCategoryId,
                date: initialDate,
                startMinuteOfDay: startMinuteTotal,
                durationMinutes: vm.durationMinutes,
                targetPomodoros: vm.targetPomodoros,
                completedPomodoros: 0,
                isCompleted: false,
                recurrenceRule: rule,
                bufferAfterMinutes: vm.bufferAfterMinutes
            )
            dataManager.addBlock(newBlock)
        }
    }
}
