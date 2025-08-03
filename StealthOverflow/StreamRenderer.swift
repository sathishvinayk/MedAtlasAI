import Cocoa

// MARK: - StreamRenderer
enum StreamRenderer {
    static var windowResizeObserver: Any?
    static var debounceTimer: Timer?

    final class StreamMessageController {
        let textBlock: TextBlock
        // Unified synchronization
        private let stateLock = NSRecursiveLock()
        private let processingQueue = DispatchQueue(label: "stream.processor", qos: .userInteractive)
        private var displayLink: DisplayLink?
        
        // Protected state
        private var _isAnimating = false
        private var _fullTextBuffer = NSMutableAttributedString()
        private var _isInCodeBlock = false
        private var _codeBlockBuffer = ""
        private var _lastRenderTime: CFTimeInterval = 0
        
        // Constants
        private let minFrameInterval: CFTimeInterval = 1/60
        
        private let regularAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.textColor
        ]

        // Thread-safe property access
        private var isAnimating: Bool {
            get { stateLock.withLock { _isAnimating } }
            set { stateLock.withLock { _isAnimating = newValue } }
        }
        
        private var isInCodeBlock: Bool {
            get { stateLock.withLock { _isInCodeBlock } }
            set { stateLock.withLock { _isInCodeBlock = newValue } }
        }
        
        private var codeBlockBuffer: String {
            get { stateLock.withLock { _codeBlockBuffer } }
            set { stateLock.withLock { _codeBlockBuffer = newValue } }
        }
        
