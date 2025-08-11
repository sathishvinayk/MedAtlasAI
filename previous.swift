import Cocoa
import Carbon

var isStealthVisible = true

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

var hotKeyHandler: EventHandlerRef?

let hotKeyCallback: EventHandlerUPP = { _, eventRef, _ in
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


class AppDelegate: NSObject, NSApplicationDelegate, NSTextViewDelegate {
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
        registerHotKey()
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
        // window.sharingType = .none
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

        setupChatUI(in: blur)
        DispatchQueue.main.async {
            self.textView.window?.makeFirstResponder(self.textView)
        }
    }

    func registerHotKey() {
        var hotKeyRef: EventHotKeyRef? = nil
        let hotKeyID = EventHotKeyID(signature: OSType(UInt32(truncatingIfNeeded: "stea".hashValue)), id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_X), UInt32(cmdKey | shiftKey), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)

        let eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyCallback, 1, [eventType], nil, &hotKeyHandler)
    }

    func setupChatUI(in container: NSView) {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        messagesStack = NSStackView()
        messagesStack.orientation = .vertical
        messagesStack.alignment = .leading
        messagesStack.spacing = 8
        messagesStack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        messagesStack.translatesAutoresizingMaskIntoConstraints = false

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(messagesStack)
        scrollView.documentView = documentView

        let inputContainer = NSView()
        inputContainer.translatesAutoresizingMaskIntoConstraints = false
        inputContainer.wantsLayer = true
        inputContainer.layer?.cornerRadius = 12
        inputContainer.layer?.masksToBounds = true
        inputContainer.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.8).cgColor

        inputScroll = NSScrollView()
        inputScroll.translatesAutoresizingMaskIntoConstraints = false
        inputScroll.borderType = .noBorder
        inputScroll.hasVerticalScroller = true
        inputScroll.autohidesScrollers = false
        inputScroll.drawsBackground = false
        inputScroll.backgroundColor = .clear
        inputScroll.scrollerStyle = .overlay
        inputScroll.verticalScrollElasticity = .allowed 

        // textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 32))
        textView = ChatTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 32))
        textView.minSize = NSSize(width: 0, height: 32)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false

        textView.font = NSFont.systemFont(ofSize: 14)
        textView.backgroundColor = .clear
        textView.delegate = self
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.isFieldEditor = false
        textView.allowsDocumentBackgroundColorChange = true
        textView.importsGraphics = false
        textView.usesFindBar = false
        textView.textColor = .labelColor
        textView.translatesAutoresizingMaskIntoConstraints = false

        inputScroll.documentView = textView

        let sendButton = NSButton(title: "➤", target: self, action: #selector(handleInput))
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.bezelStyle = .inline
        sendButton.font = NSFont.systemFont(ofSize: 16)
        sendButton.setButtonType(.momentaryPushIn)
        sendButton.isBordered = false
        sendButton.wantsLayer = true
        sendButton.contentTintColor = .systemBlue
        sendButton.toolTip = "Send"

        container.addSubview(scrollView)
        container.addSubview(inputContainer)
        inputContainer.addSubview(inputScroll)
        inputContainer.addSubview(sendButton)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            scrollView.bottomAnchor.constraint(equalTo: inputContainer.topAnchor, constant: -12),

            inputContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            inputContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            inputContainer.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),

            inputScroll.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor, constant: 12),
            inputScroll.topAnchor.constraint(equalTo: inputContainer.topAnchor, constant: 6),
            inputScroll.bottomAnchor.constraint(equalTo: inputContainer.bottomAnchor, constant: -6),
            inputScroll.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),

            sendButton.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor, constant: -12),
            sendButton.centerYAnchor.constraint(equalTo: inputContainer.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 22),
            sendButton.heightAnchor.constraint(equalToConstant: 22),

            messagesStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            messagesStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            messagesStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            messagesStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            messagesStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            textView.leadingAnchor.constraint(equalTo: inputScroll.contentView.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: inputScroll.contentView.trailingAnchor),
            textView.topAnchor.constraint(equalTo: inputScroll.contentView.topAnchor),
            textView.bottomAnchor.constraint(equalTo: inputScroll.contentView.bottomAnchor),
        ])

        inputHeightConstraint = inputScroll.heightAnchor.constraint(equalToConstant: 120)
        inputHeightConstraint.priority = .defaultHigh
        inputHeightConstraint.isActive = true

        textDidChange(Notification(name: NSText.didChangeNotification))
    }

    @objc func handleInput() {
        let text = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        addMessage("You: \(text)", isUser: true)
        textView.string = ""
        textDidChange(Notification(name: NSText.didChangeNotification))

        fetchGPTResponse(for: text) { response in
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

    
    func mockResponse(for text: String) -> String {
        return "This is a mock response to: \"\(text)\""
    }

    func fetchGPTResponse(for prompt: String, completion: @escaping (String) -> Void) {
        let OpenRouterKey = "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"
        let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(OpenRouterKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "model": "mistralai/mistral-7b-instruct",
            "messages": [
                ["role": "system", "content": "You are a helpful assistant."],
                ["role": "user", "content": prompt]
            ]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion("Network error: \(error.localizedDescription)")
                }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    completion("No data received.")
                }
                return
            }

            // 💡 Print raw response for inspection
            if let raw = String(data: data, encoding: .utf8) {
                print("Raw GPT response:\n\(raw)")
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let message = choices.first?["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    DispatchQueue.main.async {
                        completion(content.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                } else {
                    DispatchQueue.main.async {
                        completion("Error parsing response (missing expected fields).")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion("JSON parse error: \(error.localizedDescription)")
                }
            }
        }.resume()
    }
}
