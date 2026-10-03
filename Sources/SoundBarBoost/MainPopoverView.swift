import SwiftUI
import AppKit
import CoreAudio

// MARK: - Terminal Theme Palette (Retro Phosphor & Cyberpunk TUI)
private enum TermTheme {
    static let bgDark = Color(red: 0.04, green: 0.06, blue: 0.05)
    static let cardBg = Color(red: 0.06, green: 0.10, blue: 0.07)
    static let cardBorder = Color(red: 0.18, green: 0.40, blue: 0.25)
    static let borderSubtle = Color(red: 0.12, green: 0.26, blue: 0.16)
    
    static let green = Color(red: 0.22, green: 0.95, blue: 0.45)
    static let greenBright = Color(red: 0.35, green: 1.0, blue: 0.55)
    static let cyan = Color(red: 0.15, green: 0.88, blue: 1.0)
    static let amber = Color(red: 1.0, green: 0.78, blue: 0.25)
    static let red = Color(red: 1.0, green: 0.35, blue: 0.35)
    static let dimText = Color(red: 0.50, green: 0.70, blue: 0.55)
    static let disabledText = Color(red: 0.30, green: 0.45, blue: 0.35)
    static let buttonBg = Color(red: 0.08, green: 0.15, blue: 0.10)
    static let buttonActiveBg = Color(red: 0.12, green: 0.30, blue: 0.18)
}

// MARK: - Safe ASCII Progress Bar Helper
private func renderAsciiBar(value: Double, maxValue: Double = 1.0, width: Int = 18) -> String {
    guard maxValue > 0, width > 0 else { return "[]" }
    let clamped = Swift.max(0.0, Swift.min(maxValue, value))
    let fraction = clamped / maxValue
    let filled = Swift.max(0, Swift.min(width, Int(round(fraction * Double(width)))))
    let empty = Swift.max(0, width - filled)
    let fillStr = String(repeating: "█", count: filled)
    let emptyStr = String(repeating: "░", count: empty)
    return "[\(fillStr)\(emptyStr)]"
}

// MARK: - Terminal Card Container with Box-Drawing ASCII Frames
private struct TermCard<Content: View>: View {
    let title: String
    let badge: String?
    let content: Content
    
    init(title: String, badge: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.badge = badge
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Box Top Border
            HStack(spacing: 3) {
                Text("┌──[")
                    .foregroundColor(TermTheme.cardBorder)
                Text(title)
                    .foregroundColor(TermTheme.green)
                    .fontWeight(.bold)
                Text("]")
                    .foregroundColor(TermTheme.cardBorder)
                
                if let badge = badge {
                    Text("[")
                        .foregroundColor(TermTheme.cardBorder)
                    Text(badge)
                        .foregroundColor(TermTheme.cyan)
                        .fontWeight(.semibold)
                    Text("]")
                        .foregroundColor(TermTheme.cardBorder)
                }
                
                Text(String(repeating: "─", count: 8))
                    .foregroundColor(TermTheme.cardBorder)
                
                Spacer()
                Text("┐")
                    .foregroundColor(TermTheme.cardBorder)
            }
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            
            // Content
            content
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            
            // Box Bottom Border
            HStack {
                Text("└" + String(repeating: "─", count: 34))
                    .foregroundColor(TermTheme.cardBorder)
                Spacer()
                Text("┘")
                    .foregroundColor(TermTheme.cardBorder)
            }
            .font(.system(size: 11, weight: .bold, design: .monospaced))
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(TermTheme.cardBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(TermTheme.borderSubtle, lineWidth: 1)
                )
        )
    }
}

// MARK: - Terminal ASCII Button
private struct TermButton: View {
    let title: String
    var isActive: Bool = false
    var color: Color = TermTheme.green
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text("[ \(title) ]")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(isActive ? TermTheme.bgDark : color)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isActive ? color : TermTheme.buttonBg)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(color.opacity(isActive ? 1.0 : 0.6), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Draggable Device Radar Badge
private struct DeviceRadarBadge: View {
    let name: String
    let isSelected: Bool
    let isRouting: Bool
    let onSelect: () -> Void
    let onDrag: (CGPoint) -> Void
    
    var body: some View {
        HStack(spacing: 2) {
            Text("[")
                .foregroundColor(isSelected ? TermTheme.amber : (isRouting ? TermTheme.green : TermTheme.dimText))
            Text(name.uppercased())
                .foregroundColor(isSelected ? TermTheme.bgDark : (isRouting ? TermTheme.greenBright : TermTheme.dimText))
            Text("]")
                .foregroundColor(isSelected ? TermTheme.amber : (isRouting ? TermTheme.green : TermTheme.dimText))
        }
        .font(.system(size: 9.5, weight: .black, design: .monospaced))
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(isSelected ? TermTheme.amber : (isRouting ? TermTheme.buttonBg : Color.black.opacity(0.85)))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(isSelected ? TermTheme.amber : (isRouting ? TermTheme.green.opacity(0.8) : TermTheme.borderSubtle), lineWidth: isSelected ? 1.5 : 1)
                )
        )
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("radarGrid"))
                .onChanged { val in
                    onSelect()
                    let dragDist = sqrt(val.translation.width * val.translation.width + val.translation.height * val.translation.height)
                    if dragDist > 1.5 {
                        onDrag(val.location)
                    }
                }
        )
    }
}

// MARK: - Interactive 2D Soundstage Minimap View (Physical Output Devices)
private struct SoundstageMinimapView: View {
    @ObservedObject var devManager = AudioDeviceManager.shared
    
    private let maxDistanceMeters: Double = 5.0
    
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let cx = w / 2.0
            let cy = h / 2.0
            let maxR = Swift.min(w / 2.0 - 24, h / 2.0 - 18)
            
