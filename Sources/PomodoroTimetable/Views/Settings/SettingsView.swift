import SwiftUI

@MainActor
final class SettingsUIState: ObservableObject {
    @Published var newCategoryName: String = ""
    @Published var newCategoryColor: String = "#6366F1"
    @Published var showingAddCategory: Bool = false
}

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataManager: DataManager
    
    @StateObject private var uiState = SettingsUIState()
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Preferences")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dataManager.save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            Form {
                Section("Pomodoro Intervals") {
                    Picker("Work Duration:", selection: $dataManager.settings.workDurationMinutes) {
                        ForEach([15, 20, 25, 30, 45, 50, 60], id: \.self) { min in
                            Text("\(min) minutes").tag(min)
                        }
                    }
                    
                    Picker("Short Break Duration:", selection: $dataManager.settings.shortBreakDurationMinutes) {
                        ForEach([3, 5, 7, 10, 15], id: \.self) { min in
                            Text("\(min) minutes").tag(min)
                        }
                    }
                    
                    Picker("Long Break Duration:", selection: $dataManager.settings.longBreakDurationMinutes) {
                        ForEach([10, 15, 20, 25, 30], id: \.self) { min in
                            Text("\(min) minutes").tag(min)
                        }
                    }
                    
                    Picker("Long Break Interval:", selection: $dataManager.settings.longBreakInterval) {
                        ForEach([2, 3, 4, 5, 6], id: \.self) { count in
                            Text("Every \(count) pomodoros").tag(count)
                        }
                    }
                }
                
                Section("Audio & Notifications") {
                    Toggle("Play audio chime when session finishes", isOn: $dataManager.settings.playSoundChime)
                    Toggle("Send native macOS notification", isOn: $dataManager.settings.sendNotifications)
                }
                
                Section("Timetable Buffers") {
                    Picker("Default Buffer Gap:", selection: $dataManager.settings.defaultBufferMinutes) {
                        ForEach([0, 5, 10, 15, 20], id: \.self) { min in
                            Text(min == 0 ? "None" : "\(min) minutes").tag(min)
                        }
                    }
                }
                
                Section("Categories") {
                    ForEach(dataManager.categories) { category in
                        HStack {
                            Circle()
                                .fill(category.color)
                                .frame(width: 10, height: 10)
                            Text(category.name)
                                .font(.system(size: 12))
                            Spacer()
                            if dataManager.categories.count > 1 {
                                Button(action: {
                                    dataManager.categories.removeAll { $0.id == category.id }
                                    dataManager.save()
                                }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    
                    HStack {
                        TextField("New Category Name", text: $uiState.newCategoryName)
                            .textFieldStyle(.roundedBorder)
                        
                        Button("Add") {
                            guard !uiState.newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            let colors = ["#4F46E5", "#0284C7", "#10B981", "#F59E0B", "#EC4899", "#8B5CF6", "#14B8A6"]
                            let randomColor = colors[dataManager.categories.count % colors.count]
                            dataManager.categories.append(
                                TaskCategory(name: uiState.newCategoryName.trimmingCharacters(in: .whitespaces), colorHex: randomColor)
                            )
                            dataManager.save()
                            uiState.newCategoryName = ""
                        }
                        .buttonStyle(.bordered)
                        .disabled(uiState.newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.top, 4)
                }
            }
            .formStyle(.grouped)
            .padding()
        }
        .frame(width: 450, height: 500)
    }
}
