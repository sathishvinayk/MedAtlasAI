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
        NSApp.setActivationPolicy(.accessory)
        hotKeyManager = HotKeyManager()
        setupWindow()
    }

    func setupWindow() {
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let windowWidth: CGFloat = 600
        let windowHeight: CGFloat = 400
        let windowRect = NSRect(x: screenFrame.midX - windowWidth / 2, y: screenFrame.midY - windowHeight / 2, width: windowWidth, height: windowHeight)

        window = TransparentPanel(
            contentRect: windowRect, 
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered, 
            defer: false
        )

        let blur = NSVisualEffectView(frame: window.contentView!.bounds)
        blur.autoresizingMask = [.width, .height]
        blur.material = .underWindowBackground
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 16
        blur.layer?.masksToBounds = true
        blur.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.25).cgColor
        blur.frame = NSInsetRect(window.contentView!.bounds, 0, -28)

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
        
        let accessoryView = NSView()
        accessoryView.translatesAutoresizingMaskIntoConstraints = false
        accessoryView.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = accessoryView
        accessory.layoutAttribute = .top

        window.addTitlebarAccessoryViewController(accessory)
        
        window.isMovableByWindowBackground = true
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
        let label = NSTextField(wrappingLabelWithString: message)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 14)
        label.textColor = isUser ? .white : .labelColor
        label.backgroundColor = .clear
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.alignment = .left

        let bubble = NSView()
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.wantsLayer = true
        bubble.layer?.backgroundColor = isUser ? NSColor.systemBlue.withAlphaComponent(0.8).cgColor : NSColor.controlBackgroundColor.withAlphaComponent(0.6).cgColor
        bubble.layer?.cornerRadius = 14
        bubble.layer?.masksToBounds = true
        bubble.addSubview(label)

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(bubble)
        messagesStack.addArrangedSubview(container)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -8),
            label.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -12),

            bubble.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            bubble.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
            bubble.widthAnchor.constraint(lessThanOrEqualTo: messagesStack.widthAnchor, multiplier: 0.8)
        ])

        if isUser {
            bubble.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20).isActive = true
            bubble.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 80).isActive = true
        } else {
            bubble.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20).isActive = true
            bubble.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -80).isActive = true
        }
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
