import Cocoa
import Carbon

class HotKeyManager {
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var eventHandlerRef: EventHandlerRef?
    private var arrowKeyHotKeysEnabled = true
    
    init() {
        register()
        setupAppVisibilityObserver()
        print("HotKeyManager initialized - Arrow keys: \(arrowKeyHotKeysEnabled ? "ENABLED" : "DISABLED")")
    }

    deinit {
        // Clean up event handler
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
        }
        
        // Clean up hotkey registrations
        hotKeyRefs.forEach { ref in
            if let ref = ref {
                UnregisterEventHotKey(ref)
            }
        }
        
        // Remove observer
        NotificationCenter.default.removeObserver(self)
    }

    private let hotKeyCallback: EventHandlerUPP = { _, eventRef, _ in
        var hotKeyID = EventHotKeyID()
        let error = GetEventParameter(eventRef,
                                    EventParamName(kEventParamDirectObject),
                                    EventParamType(typeEventHotKeyID),
                                    nil,
                                    MemoryLayout.size(ofValue: hotKeyID),
                                    nil,
                                    &hotKeyID)
        
        guard error == noErr else { return error }
        
        DispatchQueue.main.async {
            let appDelegate = NSApp.delegate as? AppDelegate
            let hotKeyManager = appDelegate?.hotKeyManager
            
            // Debug print for all hotkey presses
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
            case 2:
                print("Quitting application")
                NSApplication.shared.terminate(nil)
            case 3 where hotKeyManager?.arrowKeyHotKeysEnabled == true:
                print("Moving window UP")
                appDelegate?.moveWindow(direction: .up)
            case 4 where hotKeyManager?.arrowKeyHotKeysEnabled == true:
                print("Moving window DOWN")
                appDelegate?.moveWindow(direction: .down)
            case 5 where hotKeyManager?.arrowKeyHotKeysEnabled == true:
                print("Moving window LEFT")
                appDelegate?.moveWindow(direction: .left)
            case 6 where hotKeyManager?.arrowKeyHotKeysEnabled == true:
                print("Moving window RIGHT")
                appDelegate?.moveWindow(direction: .right)
            case 3, 4, 5, 6:
                print("Arrow key IGNORED (passing through to other app)")
                return
            default:
                break
            }

        }
        return noErr
    }
    
    private func register() {
        // Always register these hotkeys with explicit UInt32 conversion
        registerHotKey(keyCode: UInt32(kVK_ANSI_X), modifiers: UInt32(cmdKey), id: UInt32(1), signature: "stea")
        registerHotKey(keyCode: UInt32(kVK_Escape), modifiers: UInt32(0), id: UInt32(2), signature: "quit")
        
        // Register arrow keys (they'll be conditionally handled)
        registerHotKey(keyCode: UInt32(kVK_UpArrow), modifiers: UInt32(cmdKey), id: UInt32(3), signature: "upar")
        registerHotKey(keyCode: UInt32(kVK_DownArrow), modifiers: UInt32(cmdKey), id: UInt32(4), signature: "dnar")
        registerHotKey(keyCode: UInt32(kVK_LeftArrow), modifiers: UInt32(cmdKey), id: UInt32(5), signature: "lfar")
        registerHotKey(keyCode: UInt32(kVK_RightArrow), modifiers: UInt32(cmdKey), id: UInt32(6), signature: "rtar")
        
        print("Registered all hotkeys successfully")
        setupEventHandler()
    }
    
    private func registerHotKey(keyCode: UInt32, modifiers: UInt32, id: UInt32, signature: String) {
        var hotKeyRef: EventHotKeyRef? = nil
        let hotKeyID = EventHotKeyID(
            signature: OSType(UInt32(truncatingIfNeeded: signature.hashValue)),
            id: id
        )
        
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
            print("App hidden - Disabling arrow keys")
            self?.arrowKeyHotKeysEnabled = false
        }
        
        NotificationCenter.default.addObserver(
            forName: NSApplication.didUnhideNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("App unhidden - Enabling arrow keys")
            self?.arrowKeyHotKeysEnabled = true
        }
    }
    
    // Public method to update arrow key behavior
    func setArrowKeysEnabled(_ enabled: Bool) {
        print("Arrow keys manually \(enabled ? "ENABLED" : "DISABLED")")
        arrowKeyHotKeysEnabled = enabled
    }
}
