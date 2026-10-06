import Foundation
import CoreAudio
import AudioToolbox
import AppKit
import Accelerate

// MARK: - Studio Quality Biquad IIR Filter (-24dB to +24dB)
public class BiquadFilter {
    var a0: Float = 1, a1: Float = 0, a2: Float = 0
    var b0: Float = 1, b1: Float = 0, b2: Float = 0
    var x1: Float = 0, x2: Float = 0
    var y1: Float = 0, y2: Float = 0
    
    public init() {}
    
    public func setPeaking(frequency: Float, sampleRate: Float, gainDb: Float, q: Float = 1.0) {
        if abs(gainDb) < 0.05 {
            b0 = 1; b1 = 0; b2 = 0
            a0 = 1; a1 = 0; a2 = 0
            return
        }
        let clampedGain = max(-24.0, min(24.0, gainDb))
        let A = pow(10.0, clampedGain / 40.0)
        let w0 = 2.0 * Float.pi * max(10.0, min(frequency, sampleRate * 0.45)) / sampleRate
        let alpha = sin(w0) / (2.0 * q)
        let cosw0 = cos(w0)
        
        b0 = 1.0 + alpha * A
        b1 = -2.0 * cosw0
        b2 = 1.0 - alpha * A
        a0 = 1.0 + alpha / A
        a1 = -2.0 * cosw0
        a2 = 1.0 - alpha / A
        
        b0 /= a0
        b1 /= a0
        b2 /= a0
        a1 /= a0
        a2 /= a0
    }
    
    public func setLowShelf(frequency: Float, sampleRate: Float, gainDb: Float) {
        if abs(gainDb) < 0.05 {
            b0 = 1; b1 = 0; b2 = 0; a0 = 1; a1 = 0; a2 = 0
            return
        }
        let A = pow(10.0, gainDb / 40.0)
        let w0 = 2.0 * Float.pi * max(10.0, min(frequency, sampleRate * 0.45)) / sampleRate
        let cosw0 = cos(w0)
        let sinw0 = sin(w0)
        let alpha = sinw0 / 2.0 * sqrt(2.0)
        let twoRootAAlpha = 2.0 * sqrt(A) * alpha
        
        b0 = A * ((A + 1.0) - (A - 1.0) * cosw0 + twoRootAAlpha)
        b1 = 2.0 * A * ((A - 1.0) - (A + 1.0) * cosw0)
        b2 = A * ((A + 1.0) - (A - 1.0) * cosw0 - twoRootAAlpha)
        a0 = (A + 1.0) + (A - 1.0) * cosw0 + twoRootAAlpha
        a1 = -2.0 * ((A - 1.0) + (A + 1.0) * cosw0)
        a2 = (A + 1.0) + (A - 1.0) * cosw0 - twoRootAAlpha
        
        b0 /= a0; b1 /= a0; b2 /= a0; a1 /= a0; a2 /= a0
    }
    
    public func setHighShelf(frequency: Float, sampleRate: Float, gainDb: Float) {
        if abs(gainDb) < 0.05 {
            b0 = 1; b1 = 0; b2 = 0; a0 = 1; a1 = 0; a2 = 0
            return
        }
        let A = pow(10.0, gainDb / 40.0)
        let w0 = 2.0 * Float.pi * max(10.0, min(frequency, sampleRate * 0.45)) / sampleRate
        let cosw0 = cos(w0)
        let sinw0 = sin(w0)
        let alpha = sinw0 / 2.0 * sqrt(2.0)
        let twoRootAAlpha = 2.0 * sqrt(A) * alpha
        
        b0 = A * ((A + 1.0) + (A - 1.0) * cosw0 + twoRootAAlpha)
        b1 = -2.0 * A * ((A - 1.0) + (A + 1.0) * cosw0)
        b2 = A * ((A + 1.0) + (A - 1.0) * cosw0 - twoRootAAlpha)
        a0 = (A + 1.0) - (A - 1.0) * cosw0 + twoRootAAlpha
        a1 = 2.0 * ((A - 1.0) - (A + 1.0) * cosw0)
        a2 = (A + 1.0) - (A - 1.0) * cosw0 - twoRootAAlpha
        
        b0 /= a0; b1 /= a0; b2 /= a0; a1 /= a0; a2 /= a0
    }
    
    public func setLowPass(frequency: Float, sampleRate: Float, q: Float = 0.707) {
        let w0 = 2.0 * Float.pi * max(10.0, min(frequency, sampleRate * 0.45)) / sampleRate
        let cosw0 = cos(w0)
        let alpha = sin(w0) / (2.0 * q)
        b0 = (1.0 - cosw0) * 0.5
        b1 = 1.0 - cosw0
        b2 = (1.0 - cosw0) * 0.5
        a0 = 1.0 + alpha
        a1 = -2.0 * cosw0
        a2 = 1.0 - alpha
        b0 /= a0; b1 /= a0; b2 /= a0; a1 /= a0; a2 /= a0
    }
    
    public func setHighPass(frequency: Float, sampleRate: Float, q: Float = 0.707) {
        let w0 = 2.0 * Float.pi * max(10.0, min(frequency, sampleRate * 0.45)) / sampleRate
        let cosw0 = cos(w0)
        let alpha = sin(w0) / (2.0 * q)
        b0 = (1.0 + cosw0) * 0.5
        b1 = -(1.0 + cosw0)
        b2 = (1.0 + cosw0) * 0.5
        a0 = 1.0 + alpha
        a1 = -2.0 * cosw0
        a2 = 1.0 - alpha
        b0 /= a0; b1 /= a0; b2 /= a0; a1 /= a0; a2 /= a0
    }
    
    @inline(__always)
    public func process(sample: Float) -> Float {
        let out = b0 * sample + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1
        x1 = sample
        y2 = y1
        y1 = out
        return out
    }
    
    public func reset() {
        x1 = 0; x2 = 0; y1 = 0; y2 = 0
    }
}

public class MultiBandEQ {
    var filtersL: [BiquadFilter] = (0..<10).map { _ in BiquadFilter() }
    var filtersR: [BiquadFilter] = (0..<10).map { _ in BiquadFilter() }
    let freqs: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    public private(set) var isBypassed: Bool = true
    
    public init() {}
    
    public func update(gains: [Double], sampleRate: Float = 44100) {
        var anyNonZero = false
        for (i, freq) in freqs.enumerated() {
            let gain = Float((i < gains.count) ? gains[i] : 0.0)
            if abs(gain) > 0.05 { anyNonZero = true }
            if i == 0 {
                filtersL[i].setLowShelf(frequency: 80.0, sampleRate: sampleRate, gainDb: gain)
                filtersR[i].setLowShelf(frequency: 80.0, sampleRate: sampleRate, gainDb: gain)
            } else if i == 9 {
                filtersL[i].setHighShelf(frequency: 10000.0, sampleRate: sampleRate, gainDb: gain)
                filtersR[i].setHighShelf(frequency: 10000.0, sampleRate: sampleRate, gainDb: gain)
            } else {
                filtersL[i].setPeaking(frequency: freq, sampleRate: sampleRate, gainDb: gain, q: 1.15)
                filtersR[i].setPeaking(frequency: freq, sampleRate: sampleRate, gainDb: gain, q: 1.15)
            }
        }
        self.isBypassed = !anyNonZero
    }
    
    public func setBypass(_ bypass: Bool) {
        self.isBypassed = bypass
    }
    
    @inline(__always)
    public func process(left: Float, right: Float) -> (Float, Float) {
        if isBypassed { return (left, right) }
        var l = left
        var r = right
        for i in 0..<10 {
            l = filtersL[i].process(sample: l)
            r = filtersR[i].process(sample: r)
        }
        return (l, r)
    }
    
    public func reset() {
        self.isBypassed = true
        filtersL.forEach { $0.reset() }
        filtersR.forEach { $0.reset() }
    }
}

