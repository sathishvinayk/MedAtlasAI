import Cocoa

class TransparentPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func becomeKey() {
        super.becomeKey()
    }

    override func becomeMain()  {
        super.becomeMain()
    }

    override var acceptsFirstResponder: Bool {
        return true
    }

    override func resignMain() {
        super.resignMain()
    }

    override func resignKey() {
        super.resignKey()
    }
    
    override func mouseDown(with event: NSEvent) {
        self.makeKeyAndOrderFront(nil)
        self.makeMain()
        super.mouseDown(with: event)
    }
    
    private func findTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView {
            return textView
        }

        for subview in view.subviews {
            if let found = findTextView(in: subview) {
                return found
            }
        }

        return nil
    }

}
