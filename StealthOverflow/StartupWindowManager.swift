import Cocoa

class StartupWindowManager: NSObject {
    private var startupWindow: NSWindow?
    private var chatButton: NSButton?
    private var trackingArea: NSTrackingArea?
    var onStartChat: (() -> Void)?
    
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
        startupWindow.backgroundColor = .appBackground // FIXED: Use standard color instead of .appBackground
        startupWindow.level = .floating
        startupWindow.hasShadow = true
        startupWindow.alphaValue = 0.7
        startupWindow.isMovable = false
        startupWindow.ignoresMouseEvents = true // Start ignoring all mouse events
        
        let contentView = InteractiveContentView(frame: startupWindow.contentView!.bounds)
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 8
        contentView.layer?.masksToBounds = true
        
        // Title
        let titleLabel = NSTextField(labelWithString: "Silent Glass")
        titleLabel.font = NSFont.systemFont(ofSize: 22)
        titleLabel.textColor = .labelColor
        
        // Logo
        let logo = NSImageView()
        logo.image = NSImage(named: "AppIcon") ?? NSImage(systemSymbolName: "message", accessibilityDescription: nil)
        logo.imageScaling = .scaleProportionallyUpOrDown
        
        // Chat Button - Modern styling
        chatButton = NSButton(title: "Chat AI", target: self, action: #selector(handleChatButton))
        // chatButton?.bezelStyle = .rounded
        chatButton?.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        chatButton?.wantsLayer = true
        
        // Modern button styling with hover effects
        chatButton?.isBordered = false
        chatButton?.contentTintColor = .white
        chatButton?.setButtonType(.momentaryPushIn)
        
        // Stack View
        let stackView = NSStackView(views: [titleLabel, logo, chatButton!])
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 30
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(stackView)
        contentView.managerWindow = startupWindow
        contentView.interactiveButton = chatButton
        
        startupWindow.contentView = contentView
        
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            logo.widthAnchor.constraint(equalToConstant: 150),
            logo.heightAnchor.constraint(equalToConstant: 150),
            chatButton!.widthAnchor.constraint(equalToConstant: 80),
            chatButton!.heightAnchor.constraint(equalToConstant: 30)
        ])
        
        // Set up button layer after constraints are applied
        DispatchQueue.main.async {
            self.chatButton?.layer?.cornerRadius = 6
            self.chatButton?.layer?.masksToBounds = true
            self.chatButton?.layer?.backgroundColor = NSColor.systemBlue.cgColor
            
            // Set attributed title after button is fully configured
            self.chatButton?.attributedTitle = NSAttributedString(
                string: "Chat AI",
                attributes: [
                    .foregroundColor: NSColor.white,
                    .font: NSFont.systemFont(ofSize: 14, weight: .semibold)
                ]
            )
        }
        
        return startupWindow
    }
    
    func setupTracking() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                let startupWindow = self.startupWindow,
                let contentView = startupWindow.contentView else { return }
            
            // Remove existing tracking area if any
            if let existingArea = self.trackingArea {
                contentView.removeTrackingArea(existingArea)
            }
            
            // Use full window tracking for simplicity and reliability
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
    
    func show() {
        guard let startupWindow = startupWindow else { return }
        
        startupWindow.makeKeyAndOrderFront(nil)
        setupTracking()
        NSApp.activate(ignoringOtherApps: true)
        
        // Force initial mouse position check with a slight delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let contentView = startupWindow.contentView as? InteractiveContentView {
                contentView.checkInitialMousePosition()
            }
        }
    }
    
    func close() {
        // Capture weak references to avoid potential retain cycles
        let trackingArea = self.trackingArea
        let startupWindow = self.startupWindow
        
        // Clean up on main thread
        DispatchQueue.main.async { 
            
            // Remove tracking area safely
            if let area = trackingArea, let contentView = startupWindow?.contentView {
                contentView.removeTrackingArea(area)
            }
            
            // Reset cursor
            NSCursor.arrow.set()
            
            // Close window
            startupWindow?.close()
        }
        // Clear references on main thread
        self.trackingArea = nil
        self.startupWindow = nil
        self.chatButton = nil
    }
    
    deinit {
        startupWindow?.close()
        trackingArea = nil
        chatButton = nil
    }
}

class InteractiveContentView: NSView {
    weak var managerWindow: NSWindow?
    weak var interactiveButton: NSButton?
    private var isMouseOverButton = false
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        // Remove old tracking areas
        for trackingArea in trackingAreas {
            removeTrackingArea(trackingArea)
        }
        
        // Add tracking for the entire view
        let options: NSTrackingArea.Options = [.activeAlways, .mouseEnteredAndExited, .mouseMoved]
        let trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
    }
    
    func checkInitialMousePosition() {
        guard let managerWindow = managerWindow,
              let button = interactiveButton else {
            return
        }
        
        // Get the current mouse position
        let mouseLocation = NSEvent.mouseLocation
        let windowFrame = managerWindow.frame
        
        // Check if mouse is within window bounds
        if windowFrame.contains(mouseLocation) {
            // Convert to window coordinates
            let locationInWindow = NSPoint(
                x: mouseLocation.x - windowFrame.origin.x,
                y: mouseLocation.y - windowFrame.origin.y
            )
            
            // Convert to view coordinates
            let locationInView = convert(locationInWindow, from: nil)
            
            // Convert to button coordinates
            let buttonLocation = convert(locationInView, to: button)
            
            // Check if mouse is over button
            if button.bounds.contains(buttonLocation) {
                isMouseOverButton = true
                managerWindow.ignoresMouseEvents = false
                NSCursor.pointingHand.set()
                animateButtonHover(true, button: button)
                return
            }
        }
        
        // If not over button or not in window
        isMouseOverButton = false
        managerWindow.ignoresMouseEvents = true
        NSCursor.arrow.set()
        animateButtonHover(false, button: interactiveButton)
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
        animateButtonHover(false, button: interactiveButton)
    }
    
    private func checkMousePosition(_ event: NSEvent) {
        guard let button = interactiveButton, let managerWindow = managerWindow else {
            managerWindow?.ignoresMouseEvents = true
            NSCursor.arrow.set()
            return
        }
        
        let locationInView = convert(event.locationInWindow, from: nil)
        let buttonLocation = convert(locationInView, to: button)
        
        if button.bounds.contains(buttonLocation) {
            isMouseOverButton = true
            managerWindow.ignoresMouseEvents = false
            NSCursor.pointingHand.set()
            animateButtonHover(true, button: button)
        } else {
            isMouseOverButton = false
            managerWindow.ignoresMouseEvents = true
            NSCursor.arrow.set()
            animateButtonHover(false, button: button)
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
                
                // Remove this line - corner radius is already set initially
                // button.layer?.cornerRadius = 12
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
                    // Check if mouse is still over button using a safe approach
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
        // If mouse is over button, let the button handle the event
        if !isMouseOverButton {
            // Ignore clicks outside button area
            return
        }
        
        // Button press animation
        if let button = interactiveButton {
            animateButtonPress(button)
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
