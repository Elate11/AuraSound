import SwiftUI

// MARK: - macOS 27 Liquid Glass Studio Frequency Curve Graph
public struct M3ExpEQCurveView: View {
    let gains: [Double]
    let isEnabled: Bool
    
    public init(gains: [Double], isEnabled: Bool = true) {
        self.gains = gains
        self.isEnabled = isEnabled
    }
    
    private let frequencies = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    
    public var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let midY = height / 2
            
            ZStack {
                // Frosted Glass Grid Background
                gridBackground(width: width, height: height, midY: midY)
                
                if isEnabled {
                    // Liquid Neon Fill Gradient
                    curvePath(width: width, height: height, midY: midY, closed: true)
                        .fill(
                            LinearGradient(
                                colors: [
                                    LiquidGlass.cyan.opacity(0.32),
                                    LiquidGlass.electricBlue.opacity(0.12),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    // Liquid Glass Specular Stroke
                    curvePath(width: width, height: height, midY: midY, closed: false)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    LiquidGlass.cyan,
                                    LiquidGlass.electricBlue,
                                    LiquidGlass.purple
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .round)
                        )
                        .shadow(color: LiquidGlass.cyan.opacity(0.6), radius: 6, x: 0, y: 0)
                    
                    // Glowing Glass Node Points
                    ForEach(0..<gains.count, id: \.self) { i in
                        let pt = pointFor(index: i, width: width, height: height, midY: midY)
                        ZStack {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 5, height: 5)
                            Circle()
                                .stroke(LiquidGlass.cyan, lineWidth: 1.5)
                                .frame(width: 8, height: 8)
                        }
                        .shadow(color: LiquidGlass.cyan.opacity(0.9), radius: 4, x: 0, y: 0)
                        .position(pt)
                    }
                } else {
                    // Bypass Flat Line
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: midY))
                        p.addLine(to: CGPoint(x: width, y: midY))
                    }
                    .stroke(Color.white.opacity(0.20), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                }
            }
        }
    }
    
    private func gridBackground(width: CGFloat, height: CGFloat, midY: CGFloat) -> some View {
        ZStack {
            // Horizontal 0 dB line
            Path { p in
                p.move(to: CGPoint(x: 0, y: midY))
                p.addLine(to: CGPoint(x: width, y: midY))
            }
            .stroke(Color.white.opacity(0.18), lineWidth: 1)
            
            // ±12 dB reference lines
            Path { p in
                let yPlus12 = midY - (height * 0.5 * (12.0 / 24.0))
                let yMinus12 = midY + (height * 0.5 * (12.0 / 24.0))
                p.move(to: CGPoint(x: 0, y: yPlus12))
                p.addLine(to: CGPoint(x: width, y: yPlus12))
                p.move(to: CGPoint(x: 0, y: yMinus12))
                p.addLine(to: CGPoint(x: width, y: yMinus12))
            }
            .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 0.8, dash: [3, 4]))
            
            // Vertical frequency lines
            ForEach(0..<frequencies.count, id: \.self) { i in
                let x = width * CGFloat(i) / CGFloat(frequencies.count - 1)
                Path { p in
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: height))
                }
                .stroke(Color.white.opacity(0.05), lineWidth: 0.8)
            }
        }
    }
    
    private func pointFor(index: Int, width: CGFloat, height: CGFloat, midY: CGFloat) -> CGPoint {
        guard index < gains.count else { return CGPoint(x: 0, y: midY) }
        let count = max(1, gains.count - 1)
        let x = width * CGFloat(index) / CGFloat(count)
        let gain = gains[index]
        let clamped = max(-24.0, min(24.0, gain))
        let y = midY - (height * 0.45 * CGFloat(clamped / 24.0))
        return CGPoint(x: x, y: y)
    }
    
    private func curvePath(width: CGFloat, height: CGFloat, midY: CGFloat, closed: Bool) -> Path {
        var path = Path()
        guard gains.count >= 2 else { return path }
        
        let pts = (0..<gains.count).map { pointFor(index: $0, width: width, height: height, midY: midY) }
        path.move(to: pts[0])
        
        for i in 0..<(pts.count - 1) {
            let p0 = i > 0 ? pts[i - 1] : pts[i]
            let p1 = pts[i]
            let p2 = pts[i + 1]
            let p3 = i + 2 < pts.count ? pts[i + 2] : p2
            
            let d1 = CGPoint(x: (p2.x - p0.x) * 0.22, y: (p2.y - p0.y) * 0.22)
            let d2 = CGPoint(x: (p3.x - p1.x) * 0.22, y: (p3.y - p1.y) * 0.22)
            
            let c1 = CGPoint(x: p1.x + d1.x, y: p1.y + d1.y)
            let c2 = CGPoint(x: p2.x - d2.x, y: p2.y - d2.y)
            
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        
        if closed {
            path.addLine(to: CGPoint(x: width, y: height))
            path.addLine(to: CGPoint(x: 0, y: height))
            path.closeSubpath()
        }
        return path
    }
}

