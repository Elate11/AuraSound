import SwiftUI
import AppKit

// MARK: - macOS 27 Liquid Glass Design System
public struct LiquidGlass {
    // Canvas & Glass Surfaces
    public static let canvas = Color(red: 0.05, green: 0.07, blue: 0.10)
    public static let glassSurfaceLow = Color.white.opacity(0.04)
    public static let glassSurface = Color.white.opacity(0.08)
    public static let glassSurfaceHigh = Color.white.opacity(0.14)
    public static let glassSurfaceHover = Color.white.opacity(0.22)
    
    // Liquid Specular Glass Borders
    public static let glassBorder = LinearGradient(
        colors: [Color.white.opacity(0.35), Color.white.opacity(0.08), Color(red: 0.0, green: 0.90, blue: 1.0).opacity(0.20)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    public static let glassBorderSubtle = LinearGradient(
        colors: [Color.white.opacity(0.18), Color.white.opacity(0.04)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    // macOS 27 Vibrant Neon Accents
    public static let cyan = Color(red: 0.0, green: 0.90, blue: 1.0)
    public static let electricBlue = Color(red: 0.10, green: 0.45, blue: 1.0)
    public static let purple = Color(red: 0.65, green: 0.35, blue: 1.0)
    public static let magenta = Color(red: 1.0, green: 0.20, blue: 0.65)
    public static let ruby = Color(red: 1.0, green: 0.25, blue: 0.40)
    public static let amber = Color(red: 1.0, green: 0.75, blue: 0.20)
    public static let emerald = Color(red: 0.15, green: 0.95, blue: 0.55)
    public static let white = Color.white
    public static let black = Color.black
    
    // Typography
    public static let textPrimary = Color.white
    public static let textSecondary = Color.white.opacity(0.75)
    public static let textMuted = Color.white.opacity(0.45)
    
    // Liquid Gradients
    public static let liquidCyanGradient = LinearGradient(
        colors: [Color(red: 0.0, green: 0.92, blue: 1.0), Color(red: 0.05, green: 0.45, blue: 1.0)],
        startPoint: .leading,
        endPoint: .trailing
    )
    
    public static let liquidRubyGradient = LinearGradient(
        colors: [Color(red: 1.0, green: 0.30, blue: 0.50), Color(red: 1.0, green: 0.12, blue: 0.25)],
        startPoint: .leading,
        endPoint: .trailing
    )
    
    public static let liquidPurpleGradient = LinearGradient(
        colors: [Color(red: 0.65, green: 0.35, blue: 1.0), Color(red: 0.95, green: 0.25, blue: 0.70)],
        startPoint: .leading,
        endPoint: .trailing
    )
}

// MARK: - macOS 27 Liquid Glass Card
public struct M3ExpCard<Content: View>: View {
    let cornerRadius: CGFloat
    let padding: CGFloat
    let content: Content
    
    public init(cornerRadius: CGFloat = 16, padding: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }
    
    public var body: some View {
        content
            .padding(padding)
            .background(
                ZStack {
                    VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(LiquidGlass.glassSurface)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(LiquidGlass.glassBorder, lineWidth: 1.0)
            )
            .shadow(color: Color.black.opacity(0.30), radius: 8, x: 0, y: 3)
    }
}

// MARK: - macOS 27 Liquid Glass Quick Settings Tile
public struct M3QuickSettingsTile: View {
    let icon: String
    let title: String
    let subtitle: String
    let isActive: Bool
    let activeColor: Color
    let activeContainer: Color
    let onActiveContainer: Color
    let action: () -> Void
    
    public init(
        icon: String,
        title: String,
        subtitle: String,
        isActive: Bool,
        activeColor: Color = LiquidGlass.cyan,
        activeContainer: Color = LiquidGlass.electricBlue.opacity(0.35),
        onActiveContainer: Color = Color.white,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.isActive = isActive
        self.activeColor = activeColor
        self.activeContainer = activeContainer
        self.onActiveContainer = onActiveContainer
        self.action = action
    }
    
    public var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Circle Glass Icon
                ZStack {
                    Circle()
                        .fill(isActive ? activeColor.opacity(0.30) : Color.white.opacity(0.08))
                        .frame(width: 34, height: 34)
                        .overlay(
                            Circle()
                                .stroke(isActive ? activeColor.opacity(0.6) : Color.white.opacity(0.12), lineWidth: 1)
                        )
                    
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(isActive ? activeColor : LiquidGlass.textSecondary)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(LiquidGlass.textPrimary)
                        .lineLimit(1)
                    
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(isActive ? activeColor : LiquidGlass.textMuted)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Circle()
                    .fill(isActive ? activeColor : Color.white.opacity(0.15))
                    .frame(width: 7, height: 7)
                    .shadow(color: isActive ? activeColor.opacity(0.8) : Color.clear, radius: 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isActive ? activeContainer : LiquidGlass.glassSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: isActive ? [activeColor.opacity(0.7), activeColor.opacity(0.3)] : [Color.white.opacity(0.18), Color.white.opacity(0.04)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.0
                    )
            )
            .shadow(color: isActive ? activeColor.opacity(0.15) : Color.clear, radius: 6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - macOS 27 Liquid Glass Chip
public struct M3ExpChip: View {
    let title: String
    let isSelected: Bool
    let icon: String?
    let action: () -> Void
    
    public init(title: String, isSelected: Bool, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.icon = icon
        self.action = action
    }
    
    public var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium, design: .rounded))
            }
            .foregroundColor(isSelected ? Color.white : LiquidGlass.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isSelected ? LiquidGlass.electricBlue.opacity(0.7) : LiquidGlass.glassSurface)
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? LiquidGlass.cyan.opacity(0.8) : Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: isSelected ? LiquidGlass.cyan.opacity(0.4) : Color.clear, radius: 5)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - NSVisualEffectView Helper
public struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    public init(material: NSVisualEffectView.Material = .hudWindow, blendingMode: NSVisualEffectView.BlendingMode = .behindWindow) {
        self.material = material
        self.blendingMode = blendingMode
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
