import Cocoa
final class KeyboardHandler {
    static func monitorEscapeKey() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                NSApp.terminate(nil)
                return nil
            }
            return event
        }
    }
}
