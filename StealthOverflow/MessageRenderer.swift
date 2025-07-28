// MessageRenderer.swift
import Cocoa

// MARK: - High Performance Text Components

class TextBlockView: NSView {
    private let textView: NSTextView
    private let maxWidth: CGFloat
    private var heightConstraint: NSLayoutConstraint?
    
    init(attributedText: NSAttributedString, maxWidth: CGFloat) {
        self.maxWidth = maxWidth
        self.textView = NSTextView()
        super.init(frame: .zero)
        
        setupView()
        setupTextView()
        configure(with: attributedText)
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.masksToBounds = false
    }
    
    private func setupTextView() {
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textContainer?.lineFragmentPadding = 0
        textView.translatesAutoresizingMaskIntoConstraints = false
        
        // Performance optimizations
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: maxWidth, height: .greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        
        addSubview(textView)
        
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    
    private func configure(with attributedText: NSAttributedString) {
        textView.textStorage?.setAttributedString(attributedText)
        updateHeight()
    }
    
    func updateHeight() {
        guard let container = textView.textContainer,
              let layoutManager = textView.layoutManager else { return }
        
        layoutManager.ensureLayout(for: container)
        let usedRect = layoutManager.usedRect(for: container)
        let totalHeight = ceil(usedRect.height) + textView.textContainerInset.height * 2
        
        if let heightConstraint = heightConstraint {
            heightConstraint.constant = totalHeight
        } else {
            heightConstraint = heightAnchor.constraint(equalToConstant: totalHeight)
            heightConstraint?.isActive = true
        }
    }
    
    override func layout() {
        super.layout()
        updateHeight()
    }
}

class CodeBlockView: TextBlockView {
    init(code: String, maxWidth: CGFloat) {
        let attributedString = NSAttributedString(
            string: code,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor.white,
                .backgroundColor: NSColor.black.withAlphaComponent(0.9)
            ]
        )
        
        super.init(attributedText: attributedString, maxWidth: maxWidth)
        
        // Additional code block styling
        self.wantsLayer = true
        self.layer?.cornerRadius = 6
        self.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.9).cgColor
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - Message Renderer Implementation

enum MessageRenderer {
    private static var windowResizeObserver: NSObjectProtocol?
    private static var debounceTimer: Timer?
    
    static func renderMessage(_ message: String, isUser: Bool) -> (NSView, NSView) {
        let maxWidth = calculateMaxWidth()
        
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        
        let bubble = NSView()
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.wantsLayer = true
        bubble.layer?.backgroundColor = isUser 
            ? NSColor.systemBlue.withAlphaComponent(0.8).cgColor
            : NSColor.controlBackgroundColor.withAlphaComponent(0.6).cgColor
        bubble.layer?.cornerRadius = 10
        bubble.layer?.masksToBounds = true
        
        container.addSubview(bubble)
        
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.distribution = .fill
        stack.alignment = .leading
        
        bubble.addSubview(stack)
        
        // Parse and render message segments
        let segments = splitMarkdown(message)
        segments.forEach { segment in
            let contentWidth = maxWidth - 16 // Account for padding
            if segment.isCode {
                let codeView = CodeBlockView(code: segment.content, maxWidth: contentWidth)
                stack.addArrangedSubview(codeView)
            } else {
                let attributedText = attributedTextWithInlineCode(from: segment.content)
                let textBlock = TextBlockView(attributedText: attributedText, maxWidth: contentWidth)
                stack.addArrangedSubview(textBlock)
            }
        }
        
        // Setup constraints
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -8),
            
            bubble.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            bubble.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
            bubble.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth)
        ])
        
        // Position bubble based on sender
        if isUser {
            bubble.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8).isActive = true
            bubble.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 40).isActive = true
        } else {
            bubble.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8).isActive = true
            bubble.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -40).isActive = true
        }
        
        // Setup optimized window resize handling
        setupWindowResizeHandler(for: stack)
        
        return (container, bubble)
    }
    
    // MARK: - Private Helpers
    
    private static func calculateMaxWidth() -> CGFloat {
        let screenWidth = NSScreen.main?.visibleFrame.width ?? 800
        return min(screenWidth * 0.7, 800) // 70% of screen or 800px max
    }
    
    private static func setupWindowResizeHandler(for stack: NSStackView) {
        // Remove previous observer
        if let observer = windowResizeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        
        // Add debounced resize observer
        windowResizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: nil,
            queue: .main
        ) { _ in
            // Debounce to avoid layout thrashing
            MessageRenderer.debounceTimer?.invalidate()
            MessageRenderer.debounceTimer = Timer.scheduledTimer(
                withTimeInterval: 0.05,
                repeats: false
            ) { _ in
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.15
                    context.allowsImplicitAnimation = true
                    stack.arrangedSubviews.forEach { view in
                        view.needsLayout = true
                        view.layoutSubtreeIfNeeded()
                    }
                }
            }
        }
    }
    
    // MARK: - Markdown Parsing
    
    struct MessageSegment {
        let content: String
        let isCode: Bool
    }
    
    static func splitMarkdown(_ text: String) -> [MessageSegment] {
        var segments: [MessageSegment] = []
        var current = ""
        var insideCodeBlock = false
        
        let lines = text.components(separatedBy: .newlines)
        
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if insideCodeBlock {
                    segments.append(MessageSegment(content: current, isCode: true))
                    current = ""
                } else {
                    if !current.isEmpty {
                        segments.append(MessageSegment(content: current, isCode: false))
                        current = ""
                    }
                }
                insideCodeBlock.toggle()
                continue
            }
            
            current += line + "\n"
        }
        
        if !current.isEmpty {
            segments.append(MessageSegment(content: current, isCode: insideCodeBlock))
        }
        
        return segments
    }
    
    static func attributedTextWithInlineCode(from text: String) -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: 14)
        let codeFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        
        let attributed = NSMutableAttributedString()
        let parts = text.components(separatedBy: "`")
        
        for (index, part) in parts.enumerated() {
            if index % 2 == 0 {
                // Regular text
                attributed.append(NSAttributedString(
                    string: part,
                    attributes: [
                        .font: font,
                        .foregroundColor: NSColor.labelColor
                    ]
                ))
            } else {
                // Inline code
                attributed.append(NSAttributedString(
                    string: part,
                    attributes: [
                        .font: codeFont,
                        .foregroundColor: NSColor.systemOrange,
                        .backgroundColor: NSColor(white: 0.95, alpha: 1)
                    ]
                ))
            }
        }
        
        return attributed
    }
}