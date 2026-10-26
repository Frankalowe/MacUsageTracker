import Foundation
@preconcurrency import AVFoundation
import AppKit

@MainActor
public final class MotivationPlayerService: NSObject, ObservableObject, AVAudioPlayerDelegate {
    public static let shared = MotivationPlayerService()
    
    @Published public private(set) var isPlaying: Bool = false
    @Published public private(set) var trackName: String = "The Unit (Extended Remix)"
    
    private var audioPlayer: AVAudioPlayer?
    
    private override init() {
        super.init()
    }
    
    /// Triggers quote notification and plays the motivation soundtrack till the end
    public func triggerMotivation() {
        // 1. Play the music till the end
        playMotivationSong()
        
        // 2. Dispatch a motivational quote notification immediately
        Task {
            let quote = await NotificationService.shared.getMotivationalQuote()
            NotificationService.shared.sendNotification(
                title: "⚡ Motivation Boost",
                subtitle: "— \(quote.author)",
                body: "\"\(quote.quote)\""
            )
        }
    }
    
    public func playMotivationSong() {
        stop()
        
        guard let url = findSongURL() else {
            print("Could not find motivation song mp3 file")
            return
        }
        
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            player.play()
            self.audioPlayer = player
            self.isPlaying = true
            print("Playing motivation song till the end: \(url.path)")
        } catch {
            print("Failed to initialize AVAudioPlayer: \(error)")
        }
    }
    
    public func stop() {
        if let player = audioPlayer, player.isPlaying {
            player.stop()
        }
        self.audioPlayer = nil
        self.isPlaying = false
    }
    
    public func toggle() {
        if isPlaying {
            stop()
        } else {
            triggerMotivation()
        }
    }
    
    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.audioPlayer = nil
            print("Motivation song finished playing completely.")
        }
    }
    
    private func findSongURL() -> URL? {
        let filename = "The-Unit-From-The-UnitExtended-Remix"
        
        // 1. App Bundle Resources
        if let bundleURL = Bundle.main.url(forResource: filename, withExtension: "mp3") {
            return bundleURL
        }
        
        // 2. App Bundle Contents/Resources direct path
        let bundlePath = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/\(filename).mp3")
        if FileManager.default.fileExists(atPath: bundlePath.path) {
            return bundlePath
        }
        
        // 3. Application Support directory
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let appSupportURL = appSupport.appendingPathComponent("MacUsageTracker/sounds/\(filename).mp3")
            if FileManager.default.fileExists(atPath: appSupportURL.path) {
                return appSupportURL
            }
        }
        
        // 4. Project workspace source
        let workspaceURL = URL(fileURLWithPath: "/Users/franklowe/Documents/antigravity/brave-oppenheimer/Sources/MacUsageTracker/Resources/\(filename).mp3")
        if FileManager.default.fileExists(atPath: workspaceURL.path) {
            return workspaceURL
        }
        
        // 5. Original dump source
        let dumpURL = URL(fileURLWithPath: "/Users/franklowe/Documents/dump/\(filename).mp3")
        if FileManager.default.fileExists(atPath: dumpURL.path) {
            return dumpURL
        }
        
        return nil
    }
}
