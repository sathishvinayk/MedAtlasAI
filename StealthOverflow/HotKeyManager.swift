import Cocoa
import Carbon

var hotKeyHandler: EventHandlerRef?
class HotKeyManager {
    private var hotKeyref: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    init() {
        register()
    }

    deinit {
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
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

        if hotKeyID.id == 1 {
            DispatchQueue.main.async {
                NSApp.delegate.map { ($0 as? AppDelegate)?.toggleStealthMode() }
            }
        }
        return noErr
    }
    
    private func register() {
        var hotKeyRef: EventHotKeyRef? = nil
        let hotKeyID = EventHotKeyID(signature: OSType(UInt32(truncatingIfNeeded: "stea".hashValue)), id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_X), UInt32(cmdKey | shiftKey), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)

        let eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyCallback, 1, [eventType], nil, &hotKeyHandler)
    }
}

