import Foundation
import SwiftUI
import Combine

public struct EQBand: Identifiable, Codable, Equatable {
    public let id: Int
    public let frequency: Double
    public let label: String
    public var gain: Double
    
    public init(id: Int, frequency: Double, label: String, gain: Double = 0.0) {
        self.id = id
        self.frequency = frequency
        self.label = label
        self.gain = gain
    }
}

public struct EQPreset: Identifiable, Codable, Equatable {
    public var id: String { name }
    public let name: String
    public let icon: String
    public let description: String
    public let gains: [Double]
    public var isCustom: Bool = false
    
    public static let standardBands: [Double] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    public static let standardLabels: [String] = ["32Hz", "64Hz", "125Hz", "250Hz", "500Hz", "1kHz", "2kHz", "4kHz", "8kHz", "16kHz"]
    
    public static let presets: [EQPreset] = [
        EQPreset(
            name: "Flat",
            icon: "equalizer",
            description: "Reference studio response",
            gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        ),
        EQPreset(
            name: "Bass Boost",
            icon: "speaker.wave.3.fill",
            description: "Enhanced low-end response",
            gains: [12.0, 10.0, 7.0, 4.0, 1.0, 0.0, 0.0, 1.0, 3.0, 4.0]
        ),
        EQPreset(
            name: "AirPods",
            icon: "airpodspro",
            description: "Optimized for in-ear drivers",
            gains: [6.0, 4.5, 2.0, 0.0, 1.5, 3.5, 5.0, 6.0, 7.0, 6.0]
        ),
        EQPreset(
            name: "Vocal",
            icon: "bubble.left.and.text.bubble.right.fill",
            description: "Speech and dialogue clarity",
            gains: [-4.0, -2.0, 0.0, 3.0, 6.0, 8.0, 6.0, 4.0, 2.0, 0.0]
        ),
        EQPreset(
            name: "Electronic",
            icon: "waveform.path.ecg",
            description: "Sub-bass and high-frequency sparkle",
            gains: [10.0, 8.0, 4.0, 0.0, -2.0, 2.0, 4.0, 6.0, 8.0, 9.0]
        ),
        EQPreset(
            name: "Rock",
            icon: "guitars.fill",
            description: "Mid-range drive and percussion",
            gains: [7.0, 5.5, 3.0, -1.5, -2.5, 1.5, 5.0, 7.0, 8.0, 6.0]
        ),
        EQPreset(
            name: "Pop",
            icon: "music.note",
            description: "Bright vocals with rhythmic low-end",
            gains: [4.0, 5.0, 3.0, 0.0, 1.5, 3.0, 4.5, 6.0, 5.0, 4.0]
        ),
        EQPreset(
            name: "Cinema",
            icon: "film.fill",
            description: "Wide dynamic range for films",
            gains: [8.0, 6.0, 2.0, -1.0, 1.0, 3.0, 5.0, 6.0, 7.0, 8.0]
        ),
        EQPreset(
            name: "Acoustic",
            icon: "pianokeys",
            description: "Natural acoustic instruments",
            gains: [4.0, 3.0, 1.5, 2.0, 3.0, 3.0, 4.0, 4.5, 5.0, 5.5]
        ),
        EQPreset(
            name: "Late Night",
            icon: "moon.fill",
            description: "Controlled dynamics and reduced harshness",
            gains: [-5.0, -3.0, 0.0, 1.5, 2.0, 2.0, 1.0, 0.0, -3.0, -5.0]
        )
    ]
}

// MARK: - Dolby Atmos 3D Spatial Audio Source
public struct AtmosSource: Identifiable, Codable, Equatable {
    public var id: String
    public var name: String
    public var icon: String
    public var angle: Double // -180...180 degrees (0 = center/front)
    public var distance: Double // 0.5...5.0 meters
    public var elevation: Double // 0...90 degrees (height/overhead)
    public var gain: Double // 0.0...1.5
    public var isMuted: Bool
    
