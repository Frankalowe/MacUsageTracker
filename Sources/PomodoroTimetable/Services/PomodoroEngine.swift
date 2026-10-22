import Foundation
import SwiftUI
import Combine

public enum PomodoroMode: String, CaseIterable, Sendable {
    case work = "Focus"
    case shortBreak = "Short Break"
    case longBreak = "Long Break"
    
    public var icon: String {
        switch self {
        case .work: return "brain.head.profile"
        case .shortBreak: return "cup.and.saucer.fill"
        case .longBreak: return "figure.walk"
        }
    }
}

public enum PomodoroState: Sendable {
    case idle
    case running
    case paused
}

@MainActor
public final class PomodoroEngine: ObservableObject {
    public static let shared = PomodoroEngine()
    
    @Published public var mode: PomodoroMode = .work
    @Published public var state: PomodoroState = .idle
    @Published public var timeRemaining: TimeInterval = 25 * 60
    @Published public var totalDuration: TimeInterval = 25 * 60
    @Published public var completedSessionsCount: Int = 0
    @Published public var activeBlockId: UUID? = nil
    
    private var timerCancellable: AnyCancellable?
    
    public init() {
        resetToCurrentMode()
    }
    
    public var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return 1.0 - (timeRemaining / totalDuration)
    }
    
    public var timeString: String {
        let minutes = Int(timeRemaining) / 60
        let seconds = Int(timeRemaining) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    public var menuBarTitle: String {
        switch state {
        case .idle:
            return "🍅"
        case .running:
            let symbol = (mode == .work) ? "🍅" : "☕️"
            return "\(symbol) \(timeString)"
        case .paused:
            let symbol = (mode == .work) ? "⏸ 🍅" : "⏸ ☕️"
            return "\(symbol) \(timeString)"
        }
    }
    
    public var activeBlock: TimetableBlock? {
        if let id = activeBlockId {
            return DataManager.shared.blocks.first(where: { $0.id == id })
        }
        return DataManager.shared.currentBlock()
    }
    
    // MARK: - Actions
    
    public func startSession(mode: PomodoroMode, block: TimetableBlock? = nil) {
        self.mode = mode
        if let block = block {
            self.activeBlockId = block.id
        }
        
        let settings = DataManager.shared.settings
        let durationMinutes: Int
        switch mode {
        case .work:
            durationMinutes = settings.workDurationMinutes
        case .shortBreak:
            durationMinutes = settings.shortBreakDurationMinutes
        case .longBreak:
            durationMinutes = settings.longBreakDurationMinutes
        }
        
        self.totalDuration = TimeInterval(durationMinutes * 60)
        self.timeRemaining = self.totalDuration
        self.state = .running
        
        startTimer()
    }
    
    public func togglePlayPause() {
        switch state {
        case .idle:
            let block = activeBlock ?? DataManager.shared.currentBlock()
            startSession(mode: mode, block: block)
        case .running:
            pause()
        case .paused:
            resume()
        }
    }
    
    public func pause() {
        guard state == .running else { return }
        state = .paused
        stopTimer()
    }
    
    public func resume() {
        guard state == .paused else { return }
        state = .running
        startTimer()
    }
    
    public func skip() {
        stopTimer()
        advanceToNextSession(completedNaturally: false)
    }
    
    public func reset() {
        stopTimer()
        state = .idle
        resetToCurrentMode()
    }
    
    private func resetToCurrentMode() {
        let settings = DataManager.shared.settings
        let durationMinutes: Int
        switch mode {
        case .work:
            durationMinutes = settings.workDurationMinutes
        case .shortBreak:
            durationMinutes = settings.shortBreakDurationMinutes
        case .longBreak:
            durationMinutes = settings.longBreakDurationMinutes
        }
        self.totalDuration = TimeInterval(durationMinutes * 60)
        self.timeRemaining = self.totalDuration
    }
    
    private func startTimer() {
        stopTimer()
        timerCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }
    
    private func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }
    
    private func tick() {
        guard state == .running else { return }
        if timeRemaining > 1 {
            timeRemaining -= 1
        } else {
            timeRemaining = 0
            stopTimer()
            sessionDidFinish()
        }
    }
    
    private func sessionDidFinish() {
        let settings = DataManager.shared.settings
        if settings.playSoundChime {
            NotificationManager.shared.playChime()
        }
        
        if mode == .work {
            completedSessionsCount += 1
            if let blockId = activeBlockId {
                DataManager.shared.incrementPomodoro(forBlockId: blockId)
            }
            
            let blockName = activeBlock?.title ?? "Focus session"
            if settings.sendNotifications {
                NotificationManager.shared.sendNotification(
                    title: "Pomodoro Completed!",
                    subtitle: blockName,
                    body: "Great work! Time to step away and take a well-deserved break."
                )
            }
            
            // Advance mode suggestion to break
            advanceToNextSession(completedNaturally: true)
        } else {
            if settings.sendNotifications {
                NotificationManager.shared.sendNotification(
                    title: "Break Finished!",
                    body: "Ready to jump into your next focus block?"
                )
            }
            
            self.mode = .work
            self.state = .idle
            resetToCurrentMode()
        }
    }
    
    private func advanceToNextSession(completedNaturally: Bool) {
        let settings = DataManager.shared.settings
        if mode == .work {
            if completedSessionsCount > 0 && completedSessionsCount % settings.longBreakInterval == 0 {
                self.mode = .longBreak
            } else {
                self.mode = .shortBreak
            }
        } else {
            self.mode = .work
        }
        
        // Semi-automated: stay paused / idle awaiting user start confirmation
        self.state = .idle
        resetToCurrentMode()
    }
}
