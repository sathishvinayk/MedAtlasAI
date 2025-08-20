import Cocoa
import Carbon

var hotKeyHandler: EventHandlerRef?
class HotKeyManager {
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var eventHandlerRef: EventHandlerRef?

    init() {
        register()
    }

    deinit {
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
        }
        // Clean up hotkey registrations
        hotKeyRefs.forEach { ref in
            if let ref = ref {
                UnregisterEventHotKey(ref)
            }
        }
    }

    private let hotKeyCallback: EventHandlerUPP = { _, eventRef, _ in
        var hotKeyID = EventHotKeyID()
        GetEventParameter(eventRef,
                        EventParamName(kEventParamDirectObject),
                        EventParamType(typeEventHotKeyID),
                        nil,
                        MemoryLayout.size(ofValue: hotKeyID),
                        nil,
                        &hotKeyID)

        DispatchQueue.main.async {
            switch hotKeyID.id {
            case 1:
                // Command + X - Toggle stealth mode
                NSApp.delegate.map { ($0 as? AppDelegate)?.toggleStealthMode() }
            case 2:
                // ESC - Quit the app
                NSApplication.shared.terminate(nil)
            case 3:
                // Command + Up Arrow - Move window up
                NSApp.delegate.map { ($0 as? AppDelegate)?.moveWindow(direction: .up) }
            case 4:
                // Command + Down Arrow - Move window down
                NSApp.delegate.map { ($0 as? AppDelegate)?.moveWindow(direction: .down) }
            case 5:
                // Command + Left Arrow - Move window left
                NSApp.delegate.map { ($0 as? AppDelegate)?.moveWindow(direction: .left) }
            case 6:
                // Command + Right Arrow - Move window right
                NSApp.delegate.map { ($0 as? AppDelegate)?.moveWindow(direction: .right) }
            default:
                break
            }
        }
        return noErr
    }
    
    private func register() {
        // Register Command + X hotkey (id: 1)
        var cmdXHotKeyRef: EventHotKeyRef? = nil
        let cmdXHotKeyID = EventHotKeyID(signature: OSType(UInt32(truncatingIfNeeded: "stea".hashValue)), id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_X), UInt32(cmdKey), cmdXHotKeyID, GetApplicationEventTarget(), 0, &cmdXHotKeyRef)
        hotKeyRefs.append(cmdXHotKeyRef)

        // Register ESC hotkey (id: 2)
        var escHotKeyRef: EventHotKeyRef? = nil
        let escHotKeyID = EventHotKeyID(signature: OSType(UInt32(truncatingIfNeeded: "quit".hashValue)), id: 2)
        RegisterEventHotKey(UInt32(kVK_Escape), 0, escHotKeyID, GetApplicationEventTarget(), 0, &escHotKeyRef)
        hotKeyRefs.append(escHotKeyRef)

        // Register Command + Arrow keys
        let arrowKeys = [
            (keyCode: kVK_UpArrow, id: 3, signature: "upar", direction: "up"),
            (keyCode: kVK_DownArrow, id: 4, signature: "dnar", direction: "down"),
            (keyCode: kVK_LeftArrow, id: 5, signature: "lfar", direction: "left"),
            (keyCode: kVK_RightArrow, id: 6, signature: "rtar", direction: "right")
        ]

        for arrowKey in arrowKeys {
            var hotKeyRef: EventHotKeyRef? = nil
            let hotKeyID = EventHotKeyID(signature: OSType(UInt32(truncatingIfNeeded: arrowKey.signature.hashValue)), id: UInt32(arrowKey.id))
            RegisterEventHotKey(UInt32(arrowKey.keyCode), UInt32(cmdKey), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
            hotKeyRefs.append(hotKeyRef)
        }

        // Register event handler
        let eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyCallback, 1, [eventType], nil, &eventHandlerRef)
    }
}