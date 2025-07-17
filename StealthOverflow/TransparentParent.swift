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

    override func close() {
        super.close()
        NSApp.terminate(nil)
    }
    
    override func mouseDown(with event: NSEvent) {
        self.makeKeyAndOrderFront(nil)
        self.makeMain()
        super.mouseDown(with: event)
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        repositionTrafficLights()
    }

    private func repositionTrafficLights() {
        let offsetY: CGFloat = -4
        let offsetX: CGFloat = 4
        for type in [NSWindow.ButtonType.closeButton,
                     .miniaturizeButton,
                     .zoomButton] {
            if let btn = standardWindowButton(type) {
                var frame = btn.frame
                frame.origin.y = max(frame.origin.y + offsetY, 0)
                frame.origin.x = max(frame.origin.x + offsetX, 0)
                btn.frame = frame
            }
        }
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