// MARK: - macOS 27 Liquid Glass 10-Band Graphic Equalizer Faders
public struct M3ExpEqualizerSlidersView: View {
    @ObservedObject var dsp = AudioDSPManager.shared
    
    public init() {}
    
    public var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<dsp.bands.count, id: \.self) { i in
                liquidFaderColumn(index: i)
            }
        }
        .frame(height: 145)
    }
    
    private func liquidFaderColumn(index: Int) -> some View {
        let band = dsp.bands[index]
        return GeometryReader { geo in
            let height = geo.size.height
            let sliderH = height - 28
            let gain = band.gain
            let normalized = (gain + 24.0) / 48.0
            let fillHeight = sliderH * CGFloat(normalized)
            
            VStack(spacing: 3) {
                // Value Text Pill
                Text(String(format: "%+.0f", gain))
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundColor(gain == 0 ? LiquidGlass.textMuted : (gain > 0 ? LiquidGlass.cyan : LiquidGlass.ruby))
                    .frame(height: 12)
                
                // Vertical Frosted Glass Trough
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1.0)
                        )
                    
                    // Liquid Fill Bar
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    gain >= 0 ? LiquidGlass.cyan : LiquidGlass.ruby,
                                    gain >= 0 ? LiquidGlass.electricBlue : LiquidGlass.purple
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: max(6, fillHeight))
                        .shadow(color: (gain >= 0 ? LiquidGlass.cyan : LiquidGlass.ruby).opacity(0.35), radius: 4, x: 0, y: 0)
                    
                    // Frosted Glass Knob Handle
                    Capsule()
                        .fill(Color.white)
                        .frame(width: 18, height: 7)
                        .overlay(
                            Capsule()
                                .stroke(Color.black.opacity(0.2), lineWidth: 0.5)
                        )
                        .shadow(color: Color.black.opacity(0.4), radius: 3, x: 0, y: 1)
                        .offset(y: -(fillHeight - 4))
                }
                .frame(width: 22, height: sliderH)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            let locY = gesture.location.y
                            let percent = max(0.0, min(1.0, Double(1.0 - (locY / sliderH))))
                            let newGain = -24.0 + (percent * 48.0)
                            if index < dsp.bands.count {
                                dsp.bands[index].gain = (newGain * 2.0).rounded() / 2.0
                            }
                        }
                )
                
                // Band Frequency Label
                Text(band.label)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundColor(LiquidGlass.textSecondary)
                    .lineLimit(1)
                    .frame(height: 10)
            }
        }
    }
}

// MARK: - Equalizer Presets Scroll Bar
public struct M3ExpEQPresetChipsView: View {
    @ObservedObject var dsp = AudioDSPManager.shared
    
    public init() {}
    
    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(EQPreset.presets) { preset in
                    let isSelected = dsp.selectedPreset.name == preset.name
                    M3ExpChip(
                        title: preset.name,
                        isSelected: isSelected,
                        icon: preset.icon
                    ) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            dsp.selectedPreset = preset
                            for (i, g) in preset.gains.enumerated() {
                                if i < dsp.bands.count {
                                    dsp.bands[i].gain = g
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }
}