        private let codeBlockAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.textColor,
            .backgroundColor: NSColor.controlBackgroundColor
        ]
        
        private let inlineCodeAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .backgroundColor: NSColor.controlBackgroundColor.withAlphaComponent(0.3)
        ]

        init(textBlock: TextBlock) {
            self.textBlock = textBlock
        }
        
        func appendStreamingText(_ chunk: String, isComplete: Bool = false) {
            // Capture strong reference to textBlock
            let textBlock = self.textBlock
            
            processingQueue.async { [weak self] in
                guard let self = self else { return }
                
                let cleanedChunk = chunk.cleanedForStream()
                guard !cleanedChunk.isEmpty || isComplete else { return }
                
                let update = self.processChunk(cleanedChunk, isComplete: isComplete)
                
                // Ensure UI updates on main thread
                DispatchQueue.main.async {
                    // Verify textBlock still exists
                    guard textBlock.superview != nil else { return }
                    
                    self.commitUpdate(update, isComplete: isComplete)
                }
            }
        }
        
        private func processChunk(_ chunk: String, isComplete: Bool) -> NSMutableAttributedString {
            return stateLock.withLock {
                let update = NSMutableAttributedString()
                var remainingChunk = chunk
                
                if _isInCodeBlock {
                    if let closingRange = remainingChunk.range(of: "```") {
                        let codeContent = String(remainingChunk[..<closingRange.lowerBound])
                        _codeBlockBuffer += codeContent
                        
                        update.append(createCodeBlockDelimiter())
                        update.append(createCodeBlockContent(_codeBlockBuffer))
                        update.append(createCodeBlockDelimiter())
                        
                        _codeBlockBuffer = ""
                        _isInCodeBlock = false
                        remainingChunk = String(remainingChunk[closingRange.upperBound...])
                    } else {
                        _codeBlockBuffer += remainingChunk
                        return NSMutableAttributedString()
                    }
                }
                
                if !remainingChunk.isEmpty && !_isInCodeBlock {
                    if let openingRange = remainingChunk.range(of: "```") {
                        let textBefore = String(remainingChunk[..<openingRange.lowerBound])
                        if !textBefore.isEmpty {
                            update.append(processInlineText(textBefore))
                        }
                        
                        _isInCodeBlock = true
                        update.append(createCodeBlockDelimiter())
                        
                        let afterTicks = remainingChunk.index(openingRange.lowerBound, offsetBy: 3)
                        remainingChunk = String(remainingChunk[afterTicks...])
                        _codeBlockBuffer = remainingChunk
                        remainingChunk = ""
                    }
                    
                    if !remainingChunk.isEmpty {
                        update.append(processInlineText(remainingChunk))
                    }
                }
                
                if isComplete && _isInCodeBlock {
                    update.append(createCodeBlockDelimiter())
                    update.append(createCodeBlockContent(_codeBlockBuffer))
                    update.append(createCodeBlockDelimiter())
                    _codeBlockBuffer = ""
                    _isInCodeBlock = false
                }
                
                return update
            }
        }
        
        private func commitUpdate(_ update: NSMutableAttributedString, isComplete: Bool) {
               stateLock.withLock {
                   _fullTextBuffer.append(update)
                   let bufferCopy = _fullTextBuffer.copy() as! NSAttributedString
                   
                   DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        
                        // Prevent animation during streaming
                        NSAnimationContext.beginGrouping()
                        NSAnimationContext.current.duration = 0
                        NSAnimationContext.current.allowsImplicitAnimation = false
                        
                        self.textBlock.updateFullText(bufferCopy)
                        
                        NSAnimationContext.endGrouping()
                        
                        if isComplete {
                            self.stop()
                        } else {
                            self.startDisplayLinkIfNeeded()
                        }
                    }
               }
           }
        
        private func startDisplayLinkIfNeeded() {
            stateLock.withLock {
                guard !_isAnimating else { return }
                _isAnimating = true
                
                displayLink = DisplayLink { [weak self] in
                    self?.processPendingUpdates()
                }
                displayLink?.start()
            }
        }
        
        private func processPendingUpdates() {
            stateLock.withLock {
            let currentTime = CACurrentMediaTime()
            guard currentTime - _lastRenderTime >= minFrameInterval else { return }
            
            _lastRenderTime = currentTime
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self, 
                    !self._fullTextBuffer.string.isEmpty,
                    self.textBlock.superview != nil else { return }
                
                let bufferCopy = self._fullTextBuffer.copy() as! NSAttributedString
                self.textBlock.updateFullText(bufferCopy)
            }
        }
        }
        
        private func stop() {
            stateLock.withLock {
                _isAnimating = false
                displayLink?.stop()
                displayLink = nil
            }
        }
        
        func clear() {
            stateLock.withLock {
                _fullTextBuffer = NSMutableAttributedString()
                _isInCodeBlock = false
                _codeBlockBuffer = ""
                
                DispatchQueue.main.async { [weak self] in
                    self?.textBlock.textView.string = ""
                    self?.textBlock.updateHeight()
                }
            }
        }
        
        // Helper methods
        private func createRegularText(_ text: String) -> NSMutableAttributedString {
            return NSMutableAttributedString(string: text, attributes: regularAttributes)
        }
        
        private func createCodeBlockContent(_ text: String) -> NSMutableAttributedString {
            return NSMutableAttributedString(string: text, attributes: codeBlockAttributes)
        }
        
        private func createCodeBlockDelimiter() -> NSMutableAttributedString {
            return NSMutableAttributedString(string: "```\n", attributes: codeBlockAttributes)
        }
        
        private func processInlineText(_ text: String) -> NSMutableAttributedString {
            let result = NSMutableAttributedString()
            let parts = text.components(separatedBy: "`")
            
            for (index, part) in parts.enumerated() {
                if index % 2 == 0 {
                    result.append(createRegularText(part))
                } else {
                    result.append(NSMutableAttributedString(string: part, attributes: inlineCodeAttributes))
                }
            }
            
            return result
        }
    }

    // MARK: - TextBlock
    class TextBlock: NSView {
        private(set) var textView: NSTextView
        private var heightConstraint: NSLayoutConstraint?
        private let maxWidth: CGFloat
        private var isUpdatingLayout = false
        private var lastWindowState: (frame: NSRect, isZoomed: Bool)?
    
        init(maxWidth: CGFloat) {
            self.maxWidth = maxWidth

            let textStorage = NSTextStorage()
            let layoutManager = NSLayoutManager()
            textStorage.addLayoutManager(layoutManager)
            let textContainer = NSTextContainer(containerSize: NSSize(width: maxWidth, height: .greatestFiniteMagnitude))
            layoutManager.addTextContainer(textContainer)

            self.textView = NSTextView(frame: .zero, textContainer: textContainer)

            super.init(frame: .zero)
            setupTextView()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

         override func layout() {
            guard !isUpdatingLayout else { return }
            isUpdatingLayout = true
            defer { isUpdatingLayout = false }
            
            super.layout()
            
            // Update text container width
            textView.textContainer?.containerSize = NSSize(
                width: bounds.width, 
                height: .greatestFiniteMagnitude
            )
            
            updateHeight()
        }

        private func setupTextView() {
            textView.translatesAutoresizingMaskIntoConstraints = false
            textView.isEditable = false
            textView.isSelectable = true
            textView.drawsBackground = false
            textView.textContainerInset = NSSize(width: 8, height: 8)
            textView.textContainer?.lineFragmentPadding = 0
            textView.textContainer?.widthTracksTextView = true
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

        func updateFullText(_ text: NSAttributedString) {
            assert(Thread.isMainThread, "Text updates must be on main thread")
            guard let storage = textView.textStorage else { return }
            
            storage.beginEditing()
            storage.setAttributedString(text)
            storage.endEditing()
            
            // Trigger layout without recursion
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                context.allowsImplicitAnimation = false
                self.updateHeight()
            }
        }
        
        func updateHeight() {
            guard !isUpdatingLayout,
                let container = textView.textContainer,
                let layoutManager = textView.layoutManager else { return }
            
            isUpdatingLayout = true
            defer { isUpdatingLayout = false }
            
            // Calculate required height
            layoutManager.ensureLayout(for: container)
            let usedRect = layoutManager.usedRect(for: container)
            let totalHeight = ceil(usedRect.height) + textView.textContainerInset.height * 2
            
            // Update height constraint
            if let heightConstraint = heightConstraint {
                heightConstraint.constant = totalHeight
            } else {
                heightConstraint = heightAnchor.constraint(equalToConstant: totalHeight)
                heightConstraint?.isActive = true
            }
            
            // Safely request superview layout
            if let superview = superview, superview.inLiveResize {
                superview.needsLayout = true
            }
        }
    }

    // MARK: - Public Interface
    static func renderStreamingMessage() -> (NSView, StreamMessageController) {
        let maxWidth = calculateMaxWidth()

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let bubble = NSView()
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.wantsLayer = true
        bubble.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.6).cgColor
        bubble.layer?.cornerRadius = 10
        
        container.addSubview(bubble)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.distribution = .fill
        stack.alignment = .leading

        bubble.addSubview(stack)

        let textblock = TextBlock(maxWidth: maxWidth)
        stack.addArrangedSubview(textblock)

        let controller = StreamMessageController(textBlock: textblock)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -8),
            
            bubble.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            bubble.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
            bubble.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth),
            
            bubble.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            bubble.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -40)
        ])
        _ = setupWindowResizeHandler(for: stack)

        return (container, controller)
    }

    private static func calculateMaxWidth() -> CGFloat {
        let screenWidth = NSScreen.main?.visibleFrame.width ?? 800
        return min(screenWidth * 0.7, 800) // 70% of screen or 800px max
    }

    private static func setupWindowResizeHandler(for stack: NSStackView) -> Any? {
        guard let window = stack.window else { return nil }
        
        if let observer = windowResizeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        
        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak stack] notification in
            guard let stack = stack else { return }
            
            // Skip if we're in the middle of a maximize/minimize animation
            if let window = notification.object as? NSWindow, 
            window.styleMask.contains(.fullScreen) || 
            window.isZoomed {
                return
            }
            
            debounceTimer?.invalidate()
            debounceTimer = Timer.scheduledTimer(
                withTimeInterval: 0.25, // Slightly longer debounce for smoother transitions
                repeats: false
            ) { _ in
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.25
                    context.allowsImplicitAnimation = true
                    
                    stack.arrangedSubviews.forEach { view in
                        guard let textBlock = (view.subviews.first?.subviews.first as? NSStackView)?
                            .arrangedSubviews.first as? TextBlock else { return }
                        
                        // Use a more careful layout approach
                        textBlock.textView.textContainer?.containerSize = NSSize(
                            width: textBlock.bounds.width,
                            height: .greatestFiniteMagnitude
                        )
                        textBlock.needsUpdateConstraints = true
                        textBlock.needsLayout = true
                    }
                }
            }
        }
        
        windowResizeObserver = observer
        return observer
    }
}

extension String {
    func cleanedForStream() -> String {
        var cleaned = replacingOccurrences(of: "\0", with: "")
        cleaned = cleaned.filter { char in
            let value = char.unicodeScalars.first?.value ?? 0
            return (value >= 32 && value <= 126) || // ASCII printable
                   value == 10 || // Newline
                   value == 9 || // Tab
                   (value > 127 && value <= 0xFFFF) // Common Unicode
        }
        return cleaned
    }
}

// MARK: - NSLock Extension
extension NSLock {
    func withLock<T>(_ block: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try block()
    }
}
