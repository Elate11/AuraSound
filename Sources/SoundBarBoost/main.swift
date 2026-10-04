import AppKit
import SwiftUI

public class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        statusBarController = StatusBarController()
        
        // Auto start audio routing pipeline on launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let mgr = AudioDeviceManager.shared
            mgr.refreshDevices()
            var ids = mgr.selectedDeviceIDs
            if ids.isEmpty {
                if let dev = mgr.outputDevices.first(where: { !$0.name.contains("BlackHole") && !$0.name.contains("Background Music") }) {
                    ids = Set([dev.id])
                    mgr.selectedDeviceIDs = ids
                }
            }
            if !ids.isEmpty {
                _ = RealAudioEngine.shared.startRouting(toOutputDeviceIDs: ids)
            }
        }
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        RealAudioEngine.shared.stopRouting()
    }
    
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}

@main
struct SoundBarBoostApp {
    static func main() {
        if CommandLine.arguments.contains("--capture-screenshots") {
            captureScreenshots()
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
    
    static func captureScreenshots() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        
        let outDir = "/Users/aleksandr/AuraSound/docs/screenshots"
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        
        let mgr = AudioDeviceManager.shared
        mgr.refreshDevices()
        
        let dsp = AudioDSPManager.shared
        dsp.isEQEnabled = true
        dsp.isAtmosEnabled = true
        dsp.isSpatialEnhancerEnabled = true
        dsp.isBassPunchEnabled = true
        dsp.isVocalBoostEnabled = true
        dsp.applyPreset(EQPreset.presets.first(where: { $0.name.lowercased().contains("rock") }) ?? EQPreset.presets[1])
        
        // 1. Standard Popover View (Compact 450x680)
        renderView(MainPopoverView(customHeight: 680), size: CGSize(width: 450, height: 680), path: "\(outDir)/01_main_view.png")
        
        // 2. Full High-Resolution Interface (Unscrolled 450x2250)
        renderView(MainPopoverView(customHeight: 2250), size: CGSize(width: 450, height: 2250), path: "\(outDir)/02_full_interface.png")
        
        print("Screenshots captured successfully.")
        exit(0)
    }
    
    static func renderView<V: View>(_ view: V, size: CGSize, path: String) {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: size)
        
        let window = NSWindow(
            contentRect: hostingView.bounds,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = NSColor(red: 0.04, green: 0.06, blue: 0.05, alpha: 1.0)
        window.isOpaque = true
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        
        if let rep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) {
            hostingView.cacheDisplay(in: hostingView.bounds, to: rep)
            if let pngData = rep.representation(using: .png, properties: [:]) {
                try? pngData.write(to: URL(fileURLWithPath: path))
                print("Saved screenshot to \(path)")
            }
        }
    }
}
