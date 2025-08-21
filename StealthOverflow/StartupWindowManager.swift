import Cocoa

class StartupWindowManager: NSObject {
    private var startupWindow: NSWindow?
    private var chatButton: NSButton?
    private var codeChatButton: NSButton? // New button
    private var trackingArea: NSTrackingArea?
    var onStartChat: (() -> Void)?
    var onStartCodeChat: (() -> Void)? // New callback

    func createStartupWindow() -> NSWindow? {
        let windowWidth: CGFloat = 600
        let windowHeight: CGFloat = 500
        let screenFrame = NSScreen.main?.frame ?? .zero
        let windowRect = NSRect(
            x: screenFrame.midX - windowWidth/2,
            y: screenFrame.midY - windowHeight/2,
            width: windowWidth,
            height: windowHeight
        )
        
        startupWindow = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        guard let startupWindow = startupWindow else { return nil }
        
        startupWindow.titleVisibility = .hidden
        startupWindow.titlebarAppearsTransparent = true
        startupWindow.isReleasedWhenClosed = false
        startupWindow.backgroundColor = .appBackground
        startupWindow.level = .floating
        startupWindow.hasShadow = true
        startupWindow.alphaValue = 0.7
        startupWindow.isMovable = false
        startupWindow.ignoresMouseEvents = true
        
        let contentView = InteractiveContentView(frame: startupWindow.contentView!.bounds)
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 8
        contentView.layer?.masksToBounds = true
        
        // Logo
        let logo = NSImageView()
        logo.image = NSImage(named: "AppIcon") ?? NSImage(systemSymbolName: "message", accessibilityDescription: nil)
        logo.imageScaling = .scaleProportionallyUpOrDown

        // Title
        let titleLabel = NSTextField(labelWithString: "SilentGlass")
        if let oxaniumFont = NSFont(name: "Oxanium-Bold", size: 32) {
            let attributedString = NSAttributedString(
                string: "Silent Glass",
                attributes: [
                    .font: oxaniumFont,
                    .foregroundColor: NSColor.white,
                    .kern: 2.0
                ]
            )
            titleLabel.attributedStringValue = attributedString
            
            titleLabel.wantsLayer = true
            titleLabel.shadow = NSShadow()
            titleLabel.shadow?.shadowColor = NSColor.black.withAlphaComponent(0.6)
            titleLabel.shadow?.shadowBlurRadius = 0
            titleLabel.shadow?.shadowOffset = NSSize(width: 2, height: -2)
        }

        let subTitle = NSTextField(labelWithString: "An AI Coding and Interview Assistant")
        if let lato = NSFont(name: "Lato-Italic", size: 14) {
            let attributedString = NSAttributedString(
                string: "An AI Coding and Interview Assistant",
                attributes: [
                    .font: lato,
                    .foregroundColor: NSColor.white,
                    .kern: 2.0
                ]
            )
            subTitle.attributedStringValue = attributedString
            
            subTitle.wantsLayer = true
            subTitle.shadow = NSShadow()
            subTitle.shadow?.shadowColor = NSColor.black.withAlphaComponent(0.6)
            subTitle.shadow?.shadowBlurRadius = 0
            subTitle.shadow?.shadowOffset = NSSize(width: 2, height: -2)
        }

        // Create shortcuts info view
        let shortcutsView = EnhancedShortcutsInfoView()
        shortcutsView.translatesAutoresizingMaskIntoConstraints = false

        // Chat Buttons
        chatButton = createChatButton(title: "Chat AI", action: #selector(handleChatButton))
        codeChatButton = createChatButton(title: "Code AI", action: #selector(handleCodeChatButton))
        
        // Vertical separator line
        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.3).cgColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        
        // Button container with both buttons and separator
        let buttonContainer = NSStackView(views: [chatButton!, separator, codeChatButton!])
        buttonContainer.orientation = .horizontal
        buttonContainer.spacing = 8
        buttonContainer.alignment = .centerY
        buttonContainer.translatesAutoresizingMaskIntoConstraints = false
        
        // Stack View
        let stackView = NSStackView(views: [logo, titleLabel, subTitle, buttonContainer, shortcutsView])
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 2
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(stackView)
        contentView.managerWindow = startupWindow
        
        // Register both buttons for mouse tracking
        if let chatButton = chatButton, let codeChatButton = codeChatButton {
            contentView.interactiveButtons = [chatButton, codeChatButton]
        }
        
        startupWindow.contentView = contentView
        
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -30),
            logo.widthAnchor.constraint(equalToConstant: 200),
            logo.heightAnchor.constraint(equalToConstant: 200),
            chatButton!.widthAnchor.constraint(equalToConstant: 80),
            chatButton!.heightAnchor.constraint(equalToConstant: 30),
            codeChatButton!.widthAnchor.constraint(equalToConstant: 80),
            codeChatButton!.heightAnchor.constraint(equalToConstant: 30),
            separator.widthAnchor.constraint(equalToConstant: 1),
            separator.heightAnchor.constraint(equalToConstant: 20)
        ])

        // Add some spacing between elements
        stackView.setCustomSpacing(-20, after: logo)
        stackView.setCustomSpacing(10, after: titleLabel)
        stackView.setCustomSpacing(50, after: subTitle)
        stackView.setCustomSpacing(50, after: buttonContainer)
        stackView.setCustomSpacing(05, after: shortcutsView)
        
        // Set up button layers after constraints are applied
        DispatchQueue.main.async {
            self.setupButtonAppearance()
        }
        
        return startupWindow
    }
    
    private func createChatButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        button.wantsLayer = true
        button.isBordered = false
        button.contentTintColor = .white
        button.setButtonType(.momentaryPushIn)
        return button
    }
    
    private func setupButtonAppearance() {
        [chatButton, codeChatButton].forEach { button in
            button?.layer?.cornerRadius = 6
            button?.layer?.masksToBounds = true
            button?.layer?.backgroundColor = NSColor.systemBlue.cgColor
            
            button?.attributedTitle = NSAttributedString(
                string: button?.title ?? "",
                attributes: [
                    .foregroundColor: NSColor.white,
                    .font: NSFont.systemFont(ofSize: 14, weight: .semibold)
                ]
            )
        }
    }
    
    func setupTracking() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                let startupWindow = self.startupWindow,
                let contentView = startupWindow.contentView else { return }
            
            if let existingArea = self.trackingArea {
                contentView.removeTrackingArea(existingArea)
            }
            
            let newTrackingArea = NSTrackingArea(
                rect: contentView.bounds,
                options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved],
                owner: contentView,
                userInfo: nil
            )
            
            contentView.addTrackingArea(newTrackingArea)
            self.trackingArea = newTrackingArea
        }
    }
    
    @objc private func handleChatButton() {
        print("Chat button clicked!")
        onStartChat?()
        close()
    }
    
    @objc private func handleCodeChatButton() {
        print("Code Chat button clicked!")
        onStartCodeChat?()
        close()
    }
    
    func show() {
        guard let startupWindow = startupWindow else { return }
        
        startupWindow.makeKeyAndOrderFront(nil)
        setupTracking()
        NSApp.activate(ignoringOtherApps: true)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let contentView = startupWindow.contentView as? InteractiveContentView {
                contentView.checkInitialMousePosition()
            }
        }
    }
    
    func close() {
        let trackingArea = self.trackingArea
        let startupWindow = self.startupWindow
        
        DispatchQueue.main.async { 
            if let area = trackingArea, let contentView = startupWindow?.contentView {
                contentView.removeTrackingArea(area)
            }
            
            NSCursor.arrow.set()
            startupWindow?.close()
        }
        
        self.trackingArea = nil
        self.startupWindow = nil
        self.chatButton = nil
        self.codeChatButton = nil
    }
    
    deinit {
        startupWindow?.close()
        trackingArea = nil
        chatButton = nil
        codeChatButton = nil
    }
}