    public init(id: String, name: String, icon: String = "speaker.wave.2", angle: Double, distance: Double = 2.0, elevation: Double = 0.0, gain: Double = 1.0, isMuted: Bool = false) {
        self.id = id
        self.name = name
        self.icon = icon
        self.angle = angle
        self.distance = distance
        self.elevation = elevation
        self.gain = gain
        self.isMuted = isMuted
    }
}

public class AudioDSPManager: ObservableObject {
    public static let shared = AudioDSPManager()
    
    @Published public var boostMultiplier: Double = 1.0 {
        didSet {
            RealAudioEngine.shared.updateBoost(multiplier: boostMultiplier)
            saveState()
        }
    }
    
    @Published public var isEQEnabled: Bool = true {
        didSet {
            RealAudioEngine.shared.setEQBypass(!isEQEnabled)
            saveState()
        }
    }
    
    @Published public var bands: [EQBand] = [] {
        didSet {
            RealAudioEngine.shared.updateBands(gains: bands.map { $0.gain })
            saveState()
        }
    }
    
    @Published public var selectedPreset: EQPreset = EQPreset.presets[0] {
        didSet {
            saveState()
        }
    }
    
    @Published public var customPresets: [EQPreset] = [] {
        didSet {
            saveCustomPresets()
        }
    }
    
    @Published public var isAntiClippingEnabled: Bool = true
    @Published public var isSpatialEnhancerEnabled: Bool = false
    @Published public var isBassPunchEnabled: Bool = false
    @Published public var isVocalBoostEnabled: Bool = false
    
    // MARK: - Dolby Atmos 3D Spatial Audio
    @Published public var isAtmosEnabled: Bool = true {
        didSet { saveState() }
    }
    @Published public var atmosMode: String = "CINEMA" {
        didSet { saveState() }
    }
    @Published public var atmosRoomSize: Double = 1.15 {
        didSet { saveState() }
    }
    @Published public var atmosSurroundWidth: Double = 1.45 {
        didSet { saveState() }
    }
    @Published public var atmosElevation: Double = 35.0 {
        didSet { saveState() }
    }
    @Published public var atmosBassExciter: Double = 1.35 {
        didSet { saveState() }
    }
    
    public func selectAtmosMode(_ mode: String) {
        atmosMode = mode
        switch mode {
        case "CINEMA":
            atmosRoomSize = 1.40
            atmosSurroundWidth = 1.70
            atmosElevation = 50.0
            atmosBassExciter = 1.55
        case "MUSIC":
            atmosRoomSize = 0.95
            atmosSurroundWidth = 1.50
            atmosElevation = 30.0
            atmosBassExciter = 1.25
        case "360 SPATIAL":
            atmosRoomSize = 1.70
            atmosSurroundWidth = 1.95
            atmosElevation = 75.0
            atmosBassExciter = 1.45
        default:
            break
        }
    }
    @Published public var atmosRoomPreset: String = "Cinema 7.1.4" {
        didSet { saveState() }
    }
    @Published public var selectedAtmosSourceIndex: Int = 0
    @Published public var atmosSources: [AtmosSource] = [
        AtmosSource(id: "FL", name: "Front Left",  icon: "speaker.wave.2", angle: -30, distance: 2.5, elevation: 0,  gain: 1.0, isMuted: false),
        AtmosSource(id: "C",  name: "Center",      icon: "speaker.wave.1", angle: 0,   distance: 2.5, elevation: 0,  gain: 1.0, isMuted: false),
        AtmosSource(id: "FR", name: "Front Right", icon: "speaker.wave.2", angle: 30,  distance: 2.5, elevation: 0,  gain: 1.0, isMuted: false),
        AtmosSource(id: "SL", name: "Surround L",  icon: "speaker.wave.2", angle: -90, distance: 2.0, elevation: 15, gain: 1.0, isMuted: false),
        AtmosSource(id: "SR", name: "Surround R",  icon: "speaker.wave.2", angle: 90,  distance: 2.0, elevation: 15, gain: 1.0, isMuted: false),
        AtmosSource(id: "HL", name: "Height L",    icon: "arrow.up.circle", angle: -45, distance: 2.8, elevation: 65, gain: 0.9, isMuted: false),
        AtmosSource(id: "HR", name: "Height R",    icon: "arrow.up.circle", angle: 45,  distance: 2.8, elevation: 65, gain: 0.9, isMuted: false),
    ] {
        didSet { saveState() }
    }
    
