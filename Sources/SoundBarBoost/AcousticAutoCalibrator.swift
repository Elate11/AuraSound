import Foundation
import CoreAudio
import AudioToolbox
import Accelerate
import Combine
import SwiftUI

public enum CalibrationStage: Equatable {
    case idle
    case preparing
    case measuringDeviceA(name: String, iteration: Int, total: Int, status: String)
    case measuringDeviceB(name: String, iteration: Int, total: Int, status: String)
    case calculating
    case completed(delayMs: Double, samplesCount: Int)
    case failed(reason: String)
}

public class AcousticAutoCalibrator: ObservableObject {
    public static let shared = AcousticAutoCalibrator()
    
    @Published public var stage: CalibrationStage = .idle
    @Published public var isCalibrating: Bool = false
    @Published public var progress: Double = 0.0
    @Published public var statusMessage: String = "Готов к автокалибровке"
    @Published public var measuredDelayMs: Double? = nil
    
    private var micDeviceID: AudioObjectID = 0
    private var micProcID: AudioDeviceIOProcID?
    private var micBuffer: [Float] = []
    private let micBufferCapacity: Int = 48000 * 12 // 12 seconds buffer
    private var isRecordingMic: Bool = false
    private let lock = NSLock()
    
    // Realtime-safe sample counter (lock-free 64-bit integer read)
    public private(set) var totalMicSamplesRecorded: Int = 0
    
    // Continuous Pink Noise Reference (500 ms, 1/f spectrum bandpass-filtered 140 Hz - 9000 Hz)
    // Plays as a single smooth continuous sound on each speaker — ZERO pulses!
    private lazy var continuousPinkNoise: [Float] = {
        let sampleRate: Double = 48000.0
        let count = 24000 // 500 ms of continuous pink noise
        
        // Paul Kellet's high-grade 1/f filtered pink noise
        var b0: Float = 0, b1: Float = 0, b2: Float = 0
        var b3: Float = 0, b4: Float = 0, b5: Float = 0, b6: Float = 0
        var rng: UInt64 = 0xDEAD_BEEF_CAFE_1337 // Deterministic seed
        
        func nextWhite() -> Float {
            rng ^= rng << 13
            rng ^= rng >> 7
            rng ^= rng << 17
            return Float(Int64(bitPattern: rng) % 32768) / 32768.0
        }
        
        var pink = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let white = nextWhite()
            b0 = 0.99886 * b0 + white * 0.0555179
            b1 = 0.99332 * b1 + white * 0.0750759
            b2 = 0.96900 * b2 + white * 0.1538520
            b3 = 0.86650 * b3 + white * 0.3104856
            b4 = 0.55000 * b4 + white * 0.5329522
            b5 = -0.7616 * b5 - white * 0.0168980
            let s = b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362
            b6 = white * 0.115926
            pink[i] = s * 0.11
        }
        
        // Bandpass filter 140 Hz to 9000 Hz to eliminate room rumble and ultrasonic noise
        let hp = BiquadFilter()
        hp.setHighPass(frequency: 140.0, sampleRate: Float(sampleRate), q: 0.707)
        let lp = BiquadFilter()
        lp.setLowPass(frequency: 9000.0, sampleRate: Float(sampleRate), q: 0.707)
        for i in 0..<count {
            pink[i] = lp.process(sample: hp.process(sample: pink[i]))
        }
        
        // 35ms smooth cosine fade-in and fade-out to prevent clicks
        let fadeLen = Int(sampleRate * 0.035)
        for i in 0..<fadeLen {
            let fade = 0.5 * (1.0 - cos(Double.pi * Double(i) / Double(fadeLen)))
            pink[i] *= Float(fade)
            pink[count - 1 - i] *= Float(fade)
        }
        
        // Peak normalization to 0.85
        var maxAbs: Float = 0.001
        for s in pink {
            let a = abs(s)
            if a > maxAbs { maxAbs = a }
        }
        let normFactor: Float = 0.85 / maxAbs
        for i in 0..<count {
            pink[i] *= normFactor
        }
        
