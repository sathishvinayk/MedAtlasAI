import Cocoa

class StartupWindowManager: NSObject {
    private var startupWindow: NSWindow?
    private var chatButton: NSButton?
    private var codeChatButton: NSButton?
    var onStartChat: (() -> Void)?
    var onStartCodeChat: (() -> Void)?

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
        startupWindow.level = .normal
        startupWindow.hasShadow = true
        startupWindow.alphaValue = 0.7
        startupWindow.isMovable = true // Enable window moving
        
        let contentView = MovableView(frame: startupWindow.contentView!.bounds)
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 8
        contentView.layer?.masksToBounds = true
        contentView.managedWindow = startupWindow
        
        // Logo
        let logo = NSImageView()
        logo.image = NSImage(named: "AppIcon") ?? NSImage(systemSymbolName: "message", accessibilityDescription: nil)
        logo.imageScaling = .scaleProportionallyUpOrDown

        // Title
        let titleLabel = NSTextField(labelWithString: "MedAtlasAI")
        if let oxaniumFont = NSFont(name: "Oxanium-Bold", size: 32) {
            let attributedString = NSAttributedString(
                string: "MedAtlasAI",
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

        let subTitle = NSTextField(labelWithString: "A Medical AI Coding Assistant")
        if let lato = NSFont(name: "Lato-Italic", size: 14) {
            let attributedString = NSAttributedString(
                string: "A Medical AI Coding Assistant",
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

        // Chat Button with hover effects
        chatButton = createChatButton(title: "Chat AI", action: #selector(handleChatButton))
        
        // "Press esc to quit" text with keycap style
        let escKeycap = createKeycapView(text: "esc")
        let pressText = NSTextField(labelWithString: "Press")
        let toQuitText = NSTextField(labelWithString: "to quit")
        
        // Style the text labels
        if let lato = NSFont(name: "Lato-Regular", size: 12) {
            let pressAttributedString = NSAttributedString(
                string: "Press",
                attributes: [
                    .font: lato,
                    .foregroundColor: NSColor.white.withAlphaComponent(0.8)
                ]
            )
            pressText.attributedStringValue = pressAttributedString
            
            let quitAttributedString = NSAttributedString(
                string: "to quit",
                attributes: [
                    .font: lato,
                    .foregroundColor: NSColor.white.withAlphaComponent(0.8)
                ]
            )
            toQuitText.attributedStringValue = quitAttributedString
        }
        
        pressText.isBordered = false
        pressText.backgroundColor = .clear
        pressText.isEditable = false
        toQuitText.isBordered = false
        toQuitText.backgroundColor = .clear
        toQuitText.isEditable = false
        
        // Horizontal stack for the full text with keycap
        let escStack = NSStackView(views: [pressText, escKeycap, toQuitText])
        escStack.orientation = .horizontal
        escStack.spacing = 6
        escStack.alignment = .centerY
        
        // Main stack view for all content
        let mainStackView = NSStackView(views: [logo, titleLabel, subTitle, chatButton!, escStack])
        mainStackView.orientation = .vertical
        mainStackView.alignment = .centerX
        mainStackView.spacing = 2
        mainStackView.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(mainStackView)
        startupWindow.contentView = contentView
        
        NSLayoutConstraint.activate([
            mainStackView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            mainStackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -30),
            
            // Element sizes
            logo.widthAnchor.constraint(equalToConstant: 200),
            logo.heightAnchor.constraint(equalToConstant: 200),
            chatButton!.widthAnchor.constraint(equalToConstant: 80),
            chatButton!.heightAnchor.constraint(equalToConstant: 30),
            escKeycap.widthAnchor.constraint(equalToConstant: 40),
            escKeycap.heightAnchor.constraint(equalToConstant: 24)
        ])

        // Add some spacing between elements
        mainStackView.setCustomSpacing(-20, after: logo)
        mainStackView.setCustomSpacing(10, after: titleLabel)
        mainStackView.setCustomSpacing(50, after: subTitle)
        mainStackView.setCustomSpacing(50, after: chatButton!)
        mainStackView.setCustomSpacing(30, after: escStack)
        
        return startupWindow
    }
    
    private func createChatButton(title: String, action: Selector) -> NSButton {
        let button = HoverButton(title: title, target: self, action: action)
        button.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        button.wantsLayer = true
        button.isBordered = false
        button.contentTintColor = .white
        button.setButtonType(.momentaryPushIn)
        button.layer?.cornerRadius = 6
        button.layer?.masksToBounds = true
        button.layer?.backgroundColor = NSColor.systemBlue.cgColor
        
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 14, weight: .semibold)
            ]
        )
        
        return button
    }
    
