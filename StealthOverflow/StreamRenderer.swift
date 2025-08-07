import Cocoa

// MARK: - StreamRenderer
enum StreamRenderer {
    static var windowResizeObserver: Any?
    static var debounceTimer: Timer?

    final class StreamMessageController {

        // MARK: - State Management
        enum ParserState: Equatable {
            case text
            case potentialCodeBlockStart(backticks: String)
            case inCodeBlock(language: String, openingBackticks: String)
            case potentialCodeBlockEnd(backticks: String)
            static func == (lhs: ParserState, rhs: ParserState) -> Bool {
                switch (lhs, rhs) {
                case (.text, .text):
                    return true
                case let (.potentialCodeBlockStart(lbackticks), .potentialCodeBlockStart(rbackticks)):
                    return lbackticks == rbackticks
                case let (.inCodeBlock(llang, lbackticks), .inCodeBlock(rlang, rbackticks)):
                    return llang == rlang && lbackticks == rbackticks
                case let (.potentialCodeBlockEnd(lbackticks), .potentialCodeBlockEnd(rbackticks)):
                    return lbackticks == rbackticks
                default:
                    return false
                }
            }
        }

        let textBlock: TextBlock
        // Unified synchronization
        private let processingQueue = DispatchQueue(label: "stream.processor", qos: .userInteractive)
        private var displayLink: DisplayLink?
        
        // Protected state
        private var _isAnimating = false
        private var _fullTextBuffer = NSMutableAttributedString()
        private var _isInCodeBlock = false
        private var _lastRenderTime: CFTimeInterval = 0
        
        // Constants
        private let minFrameInterval: CFTimeInterval = 1/60

        // Add parser state
        // Enhanced parser state
        // Thread-safe state access
        private let stateLock = NSRecursiveLock()
        private var _state: ParserState = .text
        private var _codeBlockBuffer = ""
        private var _languageBuffer = ""
        private var _pendingBackticks = ""
        private var _lineBuffer = ""
        private var _pendingDelimiter: NSAttributedString?
        

        // Thread-safe property access
        private var isAnimating: Bool {
            get { stateLock.withLock { _isAnimating } }
            set { stateLock.withLock { _isAnimating = newValue } }
        }

        private var parserState: ParserState {
            get { stateLock.withLock { _state } }
            set { stateLock.withLock { _state = newValue } }
        }
        
        private var codeBlockBuffer: String {
            get { stateLock.withLock { _codeBlockBuffer } }
            set { stateLock.withLock { _codeBlockBuffer = newValue } }
        }
        
        private var languageBuffer: String {
            get { stateLock.withLock { _languageBuffer } }
            set { stateLock.withLock { _languageBuffer = newValue } }
        }
        
        private var pendingBackticks: String {
            get { stateLock.withLock { _pendingBackticks } }
            set { stateLock.withLock { _pendingBackticks = newValue } }
        }
        
        private func createCodeBlockDelimiter(backticks: String, language: String = "") -> NSAttributedString {
            let text = language.isEmpty ? "\(backticks)\n" : "\(backticks)\(language)\n"
            return NSAttributedString(string: text, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.systemGray,
                .backgroundColor: NSColor.controlBackgroundColor,
                .paragraphStyle: {
                    let style = NSMutableParagraphStyle()
                    style.paragraphSpacing = 0
                    return style
                }()
            ])
        }
        
