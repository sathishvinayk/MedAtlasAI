// MessageRenderer.swift
import Cocoa

private class DisplayLink {
    private var displayLink: Any?
    private let callback: () -> Void
    private var isReady = false
    
    init(callback: @escaping () -> Void) {
        self.callback = callback
        setupDisplayLink()
    }
    
    private func setupDisplayLink() {
        if #available(macOS 15.0, *) {
            displayLink = NSApplication.shared.mainWindow?.displayLink(
                target: self,
                selector: #selector(displayLinkCallback))
            isReady = true
        } else {
            var link: CVDisplayLink?
            let status = CVDisplayLinkCreateWithActiveCGDisplays(&link)
            guard status == kCVReturnSuccess, let link = link else {
                print("DisplayLink: Failed to create CVDisplayLink")
                return
            }
            
            let callbackStatus = CVDisplayLinkSetOutputCallback(link, { (_, _, _, _, _, context) -> CVReturn in
                let wrapper = unsafeBitCast(context, to: DisplayLink.self)
                wrapper.callback()
                return kCVReturnSuccess
            }, Unmanaged.passUnretained(self).toOpaque())
            
            guard callbackStatus == kCVReturnSuccess else {
                print("DisplayLink: Failed to set callback")
                return
            }
            
            let startStatus = CVDisplayLinkStart(link)
            guard startStatus == kCVReturnSuccess else {
                print("DisplayLink: Failed to start")
                return
            }
            
            displayLink = link
            isReady = true
        }
    }
    
    @objc private func displayLinkCallback() {
        guard isReady else { return }
        callback()
    }
    
    func invalidate() {
        if #available(macOS 15.0, *) {
            // NSWindow.displayLink doesn't need explicit invalidation
        } else if let link = displayLink {
            CVDisplayLinkStop(link as! CVDisplayLink)
        }
        displayLink = nil
        isReady = false
    }
    
    deinit {
        invalidate()
    }
}

// MARK: - Streaming Text Controller
final class StreamingTextController {
    private weak var textView: NSTextView?
    private var displayLink: DisplayLink?
    private var pendingUpdates: [String] = []
    private let updateQueue = DispatchQueue(label: "streaming.text.queue", qos: .userInteractive)
    private let updateLock = NSLock()
    private var lastRenderTime: CFTimeInterval = 0
    private let minFrameInterval: CFTimeInterval = 1/60 // 60 FPS
    private var isReady = false
    
    init(textView: NSTextView) {
        self.textView = textView
        configureTextView()
        setupDisplayLink()
    }
    
    private func setupDisplayLink() {
        displayLink = DisplayLink { [weak self] in
            self?.processPendingUpdates()
        }
    }
    
    @objc private func displayLinkCallback(_ sender: Any) {
        processPendingUpdates()
    }
    
    private func configureTextView() {
        textView?.layoutManager?.showsInvisibleCharacters = false
        textView?.layoutManager?.showsControlCharacters = false
        textView?.layoutManager?.backgroundLayoutEnabled = true
        textView?.layer?.drawsAsynchronously = true
        textView?.isEditable = false
        textView?.drawsBackground = false
    }
    
    func appendStreamingText(_ newText: String) {
        updateQueue.async { [weak self] in
            guard let self = self else { return }
            self.updateLock.lock()
            self.pendingUpdates.append(newText)
            self.updateLock.unlock()
            
            // If this is the first update, trigger immediate processing
            if !self.isReady {
                DispatchQueue.main.async {
                    self.processPendingUpdates()
                }
            }
        }
    }
    