    public func applyAtmosPreset(_ presetName: String) {
        atmosRoomPreset = presetName
        switch presetName {
        case "Cinema 7.1.4":
            atmosSources = [
                AtmosSource(id: "FL", name: "Front Left",  icon: "speaker.wave.2", angle: -30, distance: 2.5, elevation: 0,  gain: 1.0, isMuted: false),
                AtmosSource(id: "C",  name: "Center",      icon: "speaker.wave.1", angle: 0,   distance: 2.5, elevation: 0,  gain: 1.0, isMuted: false),
                AtmosSource(id: "FR", name: "Front Right", icon: "speaker.wave.2", angle: 30,  distance: 2.5, elevation: 0,  gain: 1.0, isMuted: false),
                AtmosSource(id: "SL", name: "Surround L",  icon: "speaker.wave.2", angle: -90, distance: 2.0, elevation: 15, gain: 1.0, isMuted: false),
                AtmosSource(id: "SR", name: "Surround R",  icon: "speaker.wave.2", angle: 90,  distance: 2.0, elevation: 15, gain: 1.0, isMuted: false),
                AtmosSource(id: "HL", name: "Height L",    icon: "arrow.up.circle", angle: -45, distance: 2.8, elevation: 65, gain: 0.9, isMuted: false),
                AtmosSource(id: "HR", name: "Height R",    icon: "arrow.up.circle", angle: 45,  distance: 2.8, elevation: 65, gain: 0.9, isMuted: false),
            ]
        case "Headphones 3D":
            atmosSources = [
                AtmosSource(id: "FL", name: "Front Left",  icon: "speaker.wave.2", angle: -45, distance: 1.2, elevation: 0,  gain: 1.0, isMuted: false),
                AtmosSource(id: "C",  name: "Center",      icon: "speaker.wave.1", angle: 0,   distance: 1.0, elevation: 0,  gain: 1.0, isMuted: false),
                AtmosSource(id: "FR", name: "Front Right", icon: "speaker.wave.2", angle: 45,  distance: 1.2, elevation: 0,  gain: 1.0, isMuted: false),
                AtmosSource(id: "SL", name: "Surround L",  icon: "speaker.wave.2", angle: -110, distance: 1.2, elevation: 20, gain: 1.0, isMuted: false),
                AtmosSource(id: "SR", name: "Surround R",  icon: "speaker.wave.2", angle: 110,  distance: 1.2, elevation: 20, gain: 1.0, isMuted: false),
                AtmosSource(id: "HL", name: "Height L",    icon: "arrow.up.circle", angle: -50, distance: 1.5, elevation: 75, gain: 0.9, isMuted: false),
                AtmosSource(id: "HR", name: "Height R",    icon: "arrow.up.circle", angle: 50,  distance: 1.5, elevation: 75, gain: 0.9, isMuted: false),
            ]
        case "Studio 5.1":
            atmosSources = [
                AtmosSource(id: "FL", name: "Front Left",  icon: "speaker.wave.2", angle: -30, distance: 1.8, elevation: 0,  gain: 1.0, isMuted: false),
                AtmosSource(id: "C",  name: "Center",      icon: "speaker.wave.1", angle: 0,   distance: 1.8, elevation: 0,  gain: 1.0, isMuted: false),
                AtmosSource(id: "FR", name: "Front Right", icon: "speaker.wave.2", angle: 30,  distance: 1.8, elevation: 0,  gain: 1.0, isMuted: false),
                AtmosSource(id: "SL", name: "Surround L",  icon: "speaker.wave.2", angle: -110, distance: 1.8, elevation: 0,  gain: 1.0, isMuted: false),
                AtmosSource(id: "SR", name: "Surround R",  icon: "speaker.wave.2", angle: 110,  distance: 1.8, elevation: 0,  gain: 1.0, isMuted: false),
            ]
        case "Concert Hall":
            atmosSources = [
                AtmosSource(id: "FL", name: "Front Left",  icon: "speaker.wave.2", angle: -60, distance: 4.0, elevation: 10, gain: 1.1, isMuted: false),
                AtmosSource(id: "C",  name: "Center",      icon: "speaker.wave.1", angle: 0,   distance: 4.0, elevation: 10, gain: 1.0, isMuted: false),
                AtmosSource(id: "FR", name: "Front Right", icon: "speaker.wave.2", angle: 60,  distance: 4.0, elevation: 10, gain: 1.1, isMuted: false),
                AtmosSource(id: "SL", name: "Surround L",  icon: "speaker.wave.2", angle: -120, distance: 3.5, elevation: 30, gain: 1.0, isMuted: false),
                AtmosSource(id: "SR", name: "Surround R",  icon: "speaker.wave.2", angle: 120,  distance: 3.5, elevation: 30, gain: 1.0, isMuted: false),
                AtmosSource(id: "HL", name: "Height L",    icon: "arrow.up.circle", angle: -45, distance: 5.0, elevation: 80, gain: 1.0, isMuted: false),
                AtmosSource(id: "HR", name: "Height R",    icon: "arrow.up.circle", angle: 45,  distance: 5.0, elevation: 80, gain: 1.0, isMuted: false),
            ]
        default:
            break
        }
    }
    