// MARK: - Hardware-Accelerated Real-Time Spectrum Analyzer (Apple vDSP FFT)
public final class RealTimeSpectrumAnalyzer {
    private let log2n = vDSP_Length(10) // 1024 points (46.875 Hz per bin at 48kHz)
    private let n: Int
    private let fftSetup: FFTSetup
    private var real: [Float]
    private var imag: [Float]
    private var magnitudes: [Float]
    private var window: [Float]
    
    // Frequency bin ranges for the 10 bands at 48kHz:
    // 32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000 Hz
    private let bandRanges: [(start: Int, end: Int, weight: Float)] = [
        (1, 1, 1.4),     // 32 Hz
        (1, 2, 1.3),     // 64 Hz
        (2, 4, 1.2),     // 125 Hz
        (4, 7, 1.1),     // 250 Hz
        (8, 14, 1.0),    // 500 Hz
        (15, 28, 1.1),   // 1 kHz
        (29, 56, 1.3),   // 2 kHz
        (57, 112, 1.6),  // 4 kHz
        (113, 224, 2.0), // 8 kHz
        (225, 450, 2.6)  // 16 kHz
    ]
    
    public init() {
        self.n = 1 << log2n
        self.fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        self.real = [Float](repeating: 0, count: n / 2)
        self.imag = [Float](repeating: 0, count: n / 2)
        self.magnitudes = [Float](repeating: 0, count: n / 2)
        var win = [Float](repeating: 0, count: n)
        vDSP_hann_window(&win, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        self.window = win
    }
    
    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }
    
    public func analyze(samples: [Float]) -> [Float] {
        guard samples.count >= n else { return [Float](repeating: 0, count: 10) }
        
        var windowed = [Float](repeating: 0, count: n)
        vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(n))
        
        windowed.withUnsafeBufferPointer { ptr in
            ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { complexPtr in
                real.withUnsafeMutableBufferPointer { rPtr in
                    imag.withUnsafeMutableBufferPointer { iPtr in
                        var split = DSPSplitComplex(realp: rPtr.baseAddress!, imagp: iPtr.baseAddress!)
                        vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(n / 2))
                        vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                        magnitudes.withUnsafeMutableBufferPointer { mPtr in
                            vDSP_zvmags(&split, 1, mPtr.baseAddress!, 1, vDSP_Length(n / 2))
                        }
                    }
                }
            }
        }
        
        var result = [Float](repeating: 0, count: 10)
        for (i, r) in bandRanges.enumerated() {
            var sum: Float = 0
            for b in r.start...r.end {
                sum += magnitudes[b]
            }
            let avgMag = sqrt(sum / Float(r.end - r.start + 1)) * 4.0 / Float(n)
            let weighted = avgMag * r.weight
            // Gamma curve (pow 0.45) for lively, punchy, dynamic bounce
            let val = min(1.0, max(0.0, pow(weighted, 0.45)))
            result[i] = val
        }
        return result
    }
}

// MARK: - Multi-Client Studio Audio DSP
public final class MultiSinkAudioDSP {
    private let capacity: Int = 262144
    private var bufferL: [Float]
    private var bufferR: [Float]
    private var writeHead: Int = 0
    private let mask: Int
    
    private let analyzer = RealTimeSpectrumAnalyzer()
    private var fifoBuffer: [Float] = [Float](repeating: 0, count: 1024)
    private var fifoHead: Int = 0
    private var peakL: Float = 0
    private var peakR: Float = 0
    private var smoothedSpectrum: [Float] = [Float](repeating: 0, count: 10)
    
    public init() {
        self.mask = 262144 - 1
        self.bufferL = [Float](repeating: 0, count: 262144)
        self.bufferR = [Float](repeating: 0, count: 262144)
    }
    
    public func writeInterleaved(data: UnsafePointer<Float>, frameCount: Int) {
        var w = writeHead
        var fHead = fifoHead
        var localMaxL: Float = 0
        var localMaxR: Float = 0
        
        for i in 0..<frameCount {
            let l = data[i * 2]
            let r = data[i * 2 + 1]
            bufferL[w & mask] = l
            bufferR[w & mask] = r
            w += 1
            
            fifoBuffer[fHead & 1023] = (l + r) * 0.5
            fHead += 1
            
            let absL = abs(l)
            let absR = abs(r)
            if absL > localMaxL { localMaxL = absL }
            if absR > localMaxR { localMaxR = absR }
        }
        writeHead = w
        fifoHead = fHead
        
        if localMaxL > peakL { peakL = localMaxL }
        if localMaxR > peakR { peakR = localMaxR }
    }
    
    public func write(left: UnsafePointer<Float>, right: UnsafePointer<Float>?, count: Int) {
        var w = writeHead
        var fHead = fifoHead
        for i in 0..<count {
            let l = left[i]
            let r = right != nil ? right![i] : l
            bufferL[w & mask] = l
            bufferR[w & mask] = r
            w += 1
            
            fifoBuffer[fHead & 1023] = (l + r) * 0.5
            fHead += 1
        }
        writeHead = w
        fifoHead = fHead
    }
    
    public func resetSinkReadHead(sink: OutputDeviceSink, targetOffset: Double) {
        sink.readHead = Double(writeHead) - targetOffset
    }
    
    public func pushSamplesForVisualizer(_ samples: [Float]) {
        var fHead = fifoHead
        for s in samples {
            fifoBuffer[fHead & 1023] = s
            fHead += 1
        }
        fifoHead = fHead
        peakL = 0.95
        peakR = 0.95
    }
    
    public func getLiveMeters() -> (left: Float, right: Float, spectrum: [Float]) {
        let l = peakL
        let r = peakR
        peakL *= 0.82
        peakR *= 0.82
        
        var block = [Float](repeating: 0, count: 1024)
        let fHead = fifoHead
        for i in 0..<1024 {
            block[i] = fifoBuffer[(fHead + i) & 1023]
        }
        
        let rawSpec = analyzer.analyze(samples: block)
        
        // Fast attack, smooth snappy release
        for i in 0..<10 {
            if rawSpec[i] > smoothedSpectrum[i] {
                // Instant punch up on hit!
                smoothedSpectrum[i] = rawSpec[i]
            } else {
                // Smooth snappy release
                smoothedSpectrum[i] = smoothedSpectrum[i] * 0.80
            }
        }
        
        return (l, r, smoothedSpectrum)
    }
    
    /// Continuous rational studio soft-clipper: 100% bit-exact linear below knee (0.95),
    /// perfectly transparent dynamic range, strictly bounded < 1.00.
    /// Completely eliminates harsh odd harmonics, wheezing, and unwanted distortion.
    @inline(__always)
    public static func studioSoftClip(_ x: Float) -> Float {
        let absX = abs(x)
        if absX <= 0.95 {
            return x
        }
        let excess = absX - 0.95
        let compressed = excess / (1.0 + excess) * 0.045
        let out = 0.95 + compressed
        return x < 0 ? -out : out
    }
    
