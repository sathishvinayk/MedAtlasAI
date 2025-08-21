// AccessibilityHandler.swift - Updated with debug printing
import Cocoa
import Security

class AccessibilityHandler {
    static let shared = AccessibilityHandler()
    
    private var permissionTimer: Timer?
    private var intensiveTimer: Timer?
    private var continuousMonitorTimer: Timer?
    private let hasRequestedAccessibilityKey = "HasRequestedAccessibility"
    
    var hasAccessibilityPermission: Bool {
        return checkCurrentPermissionStatus()
    }

    func stopContinuousPermissionMonitoring() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        intensiveTimer?.invalidate()
        intensiveTimer = nil
        print("🛑 Stopped continuous permission monitoring")
    }

    // Existing version Handle the case where permission appears granted but isn't
    func setupContinuousPermissionMonitoring() {
        // Cancel any existing timer
        permissionTimer?.invalidate()
        
        // Check initial status
        let hasPermission = checkCurrentPermissionStatus()
        
        if hasPermission {
            print("✅ Permission already granted, no need for continuous monitoring")
            return
        }
        
        print("🔒 Setting up continuous permission monitoring")
        
        // Use a longer interval to avoid excessive checking
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            let currentStatus = self.checkCurrentPermissionStatus()
            print("🔍 Periodic permission check: \(currentStatus ? "GRANTED" : "NOT GRANTED")")
            
            if currentStatus {
                print("✅ Permission granted! Stopping monitoring")
                self.stopContinuousPermissionMonitoring()
                // Notify that permission has been granted
                NotificationCenter.default.post(name: .accessibilityPermissionGranted, object: nil)
            }
        }
        
        // Add to run loop
        RunLoop.current.add(permissionTimer!, forMode: .common)
    }

    // Improved version Handle the case where permission appears granted but isn't
    // func setupContinuousPermissionMonitoring() {
    //     // Cancel any existing timer
    //     stopContinuousPermissionMonitoring()
        
    //     // Check initial status with verification
    //     let hasPermission = checkCurrentPermissionStatusWithVerification()
        
    //     if hasPermission {
    //         print("✅ Permission verified and granted, no need for continuous monitoring")
    //         return
    //     }
        
    //     print("🔒 Setting up continuous permission monitoring")
    //     permissionTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
    //         guard let self = self else { return }
            
    //         let currentStatus = self.checkCurrentPermissionStatusWithVerification()
    //         print("🔍 Verified permission check: \(currentStatus ? "GRANTED" : "NOT GRANTED")")
            
    //         if currentStatus {
    //             print("✅ Permission verified and granted! Stopping monitoring")
    //             self.stopContinuousPermissionMonitoring()
    //             NotificationCenter.default.post(name: .accessibilityPermissionGranted, object: nil)
    //         }
    //     }
        
    //     RunLoop.current.add(permissionTimer!, forMode: .common)
    // }

    func checkCurrentPermissionStatusWithVerification() -> Bool {
        let simpleCheck = checkCurrentPermissionStatus()
        
        if simpleCheck {
            // Double-check with a more reliable method
            return verifyPermissionPersists()
        }
        
        return false
    }

    private func verifyPermissionPersists() -> Bool {
        // Try to perform an actual accessibility operation
        // If it fails, the permission might be "ghost" permission
        
        let testElement = AXUIElementCreateApplication(ProcessInfo().processIdentifier)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(testElement, kAXFocusedUIElementAttribute as CFString, &value)
        
        // If we can't access accessibility API, permission might be gone
        return result == .success
    }

    private func checkForPermissionRevocation() {
        let currentPermission = checkCurrentPermissionStatus()
        
        if !currentPermission {
            print("🚫 Accessibility permission revoked! Showing warning...")
            stopContinuousMonitoring()
            showPermissionRevokedWarning()
        } else {
            print("✅ Accessibility permission still granted")
        }
    }
    
    private func showPermissionRevokedWarning() {
        guard let window = NSApp.windows.first(where: { $0.isVisible }) else {
            print("⚠️ No window available for permission revoked warning")
            // Try again later
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.showPermissionRevokedWarning()
            }
            return
        }
        
        print("⚠️ Showing permission revoked warning")
        
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Revoked"
        alert.informativeText = "StealthOverflow has lost accessibility permissions. The app cannot function properly without this permission.\n\nPlease re-enable access in System Preferences."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Open System Preferences")
        alert.addButton(withTitle: "Quit App")
        
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn {
                print("⚙️ Opening System Preferences after revocation...")
                self?.openAccessibilityPreferences()
                self?.startIntensivePermissionMonitoring()
            } else {
                print("❌ User chose to quit after permission revocation")
                NSApp.terminate(nil)
            }
        }
    }

    // Update the existing startIntensivePermissionMonitoring method
    func startIntensivePermissionMonitoring() {
        print("⏰ Starting intensive permission monitoring (1s interval)")
        stopPermissionMonitoring()
        
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            print("⏱️ Intensive timer fired - checking permission status")
            DispatchQueue.main.async {
                self?.checkForPermissionChangeIntensive()
            }
        }
    }

    private func checkForPermissionChangeIntensive() {
        let hasPermission = checkCurrentPermissionStatus()
        
        if hasPermission {
            print("🎉 Permission granted! Stopping monitor and showing restart prompt")
            stopPermissionMonitoring()
            showRestartPrompt()
            // Restart continuous monitoring after permission is restored
            setupContinuousPermissionMonitoring()
        } else {
            print("⏳ Permission still not granted, continuing intensive monitoring...")
        }
    }
    
    func stopContinuousMonitoring() {
        continuousMonitorTimer?.invalidate()
        continuousMonitorTimer = nil
    }

    func checkCurrentPermissionStatus() -> Bool {
        // Check if the app has accessibility permissions
        let checkOptPrompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [checkOptPrompt: false]
        let status = AXIsProcessTrustedWithOptions(options as CFDictionary?)
        
        // Additional verification to prevent false negatives
        if status == false {
            // Double-check with a different method
            let trusted = AXIsProcessTrusted()
            print("🔍 Double-checking accessibility: \(trusted ? "GRANTED" : "NOT GRANTED")")
            return trusted
        }
        
        return status
    }
    
    func showAccessibilityRequestIfNeeded(on window: NSWindow) {
        let currentPermissionStatus = checkCurrentPermissionStatus()
        print("📋 Current permission status: \(currentPermissionStatus ? "GRANTED" : "NOT GRANTED")")
        
        // Only show request if permission is not granted
        if !currentPermissionStatus {
            print("👆 Showing accessibility request dialog (permission not granted)")
            showAccessibilityRequest(on: window)
        } else {
            print("✅ Permission already granted, no need to request")
        }
    }

    // For testing/debugging - reset the requested state
    func resetAccessibilityRequest() {
        UserDefaults.standard.removeObject(forKey: hasRequestedAccessibilityKey)
        print("🔄 Reset accessibility request state")
    }
    
    private func showAccessibilityRequest(on window: NSWindow) {
        print("🖼️ Displaying accessibility request alert")
        
        let alert = NSAlert()
        alert.messageText = "Accessibility Permissions Required"
        alert.informativeText = "StealthOverflow needs accessibility permissions to function properly.\n\nPlease grant access in System Preferences."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Preferences")
        alert.addButton(withTitle: "Not Now")
        alert.buttons[1].keyEquivalent = "\u{1b}" // Make ESC key trigger "Not Now"
        
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self = self else { return }
            
            print("🎯 User response: \(response == .alertFirstButtonReturn ? "Open Settings" : "Not Now")")
            
            if response == .alertFirstButtonReturn {
                print("⚙️ Opening System Preferences...")
                self.openAccessibilityPreferences()
                // Start monitoring for permission changes
                self.startPermissionMonitoring()
            } else {
                print("❌ User chose 'Not Now', quitting app")
                NSApp.terminate(nil)
            }
        }
    }
    
    func openAccessibilityPreferences() {
        print("🌐 Opening accessibility preferences pane")
        let prefPaneURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(prefPaneURL)
    }
    
    func startPermissionMonitoring() {
        print("⏰ Starting permission monitoring timer (2s interval)")
        stopPermissionMonitoring()
        
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            print("⏱️ Timer fired - checking permission status")
            // Ensure we're on the main thread for UI operations
            DispatchQueue.main.async {
                self?.checkForPermissionChange()
            }
        }
    }
    
    func stopPermissionMonitoring() {
        if permissionTimer != nil {
            print("⏹️ Stopping permission monitoring")
            permissionTimer?.invalidate()
            permissionTimer = nil
        }
    }
    
    func checkPermissionStatus() {
        print("🔍 Periodic permission check")
        _ = checkCurrentPermissionStatus()
    }
    
    // AccessibilityHandler.swift - Updated checkForPermissionChange method
    private func checkForPermissionChange() {
        let hasPermission = checkCurrentPermissionStatus()
        
        if hasPermission {
            print("🎉 Permission granted! Stopping monitor and showing restart prompt")
            stopPermissionMonitoring()
            
            // Show restart prompt on the main thread and ensure we have a window
            DispatchQueue.main.async { [weak self] in
                self?.showRestartPrompt()
            }
        } else {
            print("⏳ Permission still not granted, continuing monitoring...")
        }
    }

    // Updated showRestartPrompt method
    private func showRestartPrompt() {
        // Try to get any visible window, not just the main window
        guard let window = NSApp.windows.first(where: { $0.isVisible }) else {
            print("⚠️ No visible window found for restart prompt, trying to create one...")
            createTemporaryWindowForRestartPrompt()
            return
        }
        
        print("🔄 Showing restart prompt on window: \(window.title)")
        
        let alert = NSAlert()
        alert.messageText = "Restart Required"
        alert.informativeText = "Accessibility permissions have been granted!\n\nPlease restart the application for changes to take effect."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Quit Now")
        alert.addButton(withTitle: "Later")
        
        alert.beginSheetModal(for: window) { response in
            print("🎯 Restart response: \(response == .alertFirstButtonReturn ? "Quit Now" : "Later")")
            if response == .alertFirstButtonReturn {
                print("👋 Quitting application...")
                NSApp.terminate(nil)
            }
        }
    }

    // Add this new method to create a temporary window if no windows are available
    private func createTemporaryWindowForRestartPrompt() {
        print("🪟 Creating temporary window for restart prompt")
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        window.center()
        window.title = "StealthOverflow - Restart Required"
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        
        // Add a small delay to ensure the window is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.showRestartPrompt()
        }
    }
    
    deinit {
        print("♻️ AccessibilityHandler deinitializing")
        stopPermissionMonitoring()
        stopContinuousMonitoring()
    }
}