    private func createKeycapView(text: String) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 4
        container.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.3).cgColor
        
        let label = NSTextField(labelWithString: text.uppercased())
        if let font = NSFont.systemFont(ofSize: 10, weight: .medium) {
            let attributedString = NSAttributedString(
                string: text.uppercased(),
                attributes: [
                    .font: font,
                    .foregroundColor: NSColor.white.withAlphaComponent(0.9),
                    .kern: 0.5
                ]
            )
            label.attributedStringValue = attributedString
        }
        label.alignment = .center
        
        container.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            container.widthAnchor.constraint(equalToConstant: 40),
            container.heightAnchor.constraint(equalToConstant: 24)
        ])
        
        return container
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
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func close() {
        DispatchQueue.main.async {
            self.startupWindow?.close()
        }
        
        self.startupWindow = nil
        self.chatButton = nil
        self.codeChatButton = nil
    }
    
    deinit {
        startupWindow?.close()
        chatButton = nil
        codeChatButton = nil
    }
}

// Simple HoverButton class for hover animations
class HoverButton: NSButton {
    private var trackingArea: NSTrackingArea?
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        animateHover(true)
        NSCursor.pointingHand.set()
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        animateHover(false)
        NSCursor.arrow.set()
    }
    
    private func animateHover(_ isHovering: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.allowsImplicitAnimation = true
            
            if isHovering {
                self.layer?.backgroundColor = NSColor.systemBlue.withSystemEffect(.pressed).cgColor
                self.layer?.borderWidth = 1.0
                self.layer?.borderColor = NSColor.systemBlue.cgColor
            } else {
                self.layer?.backgroundColor = NSColor.systemBlue.cgColor
                self.layer?.borderWidth = 0
                self.layer?.borderColor = nil
            }
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        animatePress()
        super.mouseDown(with: event)
    }
    
    private func animatePress() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            self.layer?.backgroundColor = NSColor.systemBlue.withSystemEffect(.deepPressed).cgColor
        } completionHandler: {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.1
                if self.isMouseOverButton() {
                    self.layer?.backgroundColor = NSColor.systemBlue.withSystemEffect(.pressed).cgColor
                } else {
                    self.layer?.backgroundColor = NSColor.systemBlue.cgColor
                }
            }
        }
    }
    
    private func isMouseOverButton() -> Bool {
        guard let window = self.window else { return false }
        let mouseLocation = NSEvent.mouseLocation
        let windowFrame = window.frame
        let buttonFrame = self.convert(self.bounds, to: nil)
        let actualButtonFrame = NSRect(
            x: windowFrame.origin.x + buttonFrame.origin.x,
            y: windowFrame.origin.y + buttonFrame.origin.y,
            width: buttonFrame.width,
            height: buttonFrame.height
        )
        return actualButtonFrame.contains(mouseLocation)
    }
}

// View that enables click-and-drag window movement
class MovableView: NSView {
    weak var managedWindow: NSWindow?
    private var initialLocation: NSPoint?
    
    override func mouseDown(with event: NSEvent) {
        // Only handle movement if not clicking on a button
        if let hitView = hitTest(event.locationInWindow), hitView is NSButton {
            super.mouseDown(with: event)
            return
        }
        
        initialLocation = event.locationInWindow
        NSCursor.closedHand.set()
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard let window = managedWindow, let initialLocation = initialLocation else {
            super.mouseDragged(with: event)
            return
        }
        
        let currentLocation = event.locationInWindow
        let deltaX = currentLocation.x - initialLocation.x
        let deltaY = currentLocation.y - initialLocation.y
        
        var newOrigin = window.frame.origin
        newOrigin.x += deltaX
        newOrigin.y += deltaY
        
        window.setFrameOrigin(newOrigin)
    }
    
    override func mouseUp(with event: NSEvent) {
        initialLocation = nil
        NSCursor.arrow.set()
        super.mouseUp(with: event)
    }
    
    // Allow the view to become first responder to receive mouse events
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    override func becomeFirstResponder() -> Bool {
        return true
    }
}