            ZStack {
                radarCanvas(cx: cx, cy: cy, maxR: maxR)
                
                Text("+")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(TermTheme.greenBright)
                    .position(x: cx, y: cy)
                
                deviceNodes(cx: cx, cy: cy, maxR: maxR)
            }
            .coordinateSpace(name: "radarGrid")
            .contentShape(Rectangle())
            .gesture(
                DragGesture(coordinateSpace: .named("radarGrid"))
                    .onChanged { val in
                        let activeID = devManager.selectedSpatialDeviceID != 0 ? devManager.selectedSpatialDeviceID : (devManager.outputDevices.first?.id ?? 0)
                        if activeID != 0 {
                            updatePosition(for: activeID, location: val.location, cx: cx, cy: cy, maxR: maxR)
                        }
                    }
            )
        }
        .frame(height: 215)
        .background(Color.black.opacity(0.50))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(TermTheme.borderSubtle, lineWidth: 1))
    }
    
    private func radarCanvas(cx: CGFloat, cy: CGFloat, maxR: CGFloat) -> some View {
        Canvas { context, size in
            let center = CGPoint(x: cx, y: cy)
            
            let rings: [Double] = [1.0, 2.5, 5.0]
            for ringDist in rings {
                let r = CGFloat(ringDist / maxDistanceMeters) * maxR
                let rect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
                context.stroke(
                    Path(ellipseIn: rect),
                    with: .color(TermTheme.cardBorder.opacity(0.40)),
                    lineWidth: 1
                )
            }
            
            var hPath = Path()
            hPath.move(to: CGPoint(x: cx - maxR - 8, y: cy))
            hPath.addLine(to: CGPoint(x: cx + maxR + 8, y: cy))
            context.stroke(hPath, with: .color(TermTheme.borderSubtle), lineWidth: 1)
            
            var vPath = Path()
            vPath.move(to: CGPoint(x: cx, y: cy - maxR - 8))
            vPath.addLine(to: CGPoint(x: cx, y: cy + maxR + 8))
            context.stroke(vPath, with: .color(TermTheme.borderSubtle), lineWidth: 1)
            
            let activeID = devManager.selectedSpatialDeviceID != 0 ? devManager.selectedSpatialDeviceID : (devManager.outputDevices.first?.id ?? 0)
            if activeID != 0 {
                let pos = devManager.getSpatialPosition(for: activeID)
                let rad = CGFloat(pos.angle * .pi / 180.0)
                let r = CGFloat(Swift.min(5.0, Swift.max(0.5, pos.distance)) / maxDistanceMeters) * maxR
                let px = cx + sin(rad) * r
                let py = cy - cos(rad) * r
                
                var selLine = Path()
                selLine.move(to: center)
                selLine.addLine(to: CGPoint(x: px, y: py))
                context.stroke(
                    selLine,
                    with: .color(TermTheme.amber.opacity(0.65)),
                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                )
            }
        }
    }
    
    private func deviceNodes(cx: CGFloat, cy: CGFloat, maxR: CGFloat) -> some View {
        ForEach(devManager.outputDevices) { device in
            let isSelected = (devManager.selectedSpatialDeviceID == device.id || (devManager.selectedSpatialDeviceID == 0 && device.id == devManager.outputDevices.first?.id))
            let isRouting = devManager.selectedDeviceIDs.contains(device.id)
            let pos = devManager.getSpatialPosition(for: device.id)
            let rad = CGFloat(pos.angle * .pi / 180.0)
            let r = CGFloat(Swift.min(5.0, Swift.max(0.5, pos.distance)) / maxDistanceMeters) * maxR
            let px = cx + sin(rad) * r
            let py = cy - cos(rad) * r
            
            DeviceRadarBadge(
                name: device.shortName,
                isSelected: isSelected,
                isRouting: isRouting,
                onSelect: {
                    devManager.selectedSpatialDeviceID = device.id
                },
                onDrag: { loc in
                    updatePosition(for: device.id, location: loc, cx: cx, cy: cy, maxR: maxR)
                }
            )
            .position(x: px, y: py)
        }
    }
    
    private func updatePosition(for deviceID: AudioDeviceID, location: CGPoint, cx: CGFloat, cy: CGFloat, maxR: CGFloat) {
        guard deviceID != 0 else { return }
        
        let dx = Double(location.x - cx)
        let dy = Double(location.y - cy)
        let distPx = sqrt(dx * dx + dy * dy)
        let clampedDistPx = Swift.max(8.0, Swift.min(Double(maxR), distPx))
        let distance = Swift.max(0.5, Swift.min(5.0, (clampedDistPx / Double(maxR)) * 5.0))
        let distanceRounded = round(distance * 10.0) / 10.0
        
        let rad = atan2(dx, -dy)
        var deg = round(rad * 180.0 / .pi)
        if deg > 180 { deg -= 360 }
        if deg < -180 { deg += 360 }
        
        devManager.setSpatialPosition(for: deviceID, angle: deg, distance: distanceRounded)
    }
}

// MARK: - Main ASCII TUI Popover View
public struct MainPopoverView: View {
    @ObservedObject var devManager = AudioDeviceManager.shared
    @ObservedObject var dsp = AudioDSPManager.shared
    @ObservedObject var engine = RealAudioEngine.shared
    @ObservedObject var calibrator = AcousticAutoCalibrator.shared
    @ObservedObject var viper = ViperDSPManager.shared
    
    public var customHeight: CGFloat? = nil
    
    public init(customHeight: CGFloat? = nil) {
        self.customHeight = customHeight
    }
    