        private let codeBlockAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.textColor,
            .backgroundColor: NSColor.controlBackgroundColor,
            .paragraphStyle: {
                let style = NSMutableParagraphStyle()
                style.lineHeightMultiple = 1.2
                style.paragraphSpacing = 0  // Important for keeping blocks together
                return style
            }()
        ]

        private let regularAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.textColor,
            .backgroundColor: NSColor.clear,
            .paragraphStyle: {
                let style = NSMutableParagraphStyle()
                style.lineHeightMultiple = 1.2
                return style
            }()
        ]

        private let inlineCodeAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
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
                // Combine with any previous partial line
                var remainingText = _lineBuffer + chunk
                _lineBuffer = ""
                
                let output = NSMutableAttributedString()
                        
                // Special case: if text is completely plain, process immediately
                if !remainingText.contains("`") && parserState == .text {
                    output.append(createRegularText(remainingText))
                    return output
                }
                
                while !remainingText.isEmpty {
                    // Process complete lines only
                    if let newlineIndex = remainingText.firstIndex(of: "\n") {
                        let line = String(remainingText[..<newlineIndex])
                        remainingText = String(remainingText[remainingText.index(after: newlineIndex)...])
                        
                        output.append(processLine(line + "\n"))
                    } else {
                        // Buffer incomplete line for next chunk
                        _lineBuffer = remainingText
                        remainingText = ""
                    }
                }
                
                if isComplete && !_lineBuffer.isEmpty {
                    output.append(processLine(_lineBuffer))
                    _lineBuffer = ""
                }
                
                return output
            }
        }

        private func findClosingBackticks(in text: String, openingBackticks: String) -> (Range<String.Index>, String)? {
            let minBackticks = max(3, openingBackticks.count)
            let pattern = #"(?:^|\n)(`{\#(minBackticks),})(?=\s|$)"#
            
            guard let regex = try? NSRegularExpression(pattern: pattern),
                let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                let ticksRange = Range(match.range(at: 1), in: text) else {
                return nil
            }
            
            let backticks = String(text[ticksRange])
            return (ticksRange, backticks)
        }

        private func processLine(_ line: String) -> NSAttributedString {
            let output = NSMutableAttributedString()
            var remainingLine = line

            // Early return for completely plain text
            if !remainingLine.contains("`") && parserState == .text {
                return createRegularText(remainingLine)
            }
            
            while !remainingLine.isEmpty {
                switch parserState {
                case .text:
                    print("Text \(remainingLine)")
                    if let backtickIndex = remainingLine.firstIndex(of: "`") {
                        // Process text before backticks
                        let textBefore = String(remainingLine[..<backtickIndex])
                        if !textBefore.isEmpty {
                            output.append(createRegularText(textBefore))
                        }
                        
                        // Process backticks
                        let backtickPart = String(remainingLine[backtickIndex...])
                        if let backtickCount = countConsecutiveBackticks(backtickPart), backtickCount >= 3 {
                            let backticks = String(backtickPart.prefix(backtickCount))
                            let remainingAfterBackticks = String(backtickPart.dropFirst(backtickCount))
                            
                            parserState = .potentialCodeBlockStart(backticks: backticks)
                            remainingLine = remainingAfterBackticks
                        } else {
                            output.append(processInlineCode(backtickPart))
                            remainingLine = ""
                        }
                    } else {
                        output.append(createRegularText(remainingLine))
                        remainingLine = ""
                    }
                    
                case .potentialCodeBlockStart(let backticks):
                    if let newlineIndex = remainingLine.firstIndex(of: "\n") {
                        let languagePart = String(remainingLine[..<newlineIndex])
                        let validatedLanguage = validateAndAutocorrectLanguage(languagePart)
                        
                        // Create the opening delimiter (not added to output yet)
                        _pendingDelimiter = createCodeBlockDelimiter(
                            backticks: backticks,
                            language: validatedLanguage
                        )
                        
                        // Skip past the language and newline
                        remainingLine = String(remainingLine[remainingLine.index(after: newlineIndex)...])
                        parserState = .inCodeBlock(language: validatedLanguage, openingBackticks: backticks)
                    } else {
                        _languageBuffer += remainingLine
                        remainingLine = ""
                    }
                    
                case .inCodeBlock(let language, let openingBackticks):
                    if let (endRange, foundBackticks) = findClosingBackticks(in: remainingLine, openingBackticks: openingBackticks) {
                        // Create the complete code block
                        let codeBlock = NSMutableAttributedString()
                        
                        // 1. Add opening delimiter if we have one
                        if let delimiter = _pendingDelimiter {
                            codeBlock.append(delimiter)
                            _pendingDelimiter = nil
                        }
                        
                        // 2. Add ONLY the code content (exclude closing backticks)
                        let content = String(remainingLine[..<endRange.lowerBound])
                        codeBlock.append(createCodeBlockContent(content))
                        
                        // 3. Add closing delimiter
                        codeBlock.append(createCodeBlockDelimiter(backticks: foundBackticks))
                        
                        output.append(codeBlock)
                        parserState = .text
                        
                        // Skip past the closing backticks
                        remainingLine = String(remainingLine[endRange.upperBound...])
                    } else {
                        // No closing backticks found yet - add as code content
                        if let delimiter = _pendingDelimiter {
                            output.append(delimiter)
                            _pendingDelimiter = nil
                        }
                        output.append(createCodeBlockContent(remainingLine))
                        remainingLine = ""
                    }
                    
                case .potentialCodeBlockEnd(let backticks):
                    // Handle incomplete closing fence
                    if remainingLine.allSatisfy({ $0 == "`" }) {
                        _pendingBackticks += remainingLine
                        remainingLine = ""
                    } else {
                        output.append(createCodeBlockContent(backticks + remainingLine))
                        parserState = .text
                        remainingLine = ""
                    }
                }
            }
            
            return output
        }

        private func processInlineCode(_ text: String) -> NSAttributedString {
            let result = NSMutableAttributedString(string: text, attributes: regularAttributes) // Start with base attributes
            let pattern = "`([^`]+)`"
            
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                return result
            }
            
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches.reversed() {
                if match.range.location != NSNotFound && match.range.length > 0 {
                    let codeRange = match.range(at: 1)
                    
                    // First reset all attributes to regular ones
                    result.setAttributes(regularAttributes, range: match.range)
                    
                    // Then apply inline code attributes just to the content
                    result.setAttributes(inlineCodeAttributes, range: codeRange)
                    
                    // Remove the backticks themselves
                    result.replaceCharacters(in: match.range, with: result.attributedSubstring(from: codeRange))
                }
            }
            
            return result
        }        
        

        private func validateAndAutocorrectLanguage(_ language: String) -> String {
            let autocorrections = [
                "ript": "javascript",
                "n": "python",
                "ja": "java",
                "js": "javascript",
                "c++": "cpp",
                "c#": "csharp"
            ]
            
            let normalized = language.lowercased()
            
            // Check if we have a direct autocorrection
            if let corrected = autocorrections[normalized] {
                return corrected
            }
            
            // Check against valid languages
            let validLanguages: Set<String> = [
                "swift", "python", "javascript", "typescript", "java",
                "kotlin", "c", "cpp", "csharp", "go", "ruby", "php",
                "rust", "scala", "dart", "r", "objectivec", "bash", "sh",
                "json", "yaml", "xml", "html", "css", "markdown", "text"
            ]
            
            return validLanguages.contains(normalized) ? normalized : ""
        }
        
        private func finalizeIncompleteBlocks(output: inout NSMutableAttributedString) {
            stateLock.withLock {
                switch _state {
                case .inCodeBlock(_, let openingBackticks):
                    output.append(createCodeBlockContent(_codeBlockBuffer))
                    output.append(createCodeBlockDelimiter(backticks: openingBackticks))
                case .potentialCodeBlockStart(let backticks):
                    output.append(createRegularText(backticks + _languageBuffer))
                case .potentialCodeBlockEnd(let backticks):
                    output.append(createRegularText(backticks))
                default:
                    break
                }
                
                // Reset all state
                _state = .text
                _codeBlockBuffer = ""
                _languageBuffer = ""
                _pendingBackticks = ""
                _lineBuffer = ""
            }
        }


        // MARK: - Helper Methods
        private func countConsecutiveBackticks(_ text: String) -> Int? {
            guard let first = text.first, first == "`" else { return nil }
            return text.prefix { $0 == "`" }.count
        }
        
        // Thread-safe version using NSString
        // MARK: - Enhanced Code Block Detection
        private func findPotentialCodeBlockEnd(in text: String, openingBackticks: String) -> (Range<String.Index>, String)? {
            let minBackticks = max(3, openingBackticks.count)
            let pattern = #"(?:(?:^|\n)[ ]{0,3})(`{\#(minBackticks),})(?=\s|$)"#
            
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let ticksRange = Range(match.range(at: 1), in: text) else {
                return nil
            }
            
            let backticks = String(text[ticksRange])
            return (ticksRange, backticks)
        }

        private struct CodeBlockMatch {
            let range: Range<String.Index>
            let language: String
            let content: String
        }

        private func findPartialCodeBlockEnd(in text: String, openingBackticks: String) -> String? {
            let minBackticks = max(3, openingBackticks.count)
            let partialTicks = text.prefix(minBackticks).filter { $0 == "`" }
            return partialTicks.count >= 1 ? String(partialTicks) : nil
        }

        // MARK: - Nested Fence Handling (Optional)
        private func handleNestedFences(in content: String, openingBackticks: String) -> String {
            let fenceCount = openingBackticks.count
            let nestedPattern = #"(^|\n)(`{3,})(?=\n|$)"#
            
            guard fenceCount > 3,
                  let regex = try? NSRegularExpression(pattern: nestedPattern) else {
                return content
            }
            
            var processed = content
            let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))
            
            for match in matches.reversed() {
                if let range = Range(match.range(at: 2), in: content) {
                    let ticks = String(content[range])
                    if ticks.count >= fenceCount {
                        // Escape inner fences by adding one more backtick
                        processed.replaceSubrange(range, with: ticks + "`")
                    }
                }
            }
            
            return processed
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
        
        private func createRegularText(_ text: String) -> NSAttributedString {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineHeightMultiple = 1.2
            
            return NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor.textColor,
                .backgroundColor: NSColor.clear,
                .paragraphStyle: paragraphStyle,
                .baselineOffset: 0,
                .kern: 0, // Explicitly reset kerning
                .ligature: 0, // Explicitly reset ligatures
                .strikethroughStyle: 0, // Explicitly reset strikethrough
                .underlineStyle: 0 // Explicitly reset underline
            ])
        }
        
        private func createCodeBlockContent(_ text: String) -> NSAttributedString {
            let cleanedText = text
                .replacingOccurrences(of: "\t", with: "    ")
                .replacingOccurrences(of: "\r\n", with: "\n")
            
            return NSAttributedString(string: cleanedText, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.textColor,
                .backgroundColor: NSColor.textBackgroundColor
            ])
        }
        
        // MARK: - Enhanced Inline Code Handling
        private func processInlineText(_ text: String) -> NSMutableAttributedString {
            let result = NSMutableAttributedString(string: text, attributes: regularAttributes)
            let pattern = "`([^`]+)`"
            
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                return result
            }
            
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches.reversed() { // Process backwards to avoid range issues
                if match.range.location != NSNotFound && match.range.length > 0 {
                    let codeRange = match.range(at: 1) // Get the content inside backticks
                    result.setAttributes(inlineCodeAttributes, range: codeRange)
                    
                    // Remove the backticks themselves
                    result.replaceCharacters(in: match.range, with: result.attributedSubstring(from: codeRange))
                }
            }
            
            return result
        }

        // MARK: - Language Validation
        private static let validLanguages: Set<String> = [
            "swift", "python", "javascript", "typescript", "java", 
            "kotlin", "c", "cpp", "csharp", "go", "ruby", "php",
            "rust", "scala", "dart", "r", "objectivec", "bash", "sh",
            "json", "yaml", "xml", "html", "css", "markdown", "text"
        ]

        private func normalizeLanguage(_ language: String) -> String {
            // Remove non-ASCII and normalize
            let asciiOnly = language.unicodeScalars
                .filter { $0.isPrintableASCII }
                .map { String($0) }
                .joined()
            
            // Optional: Whitelist validation
            if Self.validLanguages.contains(asciiOnly.lowercased()) {
                return asciiOnly.lowercased()
            }
            return asciiOnly
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


// Add this extension at the top level of your file (not inside any class/struct)
extension Unicode.Scalar {
    var isPrintableASCII: Bool {
        return value >= 32 && value <= 126  // ASCII printable range
    }
}
