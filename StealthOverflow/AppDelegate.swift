import Cocoa
import Carbon

var isStealthVisible = true

class TransparentPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
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

extension AppDelegate: NSTextViewDelegate {
    func textDidEndEditing(_ notification: Notification) {
        handleInput()
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: TransparentPanel!
    var messagesStack: NSStackView!
    var inputField: NSTextField!

    
    func toggleStealthMode() {
        isStealthVisible.toggle()
        if isStealthVisible {
            window.orderFrontRegardless()
        } else {
            window.orderOut(nil)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerHotKey()

        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let windowWidth: CGFloat = 600
        let windowHeight: CGFloat = 400
        let windowRect = NSRect(
            x: screenFrame.midX - (windowWidth / 2),
            y: screenFrame.midY - (windowHeight / 2),
            width: windowWidth,
            height: windowHeight
        )

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

        setupChatUI(in: blur)
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

        inputField = NSTextField()
        inputField.translatesAutoresizingMaskIntoConstraints = false
        inputField.placeholderString = "Ask something..."
        inputField.isBezeled = false
        inputField.isBordered = false
        inputField.drawsBackground = false
        inputField.font = NSFont.systemFont(ofSize: 14)
        inputField.focusRingType = .none
        inputField.lineBreakMode = .byTruncatingTail
        inputField.usesSingleLineMode = true
        inputField.target = self
        inputField.action = #selector(handleInput)
        
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
        inputContainer.addSubview(inputField)
        inputContainer.addSubview(sendButton)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            scrollView.bottomAnchor.constraint(equalTo: inputContainer.topAnchor, constant: -12),
            
            inputContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            inputContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            inputContainer.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
            inputContainer.heightAnchor.constraint(equalToConstant: 36),
            
            inputField.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor, constant: 12),
            inputField.centerYAnchor.constraint(equalTo: inputContainer.centerYAnchor),
            inputField.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),
            inputField.heightAnchor.constraint(equalToConstant: 22),
            
            sendButton.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor, constant: -12),
            sendButton.centerYAnchor.constraint(equalTo: inputContainer.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 22),
            sendButton.heightAnchor.constraint(equalToConstant: 22),
            
            messagesStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            messagesStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            messagesStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            messagesStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            messagesStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])
    }

    @objc func handleInput() {
        let text = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        addMessage("You: \(text)", isUser: true)
        inputField.stringValue = ""
        
        fetchGPTResponse(for: text) {
            response in self.addMessage("GPT: \(response)", isUser: false)
        }
    }

    func addMessage(_ message: String, isUser: Bool) {
        let label = NSTextField(wrappingLabelWithString: message)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 14)
        
//        label.preferredMaxLayoutWidth = CGFloat.greatestFiniteMagnitude
        
        label.textColor = isUser ? NSColor.white : NSColor.labelColor
        label.backgroundColor = .clear
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        
        label.alignment = .left
        
//        DispatchQueue.main.async {
//            label.preferredMaxLayoutWidth = self.messagesStack.frame.width - 20
//        }

        // Container view with a subtle background (chat bubble)
        let bubble = NSView()
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.wantsLayer = true
        bubble.layer?.cornerRadius = 14
        bubble.layer?.masksToBounds = true
        bubble.layer?.backgroundColor = isUser
            ? NSColor.systemBlue.withAlphaComponent(0.8).cgColor
            : NSColor.controlBackgroundColor.withAlphaComponent(0.6).cgColor

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
