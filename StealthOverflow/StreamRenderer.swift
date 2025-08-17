import Cocoa

enum StreamRenderer {
    static var windowResizeObserver: Any?
    static var debounceTimer: Timer?
    
    // MARK: - Public Interface
    static func renderStreamingMessage() -> (NSView, StreamMessageController) {
        let maxWidth = calculateMaxWidth()
        
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let bubble = NSView()
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.wantsLayer = true
        // bubble.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.6).cgColor
        bubble.layer?.cornerRadius = 10
        
        container.addSubview(bubble)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.distribution = .fill
        stack.alignment = .leading

        bubble.addSubview(stack)

        let controller = StreamMessageController(
            containerView: container, 
            stackView: stack, 
            maxWidth: maxWidth
        )

        let bubbleWidth = bubble.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -8)
        bubbleWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -4),
            stack.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -2),
            
            bubble.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            bubble.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),

            bubbleWidth,
            bubble.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            bubble.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth),

            bubble.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bubble.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
        ])

        _ = setupWindowResizeHandler(for: bubble, container: container)

        return (container, controller)
    }

    private static func calculateMaxWidth() -> CGFloat {
        let screenWidth = NSScreen.main?.visibleFrame.width ?? 800
        return min(screenWidth * 1, 800)
    }

    private static func setupWindowResizeHandler(for bubble: NSView, container: NSView) -> Any? {
        guard let window = bubble.window else { return nil }
        
        return NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { _ in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.allowsImplicitAnimation = true
                
                if let constraint = bubble.constraints.first(where: {
                    $0.firstAttribute == .width &&
                    $0.secondAttribute == .width &&
                    $0.secondItem === container
                }) {
                    constraint.constant = -5
                }
                
                container.needsLayout = true
                container.layoutSubtreeIfNeeded()
            }
        }
    }

    private static func updateStackLayout(_ stack: NSStackView) {
        stack.arrangedSubviews.forEach { view in
            guard let textBlock = view.subviews.first?.subviews.first as? TextBlock else { return }
            textBlock.textView.textContainer?.containerSize = NSSize(
                width: textBlock.bounds.width,
                height: .greatestFiniteMagnitude
            )
            textBlock.needsUpdateConstraints = true
            textBlock.needsLayout = true
        }
    }
}