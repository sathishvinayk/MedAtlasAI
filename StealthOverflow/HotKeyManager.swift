import Cocoa
import Carbon

class HotKeyManager {
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var hotKeyIDs: [UInt32] = [] // Track IDs separately
    private var eventHandlerRef: EventHandlerRef?
    private var arrowKeyHotKeysEnabled = true
    private var arrowKeyHotKeyIDs: Set<UInt32> = [3, 4, 5, 6] // Use Set for faster lookup
    private let windowMovementManager = WindowMovementManager()
    
    init() {
        registerPermanentHotKeys()
        setupAppVisibilityObserver()
        updateArrowKeyRegistration()
        print("HotKeyManager initialized - Arrow keys: \(arrowKeyHotKeysEnabled ? "ENABLED" : "DISABLED")")
    }

    deinit {
        cleanup()
    }
    
    private func cleanup() {
        // Clean up event handler
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
        
        // Clean up all hotkey registrations
        unregisterAllHotKeys()
        
        // Remove observer
        NotificationCenter.default.removeObserver(self)
    }

    private let hotKeyCallback: EventHandlerUPP = { _, eventRef, _ in
        var hotKeyID = EventHotKeyID()
        var size = MemoryLayout<EventHotKeyID>.size
        
        let error = GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            size,
            nil,
            &hotKeyID
        )
        
        guard error == noErr else { return error }
        
