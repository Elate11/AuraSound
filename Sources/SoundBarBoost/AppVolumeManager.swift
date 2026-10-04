import Foundation
import AppKit

public struct AppAudioTarget: Identifiable, Equatable {
    public let id: String
    public let pid: pid_t
    public let name: String
    public let bundleId: String
    public let icon: NSImage?
    public var volume: Float // 0.0 to 1.0
    public var isMuted: Bool
    
    public static func == (lhs: AppAudioTarget, rhs: AppAudioTarget) -> Bool {
        lhs.id == rhs.id && lhs.volume == rhs.volume && lhs.isMuted == rhs.isMuted
    }
}

public class AppVolumeManager: ObservableObject {
    public static let shared = AppVolumeManager()
    
    @Published public var apps: [AppAudioTarget] = []
    
    private let queue = DispatchQueue(label: "com.aurasound.appvolume", qos: .userInitiated)
    private var savedVolumes: [String: Float] = [:]
    private var savedMutes: [String: Bool] = [:]
    
    // Priority apps that commonly play audio
    private let priorityKeywords = [
        "музыка", "music", "spotify", "safari", "chrome", "arc", "brave", "firefox",
        "telegram", "discord", "vlc", "iina", "quicktime", "youtube", "podcast",
        "yandex", "яндекс", "vk", "zoom", "teams", "slack"
    ]
    
    public init() {
        loadSavedSettings()
        refreshApps()
        setupWorkspaceObservers()
    }
    
    private func setupWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(onAppChanged), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(onAppChanged), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(onAppChanged), name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }
    
    @objc private func onAppChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.refreshApps()
        }
    }
    
    public func refreshApps() {
        let running = NSWorkspace.shared.runningApplications
        let myPid = ProcessInfo.processInfo.processIdentifier
        
        var targets: [AppAudioTarget] = []
        
        for app in running {
            guard app.processIdentifier != myPid else { continue }
            
            // Only regular apps with UI or known background audio players
            guard app.activationPolicy == .regular || isKnownAudioApp(app) else { continue }
            
            let name = app.localizedName ?? "Application"
            let bundleId = app.bundleIdentifier ?? name
            let id = bundleId.lowercased()
            
            let savedVol = savedVolumes[id] ?? 1.0
            let savedMute = savedMutes[id] ?? false
            
            let target = AppAudioTarget(
                id: id,
                pid: app.processIdentifier,
                name: name,
                bundleId: bundleId,
                icon: app.icon,
                volume: savedVol,
                isMuted: savedMute
            )
            targets.append(target)
        }
        
        // Sort priority audio apps first, then alphabetically
        targets.sort { a, b in
            let aPriority = isPriority(a)
            let bPriority = isPriority(b)
            if aPriority != bPriority {
                return aPriority && !bPriority
            }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        
        self.apps = targets
    }
    
    private func isPriority(_ app: AppAudioTarget) -> Bool {
        let lower = (app.name + " " + app.bundleId).lowercased()
        return priorityKeywords.contains { lower.contains($0) }
    }
    
    private func isKnownAudioApp(_ app: NSRunningApplication) -> Bool {
        let lower = ((app.localizedName ?? "") + " " + (app.bundleIdentifier ?? "")).lowercased()
        return priorityKeywords.contains { lower.contains($0) }
    }
    
    public func setVolume(for id: String, volume: Float) {
        let clamped = max(0.0, min(1.0, volume))
        if let idx = apps.firstIndex(where: { $0.id == id }) {
            apps[idx].volume = clamped
            if clamped > 0.0 && apps[idx].isMuted {
                apps[idx].isMuted = false
                savedMutes[id] = false
            }
            savedVolumes[id] = clamped
            saveSettings()
            
            let target = apps[idx]
            applyVolumeToApp(target: target, volume: target.isMuted ? 0.0 : clamped)
        }
    }
    
    public func toggleMute(for id: String) {
        if let idx = apps.firstIndex(where: { $0.id == id }) {
            apps[idx].isMuted.toggle()
            let isMuted = apps[idx].isMuted
            savedMutes[id] = isMuted
            saveSettings()
            
            let target = apps[idx]
            applyVolumeToApp(target: target, volume: isMuted ? 0.0 : target.volume)
        }
    }
    
    private func applyVolumeToApp(target: AppAudioTarget, volume: Float) {
        queue.async {
            let bundle = target.bundleId.lowercased()
            let name = target.name
            
            if bundle.contains("spotify") {
                let vol100 = Int(volume * 100.0)
                let script = "tell application \"Spotify\" to set sound volume to \(vol100)"
                self.runAppleScript(script)
            } else if bundle.contains("music") || bundle.contains("itunes") {
                let vol100 = Int(volume * 100.0)
                let script = "tell application \"Music\" to set sound volume to \(vol100)"
                self.runAppleScript(script)
            } else if bundle.contains("vlc") {
                let vol256 = Int(volume * 256.0)
                let script = "tell application \"VLC\" to set audio volume to \(vol256)"
                self.runAppleScript(script)
            } else if bundle.contains("quicktime") {
                let script = "tell application \"QuickTime Player\" to if (count of documents) > 0 then set audio volume of document 1 to \(volume)"
                self.runAppleScript(script)
            } else if bundle.contains("safari") {
                let script = """
                tell application "Safari"
                    repeat with w in windows
                        repeat with t in tabs of w
                            try
                                do JavaScript "document.querySelectorAll('audio, video').forEach(el => el.volume = \(volume));" in t
                            end try
                        end repeat
                    end repeat
                end tell
                """
                self.runAppleScript(script)
            } else if bundle.contains("chrome") || bundle.contains("arc") || bundle.contains("brave") || bundle.contains("edge") {
                let appName = name
                let script = """
                tell application "\(appName)"
                    repeat with w in windows
                        repeat with t in tabs of w
                            try
                                execute t javascript "document.querySelectorAll('audio, video').forEach(el => el.volume = \(volume));"
                            end try
                        end repeat
                    end repeat
                end tell
                """
                self.runAppleScript(script)
            }
        }
    }
    
    private func runAppleScript(_ source: String) {
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: source) {
            scriptObject.executeAndReturnError(&error)
        }
    }
    
    private func loadSavedSettings() {
        if let vols = UserDefaults.standard.dictionary(forKey: "Aura_AppVolumes") as? [String: Float] {
            savedVolumes = vols
        }
        if let mutes = UserDefaults.standard.dictionary(forKey: "Aura_AppMutes") as? [String: Bool] {
            savedMutes = mutes
        }
    }
    
    private func saveSettings() {
        UserDefaults.standard.set(savedVolumes, forKey: "Aura_AppVolumes")
        UserDefaults.standard.set(savedMutes, forKey: "Aura_AppMutes")
    }
}
