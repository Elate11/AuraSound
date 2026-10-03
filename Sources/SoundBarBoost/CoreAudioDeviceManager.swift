import Foundation
import CoreAudio
import AudioToolbox
import Combine

public struct AudioDevice: Identifiable, Hashable {
    public let id: AudioObjectID
    public let name: String
    public let uid: String
    public let transportType: UInt32
    public var isDefault: Bool
    public var volume: Float
    public var isMuted: Bool
    
    public var iconName: String {
        let lower = name.lowercased()
        if lower.contains("airpods max") {
            return "airpodsmax"
        } else if lower.contains("airpods pro") {
            return "airpodspro"
        } else if lower.contains("airpods") {
            return "airpods"
        } else if lower.contains("beats") {
            return "beats.headphones"
        } else if lower.contains("headphone") || lower.contains("headset") {
            return "headphones"
        } else if lower.contains("studio display") || lower.contains("display") || lower.contains("hdmi") {
            return "display"
        } else if lower.contains("macbook") || lower.contains("internal") || lower.contains("speaker") || lower.contains("built-in") || lower.contains("динамики") {
            return "laptopcomputer"
        } else if transportType == kAudioDeviceTransportTypeBluetooth || transportType == kAudioDeviceTransportTypeBluetoothLE {
            return "wave.3.forward.circle.fill"
        } else if transportType == kAudioDeviceTransportTypeAirPlay {
            return "airplayaudio"
        } else if transportType == kAudioDeviceTransportTypeUSB {
            return "cable.connector"
        }
        return "speaker.wave.2.fill"
    }
    
    public var typeDescription: String {
        switch transportType {
        case kAudioDeviceTransportTypeBuiltIn:
            return "Built-in Speaker"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return "Bluetooth Audio"
        case kAudioDeviceTransportTypeAirPlay:
            return "AirPlay"
        case kAudioDeviceTransportTypeUSB:
            return "USB Audio"
        case kAudioDeviceTransportTypeDisplayPort, kAudioDeviceTransportTypeHDMI:
            return "Display / HDMI"
        default:
            return "Audio Output"
        }
    }
    
    public var shortName: String {
        let lower = name.lowercased()
        if lower.contains("macbook") || lower.contains("динамики") {
            return "MacBook"
        } else if lower.contains("rockbox") {
            return "Rockbox"
        } else if lower.contains("airpods") {
            return "AirPods"
        } else if lower.contains("monitor") || lower.contains("display") {
            return "Monitor"
        } else {
            let words = name.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            return words.prefix(2).joined(separator: " ")
        }
    }
}

public class AudioDeviceManager: ObservableObject {
    public static let shared = AudioDeviceManager()
    
    @Published public var outputDevices: [AudioDevice] = []
    @Published public var selectedDeviceIDs: Set<AudioObjectID> = []
    @Published public var masterVolume: Float = 0.85
    @Published public var deviceVolumes: [AudioObjectID: Float] = [:]
    
    // Physical Output Device Spatial Positions on Minimap
    @Published public var devicePositions: [AudioObjectID: (angle: Double, distance: Double)] = [:]
    @Published public var selectedSpatialDeviceID: AudioObjectID = 0
    @Published public var isMuted: Bool = false
    
    public init() {
        refreshDevices()
        setupListeners()
    }
    
    public var primaryDevice: AudioDevice? {
        if let firstID = selectedDeviceIDs.first {
            return outputDevices.first(where: { $0.id == firstID })
        }
        return outputDevices.first
    }
    
    public var currentDevice: AudioDevice? {
        return primaryDevice
    }
    
    public func refreshDevices() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        guard status == noErr else { return }
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = [AudioObjectID](repeating: 0, count: deviceCount)
        
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        guard status == noErr else { return }
        
        let defaultOutputID = getDefaultOutputDeviceID()
        var devices: [AudioDevice] = []
        