// Updated InteractiveContentView to handle multiple buttons
class InteractiveContentView: NSView {
    weak var managerWindow: NSWindow?
    var interactiveButtons: [NSButton] = [] // Now supports multiple buttons
    private var isMouseOverButton = false
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        for trackingArea in trackingAreas {
            removeTrackingArea(trackingArea)
        }
        
        let options: NSTrackingArea.Options = [.activeAlways, .mouseEnteredAndExited, .mouseMoved]
        let trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
    }
    
    func checkInitialMousePosition() {
        guard let managerWindow = managerWindow else { return }
        
        let mouseLocation = NSEvent.mouseLocation
        let windowFrame = managerWindow.frame
        
        if windowFrame.contains(mouseLocation) {
            let locationInWindow = NSPoint(
                x: mouseLocation.x - windowFrame.origin.x,
                y: mouseLocation.y - windowFrame.origin.y
            )
            
            let locationInView = convert(locationInWindow, from: nil)
            
            // Check all interactive buttons
            for button in interactiveButtons {
                let buttonLocation = convert(locationInView, to: button)
                if button.bounds.contains(buttonLocation) {
                    isMouseOverButton = true
                    managerWindow.ignoresMouseEvents = false
                    NSCursor.pointingHand.set()
                    animateButtonHover(true, button: button)
                    return
                }
            }
        }
        
        isMouseOverButton = false
        managerWindow.ignoresMouseEvents = true
        NSCursor.arrow.set()
        interactiveButtons.forEach { animateButtonHover(false, button: $0) }
    }
    
    override func mouseEntered(with event: NSEvent) {
        checkMousePosition(event)
    }
    
    override func mouseMoved(with event: NSEvent) {
        checkMousePosition(event)
    }
    
    override func mouseExited(with event: NSEvent) {
        isMouseOverButton = false
        managerWindow?.ignoresMouseEvents = true
        NSCursor.arrow.set()
        interactiveButtons.forEach { animateButtonHover(false, button: $0) }
    }
    
    private func checkMousePosition(_ event: NSEvent) {
        guard let managerWindow = managerWindow else {
            managerWindow?.ignoresMouseEvents = true
            NSCursor.arrow.set()
            return
        }
        
        let locationInView = convert(event.locationInWindow, from: nil)
        var foundHover = false
        
        for button in interactiveButtons {
            let buttonLocation = convert(locationInView, to: button)
            if button.bounds.contains(buttonLocation) {
                foundHover = true
                isMouseOverButton = true
                managerWindow.ignoresMouseEvents = false
                NSCursor.pointingHand.set()
                animateButtonHover(true, button: button)
            } else {
                animateButtonHover(false, button: button)
            }
        }
        
        if !foundHover {
            isMouseOverButton = false
            managerWindow.ignoresMouseEvents = true
            NSCursor.arrow.set()
        }
    }

    private func animateButtonHover(_ isHovering: Bool, button: NSButton?) {
        DispatchQueue.main.async {
            guard let button = button, button.wantsLayer else { return }
            
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                context.allowsImplicitAnimation = true
                
                if isHovering {
                    button.layer?.backgroundColor = NSColor.systemBlue.withSystemEffect(.pressed).cgColor
                    button.layer?.borderWidth = 1.0
                    button.layer?.borderColor = NSColor.systemBlue.cgColor
                } else {
                    button.layer?.backgroundColor = NSColor.systemBlue.cgColor
                    button.layer?.borderWidth = 0
                    button.layer?.borderColor = nil
                }
            }
        }
    }

    private func animateButtonPress(_ button: NSButton) {
        DispatchQueue.main.async {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.1
                button.layer?.backgroundColor = NSColor.systemBlue.withSystemEffect(.deepPressed).cgColor
            } completionHandler: {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.1
                    // Check if mouse is still over button
                    if let window = button.window, 
                       let contentView = window.contentView as? InteractiveContentView,
                       contentView.isMouseOverButton {
                        button.layer?.backgroundColor = NSColor.systemBlue.withSystemEffect(.pressed).cgColor
                    } else {
                        button.layer?.backgroundColor = NSColor.systemBlue.cgColor
                    }
                }
            }
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        if !isMouseOverButton {
            return
        }
        
        let locationInView = convert(event.locationInWindow, from: nil)
        for button in interactiveButtons {
            let buttonLocation = convert(locationInView, to: button)
            if button.bounds.contains(buttonLocation) {
                animateButtonPress(button)
                // The button's target-action will handle the actual click
                break
            }
        }
        
        super.mouseDown(with: event)
    }
    
    // Ensure proper behavior with trackpad
    override func scrollWheel(with event: NSEvent) {
        // Allow scroll events to pass through
    }
    
    override func magnify(with event: NSEvent) {
        // Allow magnification events to pass through
    }
    
    override func swipe(with event: NSEvent) {
        // Allow swipe events to pass through
    }
    
    override var acceptsFirstResponder: Bool {
        return false
    }
}