    @Published public var syncDelayMs: Double = 0.0 {
        didSet {
            RealAudioEngine.shared.updateSyncDelay(ms: isSyncCompensationEnabled ? syncDelayMs : 0.0)
            saveState()
        }
    }
    @Published public var isSyncCompensationEnabled: Bool = false {
        didSet {
            RealAudioEngine.shared.updateSyncDelay(ms: isSyncCompensationEnabled ? syncDelayMs : 0.0)
            saveState()
        }
    }
    
    public var isAntiClip: Bool {
        get { isAntiClippingEnabled }
        set { isAntiClippingEnabled = newValue }
    }
    
    public var isSpatial: Bool {
        get { isSpatialEnhancerEnabled }
        set { isSpatialEnhancerEnabled = newValue }
    }
    
    public var isBassPunch: Bool {
        get { isBassPunchEnabled }
        set { isBassPunchEnabled = newValue }
    }
    
    public var isVocalBoost: Bool {
        get { isVocalBoostEnabled }
        set { isVocalBoostEnabled = newValue }
    }
    
    public var eqGains: [Double] {
        return bands.map { $0.gain }
    }
    
    public func setGain(index: Int, gain: Double) {
        updateBand(index: index, gain: gain)
    }
    
    @Published public var liveLeftLevel: Float = 0.0
    @Published public var liveRightLevel: Float = 0.0
    @Published public var liveSpectrum: [Float] = Array(repeating: 0.1, count: 12)
    @Published public var isLimiterEngaged: Bool = false
    
    private var visualizerTimer: Timer?
    
    public init() {
        var initialBands: [EQBand] = []
        for (i, freq) in EQPreset.standardBands.enumerated() {
            initialBands.append(
                EQBand(id: i, frequency: freq, label: EQPreset.standardLabels[i], gain: 0.0)
            )
        }
        self.bands = initialBands
        
        loadState()
        startVisualizerSimulation()
        
        RealAudioEngine.shared.updateBands(gains: bands.map { $0.gain })
        RealAudioEngine.shared.updateBoost(multiplier: boostMultiplier)
    }
    
