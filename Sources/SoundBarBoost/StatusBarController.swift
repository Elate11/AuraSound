import SwiftUI
import AppKit

public class StatusBarController: NSObject {
    private var statusBar: NSStatusBar
    private var statusItem: NSStatusItem
    private var popover: NSPopover
    private var eventMonitor: Any?
    
    public override init() {
        self.statusBar = NSStatusBar.system
        self.statusItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        
        super.init()
        
        setupPopover()
        setupStatusButton()
        setupEventMonitor()
        observeAudioState()
    }
    
    private func setupPopover() {
        popover.contentSize = NSSize(width: 450, height: 680)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: MainPopoverView())
    }
    
    private func setupStatusButton() {
        guard let button = statusItem.button else { return }
        updateStatusButtonImage()
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }
    
    private func observeAudioState() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateStatusButtonImage()
        }
    }
    
    private func updateStatusButtonImage() {
        guard let button = statusItem.button else { return }
        
        let dsp = AudioDSPManager.shared
        let isBoosted = dsp.boostMultiplier > 1.0
        let imageName = isBoosted ? "speaker.wave.3.fill" : "speaker.wave.2.fill"
        
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        if let image = NSImage(systemSymbolName: imageName, accessibilityDescription: "SoundBar")?.withSymbolConfiguration(config) {
            button.image = image
            button.imagePosition = .imageLeft
            
            if isBoosted {
                button.attributedTitle = NSAttributedString(
                    string: " \(dsp.boostPercentage)%",
                    attributes: [
                        .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
                        .foregroundColor: NSColor(red: 1.0, green: 0.25, blue: 0.4, alpha: 1.0)
                    ]
                )
            } else {
                button.title = ""
            }
        }
    }
    
    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
    
    private func setupEventMonitor() {
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, self.popover.isShown else { return }
            self.popover.performClose(event)
        }
        
        // Global media key handler for Mac hardware volume keys (F11 / F12 / F10)
        NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { event in
            guard event.subtype.rawValue == 8 else { return }
            let keyCode = ((event.data1 & 0xFFFF0000) >> 16)
            let keyFlags = ((event.data1 & 0x0000FF00) >> 8)
            let keyState = (((keyFlags & 0xFF)) == 0xA) // Key down
            
            if keyState {
                let mgr = AudioDeviceManager.shared
                if keyCode == 0 { // NX_KEYTYPE_SOUND_UP
                    DispatchQueue.main.async {
                        mgr.setVolume(mgr.masterVolume + 0.0625)
                    }
                } else if keyCode == 1 { // NX_KEYTYPE_SOUND_DOWN
                    DispatchQueue.main.async {
                        mgr.setVolume(mgr.masterVolume - 0.0625)
                    }
                } else if keyCode == 7 { // NX_KEYTYPE_MUTE
                    DispatchQueue.main.async {
                        mgr.setMute(!mgr.isMuted)
                    }
                }
            }
        }
    }
}
