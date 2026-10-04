import Foundation
import AppKit
import CoreAudio

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
        "музыка", "music", "spotify", "safari", "chrome", "arc", "brave", "firefox", "opera", "edge",
        "telegram", "discord", "vlc", "iina", "quicktime", "youtube", "podcast",
        "yandex", "яндекс", "vk", "zoom", "teams", "slack", "soundcloud", "twitch", "kinopoisk"
    ]
    
    private var previousVolumes: [String: Float] = [:]
    
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
        var seenBundleIDs = Set<String>()
        var seenNames = Set<String>()
        
        for app in running {
            guard app.processIdentifier != myPid else { continue }
            
            // STRICTLY only regular apps with a user interface window
            guard app.activationPolicy == .regular else { continue }
            
            let rawName = app.localizedName ?? "Application"
            let rawBundleId = app.bundleIdentifier ?? rawName
            let lowerBundle = rawBundleId.lowercased()
            let lowerName = rawName.lowercased()
            
            // Explicitly ignore WebKit / Safari sub-processes, sandboxes, daemons, helpers, XPC services
            if lowerBundle.contains("webkit") ||
               lowerBundle.contains("helper") ||
               lowerBundle.contains("service") ||
               lowerBundle.contains("xpc") ||
               lowerBundle.contains("sandbox") ||
               lowerBundle.contains("broker") ||
               lowerName.contains("веб-контент") ||
               lowerName.contains("web content") ||
               lowerName.contains("networking") ||
               lowerName.contains("media") {
                continue
            }
            
            // Filter to show ONLY real audio-playing applications (browsers, media players, voice apps)
            let isAudioApp = priorityKeywords.contains { lowerBundle.contains($0) || lowerName.contains($0) }
            guard isAudioApp else { continue }
            
            // Normalize Safari so there is strictly one single Safari entry
            let finalName: String
            let finalBundleId: String
            if lowerBundle == "com.apple.safari" || (lowerBundle.hasPrefix("com.apple.safari") && !lowerBundle.contains("webapp")) {
                finalName = "Safari"
                finalBundleId = "com.apple.Safari"
            } else {
                finalName = rawName
                finalBundleId = rawBundleId
            }
            
            let id = finalBundleId.lowercased()
            
            // Deduplicate: each application appears at most once
            if seenBundleIDs.contains(id) || seenNames.contains(finalName.lowercased()) {
                continue
            }
            seenBundleIDs.insert(id)
            seenNames.insert(finalName.lowercased())
            
            let savedVol = savedVolumes[id] ?? 1.0
            let savedMute = savedMutes[id] ?? false
            
            let target = AppAudioTarget(
                id: id,
                pid: app.processIdentifier,
                name: finalName,
                bundleId: finalBundleId,
                icon: app.icon,
                volume: savedVol,
                isMuted: savedMute
            )
            targets.append(target)
        }
        
        // Sort priority audio apps first, then alphabetically
        targets.sort { a, b in
            a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        
        self.apps = targets
    }
    
    private func isPriority(_ app: AppAudioTarget) -> Bool {
        let lower = (app.name + " " + app.bundleId).lowercased()
        return priorityKeywords.contains { lower.contains($0) }
    }
    
    public func setVolume(for id: String, volume: Float) {
        let clamped = max(0.0, min(1.0, volume))
        if let idx = apps.firstIndex(where: { $0.id == id }) {
            let oldVol = previousVolumes[id] ?? apps[idx].volume
            apps[idx].volume = clamped
            if clamped > 0.0 && apps[idx].isMuted {
                apps[idx].isMuted = false
                savedMutes[id] = false
            }
            savedVolumes[id] = clamped
            saveSettings()
            
            let target = apps[idx]
            applyVolumeToApp(target: target, volume: target.isMuted ? 0.0 : clamped, oldVolume: oldVol)
            previousVolumes[id] = clamped
        }
    }
    
    public func toggleMute(for id: String) {
        if let idx = apps.firstIndex(where: { $0.id == id }) {
            apps[idx].isMuted.toggle()
            let isMuted = apps[idx].isMuted
            savedMutes[id] = isMuted
            saveSettings()
            
            let target = apps[idx]
            let oldVol = previousVolumes[id] ?? target.volume
            applyVolumeToApp(target: target, volume: isMuted ? 0.0 : target.volume, oldVolume: oldVol)
        }
    }
    
    private func applyVolumeToApp(target: AppAudioTarget, volume: Float, oldVolume: Float) {
        queue.async {
            let bundle = target.bundleId.lowercased()
            let name = target.name
            let isMute = target.isMuted || volume <= 0.001
            let vol100 = Int(max(0.0, min(1.0, volume)) * 100.0)
            
            // 1. Direct hardware-level PCM scaling in CoreAudio HAL driver (SoundSource method)
            self.applyVolumeViaDriver(target: target, volume: volume, isMute: isMute)
            
            if bundle.contains("spotify") {
                let targetVol = isMute ? 0 : vol100
                let script = "tell application \"Spotify\" to set sound volume to \(targetVol)"
                self.runAppleScript(script)
            } else if bundle.contains("music") || bundle.contains("itunes") {
                let script = "tell application \"Music\" to set mute to \(isMute)\ntell application \"Music\" to set sound volume to \(vol100)"
                self.runAppleScript(script)
            } else if bundle.contains("vlc") {
                let vol256 = Int(volume * 256.0)
                let script = isMute ? "tell application \"VLC\" to mute" : "tell application \"VLC\" to set audio volume to \(vol256)"
                self.runAppleScript(script)
            } else if bundle.contains("quicktime") {
                let script = "tell application \"QuickTime Player\" to if (count of documents) > 0 then set audio volume of document 1 to \(isMute ? 0.0 : volume)"
                self.runAppleScript(script)
            } else if bundle.contains("safari") && !bundle.contains("webapp") {
                if isMute {
                    let script = """
                    tell application "Safari"
                        repeat with w in windows
                            repeat with t in tabs of w
                                try
                                    do JavaScript "document.querySelectorAll('audio, video').forEach(el => { el.muted = true; el.volume = 0; });" in t
                                end try
                            end repeat
                        end repeat
                    end tell
                    tell application "System Events"
                        tell process "Safari"
                            try
                                click menu item "Выключить звук на вкладке" of menu "Окно" of menu bar 1
                            end try
                            try
                                click menu item "Mute This Tab" of menu "Window" of menu bar 1
                            end try
                            try
                                click menu item "Выключить звук на остальных вкладках" of menu "Окно" of menu bar 1
                            end try
                            try
                                click menu item "Mute Other Tabs" of menu "Window" of menu bar 1
                            end try
                        end tell
                    end tell
                    """
                    self.runAppleScript(script)
                } else {
                    let script = """
                    tell application "Safari"
                        repeat with w in windows
                            repeat with t in tabs of w
                                try
                                    do JavaScript "document.querySelectorAll('audio, video').forEach(el => { el.muted = false; el.volume = \(volume); });" in t
                                end try
                            end repeat
                        end repeat
                    end tell
                    tell application "System Events"
                        tell process "Safari"
                            try
                                click menu item "Включить звук на вкладке" of menu "Окно" of menu bar 1
                            end try
                            try
                                click menu item "Unmute This Tab" of menu "Window" of menu bar 1
                            end try
                        end tell
                    end tell
                    """
                    self.runAppleScript(script)
                }
            } else if bundle.contains("chrome") || bundle.contains("arc") || bundle.contains("brave") || bundle.contains("edge") {
                let appName = name
                let script = """
                tell application "\(appName)"
                    repeat with w in windows
                        repeat with t in tabs of w
                            try
                                execute t javascript "document.querySelectorAll('audio, video').forEach(el => { el.muted = \(isMute); el.volume = \(volume); });"
                            end try
                        end repeat
                    end repeat
                end tell
                tell application "System Events"
                    tell process "\(appName)"
                        try
                            click menu item "\(isMute ? "Mute Tab" : "Unmute Tab")" of menu "Window" of menu bar 1
                        end try
                        try
                            click menu item "\(isMute ? "Заглушить вкладку" : "Включить звук")" of menu "Окно" of menu bar 1
                        end try
                    end tell
                end tell
                """
                self.runAppleScript(script)
            } else if bundle.contains("yandex") || name.lowercased().contains("яндекс") {
                if isMute {
                    self.postKey(pid: target.pid, keyCode: 49) // Spacebar toggle play/pause
                } else {
                    let delta = volume - oldVolume
                    if abs(delta) >= 0.03 {
                        let steps = min(10, max(1, Int(round(abs(delta) / 0.04))))
                        let keyCode: CGKeyCode = delta > 0 ? 126 : 125 // Cmd+Up / Cmd+Down
                        for _ in 0..<steps {
                            self.postKey(pid: target.pid, keyCode: keyCode, flags: .maskCommand)
                            usleep(25000)
                        }
                    }
                }
            } else if bundle.contains("soundcloud") || bundle.contains("telegram") || bundle.contains("discord") {
                if isMute {
                    self.postKey(pid: target.pid, keyCode: 49) // Spacebar toggle play/pause
                }
            }
        }
    }
    
    private func postKey(pid: pid_t, keyCode: CGKeyCode, flags: CGEventFlags = []) {
        if let eventDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) {
            eventDown.flags = flags
            eventDown.postToPid(pid)
        }
        usleep(15000)
        if let eventUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) {
            eventUp.flags = flags
            eventUp.postToPid(pid)
        }
    }
    
    public func applyVolumeViaDriver(target: AppAudioTarget, volume: Float, isMute: Bool) {
        guard let devID = findDriverDeviceID() else { return }
        
        let rvol: Int32 = isMute ? 0 : Int32(round(max(0.0, min(1.0, volume)) * 100.0))
        
        var list: [NSDictionary] = [
            [
                "pid" as NSString: NSNumber(value: target.pid),
                "rvol" as NSString: NSNumber(value: rvol)
            ],
            [
                "bid" as NSString: target.bundleId as NSString,
                "rvol" as NSString: NSNumber(value: rvol)
            ]
        ]
        
        if target.bundleId.contains("yandex") || target.name.lowercased().contains("яндекс") {
            list.append([
                "bid" as NSString: "ru.yandex.desktop.music.helper" as NSString,
                "rvol" as NSString: NSNumber(value: rvol)
            ])
            list.append([
                "bid" as NSString: "ru.yandex.desktop.music" as NSString,
                "rvol" as NSString: NSNumber(value: rvol)
            ])
        } else if target.bundleId.contains("safari") {
            list.append([
                "bid" as NSString: "com.apple.WebKit.GPU" as NSString,
                "rvol" as NSString: NSNumber(value: rvol)
            ])
            list.append([
                "bid" as NSString: "com.apple.WebKit.WebContent" as NSString,
                "rvol" as NSString: NSNumber(value: rvol)
            ])
        } else if target.bundleId.contains("chrome") {
            list.append([
                "bid" as NSString: "com.google.Chrome.helper" as NSString,
                "rvol" as NSString: NSNumber(value: rvol)
            ])
        }
        
        var appVolumesAddr = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(0x61707673), // 'apvs'
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let array: NSArray = list as NSArray
        var cfArr: CFArray = array as CFArray
        let dataSize = UInt32(MemoryLayout<CFArray>.size)
        
        _ = withUnsafePointer(to: &cfArr) { ptr in
            AudioObjectSetPropertyData(devID, &appVolumesAddr, 0, nil, dataSize, ptr)
        }
    }
    
    private func findDriverDeviceID() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return nil }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceIDs) == noErr else { return nil }
        
        var apvsAddr = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(0x61707673), // 'apvs'
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        for devID in deviceIDs {
            if AudioObjectHasProperty(devID, &apvsAddr) {
                return devID
            }
        }
        return nil
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
