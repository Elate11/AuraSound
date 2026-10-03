import Foundation
import SwiftUI
import AppKit
import Accelerate
import UniformTypeIdentifiers

public class ViperDSPManager: ObservableObject {
    public static let shared = ViperDSPManager()
    
    // MARK: - Master & Module Switches
    @Published public var isViperEnabled: Bool = false
    @Published public var isConvolverEnabled: Bool = false
    @Published public var isViperBassEnabled: Bool = false
    @Published public var isViperClarityEnabled: Bool = false
    @Published public var isTubeSimulatorEnabled: Bool = false
    
    // MARK: - Active File Names
    @Published public var loadedPresetName: String = "NONE"
    @Published public var loadedKernelName: String = "NONE"
    
    // MARK: - Adjustable Parameters
    @Published public var convolverWet: Float = 0.85
    @Published public var viperBassGain: Float = 6.0 // dB (0 to 14)
    @Published public var viperBassFreq: Float = 80.0 // Hz (40, 60, 80, 100)
    @Published public var viperClarityGain: Float = 4.0 // dB (0 to 12)
    @Published public var statusMessage: String = "VIPER4ANDROID READY"
    
    // MARK: - Convolver IRS Impulse Response Kernel (Lock-free realtime audio access)
    public var kernelL: [Float] = []
    public var kernelR: [Float] = []
    public var kernelRevL: [Float] = []
    public var kernelRevR: [Float] = []
    public var kernelLength: Int = 0
    private let kernelLock = NSLock()
    
    public init() {
        createDefaultDirectories()
    }
    
    public func createDefaultDirectories() {
        let musicDir = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first!
        let viperDir = musicDir.appendingPathComponent("AuraSound/ViPER")
        try? FileManager.default.createDirectory(at: viperDir, withIntermediateDirectories: true)
    }
    
    // MARK: - File Dialogs (NSOpenPanel)
    public func openPresetFileDialog() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let panel = NSOpenPanel()
            panel.title = "SELECT VIPER4ANDROID / JAMESDSP PRESET"
            panel.prompt = "LOAD PRESET"
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            var types: [UTType] = [.xml, .json, .plainText]
            if let customXml = UTType(filenameExtension: "xml") { types.append(customXml) }
            panel.allowedContentTypes = types
            
