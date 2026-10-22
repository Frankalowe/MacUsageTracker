import SwiftUI

@MainActor
final class CardUIState: ObservableObject {
    @Published var isHovered: Bool = false
}

public struct BlockCardView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var pomodoroEngine: PomodoroEngine
    
    let block: TimetableBlock
    let height: CGFloat
    let onEdit: () -> Void
    
    @StateObject private var uiState = CardUIState()
    
    public init(block: TimetableBlock, height: CGFloat, onEdit: @escaping () -> Void) {
        self.block = block
        self.height = height
        self.onEdit = onEdit
    }
    
    private var category: TaskCategory {
        dataManager.category(for: block.categoryId)
    }
    
    private var isCurrentBlock: Bool {
        pomodoroEngine.activeBlockId == block.id
    }
    
    public var body: some View {
        ZStack(alignment: .topLeading) {
            // Card Background
            RoundedRectangle(cornerRadius: 6)
                .fill(category.color.opacity(block.isCompleted ? 0.15 : 0.22))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            isCurrentBlock ? Color.accentColor : category.color.opacity(0.8),
                            lineWidth: isCurrentBlock ? 2 : 1
                        )
                )
            
            // Left color strip
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(category.color)
                    .frame(width: 4)
                    .padding(.vertical, 3)
                    .padding(.leading, 3)
                
                Spacer()
            }
            
            // Content
            VStack(alignment: .leading, spacing: 3) {
                // Header row: Title + Actions
                HStack(alignment: .top) {
                    Text(block.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(block.isCompleted ? .secondary : .primary)
                        .strikethrough(block.isCompleted)
                        .lineLimit(height < 50 ? 1 : 2)
                    
                    Spacer(minLength: 4)
                    
                    if uiState.isHovered || block.isCompleted {
                        Button(action: {
                            dataManager.toggleBlockCompletion(withId: block.id)
                        }) {
                            Image(systemName: block.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 11))
                                .foregroundColor(block.isCompleted ? .green : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                // Time Range
                if height >= 45 {
                    Text(block.timeRangeFormatted)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                // Pomodoro Pill / Recurrence badge
                if height >= 65 {
                    Spacer(minLength: 0)
                    
                    HStack(spacing: 6) {
                        // Pomodoro progress
                        HStack(spacing: 2) {
                            Text("🍅")
                                .font(.system(size: 9))
                            Text("\(block.completedPomodoros)/\(block.targetPomodoros)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.08))
                        .clipShape(Capsule())
                        
                        if block.recurrenceRule.frequency != .none {
                            Image(systemName: "repeat")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                        
                        if block.bufferAfterMinutes > 0 {
                            Text("+\(block.bufferAfterMinutes)m buf")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if uiState.isHovered && !block.isCompleted {
                            Button(action: {
                                pomodoroEngine.startSession(mode: .work, block: block)
                            }) {
                                HStack(spacing: 2) {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 7))
                                    Text("Focus")
                                        .font(.system(size: 8, weight: .bold))
                                }
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .frame(height: max(26, height))
        .contentShape(Rectangle())
        .onTapGesture {
            onEdit()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                uiState.isHovered = hovering
            }
        }
    }
}