    deinit {
        visualizerTimer?.invalidate()
    }
    
    public var boostPercentage: Int {
        Int(round(boostMultiplier * 100))
    }
    
    public var isOverdrive: Bool {
        boostMultiplier > 1.0
    }
    
    public func applyPreset(_ preset: EQPreset) {
        selectedPreset = preset
        for i in 0..<min(bands.count, preset.gains.count) {
            bands[i].gain = preset.gains[i]
        }
        RealAudioEngine.shared.updateBands(gains: bands.map { $0.gain })
    }
    
    public func updateBand(index: Int, gain: Double) {
        guard index >= 0 && index < bands.count else { return }
        bands[index].gain = max(-24.0, min(24.0, gain))
        RealAudioEngine.shared.updateBands(gains: bands.map { $0.gain })
        
        if selectedPreset.name != "Custom" {
            let isMatching = bands.enumerated().allSatisfy { (idx, band) in
                idx < selectedPreset.gains.count && abs(band.gain - selectedPreset.gains[idx]) < 0.1
            }
            if !isMatching {
                selectedPreset = EQPreset(
                    name: "Custom",
                    icon: "slider.vertical.3",
                    description: "User customized EQ curve",
                    gains: bands.map { $0.gain },
                    isCustom: true
                )
            }
        }
    }
    
    public func resetEQ() {
        applyPreset(EQPreset.presets[0])
    }
    
    public func saveCurrentAsCustomPreset(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let newPreset = EQPreset(
            name: trimmed,
            icon: "slider.horizontal.3",
            description: "Custom user preset",
            gains: bands.map { $0.gain },
            isCustom: true
        )
        customPresets.removeAll { $0.name == trimmed }
        customPresets.append(newPreset)
        selectedPreset = newPreset
    }
    
    public func deleteCustomPreset(_ preset: EQPreset) {
        customPresets.removeAll { $0.name == preset.name }
        if selectedPreset.name == preset.name {
            resetEQ()
        }
    }
    
