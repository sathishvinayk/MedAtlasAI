import Cocoa

class ChatTextView: NSTextView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let commandOnly = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
        if commandOnly && event.charactersIgnoringModifiers == "a" {
            self.selectAll(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