    public func readAndProcessForSink(
        sink: OutputDeviceSink,
        leftOut: UnsafeMutablePointer<Float>,
        rightOut: UnsafeMutablePointer<Float>,
        count: Int,
        boost: Float,
        isEQEnabled: Bool,
        isAntiClip: Bool,
        isSpatial: Bool,
        isBassPunch: Bool,
        isVocalBoost: Bool
    ) {
        if abs(sink.currentDelaySamples - sink.targetDelaySamples) > 0.5 {
            let diff = sink.targetDelaySamples - sink.currentDelaySamples
            sink.currentDelaySamples += diff * 0.05
        }
        let targetOffset: Double = 3072.0 + max(0.0, sink.currentDelaySamples)
        
        var rHead = sink.readHead
        if rHead < 0 {
            if Double(writeHead) < targetOffset {
                for i in 0..<count {
                    leftOut[i] = 0
                    rightOut[i] = 0
                }
                return
            } else {
                rHead = max(0.0, Double(writeHead) - targetOffset)
                sink.readHead = rHead
                sink.isPrebuffered = true
            }
        }
        
        let available = Double(writeHead) - rHead
        let ratio = sink.resampleRatio
        let needed = Double(count) * ratio
        
        if available < needed {
            // Buffer underrun protection: gracefully realign without clicking or dumping harsh static
            rHead = max(0.0, Double(writeHead) - targetOffset)
            sink.readHead = rHead
            for i in 0..<count {
                leftOut[i] = 0
                rightOut[i] = 0
            }
            return
        }
        
        // Large drift resync ONLY on true hardware stall / sleep / wake (> 6x target offset or negative)
        if available > (targetOffset * 6.0) || available < 0 {
            rHead = max(0.0, Double(writeHead) - targetOffset)
            sink.readHead = rHead
        }
        
        let drift = available - targetOffset
        // Adaptive clock crystal tracking: smooth fractional frequency pull (max +-0.05%)
        let pullFactor = max(-0.0005, min(0.0005, drift * 0.0000002))
        let effectiveRatio = ratio * (1.0 + pullFactor)
        
        // Precompute Dolby Atmos spatial parameters ONCE per buffer (ZERO allocation in inner loop)
        let dspMgr = AudioDSPManager.shared
        let isAtmos = dspMgr.isAtmosEnabled
        let atmosWidth = Float(dspMgr.atmosSurroundWidth)
        let atmosSub = Float(dspMgr.atmosBassExciter)
        let atmosRoom = Float(dspMgr.atmosRoomSize)
        let atmosElev = Float(dspMgr.atmosElevation) / 90.0
        
        // ViPER4Android & JamesDSP Precomputations
        let viper = ViperDSPManager.shared
        let isViper = viper.isViperEnabled
        let isConv = isViper && viper.isConvolverEnabled && viper.kernelLength > 16
        let kLen = viper.kernelLength
        let convWet = viper.convolverWet
        let isVBass = isViper && viper.isViperBassEnabled
        let isVClarity = isViper && viper.isViperClarityEnabled
        let isTube = isViper && viper.isTubeSimulatorEnabled
        
        if isVBass {
            sink.viperBassFilterL.setPeaking(frequency: viper.viperBassFreq, sampleRate: 48000.0, gainDb: viper.viperBassGain, q: 1.1)
            sink.viperBassFilterR.setPeaking(frequency: viper.viperBassFreq, sampleRate: 48000.0, gainDb: viper.viperBassGain, q: 1.1)
        }
        if isVClarity {
            sink.viperClarityFilterL.setHighShelf(frequency: 3500.0, sampleRate: 48000.0, gainDb: viper.viperClarityGain)
            sink.viperClarityFilterR.setHighShelf(frequency: 3500.0, sampleRate: 48000.0, gainDb: viper.viperClarityGain)
        }
        if isBassPunch {
            sink.bassFilterL.setPeaking(frequency: 100.0, sampleRate: 48000.0, gainDb: Float(dspMgr.bassPunchGain), q: 0.8)
            sink.bassFilterR.setPeaking(frequency: 100.0, sampleRate: 48000.0, gainDb: Float(dspMgr.bassPunchGain), q: 0.8)
        }
        if isVocalBoost {
            sink.vocalFilterL.setPeaking(frequency: 2800.0, sampleRate: 48000.0, gainDb: Float(dspMgr.vocalBoostGain), q: 1.2)
            sink.vocalFilterR.setPeaking(frequency: 2800.0, sampleRate: 48000.0, gainDb: Float(dspMgr.vocalBoostGain), q: 1.2)
        }
        
        let is1to1 = abs(ratio - 1.0) < 0.0001
        
        for i in 0..<count {
            let index0 = Int(floor(rHead))
            
            var rawL: Float
            var rawR: Float
            
            if is1to1 {
                // 100% bit-exact direct playback without resampling: pristine highs and transients
                rawL = bufferL[index0 & mask]
                rawR = bufferR[index0 & mask]
            } else {
                let frac = Float(rHead - Double(index0))
                let im1 = index0 - 1
                let i0 = index0
                let i1 = index0 + 1
                let i2 = index0 + 2
                
                let ym1L = bufferL[im1 & mask]
                let y0L  = bufferL[i0 & mask]
                let y1L  = bufferL[i1 & mask]
                let y2L  = bufferL[i2 & mask]
                let c0L = y0L
                let c1L = 0.5 * (y1L - ym1L)
                let c2L = ym1L - 2.5 * y0L + 2.0 * y1L - 0.5 * y2L
                let c3L = 0.5 * (y2L - ym1L) + 1.5 * (y0L - y1L)
                rawL = ((c3L * frac + c2L) * frac + c1L) * frac + c0L
                
                let ym1R = bufferR[im1 & mask]
                let y0R  = bufferR[i0 & mask]
                let y1R  = bufferR[i1 & mask]
                let y2R  = bufferR[i2 & mask]
                let c0R = y0R
                let c1R = 0.5 * (y1R - ym1R)
                let c2R = ym1R - 2.5 * y0R + 2.0 * y1R - 0.5 * y2R
                let c3R = 0.5 * (y2R - ym1R) + 1.5 * (y0R - y1R)
                rawR = ((c3R * frac + c2R) * frac + c1R) * frac + c0R
            }
            
            rHead += effectiveRatio
            
            // 1. Equalizer (Per-Sink Isolated Filter)
            if isEQEnabled {
                (rawL, rawR) = sink.eq.process(left: rawL, right: rawR)
            }
            
            // 2. Bass Punch
            if isBassPunch {
                let bassL = sink.bassFilterL.process(sample: rawL)
                let bassR = sink.bassFilterR.process(sample: rawR)
                rawL = rawL * 0.75 + bassL * 0.35
                rawR = rawR * 0.75 + bassR * 0.35
            }
            
            // 3. Vocal Clarity
            if isVocalBoost {
                rawL = sink.vocalFilterL.process(sample: rawL)
                rawR = sink.vocalFilterR.process(sample: rawR)
            }
            
            // 3b. ViPER4Android Bass, Clarity, and Tube Warmth
            if isVBass {
                rawL = sink.viperBassFilterL.process(sample: rawL)
                rawR = sink.viperBassFilterR.process(sample: rawR)
            }
            if isVClarity {
                rawL = sink.viperClarityFilterL.process(sample: rawL)
                rawR = sink.viperClarityFilterR.process(sample: rawR)
            }
            if isTube {
                rawL = rawL - 0.12 * rawL * abs(rawL)
                rawR = rawR - 0.12 * rawR * abs(rawR)
            }
            
            // 4. Maximum Impact Dolby Atmos 7.1.4 3D Spatializer (Multiband Frequency-Split Spatial Processing)
            if isAtmos {
                // Center dialogue/vocals & mid-frequency anchor
                let mid = (rawL + rawR) * 0.5
                let side = (rawL - rawR) * 0.5
                
                // MULTIBAND FREQUENCY SPLIT:
                // Lows (<180Hz) are kept strictly mono in the center anchor to prevent phase cancellation & distortion.
                let midBass = sink.crossoverLowL.process(sample: mid)
                let midAir = mid - midBass
                
                // Eliminate bass from side channel: guarantee zero out-of-phase low-frequency cancellation
                let sideBass = sink.crossoverLowR.process(sample: side)
                let sideAir = side - sideBass
                
                let sideHigh = sink.crossoverHighL.process(sample: sideAir)
                let sideMid = sideAir - sideHigh
                
                // --- A. SCHROEDER ALL-PASS 3D PHASE DECORRELATOR ---
                // Only decorrelate midAir (vocals, acoustic reflections, high-frequency spatial cues)
                // NEVER pass low frequencies through delay lines!
                let apIn = midAir * 0.30
                let apIndex = sink.apHead0 % 225
                let vDelayed = sink.apL0[apIndex]
                let g: Float = 0.55
                let v = apIn + g * vDelayed
                let decorrelated3D = -g * v + vDelayed
                sink.apL0[apIndex] = v
                sink.apHead0 += 1
                
                // --- B. BINAURAL HAAS ACOUSTIC CROSSTALK CANCELLATION ---
                // Delay buffer: 18 samples (~0.38 ms at 48kHz, exact acoustic interaural head width)
                sink.xtalkL[sink.xtalkHead & 63] = sideHigh
                let delayedSideHigh = sink.xtalkL[(sink.xtalkHead - 18) & 63]
                sink.xtalkHead += 1
                
                let width = min(2.0, max(0.8, Float(atmosWidth) * 0.75))
                let intensity = min(2.0, max(0.5, Float(dspMgr.spatialIntensity3D) * 0.70))
                
                // Spatialized high-frequency binaural cues with crosstalk cancellation
                let spatialHigh = (sideHigh * width * 1.10) - (delayedSideHigh * 0.25 * intensity)
                
                // Expansive focused stereo width for mids
                let spatialMid = sideMid * min(1.5, width * 0.90)
                
                // Total spatial side signal: clean stereo width + pristine 3D phase decorrelation (strictly no bass)
                let spatialSide = spatialMid + spatialHigh + (decorrelated3D * 0.30 * intensity)
                
                // --- C. DOLBY ATMOS HEIGHT / PINNA ELEVATION CUES (Overhead 3D Sound) ---
                var heightL: Float = 0
                var heightR: Float = 0
                if atmosElev > 0.05 {
                    let elevFactor = min(1.0, Float(atmosElev)) * 0.30
                    let pinnaL = sink.heightFilterL.process(sample: sideHigh + (decorrelated3D * 0.15))
                    let pinnaR = sink.heightFilterR.process(sample: -sideHigh - (decorrelated3D * 0.15))
                    heightL = (pinnaL - sideHigh) * elevFactor
                    heightR = (pinnaR - (-sideHigh)) * elevFactor
                }
                
                // --- D. CINEMA / STUDIO 3D EARLY REFLECTIONS (Acoustic spatial boundary) ---
                let roomFactor = min(1.0, Float(atmosRoom) * 0.20)
                sink.surroundDelayL[sink.surroundHead & 4095] = sideAir + (decorrelated3D * 0.15)
                let refl1 = sink.surroundDelayL[(sink.surroundHead - 190) & 4095] * 0.20
                let refl2 = sink.surroundDelayL[(sink.surroundHead - 390) & 4095] * 0.15
                let refl3 = sink.surroundDelayL[(sink.surroundHead - 280) & 4095] * -0.18
                let refl4 = sink.surroundDelayL[(sink.surroundHead - 560) & 4095] * -0.12
                sink.surroundHead += 1
                
                let roomL = (refl1 + refl2) * roomFactor
                let roomR = (refl3 + refl4) * roomFactor
                
                // --- E. CINEMA / NEAR-FIELD SUB-BASS IMPACT (Centered, punchy LFE) ---
                var subLFE: Float = 0
                if atmosSub > 1.02 {
                    let subFactor = min(1.0, Float(atmosSub - 1.0)) * 0.35
                    let filteredSub = sink.subBassL.process(sample: midBass)
                    subLFE = filteredSub * subFactor
                }
                
                // --- F. 3D HOLOGRAM SUMMATION WITH CLEAN MONO-BASS ANCHOR ---
                let role = sink.spatialRole
                let compL: Float
                let compR: Float
                
                // Distance reverberation factor: further speakers carry more room ambiance and surround cues
                let dist = Float(max(0.5, min(5.0, sink.distanceMeters)))
                let roomScale = min(1.5, 0.75 + (dist - 0.8) * 0.25)
                let actualRoomL = roomL * roomScale
                let actualRoomR = roomR * roomScale
                
                // Unified, distortion-free constant-energy matrixing:
                // Bass is identical on Left and Right (mono anchor), providing maximum acoustic punch with zero cancellation.
                let totalBass = (midBass * 0.85) + (subLFE * 0.25)
                
                if role == .leftChannel {
                    compL = totalBass + (midAir * 0.65) + (spatialSide * 0.55) + (heightL * 0.15) + (actualRoomL * 0.12)
                    compR = 0.02 * compL
                } else if role == .rightChannel {
                    let rSide = totalBass + (midAir * 0.65) - (spatialSide * 0.55) + (heightR * 0.15) + (actualRoomR * 0.12)
                    compL = 0.02 * rSide
                    compR = rSide
                } else if role == .frontCenter {
                    // Cinema Screen / Center Stage: Clear dialogue & solid center punch
                    compL = totalBass + (midAir * 0.78) + (spatialSide * 0.20) + (actualRoomL * 0.06)
                    compR = totalBass + (midAir * 0.78) - (spatialSide * 0.20) + (actualRoomR * 0.06)
                } else if role == .surroundSatellite {
                    // Cinema Surround Array: Immersive 3D side wrap
                    compL = (totalBass * 0.45) + (midAir * 0.30) + (spatialSide * 0.65) + (heightL * 0.25) + (actualRoomL * 0.25)
                    compR = (totalBass * 0.45) + (midAir * 0.30) - (spatialSide * 0.65) + (heightR * 0.25) + (actualRoomR * 0.25)
                } else {
                    // Full 3D Mix: Balanced, expansive, pristine fidelity
                    compL = totalBass + (midAir * 0.60) + (spatialSide * 0.40) + (heightL * 0.15) + (actualRoomL * 0.12)
                    compR = totalBass + (midAir * 0.60) - (spatialSide * 0.40) + (heightR * 0.15) + (actualRoomR * 0.12)
                }
                
                // Organic Soft-Knee Saturation (NO hard-clipping flat tops!)
                let peak = max(abs(compL), abs(compR))
                if peak > 0.88 {
                    let over = peak - 0.88
                    let compressedOver = tanh(over * 2.2) / 2.2
                    let smoothPeak = 0.88 + compressedOver * 0.07 // strictly caps at < 0.95
                    let scale = smoothPeak / peak
                    rawL = compL * scale
                    rawR = compR * scale
                } else {
                    rawL = compL
                    rawR = compR
                }
            } else if isSpatial {
                let mid = (rawL + rawR) * 0.5
                let side = (rawL - rawR) * 0.5 * 1.35
                let compL = mid + side
                let compR = mid - side
                let peak = max(abs(compL), abs(compR))
                if peak > 0.95 {
                    let s = 0.95 / peak
                    rawL = compL * s
                    rawR = compR * s
                } else {
                    rawL = compL
                    rawR = compR
                }
            }
            
            // 5. Intelligent Loudness Maximizer & Headroom Boost (1.0x to 5.0x = +0dB to +14dB)
            let boostedL = rawL * boost
            let boostedR = rawR * boost
            
            // 6. Transparent Broadcast Peak Limiter & Zero-Clip Engine
            if isAntiClip && (boost > 1.01 || abs(boostedL) > 0.98 || abs(boostedR) > 0.98) {
                let peak = max(abs(boostedL), abs(boostedR))
                
                // Fast attack ensures the envelope catches loud transients instantly (zero overshoot)
                if peak > sink.limiterEnvelope {
                    sink.limiterEnvelope = peak
                } else {
                    sink.limiterEnvelope = sink.limiterEnvelope * 0.9997 + peak * 0.0003
                }
                
                let ceiling: Float = 0.98
                let threshold: Float = 0.95
                let targetGain: Float
                if sink.limiterEnvelope > threshold {
                    targetGain = ceiling / sink.limiterEnvelope
                } else {
                    targetGain = 1.0
                }
                
                // Smooth transparent gain adjustment (no abrupt jumps)
                if targetGain < sink.limiterGain {
                    sink.limiterGain = sink.limiterGain * 0.85 + targetGain * 0.15
                } else {
                    sink.limiterGain = sink.limiterGain * 0.9996 + 1.0 * 0.0004
                }
                
                leftOut[i] = boostedL * sink.limiterGain
                rightOut[i] = boostedR * sink.limiterGain
            } else {
                leftOut[i] = boostedL
                rightOut[i] = boostedR
            }
        }
        
        // 7. ViPER Convolver (Real-time IRS Impulse Response Convolution via Apple Accelerate)
        if isConv && kLen > 16 {
            let m = kLen
            if sink.convHistoryL.count < m + count {
                sink.convHistoryL = [Float](repeating: 0, count: (m + count) * 2)
                sink.convHistoryR = [Float](repeating: 0, count: (m + count) * 2)
            }
            for j in 0..<m {
                sink.convHistoryL[j] = sink.convHistoryL[count + j]
                sink.convHistoryR[j] = sink.convHistoryR[count + j]
            }
            for j in 0..<count {
                sink.convHistoryL[m + j] = leftOut[j]
                sink.convHistoryR[m + j] = rightOut[j]
            }
            var convL = [Float](repeating: 0, count: count)
            var convR = [Float](repeating: 0, count: count)
            sink.convHistoryL.withUnsafeBufferPointer { hPtr in
                viper.kernelRevL.withUnsafeBufferPointer { kPtr in
                    convL.withUnsafeMutableBufferPointer { cPtr in
                        vDSP_conv(hPtr.baseAddress!, 1, kPtr.baseAddress!, 1, cPtr.baseAddress!, 1, vDSP_Length(count), vDSP_Length(m))
                    }
                }
            }
            sink.convHistoryR.withUnsafeBufferPointer { hPtr in
                viper.kernelRevR.withUnsafeBufferPointer { kPtr in
                    convR.withUnsafeMutableBufferPointer { cPtr in
                        vDSP_conv(hPtr.baseAddress!, 1, kPtr.baseAddress!, 1, cPtr.baseAddress!, 1, vDSP_Length(count), vDSP_Length(m))
                    }
                }
            }
            let wet = convWet
            let dry = 1.0 - (wet * 0.45)
            for j in 0..<count {
                leftOut[j] = MultiSinkAudioDSP.studioSoftClip(leftOut[j] * dry + convL[j] * wet)
                rightOut[j] = MultiSinkAudioDSP.studioSoftClip(rightOut[j] * dry + convR[j] * wet)
            }
        }
        
        sink.readHead = rHead
    }
}

