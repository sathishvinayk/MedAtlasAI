import Cocoa
import Carbon

var isStealthVisible = true

class AppDelegate: NSObject, NSApplicationDelegate, NSTextViewDelegate {
    var chatApiService = ChatApiService()

    var hotKeyManager: HotKeyManager!
    var window: TransparentPanel!
    var messagesStack: NSStackView!
    var textView: NSTextView!
    var inputScroll: NSScrollView!
    var inputHeightConstraint: NSLayoutConstraint!

    func toggleStealthMode() {
        isStealthVisible.toggle()
        if isStealthVisible {
            window.orderFrontRegardless()
        } else {
            window.orderOut(nil)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        hotKeyManager = HotKeyManager()
        setupWindow()

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape key
                NSApp.terminate(nil)
                return nil
            }
            return event
        }
    }

    func setupWindow() {
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let windowWidth: CGFloat = 600
        let windowHeight: CGFloat = 400
        let windowRect = NSRect(x: screenFrame.midX - windowWidth / 2, y: screenFrame.midY - windowHeight / 2, width: windowWidth, height: windowHeight)

        window = TransparentPanel(
            contentRect: windowRect, 
            styleMask: [.titled, .resizable, .fullSizeContentView, .closable, .miniaturizable],
            backing: .buffered, 
            defer: false
        )

        let blur = NSVisualEffectView(frame: window.contentView!.bounds)
        blur.autoresizingMask = [.width, .height]
        blur.material = .underWindowBackground
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 8
        blur.layer?.masksToBounds = true
        blur.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.25).cgColor
        // blur.frame = NSInsetRect(window.contentView!.bounds, 0, -28)

        window.contentView = blur
        window.isOpaque = false
        window.hasShadow = false
        window.backgroundColor = .clear
        window.level = .floating
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .transient, .stationary]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.sharingType = .none
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        window.hidesOnDeactivate = false
        window.isMovableByWindowBackground = true
        
        let accessoryView = NSView()
        accessoryView.translatesAutoresizingMaskIntoConstraints = false
        accessoryView.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = accessoryView
        accessory.layoutAttribute = .top

        window.addTitlebarAccessoryViewController(accessory)
        
        window.styleMask.insert(.resizable)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]

        // setupChatUI(in: blur)
        let ui = ChatUIBuilder.buildChatUI(in: blur, delegate: self, target: self, sendAction: #selector(handleInput))
        messagesStack = ui.messagesStack
        textView = ui.textView
        inputScroll = ui.inputScroll
        inputHeightConstraint = ui.inputHeightConstraint

        textDidChange(Notification(name: NSText.didChangeNotification))
        
        DispatchQueue.main.async {
            self.textView.window?.makeFirstResponder(self.textView)
        }
    }

    @objc func handleInput() {
        let text = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        addMessage("You: \(text)", isUser: true)
        textView.string = ""
        textDidChange(Notification(name: NSText.didChangeNotification))

        chatApiService.fetchGPTResponse(for: text) { response in
            self.addMessage("GPT: \(response)", isUser: false)
        }
    }

    func addMessage(_ message: String, isUser: Bool) {
        let messageView = MessageRenderer.renderMessage(message, isUser: isUser)
        messagesStack.addArrangedSubview(messageView)
    }

    func textDidChange(_ notification: Notification) {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let newHeight = usedRect.height + textView.textContainerInset.height * 2
        let clampedHeight = min(max(newHeight, 32), 120)

        inputHeightConstraint.constant = clampedHeight
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        print("Received selector: \(commandSelector)")
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            let event = NSApp.currentEvent
            let isShiftPressed = event?.modifierFlags.contains(.shift) ?? false

            if !isShiftPressed {
                handleInput()
                return true
            }
            // Allow newline with Shift+Enter
        }
        return false
    }   
}
