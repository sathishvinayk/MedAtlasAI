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
        // Prevent losing focus from closing the window
    }

    override func resignKey() {
        // Prevent losing key status from closing the window
    }
}