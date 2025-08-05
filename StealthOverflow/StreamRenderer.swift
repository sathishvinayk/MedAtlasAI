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

        private func createCodeBlockDelimiter(language: String = "") -> NSMutableAttributedString {
            let delimiterText = language.isEmpty ? "```\n" : "```\(language)\n"
            return NSMutableAttributedString(string: delimiterText, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.systemGray,
                .backgroundColor: NSColor.controlBackgroundColor
            ])
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

        init(textBlock: TextBlock) {
            self.textBlock = textBlock
        }
        
        func appendStreamingText(_ chunk: String, isComplete: Bool = false) {
            // Capture strong reference to textBlock
            let textBlock = self.textBlock
            
            processingQueue.async { [weak self] in
                guard let self = self else { return }
                
                let cleanedChunk = chunk.cleanedForStream().normalizeMarkdownCodeBlocks()
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
                
                // Handle existing code block content
                if _isInCodeBlock {
                    if let endRange = findCodeBlockEnd(in: remainingChunk) {
                        // Content before closing ticks
                        let codeContent = String(remainingChunk[..<endRange.lowerBound])
                        _codeBlockBuffer += codeContent
                        
                        // Format the complete code block
                        update.append(createCodeBlockDelimiter())
                        update.append(createCodeBlockContent(_codeBlockBuffer))
                        update.append(createCodeBlockDelimiter())
                        
                        // Reset state
                        _codeBlockBuffer = ""
                        _isInCodeBlock = false
                        
                        // Process remaining text
                        remainingChunk = String(remainingChunk[endRange.upperBound...])
                    } else {
                        // No closing ticks found - buffer entire chunk
                        _codeBlockBuffer += remainingChunk
                        return NSMutableAttributedString()
                    }
                }
                
                // Process remaining text for new code blocks
                // Process remaining text for new code blocks using improved regex detection
                while !remainingChunk.isEmpty {
                    if let match = findCompleteCodeBlock(in: remainingChunk) {
                        // Add text before code block
                        let textBefore = String(remainingChunk[..<match.range.lowerBound])
                        if !textBefore.isEmpty {
                            update.append(processInlineText(textBefore))
                        }
                        
                        // Add the complete code block
                        update.append(createCodeBlockDelimiter(language: match.language))
                        update.append(createCodeBlockContent(match.content))
                        update.append(createCodeBlockDelimiter())
                        
                        // Skip processed content
                        remainingChunk = String(remainingChunk[match.range.upperBound...])
                    } 
                    else if let (startRange, language) = findCodeBlockStart(in: remainingChunk) {
                        // Handle partial code block (start found but no end)
                        let textBefore = String(remainingChunk[..<startRange.lowerBound])
                        if !textBefore.isEmpty {
                            update.append(processInlineText(textBefore))
                        }
                        
                        _isInCodeBlock = true
                        update.append(createCodeBlockDelimiter(language: language))
                        
                        // Skip language specifier if present
                        let contentStart = remainingChunk.index(startRange.lowerBound, offsetBy: 3 + language.count)
                        _codeBlockBuffer = String(remainingChunk[contentStart...])
                        remainingChunk = ""
                    }
                    else {
                        // No code blocks - process as regular text
                        update.append(processInlineText(remainingChunk))
                        remainingChunk = ""
                    }
                }
                
                // Handle incomplete code block at stream end
                if isComplete && _isInCodeBlock {
                    update.append(createCodeBlockContent(_codeBlockBuffer))
                    update.append(createCodeBlockDelimiter())
                    _codeBlockBuffer = ""
                    _isInCodeBlock = false
                }
                
                return update
            }
        }

        private struct CodeBlockMatch {
            let range: Range<String.Index>
            let language: String
            let content: String
        }

        private func findCompleteCodeBlock(in text: String) -> CodeBlockMatch? {
            let pattern = #"(?s)(^|\n)(?<ticks>```+)(?<language>\w*)\n(?<content>.*?)\n?(?<closing>```+)(\n|$)"#
            
            guard let regex = try? NSRegularExpression(pattern: pattern),
                let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
                return nil
            }
            
            let ticksRange = Range(match.range(withName: "ticks"), in: text)!
            let languageRange = Range(match.range(withName: "language"), in: text)!
            let contentRange = Range(match.range(withName: "content"), in: text)!
            let closingRange = Range(match.range(withName: "closing"), in: text)!
            
            let fullRange = Range(match.range, in: text)!
            let language = String(text[languageRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let content = String(text[contentRange])
            
            // Verify ticks count matches (at least 3)
            let ticksCount = text[ticksRange].count
            let closingCount = text[closingRange].count
            guard ticksCount >= 3 && closingCount >= 3 else { return nil }
            
            return CodeBlockMatch(
                range: fullRange,
                language: language,
                content: content
            )
        }

        private func findCodeBlockStart(in text: String) -> (range: Range<String.Index>, language: String)? {
            let pattern = #"(^|\n)(?<ticks>```+)(?<language>\w*)(\n|$)"#
            
            guard let regex = try? NSRegularExpression(pattern: pattern),
                let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                let ticksRange = Range(match.range(withName: "ticks"), in: text),
                text[ticksRange].count >= 3 else {
                return nil
            }
            
            let fullRange = Range(match.range, in: text)!
            let language = match.range(withName: "language").location != NSNotFound ?
                String(text[Range(match.range(withName: "language"), in: text)!]).trimmingCharacters(in: .whitespacesAndNewlines) :
                ""
            
            return (fullRange, language)
        }

        private func findCodeBlockEnd(in text: String) -> Range<String.Index>? {
            let pattern = #"(^|\n)(?<ticks>```+)(\n|$)"#
            
            guard let regex = try? NSRegularExpression(pattern: pattern),
                let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                let ticksRange = Range(match.range(withName: "ticks"), in: text),
                text[ticksRange].count >= 3 else {
                return nil
            }
            
            return Range(match.range, in: text)
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

extension String {
    func normalizeMarkdownCodeBlocks() -> String {
        var result = self
        
        // Fix double/malformed code blocks
        result = result.replacingOccurrences(
            of: #"```(\w*)\s*```(\w+)"#,
            with: "```$2",
            options: .regularExpression
        )
        
        // Fix single-letter language specifiers
        result = result.replacingOccurrences(
            of: #"```(\w)\s"#,
            with: "```$1",
            options: .regularExpression
        )
        
        // Ensure newlines around code blocks
        result = result.replacingOccurrences(
            of: #"(?<!\n)```(\w*)"#,
            with: "\n```$1",
            options: .regularExpression
        )
        
        return result
    }
}

// extension String {
//     func normalizeMarkdownCodeBlocks() -> String {
//         var result = self
        
//         // Fix common malformed code block patterns
//         let patterns = [
//             #"(?<!\n)(```)(\w*)\n"#: "```$2\n", // Fix missing newline after ```
//             #"```(\w+)[^\S\n]+(\n)"#: "```$1$2", // Fix extra spaces after language
//             #"```\n+```"#: "```\n```", // Fix excessive newlines
//             #"`{1,2}([^`\n]+)`{1,2}"#: "`$1`" // Normalize inline code ticks
//         ]
        
//         for (pattern, replacement) in patterns {
//             result = result.replacingOccurrences(
//                 of: pattern,
//                 with: replacement,
//                 options: .regularExpression
//             )
//         }
        
//         return result
//     }
// }