            if panel.runModal() == .OK, let url = panel.url {
                self.loadPresetFile(url: url)
            }
        }
    }
    
    public func openKernelFileDialog() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let panel = NSOpenPanel()
            panel.title = "SELECT CONVOLVER KERNEL (.IRS / .WAV)"
            panel.prompt = "LOAD KERNEL"
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            var types: [UTType] = [.wav, .audio]
            if let irsType = UTType(filenameExtension: "irs") { types.append(irsType) }
            if let binType = UTType(filenameExtension: "bin") { types.append(binType) }
            panel.allowedContentTypes = types
            
            if panel.runModal() == .OK, let url = panel.url {
                self.loadKernelFile(url: url)
            }
        }
    }
    
    // MARK: - Load Convolver Kernel (.IRS / .WAV)
    public func loadKernelFile(url: URL) {
        guard let data = try? Data(contentsOf: url) else {
            statusMessage = "ERROR: CANNOT READ KERNEL FILE"
            return
        }
        
        guard let parsed = parseRIFF(data: data) else {
            statusMessage = "ERROR: INVALID IRS/WAV RIFF FORMAT"
            return
        }
        
        // Truncate to maximum 1024 samples for real-time low-latency performance
        let maxLen = 1024
        let len = min(maxLen, parsed.left.count)
        guard len > 16 else {
            statusMessage = "ERROR: KERNEL TOO SHORT"
            return
        }
        
        var kL = Array(parsed.left.prefix(len))
        var kR = Array(parsed.right.prefix(len))
        
        // Apply smooth 32-sample fade out at end
        let fadeLen = min(32, len / 4)
        for i in 0..<fadeLen {
            let fade = 0.5 * (1.0 + cos(Double.pi * Double(i) / Double(fadeLen)))
            kL[len - fadeLen + i] *= Float(fade)
            kR[len - fadeLen + i] *= Float(fade)
        }
        
        // Peak normalization
        var maxVal: Float = 0.0001
        for s in kL { if abs(s) > maxVal { maxVal = abs(s) } }
        for s in kR { if abs(s) > maxVal { maxVal = abs(s) } }
        let norm: Float = 0.95 / maxVal
        for i in 0..<len {
            kL[i] *= norm
            kR[i] *= norm
        }
        
        kernelLock.lock()
        self.kernelL = kL
        self.kernelR = kR
        self.kernelRevL = Array(kL.reversed())
        self.kernelRevR = Array(kR.reversed())
        self.kernelLength = len
        kernelLock.unlock()
        
        DispatchQueue.main.async {
            self.loadedKernelName = url.lastPathComponent.uppercased()
            self.isConvolverEnabled = true
            self.isViperEnabled = true
            self.statusMessage = "LOADED KERNEL: \(self.loadedKernelName) (\(len) SAMPLES)"
        }
    }
    
    // MARK: - Native RIFF WAV/IRS Parser
    private func parseRIFF(data: Data) -> (left: [Float], right: [Float], sampleRate: Int)? {
        guard data.count > 44 else { return nil }
        
        let riff = String(data: data.subdata(in: 0..<4), encoding: .ascii)
        let wave = String(data: data.subdata(in: 8..<12), encoding: .ascii)
        guard riff == "RIFF", wave == "WAVE" else { return nil }
        
        var offset = 12
        var channels = 1
        var sampleRate = 48000
        var bitsPerSample = 16
        var format = 1 // 1 = PCM, 3 = IEEE Float
        var dataOffset = 0
        var dataSize = 0
        
        while offset + 8 <= data.count {
            let chunkID = String(data: data.subdata(in: offset..<offset+4), encoding: .ascii) ?? ""
            let chunkSize = Int(data.subdata(in: offset+4..<offset+8).withUnsafeBytes { $0.load(as: UInt32.self) })
            offset += 8
            
            if chunkID == "fmt " && chunkSize >= 16 {
                let fmtData = data.subdata(in: offset..<offset+chunkSize)
                format = Int(fmtData.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt16.self) })
                channels = Int(fmtData.withUnsafeBytes { $0.load(fromByteOffset: 2, as: UInt16.self) })
                sampleRate = Int(fmtData.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) })
                bitsPerSample = Int(fmtData.withUnsafeBytes { $0.load(fromByteOffset: 14, as: UInt16.self) })
            } else if chunkID == "data" {
                dataOffset = offset
                dataSize = min(chunkSize, data.count - offset)
                break
            }
            offset += chunkSize
        }
        
        guard dataOffset > 0, dataSize > 0 else { return nil }
        let rawAudio = data.subdata(in: dataOffset..<dataOffset+dataSize)
        
        var left: [Float] = []
        var right: [Float] = []
        
        if format == 1 && bitsPerSample == 16 {
            let sampleCount = dataSize / (2 * channels)
            rawAudio.withUnsafeBytes { ptr in
                let int16Ptr = ptr.bindMemory(to: Int16.self)
                for i in 0..<sampleCount {
                    let l = Float(int16Ptr[i * channels]) / 32768.0
                    left.append(l)
                    if channels >= 2 {
                        let r = Float(int16Ptr[i * channels + 1]) / 32768.0
                        right.append(r)
                    } else {
                        right.append(l)
                    }
                }
            }
        } else if format == 1 && bitsPerSample == 24 {
            let sampleCount = dataSize / (3 * channels)
            rawAudio.withUnsafeBytes { ptr in
                let u8 = ptr.bindMemory(to: UInt8.self)
                for i in 0..<sampleCount {
                    let idx = i * channels * 3
                    let b0 = Int32(u8[idx])
                    let b1 = Int32(u8[idx + 1]) << 8
                    let b2 = Int32(Int8(bitPattern: u8[idx + 2])) << 16
                    let val = Float(b0 | b1 | b2) / 8388608.0
                    left.append(val)
                    if channels >= 2 {
                        let r0 = Int32(u8[idx + 3])
                        let r1 = Int32(u8[idx + 4]) << 8
                        let r2 = Int32(Int8(bitPattern: u8[idx + 5])) << 16
                        right.append(Float(r0 | r1 | r2) / 8388608.0)
                    } else {
                        right.append(val)
                    }
                }
            }
        } else if format == 3 && bitsPerSample == 32 {
            let sampleCount = dataSize / (4 * channels)
            rawAudio.withUnsafeBytes { ptr in
                let fPtr = ptr.bindMemory(to: Float.self)
                for i in 0..<sampleCount {
                    let l = fPtr[i * channels]
                    left.append(l)
                    if channels >= 2 {
                        right.append(fPtr[i * channels + 1])
                    } else {
                        right.append(l)
                    }
                }
            }
        } else {
            return nil
        }
        
        return (left, right, sampleRate)
    }
    
    // MARK: - Load ViPER Preset (.XML / .JSON)
    public func loadPresetFile(url: URL) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            statusMessage = "ERROR: CANNOT READ PRESET"
            return
        }
        
        let ext = url.pathExtension.lowercased()
        var eqGains: [Float]? = nil
        var bassOn = false
        var bassGainVal: Float = 6.0
        var bassFreqVal: Float = 80.0
        var clarityOn = false
        var clarityGainVal: Float = 4.0
        var kernelRef: String? = nil
        
        if ext == "json" {
            // Grouped or Flat JSON parsing
            if let data = content.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                
                // 1. Equalizer bands
                if let eqObj = json["equalizer"] as? [String: Any],
                   let bands = eqObj["bands"] as? [Double] {
                    eqGains = bands.map { Float($0) }
                } else if let bands = json["eqBands"] as? [Double] {
                    eqGains = bands.map { Float($0) }
                }
                
                // 2. Bass
                if let bassObj = json["bass"] as? [String: Any] {
                    bassOn = (bassObj["enable"] as? Bool) ?? true
                    if let f = bassObj["frequency"] as? Double { bassFreqVal = Float(f) }
                    if let g = bassObj["gain"] as? Double { bassGainVal = Float(g) }
                } else if let bOn = json["bassEnabled"] as? Bool {
                    bassOn = bOn
                    if let f = json["bassFrequency"] as? Double { bassFreqVal = Float(f) }
                    if let g = json["bassGain"] as? Double { bassGainVal = Float(g) }
                }
                
                // 3. Clarity
                if let clarObj = json["clarity"] as? [String: Any] {
                    clarityOn = (clarObj["enable"] as? Bool) ?? true
                    if let g = clarObj["gain"] as? Double { clarityGainVal = Float(g) }
                } else if let cOn = json["clarityEnabled"] as? Bool {
                    clarityOn = cOn
                    if let g = json["clarityGain"] as? Double { clarityGainVal = Float(g) }
                }
                
                // 4. Convolver
                if let convObj = json["convolver"] as? [String: Any] {
                    kernelRef = convObj["kernelFile"] as? String
                } else if let k = json["convolverKernel"] as? String {
                    kernelRef = k
                }
            }
        } else {
            // XML Preset parsing (Legacy or 2.7+)
            let lines = content.components(separatedBy: .newlines)
            for line in lines {
                // EQ bands: <string name="...fireq.custom"> or <string name="65552">
                if line.contains("fireq.custom") || line.contains("65552") {
                    if let start = line.range(of: ">"), let end = line.range(of: "</") {
                        let bandStr = String(line[start.upperBound..<end.lowerBound])
                        let parts = bandStr.split(separator: ";")
                        eqGains = parts.compactMap { Float($0.trimmingCharacters(in: .whitespaces)) }
                    }
                }
                
                // Bass
                if line.contains("bass.enable") || line.contains("65574") {
                    if line.contains("true") { bassOn = true }
                }
                if line.contains("bass.freq") || line.contains("65576") {
                    if let v = extractNumber(from: line) { bassFreqVal = v }
                }
                if line.contains("bass.gain") || line.contains("65577") {
                    if let v = extractNumber(from: line) { bassGainVal = max(0, min(14, v * 0.05)) }
                }
                
                // Clarity
                if line.contains("clarity.enable") || line.contains("65578") {
                    if line.contains("true") { clarityOn = true }
                }
                if line.contains("clarity.gain") || line.contains("65580") {
                    if let v = extractNumber(from: line) { clarityGainVal = max(0, min(12, v * 0.05)) }
                }
                
                // Convolver Kernel
                if line.contains("convolver.kernel") || line.contains("65540") {
                    if let start = line.range(of: ">"), let end = line.range(of: "</") {
                        kernelRef = String(line[start.upperBound..<end.lowerBound])
                    }
                }
            }
        }
        
        // Apply EQ bands to Graphic Equalizer
        if let gains = eqGains, gains.count >= 10 {
            for i in 0..<min(10, gains.count) {
                AudioDSPManager.shared.bands[i].gain = Double(max(-12.0, min(12.0, gains[i])))
            }
            AudioDSPManager.shared.isEQEnabled = true
        }
        
        // Apply Bass & Clarity
        self.isViperBassEnabled = bassOn
        self.viperBassFreq = bassFreqVal
        self.viperBassGain = bassGainVal
        self.isViperClarityEnabled = clarityOn
        self.viperClarityGain = clarityGainVal
        
        // Try locating associated kernel file in same folder or ViPER presets dir
        if let kName = kernelRef, !kName.isEmpty, kName != "None" {
            let parentDir = url.deletingLastPathComponent()
            let candidate1 = parentDir.appendingPathComponent(kName)
            let candidate2 = parentDir.appendingPathComponent("kernel/\(kName)")
            let candidate3 = parentDir.appendingPathComponent("Kernel/\(kName)")
            if FileManager.default.fileExists(atPath: candidate1.path) {
                loadKernelFile(url: candidate1)
            } else if FileManager.default.fileExists(atPath: candidate2.path) {
                loadKernelFile(url: candidate2)
            } else if FileManager.default.fileExists(atPath: candidate3.path) {
                loadKernelFile(url: candidate3)
            }
        }
        
        DispatchQueue.main.async {
            self.loadedPresetName = url.lastPathComponent.uppercased()
            self.isViperEnabled = true
            self.statusMessage = "PRESET APPLIED: \(self.loadedPresetName)"
        }
    }
    
    private func extractNumber(from line: String) -> Float? {
        if let start = line.range(of: ">"), let end = line.range(of: "</") {
            let valStr = String(line[start.upperBound..<end.lowerBound])
            return Float(valStr.trimmingCharacters(in: .whitespaces))
        }
        return nil
    }
}