        for devID in deviceIDs {
            if hasOutputStreams(deviceID: devID) {
                let name = getDeviceName(deviceID: devID)
                if name.contains("BlackHole") {
                    continue
                }
                
                let transport = getDeviceTransportType(deviceID: devID)
                let lowerName = name.lowercased()
                
                // Exclude HDMI, DisplayPort, and Monitor display audio
                if transport == kAudioDeviceTransportTypeHDMI ||
                   transport == kAudioDeviceTransportTypeDisplayPort ||
                   lowerName.contains("hdmi") ||
                   lowerName.contains("displayport") ||
                   lowerName.contains("monitor") {
                    continue
                }
                
                let uid = getDeviceUID(deviceID: devID)
                let vol = getDeviceVolume(deviceID: devID)
                let muted = getDeviceIsMuted(deviceID: devID)
                let isDef = (devID == defaultOutputID)
                
                let dev = AudioDevice(
                    id: devID,
                    name: name,
                    uid: uid,
                    transportType: transport,
                    isDefault: isDef,
                    volume: vol,
                    isMuted: muted
                )
                devices.append(dev)
            }
        }
        
        DispatchQueue.main.async {
            self.outputDevices = devices
            
            // Clean up any previously selected HDMI / monitor devices
            let validIDs = Set(devices.map { $0.id })
            self.selectedDeviceIDs = self.selectedDeviceIDs.intersection(validIDs)
            
            // Auto-select Rockbox Bluetooth Speaker + MacBook Internal Speakers
            if self.selectedDeviceIDs.isEmpty {
                var initialIDs: Set<AudioObjectID> = []
                if let bt = devices.first(where: { $0.transportType == kAudioDeviceTransportTypeBluetooth || $0.name.lowercased().contains("rockbox") }) {
                    initialIDs.insert(bt.id)
                }
                if let internalSpk = devices.first(where: { $0.transportType == kAudioDeviceTransportTypeBuiltIn || $0.name.lowercased().contains("динамики") || $0.name.lowercased().contains("macbook") }) {
                    initialIDs.insert(internalSpk.id)
                } else if let first = devices.first {
                    initialIDs.insert(first.id)
                }
                self.selectedDeviceIDs = initialIDs
            }
            
            self.autoEstimateSyncDelay()
            self.setupVolumeSyncListeners()
            
            // Auto start audio routing pipeline as soon as devices are populated
            if !RealAudioEngine.shared.isRoutingActive && !self.selectedDeviceIDs.isEmpty {
                _ = RealAudioEngine.shared.startRouting(toOutputDeviceIDs: self.selectedDeviceIDs)
            }
        }
    }
    
    public func autoEstimateSyncDelay() {
        let hasBT = selectedDeviceIDs.contains { RealAudioEngine.shared.isBluetoothDevice(deviceID: $0) }
        guard hasBT && selectedDeviceIDs.count > 1 else { return }
        
        for devID in selectedDeviceIDs {
            if RealAudioEngine.shared.isBluetoothDevice(deviceID: devID) {
                let name = getDeviceName(deviceID: devID).lowercased()
                let hw = RealAudioEngine.shared.getDeviceHardwareLatency(deviceID: devID)
                
                var estimatedMs = max(180.0, hw.totalMs + 140.0) // CoreAudio transport + DSP hardware buffer
                if name.contains("rockbox") {
                    estimatedMs = 320.0
                } else if name.contains("airpods") {
                    estimatedMs = 160.0
                }
                
                if AcousticAutoCalibrator.shared.measuredDelayMs == nil {
                    AudioDSPManager.shared.syncDelayMs = estimatedMs
                    RealAudioEngine.shared.updateSyncDelay(ms: estimatedMs)
                }
                break
            }
        }
    }
    
    private var isUpdatingVolumeInternally: Bool = false
    
    private func setupListeners() {
        var defaultDevAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultDevAddress,
            DispatchQueue.main
        ) { [weak self] _, _ in
            self?.refreshDevices()
        }
        
        setupBlackHoleVolumeListener()
    }
    
    private var registeredVolumeListenerDeviceIDs: Set<AudioObjectID> = []
    
    public func setupBlackHoleVolumeListener() {
        setupVolumeSyncListeners()
    }
    
    public func setupVolumeSyncListeners() {
        // Listen ONLY on BlackHole 2ch so keyboard volume keys adjust exclusively the Master Volume
        if let bhID = RealAudioEngine.shared.findInputDevice(nameSubstring: "BlackHole") {
            registerVolumeListener(for: bhID, syncToBlackHole: false)
        }
    }
    
    private func registerVolumeListener(for deviceID: AudioObjectID, syncToBlackHole: Bool) {
        guard !registeredVolumeListenerDeviceIDs.contains(deviceID) else { return }
        registeredVolumeListenerDeviceIDs.insert(deviceID)
        
        var volAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectAddPropertyListenerBlock(deviceID, &volAddress, DispatchQueue.main) { [weak self] _, _ in
            guard let self = self, !self.isUpdatingVolumeInternally else { return }
            let currentVol = self.getDeviceVolume(deviceID: deviceID)
            self.setVolume(currentVol, syncToBlackHole: syncToBlackHole)
        }
    }
    
    public func toggleDeviceSelection(_ device: AudioDevice) {
        if selectedDeviceIDs.contains(device.id) {
            // Keep at least one device selected
            if selectedDeviceIDs.count > 1 {
                selectedDeviceIDs.remove(device.id)
            }
        } else {
            selectedDeviceIDs.insert(device.id)
        }
        
        autoEstimateSyncDelay()
        
        // Update live Multi-Output routing immediately
        if RealAudioEngine.shared.isRoutingActive {
            _ = RealAudioEngine.shared.startRouting(toOutputDeviceIDs: selectedDeviceIDs)
        }
    }
    
    public func selectSingleDevice(_ device: AudioDevice) {
        selectedDeviceIDs = [device.id]
        if RealAudioEngine.shared.isRoutingActive {
            _ = RealAudioEngine.shared.startRouting(toOutputDeviceIDs: selectedDeviceIDs)
        }
    }
    
    public func getVolumeForDevice(_ id: AudioObjectID) -> Float {
        if let v = deviceVolumes[id] {
            return v
        }
        let sysVol = getDeviceVolume(deviceID: id)
        let fallback = sysVol > 0 ? sysVol : masterVolume
        deviceVolumes[id] = fallback
        return fallback
    }
    
    public func setVolumeForDevice(_ id: AudioObjectID, volume: Float) {
        let clamped = max(0.0, min(1.0, volume))
        deviceVolumes[id] = clamped
        setDeviceVolume(deviceID: id, volume: clamped)
        RealAudioEngine.shared.setSinkVolume(deviceID: id, volume: clamped)
    }
    
    public func setVolume(_ volume: Float, syncToBlackHole: Bool = true) {
        let clamped = max(0.0, min(1.0, volume))
        masterVolume = clamped
        isUpdatingVolumeInternally = true
        defer { isUpdatingVolumeInternally = false }
        
        // Update BlackHole 2ch so system menu bar / OSD matches masterVolume
        if syncToBlackHole, let bhID = RealAudioEngine.shared.findInputDevice(nameSubstring: "BlackHole") {
            setDeviceVolume(deviceID: bhID, volume: clamped)
        }
    }
    
    // MARK: - Physical Device Spatial Positioning & Soundstage
    public func getSpatialPosition(for deviceID: AudioObjectID) -> (angle: Double, distance: Double) {
        if let pos = devicePositions[deviceID] {
            return pos
        }
        let dev = outputDevices.first { $0.id == deviceID }
        let name = dev?.name.lowercased() ?? ""
        let isBuiltIn = dev?.transportType == kAudioDeviceTransportTypeBuiltIn || name.contains("macbook") || name.contains("динамики")
        let isBT = dev?.transportType == kAudioDeviceTransportTypeBluetooth || name.contains("rockbox")
        
        let defaultPos: (angle: Double, distance: Double)
        if isBuiltIn {
            defaultPos = (angle: 0.0, distance: 1.0) // Front Center
        } else if isBT {
            defaultPos = (angle: 60.0, distance: 2.2) // Front Right
        } else {
            defaultPos = (angle: -60.0, distance: 2.0) // Front Left
        }
        devicePositions[deviceID] = defaultPos
        return defaultPos
    }
    
    public func setSpatialPosition(for deviceID: AudioObjectID, angle: Double, distance: Double) {
        let clampedDist = max(0.5, min(5.0, distance))
        let clampedAngle = max(-180.0, min(180.0, angle))
        devicePositions[deviceID] = (angle: clampedAngle, distance: clampedDist)
    }
    
    public func getSpatialPan(for deviceID: AudioObjectID) -> (panL: Float, panR: Float) {
        let pos = getSpatialPosition(for: deviceID)
        let rad = Float(pos.angle * .pi / 180.0)
        let pan = (sin(rad) + 1.0) * 0.5 // 0.0 (Left) to 1.0 (Right)
        
        // Panning curve preserving stereo energy
        let panL = Float(1.0 - max(0.0, (pan - 0.5) * 1.4))
        let panR = Float(1.0 - max(0.0, (0.5 - pan) * 1.4))
        return (panL: max(0.2, min(1.0, panL)), panR: max(0.2, min(1.0, panR)))
    }
    
    private func setDeviceVolume(deviceID: AudioObjectID, volume: Float) {
        var vol = volume
        for channel: UInt32 in [kAudioObjectPropertyElementMain, 0, 1, 2] {
            var chanAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: channel
            )
            if AudioObjectHasProperty(deviceID, &chanAddress) {
                let size = UInt32(MemoryLayout<Float32>.size)
                AudioObjectSetPropertyData(deviceID, &chanAddress, 0, nil, size, &vol)
            }
        }
    }
    
    public func setMute(_ mute: Bool) {
        isMuted = mute
        var muteVal: UInt32 = mute ? 1 : 0
        for devID in selectedDeviceIDs {
            var propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            if AudioObjectHasProperty(devID, &propertyAddress) {
                let size = UInt32(MemoryLayout<UInt32>.size)
                AudioObjectSetPropertyData(devID, &propertyAddress, 0, nil, size, &muteVal)
            }
        }
    }
    
    private func getDefaultOutputDeviceID() -> AudioObjectID {
        var defaultID = AudioObjectID(0)
        var propertySize = UInt32(MemoryLayout<AudioObjectID>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &defaultID
        )
        return defaultID
    }
    
    private func hasOutputStreams(deviceID: AudioObjectID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        return (status == noErr && dataSize > 0)
    }
    
    private func getDeviceName(deviceID: AudioObjectID) -> String {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var unmanagedCFString: Unmanaged<CFString>? = nil
        var propertySize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &unmanagedCFString)
        if status == noErr, let cf = unmanagedCFString {
            return cf.takeRetainedValue() as String
        }
        return "Audio Output (\(deviceID))"
    }
    
    private func getDeviceUID(deviceID: AudioObjectID) -> String {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var unmanagedCFString: Unmanaged<CFString>? = nil
        var propertySize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &unmanagedCFString)
        if status == noErr, let cf = unmanagedCFString {
            return cf.takeRetainedValue() as String
        }
        return "\(deviceID)"
    }
    
    private func getDeviceTransportType(deviceID: AudioObjectID) -> UInt32 {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &transport)
        if status == noErr {
            return transport
        }
        return 0
    }
    
    private func getDeviceVolume(deviceID: AudioObjectID) -> Float {
        for channel: UInt32 in [kAudioObjectPropertyElementMain, 0, 1, 2] {
            var propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: channel
            )
            var volume: Float32 = 0.5
            var propertySize = UInt32(MemoryLayout<Float32>.size)
            let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &volume)
            if status == noErr {
                return volume
            }
        }
        return 0.85
    }
    
    private func getDeviceIsMuted(deviceID: AudioObjectID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var isMuted: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &isMuted)
        if status == noErr {
            return isMuted != 0
        }
        return false
    }
}