        DispatchQueue.main.async {
            let appDelegate = NSApp.delegate as? AppDelegate
            let hotKeyManager = appDelegate?.hotKeyManager
            
            let hotkeyName: String
            switch Int(hotKeyID.id) {
            case 1: hotkeyName = "Command + X"
            case 2: hotkeyName = "ESC"
            case 3: hotkeyName = "Command + ↑"
            case 4: hotkeyName = "Command + ↓"
            case 5: hotkeyName = "Command + ←"
            case 6: hotkeyName = "Command + →"
            default: hotkeyName = "Unknown (\(hotKeyID.id))"
            }

            print("Hotkey pressed: \(hotkeyName) - App hidden: \(NSApplication.shared.isHidden) - Arrow keys enabled: \(hotKeyManager?.arrowKeyHotKeysEnabled ?? false)")
            
            switch Int(hotKeyID.id) {
            case 1:
                print("Toggling stealth mode")
                appDelegate?.toggleStealthMode()
                hotKeyManager?.updateArrowKeyRegistrationBasedOnAppState()
            case 2:
                print("Quitting application")
                NSApplication.shared.terminate(nil)
            case 3:
                print("Moving window UP")
                hotKeyManager?.windowMovementManager.moveAllVisibleWindows(direction: .up)
            case 4:
                print("Moving window DOWN")
                hotKeyManager?.windowMovementManager.moveAllVisibleWindows(direction: .down)
            case 5:
                print("Moving window LEFT")
                hotKeyManager?.windowMovementManager.moveAllVisibleWindows(direction: .left)
            case 6:
                print("Moving window RIGHT")
                hotKeyManager?.windowMovementManager.moveAllVisibleWindows(direction: .right)
            default:
                break
            }
        }
        return noErr
    }
    
    private func registerPermanentHotKeys() {
        // Always register these hotkeys
        registerHotKey(keyCode: UInt32(kVK_ANSI_X), modifiers: UInt32(cmdKey), id: 1, signature: "stea")
        registerHotKey(keyCode: UInt32(kVK_Escape), modifiers: 0, id: 2, signature: "quit")
        
        print("Registered permanent hotkeys successfully")
        setupEventHandler()
    }
    
    private func registerArrowKeys() {
        // Register arrow keys
        registerHotKey(keyCode: UInt32(kVK_UpArrow), modifiers: UInt32(cmdKey), id: 3, signature: "upar")
        registerHotKey(keyCode: UInt32(kVK_DownArrow), modifiers: UInt32(cmdKey), id: 4, signature: "dnar")
        registerHotKey(keyCode: UInt32(kVK_LeftArrow), modifiers: UInt32(cmdKey), id: 5, signature: "lfar")
        registerHotKey(keyCode: UInt32(kVK_RightArrow), modifiers: UInt32(cmdKey), id: 6, signature: "rtar")
        
        print("Registered arrow key hotkeys")
    }
    
    private func unregisterArrowKeys() {
        var newRefs: [EventHotKeyRef?] = []
        var newIDs: [UInt32] = []
        
        for (index, ref) in hotKeyRefs.enumerated() {
            if let ref = ref {
                let id = hotKeyIDs[index]
                
                if arrowKeyHotKeyIDs.contains(id) {
                    UnregisterEventHotKey(ref)
                    print("Unregistered arrow key hotkey ID: \(id)")
                } else {
                    newRefs.append(ref)
                    newIDs.append(id)
                }
            }
        }
        
        hotKeyRefs = newRefs
        hotKeyIDs = newIDs
        print("Unregistered all arrow key hotkeys")
    }
    
    private func unregisterAllHotKeys() {
        for ref in hotKeyRefs {
            if let ref = ref {
                UnregisterEventHotKey(ref)
            }
        }
        hotKeyRefs.removeAll()
        hotKeyIDs.removeAll()
    }
    
    private func registerHotKey(keyCode: UInt32, modifiers: UInt32, id: UInt32, signature: String) {
        var hotKeyRef: EventHotKeyRef? = nil
        
        // Convert signature string to OSType safely
        let signatureValue: OSType
        if let data = signature.data(using: .macOSRoman), data.count >= 4 {
            signatureValue = data.withUnsafeBytes { $0.load(as: OSType.self) }
        } else {
            // Fallback: use hash value
            signatureValue = OSType(signature.hashValue & 0xFFFFFFFF)
        }
        
        let hotKeyID = EventHotKeyID(signature: signatureValue, id: id)
        
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if status == noErr, let ref = hotKeyRef {
            hotKeyRefs.append(ref)
            hotKeyIDs.append(id)
            let keyName = getKeyName(keyCode: keyCode)
            print("✓ Registered hotkey: \(keyName) with modifiers: \(modifiers) (ID: \(id))")
        } else {
            let keyName = getKeyName(keyCode: keyCode)
            print("✗ Failed to register hotkey: \(keyName) - status: \(status)")
        }
    }
    
    private func getKeyName(keyCode: UInt32) -> String {
        switch keyCode {
        case UInt32(kVK_ANSI_X):     return "X"
        case UInt32(kVK_Escape):     return "ESC"
        case UInt32(kVK_UpArrow):    return "↑"
        case UInt32(kVK_DownArrow):  return "↓"
        case UInt32(kVK_LeftArrow):  return "←"
        case UInt32(kVK_RightArrow): return "→"
        default:                     return "Unknown (\(keyCode))"
        }
    }

    private func setupEventHandler() {
        var eventHandler: EventHandlerRef? = nil
        let eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyCallback,
            1,
            [eventType],
            nil,
            &eventHandler
        )
        
        if status == noErr {
            eventHandlerRef = eventHandler
            print("✓ Event handler installed successfully")
        } else {
            print("✗ Failed to install event handler: \(status)")
        }
    }
    
    private func setupAppVisibilityObserver() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didHideNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("App didHideNotification received - Unregistering arrow keys")
            self?.arrowKeyHotKeysEnabled = false
            self?.unregisterArrowKeys()
        }
        
        NotificationCenter.default.addObserver(
            forName: NSApplication.didUnhideNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("App didUnhideNotification received - Registering arrow keys")
            self?.arrowKeyHotKeysEnabled = true
            self?.registerArrowKeys()
        }
    }
    
    private func updateArrowKeyRegistration() {
        if arrowKeyHotKeysEnabled {
            registerArrowKeys()
        } else {
            unregisterArrowKeys()
        }
    }
    
    private func updateArrowKeyRegistrationBasedOnAppState() {
        let shouldEnable = !NSApplication.shared.isHidden
        if arrowKeyHotKeysEnabled != shouldEnable {
            print("App state changed - Arrow keys: \(shouldEnable ? "ENABLING" : "DISABLING")")
            arrowKeyHotKeysEnabled = shouldEnable
            updateArrowKeyRegistration()
        }
    }
    
    func setArrowKeysEnabled(_ enabled: Bool) {
        print("Arrow keys manually \(enabled ? "ENABLED" : "DISABLED")")
        arrowKeyHotKeysEnabled = enabled
        updateArrowKeyRegistration()
    }
}