    public var body: some View {
        ZStack {
            // Dark CRT Terminal Canvas
            TermTheme.bgDark
                .ignoresSafeArea()
            
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 10) {
                    asciiLogoHeader
                    
                    realTimeAsciiEqualizerSection
                    
                    masterAndRoutingSection
                    
                    soundBoosterSection
                    
                    dolbyAtmosSpatialSection
                    
                    viperEngineSection
                    
                    dspModulesSection
                    
                    equalizerSection
                    
                    terminalFooterSection
                }
                .padding(12)
            }
        }
        .frame(width: 450, height: customHeight ?? 680)
        .colorScheme(.dark)
        .onAppear {
            engine.checkBlackHoleAvailability()
        }
    }
    
    // MARK: - ASCII Banner & Engine Power Switch
    private var asciiLogoHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("█▀█ █ █ █▀▄ █▀█ █▀ █▀█ █ █ █▄ █ █▀▄")
                        .font(.system(size: 9.5, weight: .black, design: .monospaced))
                        .foregroundColor(TermTheme.greenBright)
                    Text("█▀█ █▄█ █▀▄ █▀█ ▄█ █▄█ █▄█ █ ▀█ █▄▀")
                        .font(.system(size: 9.5, weight: .black, design: .monospaced))
                        .foregroundColor(TermTheme.green)
                }
                
                Spacer()
                
                // Live Routing Engine Switch (No Emojis)
                Button(action: {
                    if engine.isRoutingActive {
                        engine.stopRouting()
                    } else {
                        _ = engine.startRouting(toOutputDeviceIDs: devManager.selectedDeviceIDs)
                    }
                }) {
                    HStack(spacing: 4) {
                        Text(engine.isRoutingActive ? "[ ENGINE: RUNNING ]" : "[ ENGINE: OFF ]")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(engine.isRoutingActive ? TermTheme.green : TermTheme.amber)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(engine.isRoutingActive ? Color(red: 0.05, green: 0.22, blue: 0.1) : Color(red: 0.22, green: 0.12, blue: 0.05))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 3)
                                            .stroke(engine.isRoutingActive ? TermTheme.green : TermTheme.amber, lineWidth: 1)
                                    )
                            )
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 2)
            
            // Status bar
            HStack(spacing: 10) {
                Text(engine.hasBlackHole ? "[BH2CH: OK]" : "[BH2CH: MISSING]")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(engine.hasBlackHole ? TermTheme.green : TermTheme.red)
                
                Spacer()
                
                Text("SINKS: \(devManager.selectedDeviceIDs.count) ACTIVE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(TermTheme.cyan)
            }
        }
    }
    
    // MARK: - Real-Time ASCII Spectrum Equalizer (Live Dancing Bars)
    private var realTimeAsciiEqualizerSection: some View {
        let leftPct = Int(dsp.liveLeftLevel * 100)
        let rightPct = Int(dsp.liveRightLevel * 100)
        let totalRows = 6
        let labels = ["32", "64", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
        
        return TermCard(title: "00: LIVE ASCII SPECTRUM EQ", badge: "REAL-TIME") {
            VStack(alignment: .leading, spacing: 5) {
                // Peak Stereo VU Meters (Clean, No Test Ping Button)
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Text("L")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(TermTheme.green)
                        Text(renderAsciiBar(value: Double(dsp.liveLeftLevel), maxValue: 1.0, width: 10))
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .foregroundColor(leftPct > 85 ? TermTheme.red : TermTheme.green)
                        Text("\(leftPct)%")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundColor(TermTheme.dimText)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Text("R")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(TermTheme.green)
                        Text(renderAsciiBar(value: Double(dsp.liveRightLevel), maxValue: 1.0, width: 10))
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .foregroundColor(rightPct > 85 ? TermTheme.red : TermTheme.green)
                        Text("\(rightPct)%")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundColor(TermTheme.dimText)
                    }
                }
                
                // Vertical ASCII Frequency Columns Matrix (7 Rows x 10 Bands)
                VStack(spacing: 2) {
                    ForEach((0..<totalRows).reversed(), id: \.self) { rowIndex in
                        HStack(spacing: 0) {
                            // Row dB reference
                            let dbLabel = rowIndex == 5 ? "+12" : (rowIndex == 3 ? "  0" : (rowIndex == 0 ? "-12" : "   "))
                            Text(dbLabel)
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundColor(TermTheme.disabledText)
                                .frame(width: 24, alignment: .leading)
                            
                            // 10 Frequency Columns
                            ForEach(0..<min(10, dsp.liveSpectrum.count), id: \.self) { bandIdx in
                                let bandVal = Double(dsp.liveSpectrum[bandIdx])
                                let activeBlocks = Int(round(bandVal * Double(totalRows)))
                                let isLit = (rowIndex < activeBlocks)
                                
                                Text(isLit ? "██" : "··")
                                    .font(.system(size: 10, weight: .black, design: .monospaced))
                                    .foregroundColor(
                                        isLit ?
                                        (rowIndex >= 5 ? TermTheme.red : (rowIndex >= 4 ? TermTheme.amber : TermTheme.green)) :
                                        TermTheme.disabledText.opacity(0.35)
                                    )
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.35))
                
                // Frequency band axis labels
                HStack(spacing: 0) {
                    Text("   ")
                        .frame(width: 24)
                    ForEach(0..<10, id: \.self) { idx in
                        Text(labels[idx])
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundColor(TermTheme.dimText)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
    
    // MARK: - Section 01: Master Audio & Output Device Routing (Unified)
    private var masterAndRoutingSection: some View {
        TermCard(title: "01: MASTER & OUTPUT ROUTING", badge: "\(Int(devManager.masterVolume * 100))%") {
            VStack(alignment: .leading, spacing: 8) {
                masterLevelRow
                
                Divider()
                    .background(TermTheme.borderSubtle)
                
                outputSinksList
                
                if devManager.selectedDeviceIDs.count > 1 {
                    Divider()
                        .background(TermTheme.borderSubtle)
                    
                    syncDelayRow
                }
            }
        }
    }
    
    private var masterLevelRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("MASTER LEVEL: \(Int(devManager.masterVolume * 100))%")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(devManager.isMuted ? TermTheme.red : TermTheme.green)
                
                Spacer()
                
                Text(renderAsciiBar(value: Double(devManager.masterVolume), maxValue: 1.0, width: 16))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(devManager.isMuted ? TermTheme.disabledText : TermTheme.green)
            }
            
            Slider(
                value: Binding(
                    get: { Double(devManager.masterVolume) },
                    set: { devManager.setVolume(Float($0)) }
                ),
                in: 0.0...1.0
            )
            .accentColor(TermTheme.green)
            
            HStack(spacing: 5) {
                TermButton(
                    title: devManager.isMuted ? "UNMUTE" : "MUTE",
                    isActive: devManager.isMuted,
                    color: devManager.isMuted ? TermTheme.red : TermTheme.amber
                ) {
                    devManager.setMute(!devManager.isMuted)
                }
                
                TermButton(title: "-5%") {
                    devManager.setVolume(devManager.masterVolume - 0.05)
                }
                
                TermButton(title: "+5%") {
                    devManager.setVolume(devManager.masterVolume + 0.05)
                }
                
                Spacer()
                
                TermButton(title: "50%", isActive: abs(devManager.masterVolume - 0.5) < 0.03) {
                    devManager.setVolume(0.50)
                }
                
                TermButton(title: "100%", isActive: devManager.masterVolume >= 0.98) {
                    devManager.setVolume(1.00)
                }
            }
        }
    }
    
    private var outputSinksList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("──[ OUTPUT SINKS ROUTING & LEVELS ]")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(TermTheme.dimText)
                
                Spacer()
                
                Text("\(devManager.selectedDeviceIDs.count)/\(devManager.outputDevices.count) ACTIVE")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(TermTheme.cyan)
            }
            
            ForEach(devManager.outputDevices) { device in
                let isSelected = devManager.selectedDeviceIDs.contains(device.id)
                let vol = devManager.getVolumeForDevice(device.id)
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Button(action: {
                            devManager.toggleDeviceSelection(device)
                        }) {
                            Text(isSelected ? "[X]" : "[ ]")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(isSelected ? TermTheme.greenBright : TermTheme.dimText)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            devManager.toggleDeviceSelection(device)
                        }) {
                            Text(device.name)
                                .font(.system(size: 10.5, weight: isSelected ? .bold : .medium, design: .monospaced))
                                .foregroundColor(isSelected ? TermTheme.green : TermTheme.dimText)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        
                        Spacer()
                        
                        Text("[\(device.typeDescription)]")
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .foregroundColor(TermTheme.disabledText)
                        
                        Text("\(Int(vol * 100))%")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(isSelected ? TermTheme.green : TermTheme.disabledText)
                    }
                    
                    HStack(spacing: 6) {
                        Text(renderAsciiBar(value: Double(vol), maxValue: 1.0, width: 12))
                            .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                            .foregroundColor(isSelected ? TermTheme.green : TermTheme.disabledText)
                        
                        Slider(
                            value: Binding(
                                get: { Double(devManager.getVolumeForDevice(device.id)) },
                                set: { devManager.setVolumeForDevice(device.id, volume: Float($0)) }
                            ),
                            in: 0.0...1.0
                        )
                        .accentColor(isSelected ? TermTheme.green : TermTheme.disabledText)
                        
                        TermButton(title: "-") {
                            devManager.setVolumeForDevice(device.id, volume: vol - 0.05)
                        }
                        TermButton(title: "+") {
                            devManager.setVolumeForDevice(device.id, volume: vol + 0.05)
                        }
                    }
                }
                .padding(.vertical, 2)
                
                if device.id != devManager.outputDevices.last?.id {
                    Divider()
                        .background(TermTheme.borderSubtle.opacity(0.5))
                }
            }
        }
    }
    
    private var syncDelayRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("SYNC DELAY: \(Int(dsp.syncDelayMs)) ms")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(TermTheme.cyan)
                
                Spacer()
                
                TermButton(title: "-10ms", color: TermTheme.cyan) {
                    dsp.syncDelayMs = Swift.max(0.0, dsp.syncDelayMs - 10.0)
                }
                
                TermButton(title: "+10ms", color: TermTheme.cyan) {
                    dsp.syncDelayMs = Swift.min(600.0, dsp.syncDelayMs + 10.0)
                }
                
                TermButton(
                    title: calibrator.isCalibrating ? "CALIBRATING..." : "AUTO-CALIBRATE",
                    isActive: calibrator.isCalibrating,
                    color: TermTheme.amber
                ) {
                    calibrator.startAutoCalibration()
                }
            }
            
            if calibrator.isCalibrating || calibrator.measuredDelayMs != nil {
                Text("> \(calibrator.statusMessage)")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundColor(calibrator.isCalibrating ? TermTheme.amber : TermTheme.green)
            }
        }
        .padding(.top, 2)
    }
    
    // MARK: - Section 02: Sound Booster & Overdrive (100% - 200%)
    private var soundBoosterSection: some View {
        let pct = dsp.boostPercentage
        let isOverdrive = dsp.boostMultiplier > 1.01
        let boostDb = isOverdrive ? String(format: "+%.1f dB", 20.0 * log10(dsp.boostMultiplier)) : "0.0 dB (clean)"
        let meterColor = pct > 165 ? TermTheme.red : (pct > 125 ? TermTheme.amber : TermTheme.cyan)
        
        return TermCard(title: "02: SOUND BOOSTER / PREAMP", badge: "\(pct)%") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Gain: \(pct)% [\(boostDb)]")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(meterColor)
                    
                    Spacer()
                    
                    Text(renderAsciiBar(value: dsp.boostMultiplier, maxValue: 2.0, width: 18))
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(meterColor)
                }
                
                Slider(
                    value: $dsp.boostMultiplier,
                    in: 1.0...2.0,
                    step: 0.05
                )
                .accentColor(meterColor)
                
                HStack(spacing: 5) {
                    TermButton(title: "100%", isActive: abs(dsp.boostMultiplier - 1.0) < 0.02, color: TermTheme.cyan) {
                        dsp.boostMultiplier = 1.0
                    }
                    TermButton(title: "125%", isActive: abs(dsp.boostMultiplier - 1.25) < 0.02, color: TermTheme.cyan) {
                        dsp.boostMultiplier = 1.25
                    }
                    TermButton(title: "150%", isActive: abs(dsp.boostMultiplier - 1.50) < 0.02, color: TermTheme.amber) {
                        dsp.boostMultiplier = 1.50
                    }
                    TermButton(title: "175%", isActive: abs(dsp.boostMultiplier - 1.75) < 0.02, color: TermTheme.amber) {
                        dsp.boostMultiplier = 1.75
                    }
                    TermButton(title: "200%", isActive: abs(dsp.boostMultiplier - 2.00) < 0.02, color: TermTheme.red) {
                        dsp.boostMultiplier = 2.00
                    }
                }
            }
        }
    }
    
    // MARK: - Section 03: Dolby Atmos 3D Soundstage & Positioning
    private var dolbyAtmosSpatialSection: some View {
        let activeID = devManager.selectedSpatialDeviceID != 0 ? devManager.selectedSpatialDeviceID : (devManager.outputDevices.first?.id ?? 0)
        let activeDevice = devManager.outputDevices.first { $0.id == activeID } ?? devManager.outputDevices.first
        
        return TermCard(
            title: "03: DOLBY ATMOS 3D SOUNDSTAGE",
            badge: dsp.isAtmosEnabled ? "ATMOS: ON" : "BYPASS"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                // Atmos Master Toggle & Mode Presets
                HStack(spacing: 5) {
                    TermButton(
                        title: dsp.isAtmosEnabled ? "DOLBY ATMOS: ON" : "DOLBY ATMOS: OFF",
                        isActive: dsp.isAtmosEnabled,
                        color: dsp.isAtmosEnabled ? TermTheme.greenBright : TermTheme.dimText
                    ) {
                        dsp.isAtmosEnabled.toggle()
                    }
                    
                    Spacer()
                    
                    TermButton(
                        title: "CINEMA 3D",
                        isActive: dsp.isAtmosEnabled && dsp.atmosMode == "CINEMA",
                        color: TermTheme.cyan
                    ) {
                        dsp.isAtmosEnabled = true
                        dsp.selectAtmosMode("CINEMA")
                    }
                    
                    TermButton(
                        title: "MUSIC HIFI",
                        isActive: dsp.isAtmosEnabled && dsp.atmosMode == "MUSIC",
                        color: TermTheme.green
                    ) {
                        dsp.isAtmosEnabled = true
                        dsp.selectAtmosMode("MUSIC")
                    }
                    
                    TermButton(
                        title: "360 SPATIAL",
                        isActive: dsp.isAtmosEnabled && dsp.atmosMode == "360 SPATIAL",
                        color: TermTheme.amber
                    ) {
                        dsp.isAtmosEnabled = true
                        dsp.selectAtmosMode("360 SPATIAL")
                    }
                }
                
                // Atmos Psychoacoustic Controls (Room, Width, Sub-Bass)
                if dsp.isAtmosEnabled {
                    atmosAcousticParameters
                }
                
                // Interactive 2D Soundstage Minimap (Drag or tap physical output devices)
                SoundstageMinimapView()
                
                // Device Selector Pills
                deviceSelectorPills(activeID: activeID)
                
                // Configurator for Selected Device
                if let dev = activeDevice {
                    devicePositionConfiguratorCard(device: dev)
                }
            }
        }
    }
    
    private var atmosAcousticParameters: some View {
        VStack(spacing: 4) {
            HStack {
                Text("SURROUND WIDTH: \(Int(dsp.atmosSurroundWidth * 100))%")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(TermTheme.cyan)
                Spacer()
                Slider(value: $dsp.atmosSurroundWidth, in: 1.0...2.0, step: 0.05)
                    .frame(width: 170)
                    .accentColor(TermTheme.cyan)
            }
            
            HStack {
                Text("ROOM AMBIENCE: \(String(format: "%.1f", dsp.atmosRoomSize))x")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(TermTheme.green)
                Spacer()
                Slider(value: $dsp.atmosRoomSize, in: 0.5...2.0, step: 0.05)
                    .frame(width: 170)
                    .accentColor(TermTheme.green)
            }
            
            HStack {
                Text("CINEMA SUB-BASS: \(Int(dsp.atmosBassExciter * 100))%")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(TermTheme.amber)
                Spacer()
                Slider(value: $dsp.atmosBassExciter, in: 1.0...1.8, step: 0.05)
                    .frame(width: 170)
                    .accentColor(TermTheme.amber)
            }
        }
        .padding(6)
        .background(Color.black.opacity(0.35))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(TermTheme.borderSubtle, lineWidth: 1))
    }
    
    private func deviceSelectorPills(activeID: AudioDeviceID) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(devManager.outputDevices) { dev in
                    let pos = devManager.getSpatialPosition(for: dev.id)
                    let isSel = (dev.id == activeID)
                    TermButton(
                        title: "\(dev.shortName.uppercased()) (\(Int(pos.angle))°)",
                        isActive: isSel,
                        color: isSel ? TermTheme.amber : TermTheme.dimText
                    ) {
                        devManager.selectedSpatialDeviceID = dev.id
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
    
    // MARK: - Device Position & Distance Configurator Card
    private func devicePositionConfiguratorCard(device: AudioDevice) -> some View {
        let pos = devManager.getSpatialPosition(for: device.id)
        let pan = devManager.getSpatialPan(for: device.id)
        let flightMs = pos.distance * 2.91
        let isRouting = devManager.selectedDeviceIDs.contains(device.id)
        
        return VStack(alignment: .leading, spacing: 6) {
            // Device Header & Output Switch
            HStack {
                Text("DEVICE: \(device.name.uppercased())")
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundColor(TermTheme.amber)
                    .lineLimit(1)
                
                Spacer()
                
                TermButton(
                    title: isRouting ? "ACTIVE SINK" : "DISABLED",
                    isActive: isRouting,
                    color: isRouting ? TermTheme.greenBright : TermTheme.disabledText
                ) {
                    devManager.toggleDeviceSelection(device)
                }
            }
            
            // 1. Distance Setting (0.5m to 5.0m)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Distance: \(String(format: "%.1f", pos.distance)) m")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(TermTheme.cyan)
                    Spacer()
                    HStack(spacing: 4) {
                        TermButton(title: "1.0m", color: TermTheme.cyan) {
                            devManager.setSpatialPosition(for: device.id, angle: pos.angle, distance: 1.0)
                        }
                        TermButton(title: "2.0m", color: TermTheme.cyan) {
                            devManager.setSpatialPosition(for: device.id, angle: pos.angle, distance: 2.0)
                        }
                        TermButton(title: "3.0m", color: TermTheme.cyan) {
                            devManager.setSpatialPosition(for: device.id, angle: pos.angle, distance: 3.0)
                        }
                        TermButton(title: "4.0m", color: TermTheme.cyan) {
                            devManager.setSpatialPosition(for: device.id, angle: pos.angle, distance: 4.0)
                        }
                    }
                }
                Slider(
                    value: Binding(
                        get: { devManager.getSpatialPosition(for: device.id).distance },
                        set: { devManager.setSpatialPosition(for: device.id, angle: pos.angle, distance: $0) }
                    ),
                    in: 0.5...5.0,
                    step: 0.1
                )
                .accentColor(TermTheme.cyan)
            }
            
            // 2. Azimuth Direction Angle (-180° to +180°)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Direction Angle: \(Int(pos.angle))°")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(TermTheme.green)
                    Spacer()
                    HStack(spacing: 4) {
                        TermButton(title: "-15°") {
                            devManager.setSpatialPosition(for: device.id, angle: Swift.max(-180.0, pos.angle - 15.0), distance: pos.distance)
                        }
                        TermButton(title: "0°") {
                            devManager.setSpatialPosition(for: device.id, angle: 0.0, distance: pos.distance)
                        }
                        TermButton(title: "+15°") {
                            devManager.setSpatialPosition(for: device.id, angle: Swift.min(180.0, pos.angle + 15.0), distance: pos.distance)
                        }
                    }
                }
                Slider(
                    value: Binding(
                        get: { devManager.getSpatialPosition(for: device.id).angle },
                        set: { devManager.setSpatialPosition(for: device.id, angle: $0, distance: pos.distance) }
                    ),
                    in: -180.0...180.0,
                    step: 1.0
                )
                .accentColor(TermTheme.green)
            }
            
            // 3. Acoustic Metrics
            HStack {
                Text("Acoustic Flight: \(String(format: "%.1f", flightMs)) ms")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundColor(TermTheme.dimText)
                
                Spacer()
                
                Text("Pan: \(Int(pan.panL * 100))% L / \(Int(pan.panR * 100))% R")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(TermTheme.green)
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.30))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(TermTheme.borderSubtle, lineWidth: 1))
    }
    
    // MARK: - Section 04: ViPER4Android & JamesDSP Engine
    private var viperEngineSection: some View {
        TermCard(
            title: "04: VIPER4ANDROID & JAMESDSP ENGINE",
            badge: viper.isViperEnabled ? "VIPER: ON" : "BYPASS"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                // Master Switch & File Open Buttons
                HStack(spacing: 5) {
                    TermButton(
                        title: viper.isViperEnabled ? "VIPER FX: ON" : "VIPER FX: OFF",
                        isActive: viper.isViperEnabled,
                        color: viper.isViperEnabled ? TermTheme.greenBright : TermTheme.dimText
                    ) {
                        viper.isViperEnabled.toggle()
                    }
                    
                    Spacer()
                    
                    TermButton(
                        title: "OPEN PRESET...",
                        color: TermTheme.cyan
                    ) {
                        viper.openPresetFileDialog()
                    }
                    
                    TermButton(
                        title: "OPEN KERNEL (IRS)...",
                        color: TermTheme.amber
                    ) {
                        viper.openKernelFileDialog()
                    }
                }
                
                // Active Files Badges
                VStack(spacing: 3) {
                    HStack {
                        Text("PRESET:")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundColor(TermTheme.dimText)
                        Text(viper.loadedPresetName)
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundColor(viper.loadedPresetName != "NONE" ? TermTheme.cyan : TermTheme.dimText)
                            .lineLimit(1)
                        Spacer()
                        if viper.loadedPresetName != "NONE" {
                            Button("[CLEAR]") {
                                viper.clearLoadedPreset()
                            }
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundColor(TermTheme.red)
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    HStack {
                        Text("KERNEL:")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundColor(TermTheme.dimText)
                        Text(viper.loadedKernelName)
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundColor(viper.loadedKernelName != "NONE" ? TermTheme.amber : TermTheme.dimText)
                            .lineLimit(1)
                        Spacer()
                        if viper.loadedKernelName != "NONE" {
                            Button("[CLEAR]") {
                                viper.clearLoadedKernel()
                            }
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundColor(TermTheme.red)
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                .padding(6)
                .background(Color.black.opacity(0.35))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(TermTheme.borderSubtle, lineWidth: 1))
                
                // Module Switches (Convolver, Bass, Clarity, Tube)
                viperSwitchesRow
                
                // Adjustments
                if viper.isViperEnabled {
                    viperSliders
                }
            }
        }
    }
    
    private var viperSwitchesRow: some View {
        HStack(spacing: 5) {
            TermButton(
                title: "CONVOLVER",
                isActive: viper.isConvolverEnabled,
                color: viper.isConvolverEnabled ? TermTheme.amber : TermTheme.dimText
            ) {
                viper.isConvolverEnabled.toggle()
                if viper.isConvolverEnabled { viper.isViperEnabled = true }
            }
            
            TermButton(
                title: "VIPER BASS",
                isActive: viper.isViperBassEnabled,
                color: viper.isViperBassEnabled ? TermTheme.cyan : TermTheme.dimText
            ) {
                viper.isViperBassEnabled.toggle()
                if viper.isViperBassEnabled { viper.isViperEnabled = true }
            }
            
            TermButton(
                title: "CLARITY",
                isActive: viper.isViperClarityEnabled,
                color: viper.isViperClarityEnabled ? TermTheme.green : TermTheme.dimText
            ) {
                viper.isViperClarityEnabled.toggle()
                if viper.isViperClarityEnabled { viper.isViperEnabled = true }
            }
            
            TermButton(
                title: "TUBE WARMTH",
                isActive: viper.isTubeSimulatorEnabled,
                color: viper.isTubeSimulatorEnabled ? TermTheme.amber : TermTheme.dimText
            ) {
                viper.isTubeSimulatorEnabled.toggle()
                if viper.isTubeSimulatorEnabled { viper.isViperEnabled = true }
            }
        }
    }
    
    private var viperSliders: some View {
        VStack(spacing: 4) {
            if viper.isConvolverEnabled {
                HStack {
                    Text("IRS CONVOLVER WET: \(Int(viper.convolverWet * 100))%")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundColor(TermTheme.amber)
                    Spacer()
                    Slider(value: $viper.convolverWet, in: 0.1...1.0, step: 0.05)
                        .frame(width: 170)
                        .accentColor(TermTheme.amber)
                }
            }
            
            if viper.isViperBassEnabled {
                HStack {
                    Text("BASS GAIN: +\(Int(viper.viperBassGain)) dB (\(Int(viper.viperBassFreq)) Hz)")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundColor(TermTheme.cyan)
                    Spacer()
                    Slider(value: $viper.viperBassGain, in: 1.0...14.0, step: 0.5)
                        .frame(width: 170)
                        .accentColor(TermTheme.cyan)
                }
            }
            
            if viper.isViperClarityEnabled {
                HStack {
                    Text("CLARITY GAIN: +\(Int(viper.viperClarityGain)) dB")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundColor(TermTheme.green)
                    Spacer()
                    Slider(value: $viper.viperClarityGain, in: 1.0...12.0, step: 0.5)
                        .frame(width: 170)
                        .accentColor(TermTheme.green)
                }
            }
        }
        .padding(6)
        .background(Color.black.opacity(0.35))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(TermTheme.borderSubtle, lineWidth: 1))
    }
    
    // MARK: - Section 05: DSP Processors & Flags
    private var dspModulesSection: some View {
        TermCard(title: "05: HARDWARE DSP MODULES") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    dspToggleButton(
                        title: "BASS PUNCH",
                        isEnabled: dsp.isBassPunch,
                        toggle: { dsp.isBassPunch.toggle() }
                    )
                    
                    dspToggleButton(
                        title: "SPATIAL 3D",
                        isEnabled: dsp.isSpatial,
                        toggle: { dsp.isSpatial.toggle() }
                    )
                }
                
                HStack(spacing: 8) {
                    dspToggleButton(
                        title: "VOCAL BOOST",
                        isEnabled: dsp.isVocalBoost,
                        toggle: { dsp.isVocalBoost.toggle() }
                    )
                    
                    dspToggleButton(
                        title: "ZERO-CLIP",
                        isEnabled: dsp.isAntiClip,
                        toggle: { dsp.isAntiClip.toggle() }
                    )
                }
            }
        }
    }
    
    private func dspToggleButton(title: String, isEnabled: Bool, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack(spacing: 4) {
                Text(isEnabled ? "[X]" : "[ ]")
                    .foregroundColor(isEnabled ? TermTheme.greenBright : TermTheme.dimText)
                Text(title)
                    .foregroundColor(isEnabled ? TermTheme.green : TermTheme.dimText)
                Spacer()
                Text(isEnabled ? "ON" : "OFF")
                    .foregroundColor(isEnabled ? TermTheme.greenBright : TermTheme.disabledText)
            }
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(isEnabled ? TermTheme.buttonActiveBg : TermTheme.buttonBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(isEnabled ? TermTheme.green.opacity(0.8) : TermTheme.borderSubtle, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Section 06: 10-Band Graphic Equalizer (Interactive ASCII Matrix)
    private var equalizerSection: some View {
        TermCard(title: "06: GRAPHIC EQUALIZER (10-BAND)", badge: dsp.selectedPreset.name.uppercased()) {
            VStack(alignment: .leading, spacing: 6) {
                eqPresetBar
                eqAsciiMatrix
                eqBottomControls
            }
        }
    }
    
    private var eqPresetBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(EQPreset.presets) { preset in
                    let isSelected = dsp.selectedPreset.name == preset.name
                    TermButton(
                        title: preset.name.uppercased(),
                        isActive: isSelected,
                        color: isSelected ? TermTheme.greenBright : TermTheme.dimText
                    ) {
                        dsp.applyPreset(preset)
                    }
                }
                
                TermButton(title: "RESET 0dB", color: TermTheme.amber) {
                    for i in 0..<dsp.bands.count {
                        dsp.updateBand(index: i, gain: 0.0)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
    
    private func eqDbLabel(for rowIndex: Int) -> String {
        switch rowIndex {
        case 6: return "+12"
        case 5: return " +8"
        case 4: return " +4"
        case 3: return "  0"
        case 2: return " -4"
        case 1: return " -8"
        case 0: return "-12"
        default: return "   "
        }
    }
    
    private func isEqRowLit(rowIndex: Int, gain: Double) -> Bool {
        if abs(gain) < 0.25 {
            return rowIndex == 3
        } else if gain > 0 {
            let targetRow = 3 + Int(round((gain / 12.0) * 3.0))
            return rowIndex >= 3 && rowIndex <= Swift.min(6, targetRow)
        } else {
            let targetRow = 3 - Int(round((abs(gain) / 12.0) * 3.0))
            return rowIndex <= 3 && rowIndex >= Swift.max(0, targetRow)
        }
    }
    
    private func eqBlockColor(isLit: Bool, rowIndex: Int) -> Color {
        guard isLit else { return TermTheme.disabledText.opacity(0.35) }
        if rowIndex >= 6 { return TermTheme.red }
        if rowIndex >= 5 { return TermTheme.amber }
        if rowIndex >= 4 { return TermTheme.greenBright }
        return TermTheme.green
    }
    
    private var eqAsciiMatrix: some View {
        VStack(spacing: 2) {
            ForEach((0..<7).reversed(), id: \.self) { rowIndex in
                HStack(spacing: 0) {
                    Text(eqDbLabel(for: rowIndex))
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(TermTheme.disabledText)
                        .frame(width: 24, alignment: .leading)
                    
                    ForEach(0..<Swift.min(10, dsp.bands.count), id: \.self) { bandIdx in
                        let bandGain = Double(dsp.bands[bandIdx].gain)
                        let lit = isEqRowLit(rowIndex: rowIndex, gain: bandGain)
                        
                        Text(lit ? "██" : "··")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundColor(eqBlockColor(isLit: lit, rowIndex: rowIndex))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.35))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { val in
                    let boardWidth: CGFloat = 410.0
                    let leadWidth: CGFloat = 24.0
                    let availWidth = boardWidth - leadWidth
                    let colWidth = availWidth / 10.0
                    let touchedX = val.location.x - leadWidth
                    let colIdx = Int(touchedX / colWidth)
                    if colIdx >= 0 && colIdx < dsp.bands.count {
                        let totalHeight: CGFloat = 80.0
                        let clampedY = Swift.max(0.0, Swift.min(totalHeight, val.location.y))
                        let frac = 1.0 - (clampedY / totalHeight)
                        let gainVal = (frac * 24.0) - 12.0
                        let stepGain = round(gainVal * 2.0) / 2.0
                        dsp.updateBand(index: colIdx, gain: Double(stepGain))
                    }
                }
        )
    }
    
    private var eqBottomControls: some View {
        let labels = ["32", "64", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
        
        return HStack(spacing: 0) {
            Text("   ")
                .frame(width: 24)
            
            ForEach(0..<Swift.min(10, dsp.bands.count), id: \.self) { idx in
                let band = dsp.bands[idx]
                VStack(spacing: 1) {
                    Button(action: {
                        dsp.updateBand(index: idx, gain: Swift.min(12.0, band.gain + 1.0))
                    }) {
                        Text("[+]")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(TermTheme.greenBright)
                    }
                    .buttonStyle(.plain)
                    
                    Text(String(format: "%+.0f", band.gain))
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(band.gain > 0.01 ? TermTheme.green : (band.gain < -0.01 ? TermTheme.amber : TermTheme.dimText))
                    
                    Button(action: {
                        dsp.updateBand(index: idx, gain: Swift.max(-12.0, band.gain - 1.0))
                    }) {
                        Text("[-]")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(TermTheme.amber)
                    }
                    .buttonStyle(.plain)
                    
                    Text(labels[idx])
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundColor(TermTheme.dimText)
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
    
    // MARK: - Terminal Footer Bar & Commands (No Emojis)
    private var terminalFooterSection: some View {
        HStack {
            Text("48000 Hz • 32-bit")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(TermTheme.dimText)
            
            Spacer()
            
            // Rescan devices
            TermButton(title: "RESCAN", color: TermTheme.cyan) {
                devManager.refreshDevices()
                engine.checkBlackHoleAvailability()
            }
            
            // Quit
            TermButton(title: "QUIT", color: TermTheme.red) {
                RealAudioEngine.shared.stopRouting()
                NSApp.terminate(nil)
            }
        }
        .padding(.top, 4)
    }
}