        return pink
    }()
    
    public init() {}
    
    deinit {
        stopContinuousMicRecording()
    }
    
    public func cancelCalibration() {
        RealAudioEngine.shared.endProbeSession()
        stopContinuousMicRecording()
        DispatchQueue.main.async {
            self.isCalibrating = false
            self.stage = .idle
            self.statusMessage = "Калибровка отменена"
        }
    }
    
    public func startAutoCalibration() {
        let selectedIDs = AudioDeviceManager.shared.selectedDeviceIDs
        let selectedArray = Array(selectedIDs)
        guard selectedArray.count >= 2 else {
            statusMessage = "Выберите минимум 2 устройства"
            stage = .failed(reason: "Необходимо минимум 2 активных устройства")
            return
        }
        
        guard let builtInMic = findBuiltInMicrophone() else {
            statusMessage = "Встроенный микрофон не найден"
            stage = .failed(reason: "Встроенный микрофон недоступен")
            return
        }
        
        self.micDeviceID = builtInMic
        self.isCalibrating = true
        self.progress = 0.05
        self.stage = .preparing
        self.statusMessage = "Инициализация аудиопотоков..."
        
        // Ensure multi-output streams are active and streaming
        if !RealAudioEngine.shared.isRoutingActive {
            _ = RealAudioEngine.shared.startRouting(toOutputDeviceIDs: selectedIDs)
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Stabilize audio HAL streams
            Thread.sleep(forTimeInterval: 0.30)
            
            var deviceA = selectedArray[0]
            var deviceB = selectedArray[1]
            
            let isA_BT = RealAudioEngine.shared.isBluetoothDevice(deviceID: deviceA)
            let isB_BT = RealAudioEngine.shared.isBluetoothDevice(deviceID: deviceB)
            
            // Put non-bluetooth device as Device A (reference / baseline)
            if isA_BT && !isB_BT {
                swap(&deviceA, &deviceB)
            }
            
            let nameA = RealAudioEngine.shared.getDeviceName(deviceID: deviceA)
            let nameB = RealAudioEngine.shared.getDeviceName(deviceID: deviceB)
            
            // Start Continuous Microphone Recording
            guard self.startContinuousMicRecording() else {
                DispatchQueue.main.async {
                    self.stage = .failed(reason: "Не удалось запустить микрофон")
                    self.statusMessage = "Ошибка микрофона"
                    self.isCalibrating = false
                }
                return
            }
            
            Thread.sleep(forTimeInterval: 0.20)
            
            // --- 1. Measure Device A (Speaker A) ---
            var peakOffsetA: Int? = nil
            for attempt in 1...2 {
                DispatchQueue.main.async {
                    self.stage = .measuringDeviceA(name: nameA, iteration: attempt, total: 1, status: "Воспроизведение розового шума...")
                    self.statusMessage = "Розовый шум: \(nameA)..."
                    self.progress = 0.20 + Double(attempt - 1) * 0.10
                }
                
                RealAudioEngine.shared.injectProbeChirp(deviceID: deviceA, chirp: self.continuousPinkNoise)
                
                // Wait for CoreAudio IOProc to actually write the first probe frame to hardware
                let waitStart = Date()
                var hwStartA = -1
                while hwStartA < 0 && Date().timeIntervalSince(waitStart) < 1.0 {
                    hwStartA = RealAudioEngine.shared.getProbeStartMicSample(deviceID: deviceA)
                    if hwStartA < 0 {
                        Thread.sleep(forTimeInterval: 0.005)
                    }
                }
                guard hwStartA >= 0 else { break }
                
                // Allow continuous playback (0.5s) + acoustic transit (0.9s)
                Thread.sleep(forTimeInterval: 1.40)
                let hwEndA = self.getCurrentMicSampleCount()
                let micChunkA = self.extractChunk(start: hwStartA, end: hwEndA)
                
                if let peak = self.findContinuousPeak(in: micChunkA) {
                    peakOffsetA = peak
                    break
                }
                Thread.sleep(forTimeInterval: 0.15)
            }
            
            guard let validPeakA = peakOffsetA else {
                RealAudioEngine.shared.endProbeSession()
                self.stopContinuousMicRecording()
                DispatchQueue.main.async {
                    self.stage = .failed(reason: "Микрофон не уловил сигнал от \(nameA)")
                    self.statusMessage = "Сигнал \(nameA) не распознан"
                    self.isCalibrating = false
                }
                return
            }
            
            DispatchQueue.main.async {
                self.progress = 0.50
                self.statusMessage = "\(nameA) зафиксирован"
            }
            
            Thread.sleep(forTimeInterval: 0.20)
            
            // --- 2. Measure Device B (Speaker B / Bluetooth / External) ---
            var peakOffsetB: Int? = nil
            for attempt in 1...2 {
                DispatchQueue.main.async {
                    self.stage = .measuringDeviceB(name: nameB, iteration: attempt, total: 1, status: "Воспроизведение розового шума...")
                    self.statusMessage = "Розовый шум: \(nameB)..."
                    self.progress = 0.60 + Double(attempt - 1) * 0.10
                }
                
                RealAudioEngine.shared.injectProbeChirp(deviceID: deviceB, chirp: self.continuousPinkNoise)
                
                // Wait for CoreAudio IOProc to actually write the first probe frame to hardware
                let waitStart = Date()
                var hwStartB = -1
                while hwStartB < 0 && Date().timeIntervalSince(waitStart) < 1.0 {
                    hwStartB = RealAudioEngine.shared.getProbeStartMicSample(deviceID: deviceB)
                    if hwStartB < 0 {
                        Thread.sleep(forTimeInterval: 0.005)
                    }
                }
                guard hwStartB >= 0 else { break }
                
                // Allow continuous playback (0.5s) + Bluetooth DAC buffer transit (1.1s)
                Thread.sleep(forTimeInterval: 1.60)
                let hwEndB = self.getCurrentMicSampleCount()
                let micChunkB = self.extractChunk(start: hwStartB, end: hwEndB)
                
                if let peak = self.findContinuousPeak(in: micChunkB) {
                    peakOffsetB = peak
                    break
                }
                Thread.sleep(forTimeInterval: 0.15)
            }
            
            RealAudioEngine.shared.endProbeSession()
            self.stopContinuousMicRecording()
            
            guard let validPeakB = peakOffsetB else {
                DispatchQueue.main.async {
                    self.stage = .failed(reason: "Микрофон не уловил сигнал от \(nameB)")
                    self.statusMessage = "Сигнал \(nameB) не распознан"
                    self.isCalibrating = false
                }
                return
            }
            
            // --- 3. Compute Exact Delay Differential ---
            DispatchQueue.main.async {
                self.stage = .calculating
                self.statusMessage = "Расчет задержки..."
                self.progress = 0.90
            }
            
            let micSampleRate = self.getDeviceSampleRate(deviceID: self.micDeviceID)
            
            let fasterDeviceID: AudioObjectID
            let fasterName: String
            let deltaMicSamples: Int
            
            if validPeakB >= validPeakA {
                // Device A sound reached mic sooner -> Device A is faster -> Delay Device A!
                fasterDeviceID = deviceA
                fasterName = nameA
                deltaMicSamples = validPeakB - validPeakA
            } else {
                // Device B sound reached mic sooner -> Device B is faster -> Delay Device B!
                fasterDeviceID = deviceB
                fasterName = nameB
                deltaMicSamples = validPeakA - validPeakB
            }
            
            let rawDeltaMs = (Double(deltaMicSamples) / max(8000.0, micSampleRate)) * 1000.0
            let finalDelayMs = max(0.0, min(800.0, rawDeltaMs))
            
            // Convert to internal DSP engine sample rate (typically 48000 Hz)
            let inRate = RealAudioEngine.shared.currentInSampleRate
            let engineDelaySamples = (finalDelayMs / 1000.0) * inRate
            
            Thread.sleep(forTimeInterval: 0.15)
            
            DispatchQueue.main.async {
                self.measuredDelayMs = finalDelayMs
                AudioDSPManager.shared.syncDelayMs = round(finalDelayMs)
                AudioDSPManager.shared.isSyncCompensationEnabled = true
                
                // Hardware instantaneous delay compensation on the faster device
                RealAudioEngine.shared.applyDirectSyncDelay(fasterDeviceID: fasterDeviceID, delaySamples: engineDelaySamples)
                
                self.progress = 1.0
                self.stage = .completed(delayMs: finalDelayMs, samplesCount: Int(engineDelaySamples))
                self.statusMessage = "Синхронизировано: \(Int(round(finalDelayMs))) мс (\(fasterName))"
                self.isCalibrating = false
            }
        }
    }
    
    // MARK: - Extract Mic Audio Slices
    private func extractChunk(start: Int, end: Int) -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        let totalCount = micBuffer.count
        guard start >= 0, end > start, end <= totalCount else { return [] }
        return Array(micBuffer[start..<end])
    }
    
    // MARK: - Continuous Pink Noise Band-Limited GCC-PHAT Cross-Correlation (Apple Accelerate SIMD)
    private func findContinuousPeak(in micChunk: [Float]) -> Int? {
        let ref = continuousPinkNoise
        guard micChunk.count >= ref.count else { return nil }
        
        let totalLen = micChunk.count + ref.count
        var log2n = vDSP_Length(15)
        while (1 << log2n) < totalLen && log2n < 18 {
            log2n += 1
        }
        let fftSize = 1 << log2n
        let halfSize = fftSize / 2
        
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return nil
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }
        
        var micPadded = [Float](repeating: 0, count: fftSize)
        for i in 0..<micChunk.count { micPadded[i] = micChunk[i] }
        
        var refPadded = [Float](repeating: 0, count: fftSize)
        for i in 0..<ref.count { refPadded[i] = ref[i] }
        
        var micReal = [Float](repeating: 0, count: halfSize)
        var micImag = [Float](repeating: 0, count: halfSize)
        var refReal = [Float](repeating: 0, count: halfSize)
        var refImag = [Float](repeating: 0, count: halfSize)
        
        // Forward FFT of Mic Signal
        micPadded.withUnsafeBufferPointer { mPtr in
            mPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfSize) { cPtr in
                micReal.withUnsafeMutableBufferPointer { rPtr in
                    micImag.withUnsafeMutableBufferPointer { iPtr in
                        var split = DSPSplitComplex(realp: rPtr.baseAddress!, imagp: iPtr.baseAddress!)
                        vDSP_ctoz(cPtr, 2, &split, 1, vDSP_Length(halfSize))
                        vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                    }
                }
            }
        }
        
        // Forward FFT of Reference Continuous Pink Noise
        refPadded.withUnsafeBufferPointer { rPtr in
            rPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfSize) { cPtr in
                refReal.withUnsafeMutableBufferPointer { rrPtr in
                    refImag.withUnsafeMutableBufferPointer { riPtr in
                        var split = DSPSplitComplex(realp: rrPtr.baseAddress!, imagp: riPtr.baseAddress!)
                        vDSP_ctoz(cPtr, 2, &split, 1, vDSP_Length(halfSize))
                        vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                    }
                }
            }
        }
        
        var crossReal = [Float](repeating: 0, count: halfSize)
        var crossImag = [Float](repeating: 0, count: halfSize)
        
        // Set DC & Nyquist to zero to avoid DC bias and Nyquist artifact
        crossReal[0] = 0.0
        crossImag[0] = 0.0
        
        // Band-limited GCC-PHAT: only whiten within speaker & mic operational passband (140 Hz to 10,000 Hz)
        let binHz = 48000.0 / Double(fftSize)
        let minBin = max(1, Int(140.0 / binHz))
        let maxBin = min(halfSize - 1, Int(10000.0 / binHz))
        
        for k in 1..<halfSize {
            if k >= minBin && k <= maxBin {
                let mr = micReal[k]
                let mi = micImag[k]
                let rr = refReal[k]
                let ri = -refImag[k] // Complex conjugate
                
                let cr = mr * rr - mi * ri
                let ci = mr * ri + mi * rr
                
                let mag = sqrt(cr * cr + ci * ci) + 1e-7
                crossReal[k] = cr / mag
                crossImag[k] = ci / mag
            } else {
                crossReal[k] = 0.0
                crossImag[k] = 0.0
            }
        }
        
        // Inverse FFT -> Sharp cross-correlation in time domain
        crossReal.withUnsafeMutableBufferPointer { rPtr in
            crossImag.withUnsafeMutableBufferPointer { iPtr in
                var split = DSPSplitComplex(realp: rPtr.baseAddress!, imagp: iPtr.baseAddress!)
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_INVERSE))
            }
        }
        
        var timeResult = [Float](repeating: 0, count: fftSize)
        timeResult.withUnsafeMutableBufferPointer { tPtr in
            tPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfSize) { cPtr in
                crossReal.withUnsafeBufferPointer { rPtr in
                    crossImag.withUnsafeBufferPointer { iPtr in
                        var split = DSPSplitComplex(realp: UnsafeMutablePointer(mutating: rPtr.baseAddress!),
                                                   imagp: UnsafeMutablePointer(mutating: iPtr.baseAddress!))
                        vDSP_ztoc(&split, 1, cPtr, 2, vDSP_Length(halfSize))
                    }
                }
            }
        }
        
        // Search window: from lag 0 up to micChunk.count - ref.count (up to ~1.1s delay)
        let searchRange = max(0, micChunk.count - ref.count)
        guard searchRange > 1000 else { return nil }
        
        var maxVal: Float = 0
        var maxIdx: vDSP_Length = 0
        vDSP_maxvi(timeResult, 1, &maxVal, &maxIdx, vDSP_Length(searchRange))
        
        // Minimum absolute peak to reject pure silence or disconnected mic
        guard maxVal > 6.0 else { return nil }
        
        // Calculate Peak-to-Sidelobe Ratio (PSR) for statistical certainty
        let peakIndex = Int(maxIdx)
        let guardRadius = 150 // +- 3ms acoustic direct pulse window
        var bgSum: Float = 0
        var bgSumSq: Float = 0
        var bgCount: Float = 0
        
        for i in 0..<searchRange {
            if abs(i - peakIndex) > guardRadius {
                let v = timeResult[i]
                bgSum += v
                bgSumSq += v * v
                bgCount += 1.0
            }
        }
        
        guard bgCount > 100 else { return nil }
        let bgMean = bgSum / bgCount
        let bgVariance = max(1e-8, (bgSumSq / bgCount) - (bgMean * bgMean))
        let bgStdDev = sqrt(bgVariance)
        
        let psr = (maxVal - bgMean) / bgStdDev
        
        // Standard signal-detection threshold: PSR >= 4.5 gives > 99.99% detection confidence
        guard psr >= 4.5 else {
            return nil
        }
        
        return peakIndex
    }
    
    // MARK: - Continuous Microphone IOProc Management
    private func startContinuousMicRecording() -> Bool {
        lock.lock()
        micBuffer = []
        micBuffer.reserveCapacity(micBufferCapacity)
        isRecordingMic = true
        totalMicSamplesRecorded = 0
        lock.unlock()
        
        var proc: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcID(micDeviceID, { inDevice, inNow, inInputData, inInputTime, outOutputData, inOutputTime, inClientData in
            guard let client = inClientData else { return noErr }
            let calibrator = Unmanaged<AcousticAutoCalibrator>.fromOpaque(client).takeUnretainedValue()
            
            let buffers = inInputData.pointee
            guard buffers.mNumberBuffers > 0, calibrator.isRecordingMic else { return noErr }
            let buf0 = buffers.mBuffers
            let frameCount = Int(buf0.mDataByteSize) / (Int(buf0.mNumberChannels) * MemoryLayout<Float>.size)
            guard let ptr = buf0.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            
            calibrator.lock.lock()
            if calibrator.micBuffer.count + frameCount <= calibrator.micBufferCapacity {
                if buf0.mNumberChannels >= 2 {
                    for i in 0..<frameCount {
                        calibrator.micBuffer.append(ptr[i * 2])
                    }
                } else {
                    for i in 0..<frameCount {
                        calibrator.micBuffer.append(ptr[i])
                    }
                }
            }
            calibrator.totalMicSamplesRecorded = calibrator.micBuffer.count
            calibrator.lock.unlock()
            return noErr
        }, Unmanaged.passUnretained(self).toOpaque(), &proc)
        
        if status == noErr, let p = proc {
            self.micProcID = p
            AudioDeviceStart(micDeviceID, p)
            return true
        }
        return false
    }
    
    private func stopContinuousMicRecording() {
        if let p = micProcID {
            AudioDeviceStop(micDeviceID, p)
            AudioDeviceDestroyIOProcID(micDeviceID, p)
            micProcID = nil
        }
        lock.lock()
        isRecordingMic = false
        lock.unlock()
    }
    
    public func getCurrentMicSampleCount() -> Int {
        return totalMicSamplesRecorded
    }
    
    // MARK: - Device Lookup Helpers
    private func findBuiltInMicrophone() -> AudioObjectID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize)
        guard status == noErr else { return nil }
        
        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var devIDs = [AudioObjectID](repeating: 0, count: count)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &devIDs)
        
        for id in devIDs {
            var streamAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            let st = AudioObjectGetPropertyDataSize(id, &streamAddress, 0, nil, &streamSize)
            guard st == noErr && streamSize > 0 else { continue }
            
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var cfName: Unmanaged<CFString>?
            var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &size, &cfName)
            if let name = cfName?.takeRetainedValue() as String? {
                let lower = name.lowercased()
                if lower.contains("built-in") || lower.contains("микрофон") || lower.contains("macbook") || lower.contains("internal") {
                    return id
                }
            }
        }
        
        var defaultInput = AudioObjectID(0)
        var defaultSize = UInt32(MemoryLayout<AudioObjectID>.size)
        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let defStatus = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultAddress, 0, nil, &defaultSize, &defaultInput)
        return (defStatus == noErr && defaultInput != 0) ? defaultInput : nil
    }
    
    private func getDeviceSampleRate(deviceID: AudioObjectID) -> Double {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var sampleRate: Float64 = 48000.0
        var size = UInt32(MemoryLayout<Float64>.size)
        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &size, &sampleRate)
        return (status == noErr && sampleRate > 0) ? Double(sampleRate) : 48000.0
    }
}
