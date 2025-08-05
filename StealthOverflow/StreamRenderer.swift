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
        private var lastProcessedLength: Int = 0
        
        // Protected state
        private var _isAnimating = false
        private var _fullTextBuffer = NSMutableAttributedString()
        private var _isInCodeBlock = false
        private var _lastDisplayedLength = 0
        private var _codeBlockBuffer = ""
        private var _lastRenderTime: CFTimeInterval = 0
        private var _lastProcessedChunk: String = ""
        
        // Constants
        private let minFrameInterval: CFTimeInterval = 1/60
 

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

        private func createCodeBlockDelimiter() -> NSMutableAttributedString {
            let delimiter = NSMutableAttributedString(string: "```\n", attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.systemGray,
                .backgroundColor: NSColor.controlBackgroundColor
            ])
            return delimiter
        }
        
        private let codeBlockAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.textColor,
            .backgroundColor: NSColor.controlBackgroundColor,
            .paragraphStyle: {
                let style = NSMutableParagraphStyle()
                style.lineHeightMultiple = 1.2
                style.paragraphSpacing = 8
                return style
            }()
        ]

        private let regularAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: {
                let style = NSMutableParagraphStyle()
                style.lineHeightMultiple = 1.2
                return style
            }()
        ]

        private let inlineCodeAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.systemOrange,
            .backgroundColor: NSColor.controlBackgroundColor.withAlphaComponent(0.3),
            .baselineOffset: 0
        ]

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
                        segments.append(.init(content: current, isCode: true))
                        current = ""
                    } else {
                        if !current.isEmpty {
                            segments.append(.init(content: current, isCode: false))
                            current = ""
                        }
                    }
                    insideCodeBlock.toggle()
                    continue
                }

                current += line + "\n"
            }

            if !current.isEmpty {
                segments.append(.init(content: current, isCode: insideCodeBlock))
            }

            return segments 
        }

        init(textBlock: TextBlock) {
            self.textBlock = textBlock
        }

        
        func clear() {
            stateLock.withLock {
                _fullTextBuffer = NSMutableAttributedString()
                _lastDisplayedLength = 0
                _lastProcessedChunk = ""
                _isInCodeBlock = false
                _codeBlockBuffer = ""
                
                // Don't clear the text view - it should maintain its content
                // Removed: self?.textBlock.textView.string = ""
            }
        }

        func appendStreamingText(_ chunk: String, isComplete: Bool = false) {
            processingQueue.async { [weak self] in
                guard let self = self else { return }
                
                self.stateLock.withLock {
                    // Calculate the new text by finding the difference from last chunk
                    let newText: String
                    if chunk.hasPrefix(self._lastProcessedChunk) {
                        let startIndex = chunk.index(chunk.startIndex, offsetBy: self._lastProcessedChunk.count)
                        newText = String(chunk[startIndex...])
                    } else {
                        // If prefix doesn't match, use whole chunk (fallback)
                        newText = chunk
                    }
                    
                    // Update the last processed chunk
                    self._lastProcessedChunk = chunk
                    
                    // Append to buffer
                    self._fullTextBuffer.append(NSAttributedString(
                        string: newText,
                        attributes: self.regularAttributes
                    ))
                    
                     DispatchQueue.main.async {
                        guard self.textBlock.superview != nil else { return }
                        
                        if isComplete {
                            // Final render with markdown processing
                            let segments = Self.splitMarkdown(self._fullTextBuffer.string)
                            let formatted = self.formatSegments(segments)
                            self.textBlock.updateFullText(formatted)
                        } else {
                            // For streaming, append only the new text
                            self.textBlock.textView.textStorage?.append(NSAttributedString(
                                string: newText,
                                attributes: self.regularAttributes
                            ))
                            self.textBlock.updateHeight()
                        }
                    }
                }
            }
        }

        private func formatSegments(_ segments: [MessageSegment]) -> NSAttributedString {
            let result = NSMutableAttributedString()
            for segment in segments {
                if segment.isCode {
                    result.append(createCodeBlockDelimiter())
                    result.append(createCodeBlockContent(segment.content))
                    result.append(createCodeBlockDelimiter())
                } else {
                    result.append(NSAttributedString(
                        string: segment.content,
                        attributes: regularAttributes
                    ))
                }
            }
            return result
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
        
        // Helper methods
        private func createRegularText(_ text: String) -> NSMutableAttributedString {
            return NSMutableAttributedString(string: text, attributes: regularAttributes)
        }
        
        private func createCodeBlockContent(_ text: String) -> NSMutableAttributedString {
            // Clean up the code content
            let cleanedText = text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\t", with: "    ") // Convert tabs to spaces
            
            let content = NSMutableAttributedString(string: cleanedText + "\n", attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.textColor,
                .backgroundColor: NSColor.controlBackgroundColor,
                .paragraphStyle: {
                    let style = NSMutableParagraphStyle()
                    style.lineHeightMultiple = 1.2
                    style.paragraphSpacing = 4
                    return style
                }()
            ])
            return content
        }
        
        private func processInlineText(_ text: String) -> NSMutableAttributedString {
            let result = NSMutableAttributedString(string: text, attributes: regularAttributes)
            
            // Only process backticks if they come in pairs
            let backtickCount = text.filter { $0 == "`" }.count
            guard backtickCount >= 2 && backtickCount % 2 == 0 else {
                return result
            }
            
            var backtickRanges = [Range<String.Index>]()
            var currentIndex = text.startIndex
            
            // Find all backtick pairs
            while let range = text.range(of: "`", range: currentIndex..<text.endIndex) {
                backtickRanges.append(range)
                currentIndex = range.upperBound
            }
            
            // Apply formatting to text between backtick pairs
            for i in stride(from: 0, to: backtickRanges.count, by: 2) {
                if i+1 >= backtickRanges.count { break }
                
                let start = backtickRanges[i].upperBound
                let end = backtickRanges[i+1].lowerBound
                let codeRange = NSRange(start..<end, in: text)
                
                if codeRange.location != NSNotFound {
                    result.setAttributes(inlineCodeAttributes, range: codeRange)
                    
                    // Remove the backticks themselves from display
                    let openingRange = NSRange(backtickRanges[i], in: text)
                    let closingRange = NSRange(backtickRanges[i+1], in: text)
                    result.replaceCharacters(in: closingRange, with: "")
                    result.replaceCharacters(in: openingRange, with: "")
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
    
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observeWindowState()
        }

        private func observeWindowState() {
            guard let window = window else { return }
            
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidChangeState),
                name: NSWindow.didResizeNotification,
                object: window
            )
        }

        @objc private func windowDidChangeState() {
            guard let window = window else { return }
            
            let currentState = (window.frame, window.isZoomed)
            if let lastState = lastWindowState, lastState == currentState {
                return
            }
            
            lastWindowState = currentState
            
            // Force a layout update when window state changes
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.allowsImplicitAnimation = true
                self.updateHeight()
            }
        }
        override func layout() {
            super.layout()
            
            // Calculate available width (subtracting 10 for margins + 16 for internal padding)
            let availableWidth = max(bounds.width - 52, 150) // Never go below 150
            
            textView.textContainer?.containerSize = NSSize(
                width: availableWidth,
                height: .greatestFiniteMagnitude
            )
            
            updateHeight()
        }
    
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

        private func setupTextView() {
            textView.translatesAutoresizingMaskIntoConstraints = false
            textView.isEditable = false
            textView.isSelectable = true
            textView.drawsBackground = false
            textView.textContainerInset = NSSize(width: 8, height: 8)
            textView.textContainer?.lineFragmentPadding = 0
            textView.textContainer?.widthTracksTextView = true
            textView.isHorizontallyResizable = false
            textView.layoutManager?.allowsNonContiguousLayout = false
            
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
            print("text -> \(text)")
            
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
        // Create dynamic width constraints
        let bubbleWidth = bubble.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -10)
        bubbleWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -8),
            
            bubble.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            bubble.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
            
            bubbleWidth,
            bubble.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth),
            bubble.widthAnchor.constraint(greaterThanOrEqualToConstant: 200), // Absolute minimum
            
            bubble.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            bubble.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -8),
             
        ])
        
        _ = setupWindowResizeHandler(for: bubble, container: container)

        return (container, controller)
    }

    private static func calculateMaxWidth() -> CGFloat {
        let screenWidth = NSScreen.main?.visibleFrame.width ?? 800
        return min(screenWidth * 0.7, 800) // 70% of screen or 800px max
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
                
                // Update the bubble's width constraint
                if let constraint = bubble.constraints.first(where: {
                    $0.firstAttribute == .width &&
                    $0.secondAttribute == .width &&
                    $0.secondItem === container
                }) {
                    constraint.constant = -10 // Maintain the 10pt offset
                }
                
                container.needsLayout = true
                container.layoutSubtreeIfNeeded()
            }
        }
    }

    private static func updateStackLayout(_ stack: NSStackView) {
        stack.arrangedSubviews.forEach { view in
            guard let textBlock = view.subviews.first?.subviews.first as? TextBlock else { return }
            
            // Force a layout update
            textBlock.textView.textContainer?.containerSize = NSSize(
                width: textBlock.bounds.width,
                height: .greatestFiniteMagnitude
            )
            textBlock.needsUpdateConstraints = true
            textBlock.needsLayout = true
        }
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