    private func processPendingUpdates() {
        let currentTime = CACurrentMediaTime()
        guard currentTime - lastRenderTime >= minFrameInterval else { return }
        
        var updates: [String] = []
        updateLock.lock()
        if !pendingUpdates.isEmpty {
            updates = pendingUpdates
            pendingUpdates.removeAll()
        }
        updateLock.unlock()
        
        guard !updates.isEmpty else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let textView = self.textView,
                  textView.window != nil else {
                // Requeue updates if view isn't ready
                self?.updateLock.lock()
                self?.pendingUpdates.insert(contentsOf: updates, at: 0)
                self?.updateLock.unlock()
                return
            }
            
            let combinedUpdate = updates.joined()
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.1
                context.allowsImplicitAnimation = true
                
                textView.textStorage?.append(NSAttributedString(string: combinedUpdate))
                
                if let scrollView = textView.enclosingScrollView {
                    let visibleRect = scrollView.documentVisibleRect
                    let maxY = scrollView.documentView?.bounds.maxY ?? 0
                    if maxY - visibleRect.maxY < 50 {
                        scrollView.documentView?.scroll(NSPoint(x: 0, y: maxY))
                    }
                }
            }, completionHandler: nil)
            
            self.lastRenderTime = currentTime
            self.isReady = true
        }
    }
    
    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    deinit {
        stop()
    }
}

// MARK: - Text Block View
class TextBlockView: NSView {
    let textView = NSTextView()
    private(set) var isStreaming = false
    private var heightConstraint: NSLayoutConstraint?
    private var streamingController: StreamingTextController?
    private let maxWidth: CGFloat
    
    init(attributedText: NSAttributedString? = nil, maxWidth: CGFloat) {
        self.maxWidth = maxWidth
        super.init(frame: .zero)
        setupTextView()
        
        if let attributedText = attributedText {
            setCompleteText(attributedText)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupTextView() {
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: maxWidth, height: .greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false
        
        addSubview(textView)
        
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth)
        ])
    }
    
    func beginStreaming() {
        guard !isStreaming else { return }
        isStreaming = true
        
        if window != nil {
            streamingController = StreamingTextController(textView: textView)
        } else {
            // Wait for window to be available
            DispatchQueue.main.async { [weak self] in
                self?.beginStreaming()
            }
        }
    }
    
    func appendStreamingText(_ text: String) {
        if !isStreaming {
            beginStreaming()
        }
        streamingController?.appendStreamingText(text)
        updateHeight()
    }
    
    func setCompleteText(_ text: NSAttributedString) {
        streamingController?.stop()
        isStreaming = false
        textView.textStorage?.setAttributedString(text)
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
        if !isStreaming {
            updateHeight()
        }
    }
}

// MARK: - Code Block View
final class CodeBlockView: TextBlockView {
    init(code: String, maxWidth: CGFloat) {
        super.init(maxWidth: maxWidth)
        configureCodeAppearance()
        setCompleteText(NSAttributedString(
            string: code,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor.white
            ]
        ))
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func configureCodeAppearance() {
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .white
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.9).cgColor
    }
    
    override func appendStreamingText(_ text: String) {
        let attributedString = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.white
        ])
        
        if isStreaming {
            textView.textStorage?.append(attributedString)
        } else {
            beginStreaming()
            textView.textStorage?.append(attributedString)
        }
        updateHeight()
    }
}
// MARK: - Message Renderer
enum MessageRenderer {
    private static var windowResizeObserver: Any?
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
        
        setupWindowResizeHandler(for: stack)
        
        return (container, bubble)
    }
    
    // MARK: - Private Helpers
    
    private static func calculateMaxWidth() -> CGFloat {
        let screenWidth = NSScreen.main?.visibleFrame.width ?? 800
        return min(screenWidth * 0.7, 800) // 70% of screen or 800px max
    }
    
    private static func setupWindowResizeHandler(for stack: NSStackView) {
        if let observer = windowResizeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        
        windowResizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: nil,
            queue: .main
        ) { _ in
            MessageRenderer.debounceTimer?.invalidate()
            MessageRenderer.debounceTimer = Timer.scheduledTimer(
                withTimeInterval: 0.05,
                repeats: false
            ) { _ in
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.15
                    context.allowsImplicitAnimation = true
                    stack.arrangedSubviews.forEach {
                        $0.needsLayout = true
                        $0.layoutSubtreeIfNeeded()
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
                attributed.append(NSAttributedString(
                    string: part,
                    attributes: [
                        .font: font,
                        .foregroundColor: NSColor.labelColor
                    ]
                ))
            } else {
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
