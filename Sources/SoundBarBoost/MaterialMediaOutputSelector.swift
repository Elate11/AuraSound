import SwiftUI

// MARK: - macOS 27 Liquid Glass Media Output Hub & Per-Device Sliders
public struct M3MediaOutputSelectorView: View {
    @ObservedObject var devManager = AudioDeviceManager.shared
    @ObservedObject var calibrator = AcousticAutoCalibrator.shared
    @State private var isExpanded: Bool = true
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 10) {
            headerButton
            
            if isExpanded {
                destinationListSection
                
                if devManager.selectedDeviceIDs.count > 1 {
                    zeroEchoAutoSyncSection
                }
            }
        }
    }
    
    // MARK: - Header Bar
    private var headerButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        }) {
            HStack(spacing: 12) {
                let isMulti = devManager.selectedDeviceIDs.count > 1
                let iconName = isMulti ? "speaker.wave.3.fill" : (devManager.primaryDevice?.iconName ?? "speaker.wave.2.fill")
                
                ZStack {
                    Circle()
                        .fill(LiquidGlass.electricBlue.opacity(0.35))
                        .frame(width: 38, height: 38)
                        .overlay(
                            Circle()
                                .stroke(LiquidGlass.cyan.opacity(0.4), lineWidth: 1.0)
                        )
                        .shadow(color: LiquidGlass.cyan.opacity(0.3), radius: 6, x: 0, y: 1)
                    
                    Image(systemName: iconName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(LiquidGlass.cyan)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(isMulti ? "Multi-Output Cast Hub" : (devManager.primaryDevice?.name ?? "Audio Device"))
                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                            .foregroundColor(LiquidGlass.textPrimary)
                            .lineLimit(1)
                        
                        if isMulti {
                            Text("\(devManager.selectedDeviceIDs.count) Active")
                                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                .foregroundColor(LiquidGlass.cyan)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(LiquidGlass.electricBlue.opacity(0.30))
                                        .overlay(Capsule().stroke(LiquidGlass.cyan.opacity(0.3), lineWidth: 0.5))
                                )
                        }
                    }
                    
                    HStack(spacing: 5) {
                        Circle()
                            .fill(LiquidGlass.emerald)
                            .frame(width: 6, height: 6)
                            .shadow(color: LiquidGlass.emerald.opacity(0.8), radius: 3, x: 0, y: 0)
                        
                        Text(isMulti ? "Independent Gain Mixing Active" : (devManager.primaryDevice?.typeDescription ?? "Connected"))
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(LiquidGlass.textSecondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(LiquidGlass.textSecondary)
                    .padding(6)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Device Destinations with Per-Device Liquid Sliders
    private var destinationListSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Active Outputs & Independent Volume")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(LiquidGlass.textMuted)
                    .textCase(.uppercase)
                
                Spacer()
                
                Button(action: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        if devManager.selectedDeviceIDs.count == devManager.outputDevices.count {
                            if let first = devManager.outputDevices.first {
                                devManager.selectSingleDevice(first)
                            }
                        } else {
                            for dev in devManager.outputDevices {
                                devManager.selectedDeviceIDs.insert(dev.id)
                            }
                            if RealAudioEngine.shared.isRoutingActive {
                                _ = RealAudioEngine.shared.startRouting(toOutputDeviceIDs: devManager.selectedDeviceIDs)
                            }
                        }
                    }
                }) {
                    Text(devManager.selectedDeviceIDs.count == devManager.outputDevices.count ? "Solo" : "Select All")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(LiquidGlass.cyan)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(LiquidGlass.electricBlue.opacity(0.35))
                                .overlay(Capsule().stroke(LiquidGlass.cyan.opacity(0.3), lineWidth: 0.5))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
            
            ForEach(devManager.outputDevices) { device in
                deviceCard(device: device)
            }
        }
    }
    
    // MARK: - Single Device Card with Checkbox & Liquid Volume Slider
    private func deviceCard(device: AudioDevice) -> some View {
        let isSelected = devManager.selectedDeviceIDs.contains(device.id)
        
        return VStack(spacing: 6) {
            // Main Device Row Toggle
            Button(action: {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    devManager.toggleDeviceSelection(device)
                }
            }) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(isSelected ? LiquidGlass.electricBlue.opacity(0.4) : Color.white.opacity(0.08))
                            .frame(width: 30, height: 30)
                        
                        Image(systemName: device.iconName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(isSelected ? LiquidGlass.cyan : LiquidGlass.textSecondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(device.name)
                            .font(.system(size: 12, weight: isSelected ? .bold : .medium, design: .rounded))
                            .foregroundColor(isSelected ? LiquidGlass.textPrimary : LiquidGlass.textSecondary)
                            .lineLimit(1)
                        
                        Text(device.typeDescription)
                            .font(.system(size: 9.5, weight: .regular))
                            .foregroundColor(LiquidGlass.textMuted)
                    }
                    
                    Spacer()
                    
                    // Liquid Glass Checkbox
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isSelected ? LiquidGlass.cyan : Color.clear)
                            .frame(width: 18, height: 18)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(isSelected ? LiquidGlass.cyan : Color.white.opacity(0.25), lineWidth: 1.2)
                            )
                            .shadow(color: isSelected ? LiquidGlass.cyan.opacity(0.45) : Color.clear, radius: 4, x: 0, y: 0)
                        
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Color.black)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            
            // Per-Device Liquid Glass Slider (Only visible when device is active/selected)
            if isSelected {
                deviceVolumeSlider(device: device)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? LiquidGlass.electricBlue.opacity(0.18) : Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isSelected ?
                    LinearGradient(colors: [LiquidGlass.cyan.opacity(0.4), LiquidGlass.cyan.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing) :
                    LinearGradient(colors: [Color.white.opacity(0.08), Color.white.opacity(0.02)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1.0
                )
        )
    }
    
    // MARK: - Mini Liquid Glass Slider for Specific Device
    private func deviceVolumeSlider(device: AudioDevice) -> some View {
        let currentVol = devManager.getVolumeForDevice(device.id)
        
        return GeometryReader { geo in
            let width = geo.size.width
            let height: CGFloat = 34
            let fillWidth = max(28, min(width, width * CGFloat(currentVol)))
            
            ZStack(alignment: .leading) {
                // Frosted Glass Trough
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1.0)
                    )
                
                // Liquid Cyan Fill
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [LiquidGlass.cyan, LiquidGlass.electricBlue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: fillWidth, height: height)
                    .shadow(color: LiquidGlass.cyan.opacity(0.35), radius: 5, x: 0, y: 0)
                
                // Slider Overlay Content
                HStack(spacing: 8) {
                    Image(systemName: currentVol > 0.5 ? "speaker.wave.2.fill" : (currentVol > 0 ? "speaker.wave.1.fill" : "speaker.slash.fill"))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(currentVol > 0.15 ? Color.black : LiquidGlass.textSecondary)
                        .padding(.leading, 10)
                    
                    Text(device.name)
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundColor(currentVol > 0.4 ? Color.black : LiquidGlass.textPrimary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text("\(Int(currentVol * 100))%")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(currentVol > 0.75 ? Color.black : LiquidGlass.textPrimary)
                        .padding(.trailing, 10)
                }
                .frame(height: height)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let percent = max(0.0, min(1.0, Float(gesture.location.x / width)))
                        devManager.setVolumeForDevice(device.id, volume: percent)
                    }
            )
        }
        .frame(height: 34)
    }
    
    // MARK: - Zero-Echo Acoustic Auto-Sync Section
    private var zeroEchoAutoSyncSection: some View {
        let dsp = AudioDSPManager.shared
        return VStack(spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.horizontal.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(LiquidGlass.electricBlue)
                    
                    Text("Zero-Echo Acoustic Auto-Sync")
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundColor(LiquidGlass.textPrimary)
                }
                
                Spacer()
                
                Text("\(Int(dsp.syncDelayMs)) ms")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(LiquidGlass.cyan)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(LiquidGlass.electricBlue.opacity(0.35))
                            .overlay(Capsule().stroke(LiquidGlass.cyan.opacity(0.4), lineWidth: 0.8))
                    )
            }
            
            // Auto-Calibration via Microphone Button
            Button(action: {
                AcousticAutoCalibrator.shared.startAutoCalibration()
            }) {
                HStack(spacing: 9) {
                    ZStack {
                        Circle()
                            .fill(
                                calibrator.isCalibrating ?
                                AnyShapeStyle(LiquidGlass.ruby) :
                                AnyShapeStyle(LinearGradient(colors: [LiquidGlass.cyan, LiquidGlass.electricBlue], startPoint: .topLeading, endPoint: .bottomTrailing))
                            )
                            .frame(width: 30, height: 30)
                            .shadow(color: (calibrator.isCalibrating ? LiquidGlass.ruby : LiquidGlass.cyan).opacity(0.5), radius: 6, x: 0, y: 1)
                        
                        if calibrator.isCalibrating {
                            ProgressView()
                                .scaleEffect(0.68)
                                .colorInvert()
                        } else {
                            Image(systemName: "mic.fill.badge.plus")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Color.black)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(calibrator.isCalibrating ? "Калибровка в процессе..." : "Автокалибровка через микрофон")
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                            .foregroundColor(LiquidGlass.textPrimary)
                        
                        Text(calibrator.statusMessage)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundColor(LiquidGlass.textMuted)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    if !calibrator.isCalibrating {
                        Text("Запустить")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(Color.black)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(LiquidGlass.cyan)
                                    .shadow(color: LiquidGlass.cyan.opacity(0.4), radius: 4, x: 0, y: 1)
                            )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            calibrator.isCalibrating ?
                            LiquidGlass.ruby.opacity(0.18) :
                            Color.white.opacity(0.04)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            calibrator.isCalibrating ?
                            LiquidGlass.ruby.opacity(0.5) :
                            Color.white.opacity(0.15),
                            lineWidth: 1.0
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(calibrator.isCalibrating)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1.0)
        )
        .padding(.top, 4)
    }
}