// MARK: - Multi-Output CoreAudio Sink Descriptor
public final class OutputDeviceSink {
    public let deviceID: AudioObjectID
    public var procID: AudioDeviceIOProcID?
    public let sampleRate: Double
    public let resampleRatio: Double
    public var isBluetooth: Bool
    public var delaySamples: Double
    
    // Physical Multi-Speaker Spatial Profile (Lock-Free)
    public var isBuiltIn: Bool = false
    public var distanceMeters: Double = 1.0
    public var angleDegrees: Double = 0.0
    public var spatialRole: SpatialSpeakerRole = .auto
    
    // Per-sink isolated DSP state (100% thread-safe & lock-free across realtime IOThreads)
    public var readHead: Double = -1.0
    public var isPrebuffered: Bool = false
    public let eq: MultiBandEQ = MultiBandEQ()
    public let bassFilterL: BiquadFilter = {
        let f = BiquadFilter()
        f.setPeaking(frequency: 100.0, sampleRate: 48000.0, gainDb: 4.0, q: 0.8)
        return f
    }()
    public let bassFilterR: BiquadFilter = {
        let f = BiquadFilter()
        f.setPeaking(frequency: 100.0, sampleRate: 48000.0, gainDb: 4.0, q: 0.8)
        return f
    }()
    public let vocalFilterL: BiquadFilter = {
        let f = BiquadFilter()
        f.setPeaking(frequency: 2800.0, sampleRate: 48000.0, gainDb: 3.5, q: 1.2)
        return f
    }()
    public let vocalFilterR: BiquadFilter = {
        let f = BiquadFilter()
        f.setPeaking(frequency: 2800.0, sampleRate: 48000.0, gainDb: 3.5, q: 1.2)
        return f
    }()
    
