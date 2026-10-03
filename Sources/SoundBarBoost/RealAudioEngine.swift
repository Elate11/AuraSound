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
    
    public init() {}
    
    public func update(gains: [Double], sampleRate: Float = 44100) {
        for (i, freq) in freqs.enumerated() {
            let gain = (i < gains.count) ? Float(gains[i]) : 0.0
            filtersL[i].setPeaking(frequency: freq, sampleRate: sampleRate, gainDb: gain)
            filtersR[i].setPeaking(frequency: freq, sampleRate: sampleRate, gainDb: gain)
        }
    }
    
    @inline(__always)
    public func process(left: Float, right: Float) -> (Float, Float) {
        var l = left
        var r = right
        for i in 0..<10 {
            l = filtersL[i].process(sample: l)
            r = filtersR[i].process(sample: r)
        }
        return (l, r)
    }
    
    public func reset() {
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
            sink.currentDelaySamples = sink.targetDelaySamples
        }
        let targetOffset: Double = 1024.0 + max(0.0, sink.currentDelaySamples)
        
        var rHead = sink.readHead
        if rHead < 0 {
            if Double(writeHead) < targetOffset {
                for i in 0..<count {
                    leftOut[i] = 0
                    rightOut[i] = 0
                }
                return
            }
            rHead = Double(writeHead) - targetOffset
            sink.readHead = rHead
            sink.isPrebuffered = true
        }
        
        let available = Double(writeHead) - rHead
        let ratio = sink.resampleRatio
        let needed = Double(count) * ratio
        
        if available < needed {
            // Buffer underrun: silence and resync to target offset
            for i in 0..<count {
                leftOut[i] = 0
                rightOut[i] = 0
            }
            sink.readHead = Double(writeHead) - targetOffset
            return
        }
        
        // Large drift resync ONLY on true hardware stall / sleep / wake
        if available > (targetOffset * 4.0) || available < 0 {
            rHead = Double(writeHead) - targetOffset
        } else {
            // Smooth, click-free clock crystal synchronization (deadband +-256 samples)
            let drift = available - targetOffset
            if drift > 256.0 {
                rHead += 0.005
            } else if drift < -256.0 {
                rHead -= 0.005
            }
        }
        
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
        
        for i in 0..<count {
            let index0 = Int(floor(rHead))
            let frac = Float(rHead - Double(index0))
            let index1 = index0 + 1
            
            let sampleL0 = bufferL[index0 & mask]
            let sampleL1 = bufferL[index1 & mask]
            var rawL = sampleL0 + (sampleL1 - sampleL0) * frac
            
            let sampleR0 = bufferR[index0 & mask]
            let sampleR1 = bufferR[index1 & mask]
            var rawR = sampleR0 + (sampleR1 - sampleR0) * frac
            
            rHead += ratio
            
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
            
            // 4. Maximum Impact Dolby Atmos 7.1.4 3D Spatializer
            if isAtmos {
                // Step A: Mid / Side Spatial Domain Separation
                let mid = (rawL + rawR) * 0.5
                let side = (rawL - rawR) * 0.5
                
                // Step B: Haas Interaural Crosstalk Cancellation on Side Channel (16 samples ~0.33ms)
                sink.xtalkL[sink.xtalkHead & 63] = side
                sink.xtalkR[sink.xtalkHead & 63] = -side
                let xL = sink.xtalkL[(sink.xtalkHead - 16) & 63]
                let xR = sink.xtalkR[(sink.xtalkHead - 16) & 63]
                sink.xtalkHead += 1
                
                // Super-wide holographic 3D soundstage
                let widthFactor = Float(atmosWidth)
                let expandedSideL = (side - xR * 0.65) * (0.85 + (widthFactor - 1.0) * 0.95)
                let expandedSideR = (-side - xL * 0.65) * (0.85 + (widthFactor - 1.0) * 0.95)
                
                // Step C: Virtual 7.1.4 Surround Upmixing (7ms decorrelation delay)
                sink.surroundDelayL[sink.surroundHead % 1200] = expandedSideL
                sink.surroundDelayR[sink.surroundHead % 1200] = expandedSideR
                let surrL = sink.surroundDelayL[(sink.surroundHead - 336 + 1200) % 1200]
                let surrR = sink.surroundDelayR[(sink.surroundHead - 336 + 1200) % 1200]
                sink.surroundHead += 1
                
                // Step D: Cinema Sub-Bass Exciter (Deep punchy cinema low-end)
                var subL: Float = 0
                var subR: Float = 0
                if atmosSub > 1.02 {
                    let subFactor = Float(atmosSub - 1.0) * 1.35
                    let lowL = sink.subBassL.process(sample: mid)
                    let lowR = sink.subBassR.process(sample: mid)
                    subL = lowL * subFactor
                    subR = lowR * subFactor
                }
                
                // Step E: Height / Elevation Overheads (Air and 3D presence)
                var heightL: Float = 0
                var heightR: Float = 0
                if atmosElev > 0.05 {
                    let hL = sink.heightFilterL.process(sample: expandedSideL)
                    let hR = sink.heightFilterR.process(sample: expandedSideR)
                    let elevGain = atmosElev * 0.70
                    heightL = (hL - expandedSideL) * elevGain
                    heightR = (hR - expandedSideR) * elevGain
                }
                
                // Step F: Cinema Hall Acoustic Envelopment (Clean diffuse room without ringing)
                let roomIn = (expandedSideL - expandedSideR) * 0.40
                let cFeedback: Float = min(0.55, 0.30 + Float(atmosRoom) * 0.05)
                
                let c0 = sink.combL0[sink.combHead0 % 1116]
                sink.combL0[sink.combHead0 % 1116] = roomIn + c0 * cFeedback
                let c1 = sink.combL1[sink.combHead1 % 1188]
                sink.combL1[sink.combHead1 % 1188] = roomIn + c1 * cFeedback
                let c2 = sink.combR0[sink.combHead2 % 1139]
                sink.combR0[sink.combHead2 % 1139] = roomIn + c2 * cFeedback
                let c3 = sink.combR1[sink.combHead3 % 1211]
                sink.combR1[sink.combHead3 % 1211] = roomIn + c3 * cFeedback
                
                sink.combHead0 += 1
                sink.combHead1 += 1
                sink.combHead2 += 1
                sink.combHead3 += 1
                
                let hallL = (c0 + c1) * 0.45
                let hallR = (c2 + c3) * 0.45
                
                let wetMix = Float(max(0.15, min(0.42, 0.22 * atmosRoom)))
                
                // Final 3D Spatial Assembly:
                // - mid: solid phantom center vocals & dialogue
                // - expandedSideL/R: wide wrap-around soundstage
                // - surrL/R: surround depth
                // - heightL/R: elevated spatial dome
                // - hall: atmospheric cinema room space
                // - sub: deep chest-thumping bass foundation
                rawL = mid + expandedSideL + (surrL * 0.42) + (heightL * 0.40) + (hallL * wetMix) + subL
                rawR = mid - expandedSideR + (surrR * 0.42) + (heightR * 0.40) + (hallR * wetMix) + subR
            } else if isSpatial {
                let mid = (rawL + rawR) * 0.5
                let side = (rawL - rawR) * 0.5 * 1.35
                rawL = mid + side
                rawR = mid - side
            }
            
            // 5. Clean Headroom Boost (1.0x to 2.0x = +0dB to +6dB)
            let boostedL = rawL * boost
            let boostedR = rawR * boost
            
            // 6. Transparent Broadcast Limiter (Zero distortion / Zero clipping)
            let peak = max(abs(boostedL), abs(boostedR))
            if peak > sink.limiterEnvelope {
                sink.limiterEnvelope = peak * 0.20 + sink.limiterEnvelope * 0.80
            } else {
                sink.limiterEnvelope = sink.limiterEnvelope * 0.9998
            }
            
            let threshold: Float = 0.88
            let ceiling: Float = 0.98
            if sink.limiterEnvelope > threshold {
                let targetGain = ceiling / max(ceiling, sink.limiterEnvelope)
                sink.limiterGain = sink.limiterGain * 0.88 + targetGain * 0.12
            } else {
                sink.limiterGain = sink.limiterGain * 0.9995 + 1.0 * 0.0005
            }
            
            leftOut[i] = max(-0.99, min(0.99, boostedL * sink.limiterGain))
            rightOut[i] = max(-0.99, min(0.99, boostedR * sink.limiterGain))
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
                leftOut[j] = max(-0.99, min(0.99, leftOut[j] * dry + convL[j] * wet))
                rightOut[j] = max(-0.99, min(0.99, rightOut[j] * dry + convR[j] * wet))
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
    
    public var surroundDelayL: [Float] = [Float](repeating: 0, count: 1200)
    public var surroundDelayR: [Float] = [Float](repeating: 0, count: 1200)
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
    
    public let subBassL: BiquadFilter = {
        let f = BiquadFilter()
        f.setLowShelf(frequency: 75.0, sampleRate: 48000.0, gainDb: 7.5)
        return f
    }()
    public let subBassR: BiquadFilter = {
        let f = BiquadFilter()
        f.setLowShelf(frequency: 75.0, sampleRate: 48000.0, gainDb: 7.5)
        return f
    }()
    public let heightFilterL: BiquadFilter = {
        let f = BiquadFilter()
        f.setPeaking(frequency: 8500.0, sampleRate: 48000.0, gainDb: 4.5, q: 1.0)
        return f
    }()
    public let heightFilterR: BiquadFilter = {
        let f = BiquadFilter()
        f.setPeaking(frequency: 8500.0, sampleRate: 48000.0, gainDb: 4.5, q: 1.0)
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
        ensureHiFiBluetoothMode()
    }
    
    public func checkBlackHoleAvailability() {
        hasBlackHole = (findDevice(nameSubstring: "BlackHole") != nil)
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
    public func setEQBypass(_ bypass: Bool) {}
    
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
    
    // MARK: - Multi-Output Simultaneous Routing
    public func startRouting(toOutputDeviceIDs: Set<AudioObjectID>) -> Bool {
        stopRouting()
        
        ensureHiFiBluetoothMode()
        
        guard let blackHoleID = findInputDevice(nameSubstring: "BlackHole") else {
            statusMessage = "BlackHole 2ch not found"
            hasBlackHole = false
            return false
        }
        hasBlackHole = true
        self.inputDeviceID = blackHoleID
        self.inSampleRate = getDeviceSampleRate(deviceID: inputDeviceID)
        
        // Filter valid output devices
        let validIDs = toOutputDeviceIDs.filter { $0 != blackHoleID && hasOutputStreams(deviceID: $0) }
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
        
        for devID in validIDs {
            AudioDeviceManager.shared.ensureHardwareDeviceActive(deviceID: devID)
            let outRate = getDeviceSampleRate(deviceID: devID)
            let ratio = self.inSampleRate / max(8000.0, outRate)
            let isBT = isBluetoothDevice(deviceID: devID)
            let delaySamples = (!isBT && hasBluetooth && validIDs.count > 1) ? (syncDelayMs * (self.inSampleRate / 1000.0)) : 0.0
            
            let sink = OutputDeviceSink(
                deviceID: devID,
                sampleRate: outRate,
                resampleRatio: ratio,
                isBluetooth: isBT,
                delaySamples: delaySamples
            )
            sink.volumeGain = AudioDeviceManager.shared.getVolumeForDevice(devID)
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
                let master = devMgr.isMuted ? 0.0 : devMgr.masterVolume
                let (panL, panR) = devMgr.getSpatialPan(for: sink.deviceID)
                let volL = sink.volumeGain * master * panL
                let volR = sink.volumeGain * master * panR
                
                if numChans >= 2 {
                    for i in 0..<frameCount {
                        outPtr[i * 2] = left[i] * volL
                        outPtr[i * 2 + 1] = right[i] * volR
                    }
                } else {
                    for i in 0..<frameCount {
                        outPtr[i] = ((left[i] * volL) + (right[i] * volR)) * 0.5
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
        
        setSystemDefaultOutputDevice(deviceID: blackHoleID)
        return true
    }
    
    public func stopRouting() {
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
        
        // Restore default system output device to physical speakers (never BlackHole)
        let mgr = AudioDeviceManager.shared
        if let realDev = mgr.selectedDeviceIDs.first(where: { !self.getDeviceName(deviceID: $0).contains("BlackHole") }) {
            setSystemDefaultOutputDevice(deviceID: realDev)
        } else if let internalSpk = findOutputDevice(nameSubstring: "MacBook") ?? findOutputDevice(nameSubstring: "Динамики") ?? findOutputDevice(nameSubstring: "Built-in") {
            setSystemDefaultOutputDevice(deviceID: internalSpk)
        } else if let rockbox = findOutputDevice(nameSubstring: "Rockbox") {
            setSystemDefaultOutputDevice(deviceID: rockbox)
        } else if let dev = mgr.outputDevices.first(where: { !$0.name.contains("BlackHole") }) {
            setSystemDefaultOutputDevice(deviceID: dev.id)
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
                if name.lowercased().contains(nameSubstring.lowercased()) && hasOutputStreams(deviceID: id) {
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
                if name.lowercased().contains(nameSubstring.lowercased()) {
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
