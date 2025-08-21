import Cocoa
import Security

class AccessibilityHandler {
    static let shared = AccessibilityHandler()
    
    private var globalMonitor: Any?
    private let hasShownAccessibilityRequestKey = "HasShownAccessibilityRequest"
    private let hasGrantedAccessibilityKey = "HasGrantedAccessibility"
    
    func setupGlobalEscapeMonitor() {
        // Check if we already have permission
        if checkAccessibilityPermissions() {
            startGlobalMonitor()
            
            // If user just granted access and needs to restart, show restart dialog
            if UserDefaults.standard.bool(forKey: hasShownAccessibilityRequestKey) &&
               !UserDefaults.standard.bool(forKey: hasGrantedAccessibilityKey) {
                showRestartDialog()
            }
            
            // Mark as granted for future launches
            UserDefaults.standard.set(true, forKey: hasGrantedAccessibilityKey)
            
        } else if !UserDefaults.standard.bool(forKey: hasShownAccessibilityRequestKey) {
            // First time launch without permissions - show request dialog
            showAccessibilityRequestDialog()
        }
    }
    
    func checkAccessibilityPermissions() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
    
    func startGlobalMonitor() {
        stopGlobalMonitor()
        
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 && !self.hasModifiers(event) {
                DispatchQueue.main.async {
                    NSApp.terminate(nil)
                }
            }
        }
    }
    
    func stopGlobalMonitor() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
    }
    
    func showAccessibilityRequestDialog() {
        // Mark that we've shown the request
        UserDefaults.standard.set(true, forKey: hasShownAccessibilityRequestKey)
        
        let alert = NSAlert()
        alert.messageText = "Accessibility Permissions Required"
        alert.informativeText = "StealthOverflow needs accessibility permissions to enable global Escape key functionality.\n\nPlease click 'Open Settings', enable the permission, then restart the app."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Quit App")
        alert.buttons[1].keyEquivalent = "\u{1b}"
        
        DispatchQueue.main.async {
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                self.openAccessibilityPreferences()
                // Don't quit immediately - let user enable permissions then restart manually
                // or we can auto-quit after a delay to force restart
                self.quitAfterDelay()
            } else {
                NSApp.terminate(nil)
            }
        }
    }
    
    func showRestartDialog() {
        let alert = NSAlert()
        alert.messageText = "Restart Required"
        alert.informativeText = "Accessibility permissions have been granted!\n\nPlease restart StealthOverflow for the changes to take effect."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Restart Now")
        alert.addButton(withTitle: "Later")
        
        DispatchQueue.main.async {
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                self.restartApplication()
            }
        }
    }
    
    func openAccessibilityPreferences() {
        let prefPaneURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(prefPaneURL)
    }
    
    private func quitAfterDelay() {
        // Quit after 10 seconds to encourage restart
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            let alert = NSAlert()
            alert.messageText = "Restart Needed"
            alert.informativeText = "Please quit and restart StealthOverflow to apply accessibility permissions."
            alert.addButton(withTitle: "Quit Now")
            alert.runModal()
            NSApp.terminate(nil)
        }
    }
    
    private func restartApplication() {
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", "sleep 1 && open \"\(Bundle.main.bundlePath)\""]
        task.launch()
        
        NSApp.terminate(nil)
    }
    
    private func hasModifiers(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags
        return modifiers.contains(.command) || 
               modifiers.contains(.shift) || 
               modifiers.contains(.option) || 
               modifiers.contains(.control)
    }
    
    // Call this when app becomes active to check if permissions were granted
    func checkForNewPermissions() {
        if checkAccessibilityPermissions() && 
           UserDefaults.standard.bool(forKey: hasShownAccessibilityRequestKey) &&
           !UserDefaults.standard.bool(forKey: hasGrantedAccessibilityKey) {
            
            UserDefaults.standard.set(true, forKey: hasGrantedAccessibilityKey)
            showRestartDialog()
        }
    }
    
    deinit {
        stopGlobalMonitor()
    }
}