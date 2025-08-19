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
        startupWindow.backgroundColor = NSColor.windowBackgroundColor
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
        titleLabel.font = NSFont.systemFont(ofSize: 32, weight: .bold)
        
        // Logo
        let logo = NSImageView()
        logo.image = NSImage(named: "AppIcon") ?? NSImage(systemSymbolName: "message", accessibilityDescription: nil)
        logo.imageScaling = .scaleProportionallyUpOrDown
        
        // Chat Button
        chatButton = NSButton(title: "Chat", target: self, action: #selector(handleChatButton))
        chatButton?.bezelStyle = .rounded
        chatButton?.font = NSFont.systemFont(ofSize: 18)
        
        // Stack View
        let stackView = NSStackView(views: [titleLabel, logo, chatButton!])
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 30
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(stackView)
        contentView.managerWindow = startupWindow // Use different property name
        contentView.interactiveButton = chatButton
        
        startupWindow.contentView = contentView
        
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            logo.widthAnchor.constraint(equalToConstant: 150),
            logo.heightAnchor.constraint(equalToConstant: 150),
            chatButton!.widthAnchor.constraint(equalToConstant: 100)
        ])
        
        return startupWindow
    }
    
    func setupTracking() {
        guard let startupWindow = startupWindow, let contentView = startupWindow.contentView as? InteractiveContentView else { return }
        
        // Remove existing tracking area if any
        if let existingArea = trackingArea {
            startupWindow.contentView?.removeTrackingArea(existingArea)
        }
        
        // Create tracking area for the entire content view
        let newTrackingArea = NSTrackingArea(
            rect: startupWindow.contentView!.bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved],
            owner: contentView,
            userInfo: nil
        )
        
        startupWindow.contentView?.addTrackingArea(newTrackingArea)
        trackingArea = newTrackingArea
    }
    
    @objc private func handleChatButton() {
        print("Chat button clicked!")
        onStartChat?()
        close()
    }
    
    func show() {
        startupWindow?.makeKeyAndOrderFront(nil)
        setupTracking()
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func close() {
        if let area = trackingArea, let contentView = startupWindow?.contentView {
            contentView.removeTrackingArea(area)
        }
        trackingArea = nil
        NSCursor.arrow.set()
        startupWindow?.close()
        startupWindow = nil
        chatButton = nil
    }
    
    deinit {
        close()
    }
}

class InteractiveContentView: NSView {
    weak var managerWindow: NSWindow? // Renamed to avoid conflict with NSView.window
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
            managerWindow.ignoresMouseEvents = false // Enable mouse events for button
            NSCursor.pointingHand.set()
        } else {
            isMouseOverButton = false
            managerWindow.ignoresMouseEvents = true // Disable mouse events
            NSCursor.arrow.set()
        }
    }
    
    // Handle the case where mouse is already over button when window appears
    override func mouseDown(with event: NSEvent) {
        // If mouse is over button, let the button handle the event
        if !isMouseOverButton {
            // Ignore clicks outside button area
            return
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