    // MARK: - Dolby Atmos 7.1.4 Cinema 3D Spatializer State (Per-Sink Lock-Free)
    public var xtalkL: [Float] = [Float](repeating: 0, count: 64)
    public var xtalkR: [Float] = [Float](repeating: 0, count: 64)
    public var xtalkHead: Int = 0
    
    public var surroundDelayL: [Float] = [Float](repeating: 0, count: 4096)
    public var surroundDelayR: [Float] = [Float](repeating: 0, count: 4096)
    public var surroundHead: Int = 0
    
    public var combL0: [Float] = [Float](repeating: 0, count: 1116)
    public var combL1: [Float] = [Float](repeating: 0, count: 1188)
    public var combR0: [Float] = [Float](repeating: 0, count: 1139)
    public var combR1: [Float] = [Float](repeating: 0, count: 1211)
    public var combHead0: Int = 0
    public var combHead1: Int = 0
    public var combHead2: Int = 0
    public var combHead3: Int = 0
    
    public var apL0: [Float] = [Float](repeating: 0, count: 225)
    public var apR0: [Float] = [Float](repeating: 0, count: 243)
    public var apHead0: Int = 0
    
    // Cinema Sub-Bass Filter (Clean Low-Pass below 80 Hz)
    public let subBassL: BiquadFilter = {
        let f = BiquadFilter()
        f.setLowPass(frequency: 80.0, sampleRate: 48000.0, q: 0.707)
        return f
    }()
    public let subBassR: BiquadFilter = {
        let f = BiquadFilter()
        f.setLowPass(frequency: 80.0, sampleRate: 48000.0, q: 0.707)
        return f
    }()
    public let heightFilterL: BiquadFilter = {
        let f = BiquadFilter()
        f.setHighShelf(frequency: 7500.0, sampleRate: 48000.0, gainDb: 4.0)
        return f
    }()
    public let heightFilterR: BiquadFilter = {
        let f = BiquadFilter()
        f.setHighShelf(frequency: 7500.0, sampleRate: 48000.0, gainDb: 4.0)
        return f
    }()
    
    // Multiband Frequency-Splitting Crossover Filters (Clean Mono Bass Anchor)
    public let crossoverLowL: BiquadFilter = {
        let f = BiquadFilter()
        f.setLowPass(frequency: 180.0, sampleRate: 48000.0, q: 0.707)
        return f
    }()
    public let crossoverLowR: BiquadFilter = {
        let f = BiquadFilter()
        f.setLowPass(frequency: 180.0, sampleRate: 48000.0, q: 0.707)
        return f
    }()
    public let crossoverHighL: BiquadFilter = {
        let f = BiquadFilter()
        f.setHighPass(frequency: 2200.0, sampleRate: 48000.0, q: 0.707)
        return f
    }()
    
    // MARK: - ViPER4Android & JamesDSP State (Per-Sink Lock-Free)
    public var convHistoryL: [Float] = [Float](repeating: 0, count: 2048)
    public var convHistoryR: [Float] = [Float](repeating: 0, count: 2048)
    public let viperBassFilterL: BiquadFilter = BiquadFilter()
    public let viperBassFilterR: BiquadFilter = BiquadFilter()
    public let viperClarityFilterL: BiquadFilter = BiquadFilter()
    public let viperClarityFilterR: BiquadFilter = BiquadFilter()
    
    // Linear Slewing for click-free Doppler-free dynamic delay adjustments
    public var currentDelaySamples: Double = 0.0
    public var targetDelaySamples: Double = 0.0
    
    // Transparent Broadcast Limiter State
    public var limiterEnvelope: Float = 0.0
    public var limiterGain: Float = 1.0
    
    // Per-Device Independent Volume Gain (0.0 to 1.0, lock-free)
    public var volumeGain: Float = 1.0
    