    private func startVisualizerSimulation() {
        visualizerTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.updateLiveVisualizer()
        }
    }
    
    private func updateLiveVisualizer() {
        let (rawL, rawR, spec) = RealAudioEngine.shared.dspProcessor.getLiveMeters()
        
        let boost = Float(self.boostMultiplier)
        let left = min(1.0, rawL * boost)
        let right = min(1.0, rawR * boost)
        
        self.liveLeftLevel = left
        self.liveRightLevel = right
        self.liveSpectrum = spec
        self.isLimiterEngaged = (left > 0.95 || right > 0.95) && boost > 1.2
    }
    
    private func saveState() {
        UserDefaults.standard.set(boostMultiplier, forKey: "Aura_BoostMultiplier")
        UserDefaults.standard.set(isEQEnabled, forKey: "Aura_IsEQEnabled")
        UserDefaults.standard.set(isAntiClippingEnabled, forKey: "Aura_IsAntiClip")
        UserDefaults.standard.set(isSpatialEnhancerEnabled, forKey: "Aura_IsSpatial")
        UserDefaults.standard.set(isBassPunchEnabled, forKey: "Aura_IsBassPunch")
        UserDefaults.standard.set(isVocalBoostEnabled, forKey: "Aura_IsVocalBoost")
        UserDefaults.standard.set(isAtmosEnabled, forKey: "Aura_IsAtmos")
        UserDefaults.standard.set(atmosMode, forKey: "Aura_AtmosMode")
        UserDefaults.standard.set(atmosRoomSize, forKey: "Aura_AtmosRoomSize")
        UserDefaults.standard.set(atmosSurroundWidth, forKey: "Aura_AtmosSurroundWidth")
        UserDefaults.standard.set(atmosElevation, forKey: "Aura_AtmosElevation")
        UserDefaults.standard.set(atmosBassExciter, forKey: "Aura_AtmosBassExciter")
        UserDefaults.standard.set(syncDelayMs, forKey: "Aura_SyncDelayMs")
        UserDefaults.standard.set(isSyncCompensationEnabled, forKey: "Aura_IsSyncComp")
        
        if let data = try? JSONEncoder().encode(bands) {
            UserDefaults.standard.set(data, forKey: "Aura_EQBands")
        }
        if let pData = try? JSONEncoder().encode(selectedPreset) {
            UserDefaults.standard.set(pData, forKey: "Aura_SelectedPreset")
        }
    }
    
    private func saveCustomPresets() {
        if let data = try? JSONEncoder().encode(customPresets) {
            UserDefaults.standard.set(data, forKey: "Aura_CustomPresets")
        }
    }
    
    private func loadState() {
        if let b = UserDefaults.standard.object(forKey: "Aura_BoostMultiplier") as? Double {
            self.boostMultiplier = b
        }
        if let eq = UserDefaults.standard.object(forKey: "Aura_IsEQEnabled") as? Bool {
            self.isEQEnabled = eq
        }
        self.isAntiClippingEnabled = UserDefaults.standard.bool(forKey: "Aura_IsAntiClip")
        self.isSpatialEnhancerEnabled = UserDefaults.standard.bool(forKey: "Aura_IsSpatial")
        self.isBassPunchEnabled = UserDefaults.standard.bool(forKey: "Aura_IsBassPunch")
        self.isVocalBoostEnabled = UserDefaults.standard.bool(forKey: "Aura_IsVocalBoost")
        
        if let at = UserDefaults.standard.object(forKey: "Aura_IsAtmos") as? Bool {
            self.isAtmosEnabled = at
        } else {
            self.isAtmosEnabled = true
        }
        if let d = UserDefaults.standard.object(forKey: "Aura_SyncDelayMs") as? Double {
            self.syncDelayMs = d
        }
        if let syncComp = UserDefaults.standard.object(forKey: "Aura_IsSyncComp") as? Bool {
            self.isSyncCompensationEnabled = syncComp
        }
        if let m = UserDefaults.standard.string(forKey: "Aura_AtmosMode") {
            self.atmosMode = m
        }
        if let r = UserDefaults.standard.object(forKey: "Aura_AtmosRoomSize") as? Double {
            self.atmosRoomSize = r
        }
        if let w = UserDefaults.standard.object(forKey: "Aura_AtmosSurroundWidth") as? Double {
            self.atmosSurroundWidth = w
        }
        if let e = UserDefaults.standard.object(forKey: "Aura_AtmosElevation") as? Double {
            self.atmosElevation = e
        }
        if let s = UserDefaults.standard.object(forKey: "Aura_AtmosBassExciter") as? Double {
            self.atmosBassExciter = s
        }
        
        if let data = UserDefaults.standard.data(forKey: "Aura_EQBands"),
           let savedBands = try? JSONDecoder().decode([EQBand].self, from: data),
           savedBands.count == 10 {
            self.bands = savedBands
        }
        
        if let pData = UserDefaults.standard.data(forKey: "Aura_CustomPresets"),
           let savedPresets = try? JSONDecoder().decode([EQPreset].self, from: pData) {
            self.customPresets = savedPresets
        }
        
        if let selData = UserDefaults.standard.data(forKey: "Aura_SelectedPreset"),
           let selPreset = try? JSONDecoder().decode(EQPreset.self, from: selData) {
            if selPreset.name.contains("Room Calibrated") || selPreset.name.contains("АЧХ") {
                self.selectedPreset = EQPreset.presets[0]
                for i in 0..<bands.count { bands[i].gain = 0.0 }
            } else {
                self.selectedPreset = selPreset
            }
        }
    }
}
