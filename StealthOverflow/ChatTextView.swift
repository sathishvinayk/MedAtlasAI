import Cocoa

class ChatTextView: NSTextView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "a" {
            self.selectAll(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