    // Probe Injection for Acoustic Auto-Calibration (Thread-safe lock-free)
    public var probeBuffer: [Float]? = nil
    public var probeHead: Int = 0
    public var probeStartMicSample: Int = -1
    
    public func injectProbe(samples: [Float]) {
        self.probeStartMicSample = -1
        self.probeHead = 0
        self.probeBuffer = samples
    }
    
    public init(
        deviceID: AudioObjectID,
        procID: AudioDeviceIOProcID? = nil,
        sampleRate: Double,
        resampleRatio: Double,
        isBluetooth: Bool = false,
        delaySamples: Double = 0.0
    ) {
        self.deviceID = deviceID
        self.procID = procID
        self.sampleRate = sampleRate
        self.resampleRatio = resampleRatio
        self.isBluetooth = isBluetooth
        self.delaySamples = delaySamples
        self.targetDelaySamples = delaySamples
        self.currentDelaySamples = delaySamples
    }
}

// MARK: - CoreAudio Multi-Device HAL Engine
public class RealAudioEngine: ObservableObject {
    public static let shared = RealAudioEngine()
    
    private var inputProcID: AudioDeviceIOProcID?
    private var inputDeviceID: AudioObjectID = 0
    private var inSampleRate: Double = 48000.0
    
    // Multi-Device Output Sinks (Simultaneous Multi-Output Playback)
    public var activeSinks: [AudioObjectID: OutputDeviceSink] = [:]
    
    public let dspProcessor = MultiSinkAudioDSP()
    public let eqProcessor = MultiBandEQ()
    
    @Published public var isRoutingActive: Bool = false
    @Published public var statusMessage: String = "Ready"
    @Published public var hasBlackHole: Bool = false
    @Published public var activeDeviceCount: Int = 0
    
    public init() {
        checkBlackHoleAvailability()
    }
    
    public func checkBlackHoleAvailability() {
        hasBlackHole = (findDevice(nameSubstring: "Background Music") != nil || findDevice(nameSubstring: "BlackHole") != nil)
    }
    
