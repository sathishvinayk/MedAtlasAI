import Cocoa
import Carbon

class HotKeyManager {
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var hotKeyIDs: [UInt32] = [] // Track IDs separately
    private var eventHandlerRef: EventHandlerRef?
    
    init() {
        registerPermanentHotKeys()
        print("HotKeyManager initialized - Only ESC hotkey enabled")
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
            case 2: hotkeyName = "ESC"
            default: hotkeyName = "Unknown (\(hotKeyID.id))"
            }

            print("Hotkey pressed: \(hotkeyName)")
            
            switch Int(hotKeyID.id) {
            case 2:
                print("Quitting application")
                NSApplication.shared.terminate(nil)
            default:
                break
            }
        }
        return noErr
    }
    
    private func registerPermanentHotKeys() {
        // Only register ESC hotkey
        registerHotKey(keyCode: UInt32(kVK_Escape), modifiers: 0, id: 2, signature: "quit")
        
        print("Registered ESC hotkey successfully")
        setupEventHandler()
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
        case UInt32(kVK_Escape):     return "ESC"
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
}