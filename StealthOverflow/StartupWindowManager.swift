import Cocoa

class StartupWindowManager {
    private var window: NSWindow?
    private var chatButton: NSButton?
    var onStartChat: (() -> Void)?
    
    func createStartupWindow() -> NSWindow? {
        let windowWidth: CGFloat = 400
        let windowHeight: CGFloat = 500
        let screenFrame = NSScreen.main?.frame ?? .zero
        let windowRect = NSRect(
            x: screenFrame.midX - windowWidth/2,
            y: screenFrame.midY - windowHeight/2,
            width: windowWidth,
            height: windowHeight
        )
        
        window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        guard let window = window else { return nil }
        
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        
        let contentView = NSView(frame: window.contentView!.bounds)
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
        window.contentView = contentView
        
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            logo.widthAnchor.constraint(equalToConstant: 150),
            logo.heightAnchor.constraint(equalToConstant: 150),
            chatButton!.widthAnchor.constraint(equalToConstant: 200)
        ])
        
        return window
    }
    
    @objc private func handleChatButton() {
        onStartChat?()
        window?.close()
    }
    
    func close() {
        window?.close()
        window = nil
        chatButton = nil
    }
}