    public func ensureHiFiBluetoothMode() {
        guard let micID = findBuiltInMic() else { return }
        var devID = micID
        var defaultInputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultInputAddress,
            0,
            nil,
            UInt32(MemoryLayout<AudioObjectID>.size),
            &devID
        )
    }
    
    public func updateBands(gains: [Double]) {
        eqProcessor.update(gains: gains, sampleRate: 44100)
        for sink in activeSinks.values {
            sink.eq.update(gains: gains, sampleRate: Float(sink.sampleRate))
        }
    }
    
    public func updateBoost(multiplier: Double) {}
    public func setEQBypass(_ bypass: Bool) {
        eqProcessor.setBypass(bypass)
        for sink in activeSinks.values {
            sink.eq.setBypass(bypass)
        }
    }
    
    public func isBluetoothDevice(deviceID: AudioObjectID) -> Bool {
        let transport = getDeviceTransportType(deviceID: deviceID)
        if transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE {
            return true
        }
        let name = getDeviceName(deviceID: deviceID).lowercased()
        return name.contains("bluetooth") || name.contains("rockbox") || name.contains("airpods") || name.contains("beats") || name.contains("headphone")
    }
    
    public func applyDirectSyncDelay(fasterDeviceID: AudioObjectID, delaySamples: Double) {
        for (devID, sink) in activeSinks {
            if devID == fasterDeviceID {
                sink.delaySamples = delaySamples
                sink.targetDelaySamples = delaySamples
                sink.currentDelaySamples = delaySamples
                let targetOffset = 1024.0 + delaySamples
                dspProcessor.resetSinkReadHead(sink: sink, targetOffset: targetOffset)
            } else {
                sink.delaySamples = 0.0
                sink.targetDelaySamples = 0.0
                sink.currentDelaySamples = 0.0
                let targetOffset = 1024.0
                dspProcessor.resetSinkReadHead(sink: sink, targetOffset: targetOffset)
            }
        }
    }
    
    public func updateSyncDelay(ms: Double) {
        let s = ms * (inSampleRate / 1000.0)
        let hasBluetooth = activeSinks.values.contains { $0.isBluetooth }
        
        // Pick which sink should receive delay compensation
        var sinkToDelay: OutputDeviceSink? = nil
        if hasBluetooth {
            // Delay non-bluetooth speaker (built-in speaker is faster than bluetooth)
            sinkToDelay = activeSinks.values.first { !$0.isBluetooth }
        } else {
            // If neither is bluetooth, delay the built-in speaker
            sinkToDelay = activeSinks.values.first { getDeviceTransportType(deviceID: $0.deviceID) == kAudioDeviceTransportTypeBuiltIn }
            if sinkToDelay == nil {
                sinkToDelay = activeSinks.values.first
            }
        }
        
        for (_, sink) in activeSinks {
            if sink === sinkToDelay {
                sink.delaySamples = s
                sink.targetDelaySamples = s
                sink.currentDelaySamples = s
                let targetOffset = 1024.0 + s
                dspProcessor.resetSinkReadHead(sink: sink, targetOffset: targetOffset)
            } else {
                sink.delaySamples = 0.0
                sink.targetDelaySamples = 0.0
                sink.currentDelaySamples = 0.0
                let targetOffset = 1024.0
                dspProcessor.resetSinkReadHead(sink: sink, targetOffset: targetOffset)
            }
        }
    }
    
    public var isProbingActive: Bool = false
    public var currentInSampleRate: Double { return inSampleRate }
    
    public func injectProbeChirp(deviceID: AudioObjectID, chirp: [Float]) {
        self.isProbingActive = true
        for (id, sink) in activeSinks {
            if id == deviceID {
                sink.injectProbe(samples: chirp)
            } else {
                sink.probeBuffer = nil
                sink.probeHead = 0
                sink.probeStartMicSample = -1
            }
        }
    }
    
    public func endProbeSession() {
        self.isProbingActive = false
        for (_, sink) in activeSinks {
            sink.probeBuffer = nil
            sink.probeHead = 0
            sink.probeStartMicSample = -1
        }
    }
    
    public func getProbeStartMicSample(deviceID: AudioObjectID) -> Int {
        return activeSinks[deviceID]?.probeStartMicSample ?? -1
    }
    
    public func setSinkVolume(deviceID: AudioObjectID, volume: Float) {
        if let sink = activeSinks[deviceID] {
            sink.volumeGain = max(0.0, min(1.0, volume))
        }
    }
    
    public func updateSinkSpatialProperties(deviceID: AudioObjectID? = nil) {
        let devMgr = AudioDeviceManager.shared
        for (id, sink) in activeSinks {
            let pos = devMgr.getSpatialPosition(for: id)
            let role = devMgr.resolveSpatialRole(for: id)
            sink.distanceMeters = pos.distance
            sink.angleDegrees = pos.angle
            sink.spatialRole = role
        }
        
        // Dynamically recalculate acoustic air-flight delays across active sinks
        if activeSinks.count > 1 {
            let hasBT = activeSinks.values.contains { $0.isBluetooth }
            let dists = activeSinks.keys.map { devMgr.getSpatialPosition(for: $0).distance }
            let maxDist = dists.max() ?? 1.0
            let syncDelayMs = AudioDSPManager.shared.isSyncCompensationEnabled ? AudioDSPManager.shared.syncDelayMs : 0.0
            
            for (id, s) in activeSinks {
                let d = devMgr.getSpatialPosition(for: id).distance
                let airDelayMs = max(0.0, (maxDist - d) / 0.343)
                let btDelayMs = (!s.isBluetooth && hasBT) ? syncDelayMs : 0.0
                s.targetDelaySamples = (btDelayMs + airDelayMs) * (self.inSampleRate / 1000.0)
            }
        }
    }
    
    // MARK: - Multi-Output Simultaneous Routing
    public func startRouting(toOutputDeviceIDs: Set<AudioObjectID>) -> Bool {
        stopRouting(restoreDefaultDevice: false)
        
        let captureID = AudioDeviceManager.shared.virtualCaptureDeviceID
            ?? findInputDevice(nameSubstring: "Background Music")
            ?? findInputDevice(nameSubstring: "BlackHole")
        guard let virtualID = captureID else {
            statusMessage = "Virtual audio driver not found"
            hasBlackHole = false
            return false
        }
        hasBlackHole = true
        self.inputDeviceID = virtualID
        self.inSampleRate = getDeviceSampleRate(deviceID: inputDeviceID)
        
        // Filter valid output devices
        let validIDs = toOutputDeviceIDs.filter { $0 != virtualID && hasOutputStreams(deviceID: $0) }
        guard !validIDs.isEmpty else {
            statusMessage = "No output devices selected"
            return false
        }
        
        updateBands(gains: AudioDSPManager.shared.bands.map { $0.gain })
        
        // 1. Create BlackHole Input IOProc
        let inStatus = AudioDeviceCreateIOProcID(inputDeviceID, { inDevice, inNow, inInputData, inInputTime, outOutputData, inOutputTime, inClientData in
            guard let client = inClientData else { return noErr }
            let engine = Unmanaged<RealAudioEngine>.fromOpaque(client).takeUnretainedValue()
            
            let buffers = inInputData.pointee
            guard buffers.mNumberBuffers > 0 else { return noErr }
            
            let buf0 = buffers.mBuffers
            let frameCount = Int(buf0.mDataByteSize) / (Int(buf0.mNumberChannels) * MemoryLayout<Float>.size)
            
            if buf0.mNumberChannels >= 2 {
                if let data = buf0.mData?.assumingMemoryBound(to: Float.self) {
                    engine.dspProcessor.writeInterleaved(data: data, frameCount: frameCount)
                }
            } else if let data = buf0.mData?.assumingMemoryBound(to: Float.self) {
                engine.dspProcessor.write(left: data, right: nil, count: frameCount)
            }
            return noErr
        }, Unmanaged.passUnretained(self).toOpaque(), &inputProcID)
        
        guard inStatus == noErr, let inProc = inputProcID else {
            statusMessage = "Input error: \(inStatus)"
            return false
        }
        
        // 2. Create Output IOProcs on ALL selected devices simultaneously
        var sinks: [AudioObjectID: OutputDeviceSink] = [:]
        let hasBluetooth = validIDs.contains { isBluetoothDevice(deviceID: $0) }
        let syncDelayMs = AudioDSPManager.shared.isSyncCompensationEnabled ? AudioDSPManager.shared.syncDelayMs : 0.0
        let devMgr = AudioDeviceManager.shared
        devMgr.ensureBlackHoleUnmuted()
        
        let dists = validIDs.map { devMgr.getSpatialPosition(for: $0).distance }
        let maxDist = dists.max() ?? 1.0
        
        for devID in validIDs {
            devMgr.ensureHardwareDeviceActive(deviceID: devID)
            let outRate = getDeviceSampleRate(deviceID: devID)
            let ratio = self.inSampleRate / max(8000.0, outRate)
            let isBT = isBluetoothDevice(deviceID: devID)
            let devName = getDeviceName(deviceID: devID).lowercased()
            let isBuiltIn = devName.contains("macbook") || devName.contains("динамики") || devName.contains("built-in")
            
            let pos = devMgr.getSpatialPosition(for: devID)
            let role = devMgr.resolveSpatialRole(for: devID)
            
            // Acoustic air-flight delay: sound travels 1m in ~2.91ms (0.343 m/ms). Closer speaker delayed so wavefronts arrive together.
            let airDelayMs = (!isBT && validIDs.count > 1) ? max(0.0, (maxDist - pos.distance) / 0.343) : 0.0
            let totalDelayMs = (!isBT && hasBluetooth && validIDs.count > 1) ? (syncDelayMs + airDelayMs) : 0.0
            let delaySamples = totalDelayMs * (self.inSampleRate / 1000.0)
            
            let sink = OutputDeviceSink(
                deviceID: devID,
                sampleRate: outRate,
                resampleRatio: ratio,
                isBluetooth: isBT,
                delaySamples: delaySamples
            )
            sink.isBuiltIn = isBuiltIn
            sink.distanceMeters = pos.distance
            sink.angleDegrees = pos.angle
            sink.spatialRole = role
            sink.volumeGain = devMgr.getVolumeForDevice(devID)
            sink.eq.update(gains: AudioDSPManager.shared.bands.map { $0.gain }, sampleRate: Float(outRate))
            
            var outProc: AudioDeviceIOProcID?
            
            let outStatus = AudioDeviceCreateIOProcID(devID, { inDevice, inNow, inInputData, inInputTime, outOutputData, inOutputTime, inClientData in
                guard let client = inClientData else { return noErr }
                let sink = Unmanaged<OutputDeviceSink>.fromOpaque(client).takeUnretainedValue()
                let dsp = AudioDSPManager.shared
                let engine = RealAudioEngine.shared
                
                let outBufs = outOutputData.pointee
                guard outBufs.mNumberBuffers > 0 else { return noErr }
                let buf0 = outBufs.mBuffers
                let numChans = Int(buf0.mNumberChannels)
                let frameCount = Int(buf0.mDataByteSize) / (numChans * MemoryLayout<Float>.size)
                
                guard let outPtr = buf0.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
                
                // --- HARDWARE CALIBRATION PROBE MODE ---
                if engine.isProbingActive {
                    let isThisSinkProbing = (sink.probeBuffer != nil)
                    if isThisSinkProbing, let probe = sink.probeBuffer, sink.probeHead < probe.count {
                        if sink.probeStartMicSample < 0 {
                            sink.probeStartMicSample = AcousticAutoCalibrator.shared.getCurrentMicSampleCount()
                        }
                        let pCount = probe.count
                        var pHead = sink.probeHead
                        let probeVol: Float = 0.70
                        if numChans >= 2 {
                            for i in 0..<frameCount {
                                if pHead < pCount {
                                    let s = probe[pHead] * probeVol
                                    outPtr[i * 2] = s
                                    outPtr[i * 2 + 1] = s
                                    pHead += 1
                                } else {
                                    outPtr[i * 2] = 0.0
                                    outPtr[i * 2 + 1] = 0.0
                                }
                            }
                        } else {
                            for i in 0..<frameCount {
                                if pHead < pCount {
                                    outPtr[i] = probe[pHead] * probeVol
                                    pHead += 1
                                } else {
                                    outPtr[i] = 0.0
                                }
                            }
                        }
                        sink.probeHead = pHead
                        if pHead >= pCount {
                            sink.probeBuffer = nil
                        }
                    } else {
                        // Complete silence for other devices during calibration probe
                        let totalSamples = frameCount * numChans
                        for i in 0..<totalSamples {
                            outPtr[i] = 0.0
                        }
                    }
                    return noErr
                }
                
                // --- NORMAL PLAYBACK MODE ---
                var left = [Float](repeating: 0, count: frameCount)
                var right = [Float](repeating: 0, count: frameCount)
                
                left.withUnsafeMutableBufferPointer { lPtr in
                    right.withUnsafeMutableBufferPointer { rPtr in
                        engine.dspProcessor.readAndProcessForSink(
                            sink: sink,
                            leftOut: lPtr.baseAddress!,
                            rightOut: rPtr.baseAddress!,
                            count: frameCount,
                            boost: Float(dsp.boostMultiplier),
                            isEQEnabled: dsp.isEQEnabled,
                            isAntiClip: dsp.isAntiClippingEnabled,
                            isSpatial: dsp.isSpatialEnhancerEnabled,
                            isBassPunch: dsp.isBassPunchEnabled,
                            isVocalBoost: dsp.isVocalBoostEnabled
                        )
                    }
                }
                
                let devMgr = AudioDeviceManager.shared
                let isMuted = devMgr.isMuted
                let (panL, panR) = devMgr.getSpatialPan(for: sink.deviceID)
                let volL = (isMuted ? 0.0 : sink.volumeGain) * panL
                let volR = (isMuted ? 0.0 : sink.volumeGain) * panR
                
                if numChans >= 2 {
                    for i in 0..<frameCount {
                        let sL = left[i] * volL
                        let sR = right[i] * volR
                        if dsp.boostMultiplier > 1.01 || abs(sL) > 0.98 || abs(sR) > 0.98 {
                            outPtr[i * 2] = MultiSinkAudioDSP.studioSoftClip(sL)
                            outPtr[i * 2 + 1] = MultiSinkAudioDSP.studioSoftClip(sR)
                        } else {
                            outPtr[i * 2] = sL
                            outPtr[i * 2 + 1] = sR
                        }
                    }
                } else {
                    for i in 0..<frameCount {
                        let mono = ((left[i] * volL) + (right[i] * volR)) * 0.5
                        if dsp.boostMultiplier > 1.01 || abs(mono) > 0.98 {
                            outPtr[i] = MultiSinkAudioDSP.studioSoftClip(mono)
                        } else {
                            outPtr[i] = mono
                        }
                    }
                }
                return noErr
            }, Unmanaged.passUnretained(sink).toOpaque(), &outProc)
            
            if outStatus == noErr, let p = outProc {
                sink.procID = p
                sinks[devID] = sink
                AudioDeviceStart(devID, p)
            }
        }
        
        guard !sinks.isEmpty else {
            AudioDeviceDestroyIOProcID(inputDeviceID, inProc)
            inputProcID = nil
            statusMessage = "Failed to start output devices"
            return false
        }
        
        self.activeSinks = sinks
        AudioDeviceStart(inputDeviceID, inProc)
        
        isRoutingActive = true
        activeDeviceCount = sinks.count
        statusMessage = "Multi-Output Active (\(sinks.count) Devices)"
        
        setSystemDefaultOutputDevice(deviceID: virtualID)
        return true
    }
    
    public func stopRouting(restoreDefaultDevice: Bool = true) {
        if let inProc = inputProcID {
            AudioDeviceStop(inputDeviceID, inProc)
            AudioDeviceDestroyIOProcID(inputDeviceID, inProc)
            inputProcID = nil
        }
        
        for (devID, sink) in activeSinks {
            if let p = sink.procID {
                AudioDeviceStop(devID, p)
                AudioDeviceDestroyIOProcID(devID, p)
            }
        }
        activeSinks.removeAll()
        
        isRoutingActive = false
        activeDeviceCount = 0
        statusMessage = "Booster Inactive"
        
        // Restore default system output device to physical speakers ONLY when requested (never on internal routing transitions)
        if restoreDefaultDevice {
            let mgr = AudioDeviceManager.shared
            if let realDev = mgr.selectedDeviceIDs.first(where: { !self.getDeviceName(deviceID: $0).contains("BlackHole") && !self.getDeviceName(deviceID: $0).contains("Background Music") }) {
                setSystemDefaultOutputDevice(deviceID: realDev)
            } else if let internalSpk = findOutputDevice(nameSubstring: "MacBook") ?? findOutputDevice(nameSubstring: "Динамики") ?? findOutputDevice(nameSubstring: "Built-in") {
                setSystemDefaultOutputDevice(deviceID: internalSpk)
            } else if let rockbox = findOutputDevice(nameSubstring: "Rockbox") {
                setSystemDefaultOutputDevice(deviceID: rockbox)
            } else if let dev = mgr.outputDevices.first(where: { !$0.name.contains("BlackHole") && !$0.name.contains("Background Music") }) {
                setSystemDefaultOutputDevice(deviceID: dev.id)
            }
        }
    }
    
    public func playTestSound() {
        let sampleRate = 48000.0
        let duration = 0.40
        let count = Int(sampleRate * duration)
        var samples = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let t = Double(i) / sampleRate
            let env = sin(Double.pi * Double(i) / Double(count))
            let s1 = sin(2.0 * .pi * 880.0 * t)
            let s2 = sin(2.0 * .pi * 1320.0 * t) * 0.5
            let s3 = sin(2.0 * .pi * 440.0 * t) * 0.3
            samples[i] = Float((s1 + s2 + s3) * env * 0.7)
        }
        self.dspProcessor.pushSamplesForVisualizer(samples)
        if isRoutingActive && !activeSinks.isEmpty {
            for (_, sink) in activeSinks {
                sink.injectProbe(samples: samples)
            }
        } else {
            NSSound(named: "Glass")?.play()
        }
    }
    
    // MARK: - Device Query Helpers
    
    public func getDeviceName(deviceID: AudioObjectID) -> String {
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
        return "\(deviceID)"
    }
    
    public func getDeviceTransportType(deviceID: AudioObjectID) -> UInt32 {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &transport)
        return (status == noErr) ? transport : 0
    }
    
    public func getDeviceHardwareLatency(deviceID: AudioObjectID) -> (latency: UInt32, safetyOffset: UInt32, totalMs: Double) {
        var latency: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyLatency,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &latency)
        
        var safetyOffset: UInt32 = 0
        address.mSelector = kAudioDevicePropertySafetyOffset
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &safetyOffset)
        
        let sampleRate = getDeviceSampleRate(deviceID: deviceID)
        let totalSamples = Double(latency + safetyOffset)
        let totalMs = (totalSamples / max(8000.0, sampleRate)) * 1000.0
        return (latency, safetyOffset, totalMs)
    }
    
    private func getDeviceSampleRate(deviceID: AudioObjectID) -> Double {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var sampleRate: Float64 = 44100.0
        var size = UInt32(MemoryLayout<Float64>.size)
        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &size, &sampleRate)
        return (status == noErr && sampleRate > 0) ? Double(sampleRate) : 44100.0
    }
    
    public func hasOutputStreams(deviceID: AudioObjectID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        return (status == noErr && dataSize > 0)
    }
    
    public func findOutputDevice(nameSubstring: String) -> AudioObjectID? {
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
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var cfName: Unmanaged<CFString>?
            var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            let st = AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &size, &cfName)
            if st == noErr, let name = cfName?.takeRetainedValue() as String? {
                let lower = name.lowercased()
                if lower.contains("ui sounds") { continue }
                if lower.contains(nameSubstring.lowercased()) && hasOutputStreams(deviceID: id) {
                    return id
                }
            }
        }
        return nil
    }
    
    public func findInputDevice(nameSubstring: String) -> AudioObjectID? {
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
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var cfName: Unmanaged<CFString>?
            var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            let st = AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &size, &cfName)
            if st == noErr, let name = cfName?.takeRetainedValue() as String? {
                let lower = name.lowercased()
                if lower.contains("ui sounds") { continue }
                if lower.contains(nameSubstring.lowercased()) {
                    return id
                }
            }
        }
        return nil
    }
    
    public func findDevice(nameSubstring: String) -> AudioObjectID? {
        findOutputDevice(nameSubstring: nameSubstring)
    }
    
    private func findBuiltInMic() -> AudioObjectID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize)
        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var devIDs = [AudioObjectID](repeating: 0, count: count)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &devIDs)
        
        for id in devIDs {
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var cfName: Unmanaged<CFString>?
            var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &size, &cfName)
            if let name = cfName?.takeRetainedValue() as String?,
               (name.lowercased().contains("микрофон") || name.lowercased().contains("built-in")) {
                return id
            }
        }
        return nil
    }
    
    private func getDefaultOutputDeviceID() -> AudioObjectID? {
        var defaultID = AudioObjectID(0)
        var propertySize = UInt32(MemoryLayout<AudioObjectID>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &defaultID
        )
        return (status == noErr && defaultID != 0) ? defaultID : nil
    }
    
    public func setSystemDefaultOutputDevice(deviceID: AudioObjectID) {
        var devID = deviceID
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let propertySize = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            propertySize,
            &devID
        )
    }
}
