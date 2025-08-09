import Cocoa
// MARK: - CodeBlockParser
class CodeBlockParser {
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

    // MARK: - New Output Type
    enum ParsedElement {
        case text(NSAttributedString)
        case codeBlock(language: String, content: String)
    }
    
    // Thread-safe state access
    private let stateLock = NSRecursiveLock()
    private var _state: ParserState = .text
    private var _codeBlockBuffer = ""
    private var _languageBuffer = ""
    private var _pendingBackticks = ""
    private var _lineBuffer = ""
    private var _pendingDelimiter: NSAttributedString?
    
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
    
    private var lineBuffer: String {
        get { stateLock.withLock { _lineBuffer } }
        set { stateLock.withLock { _lineBuffer = newValue } }
    }

    private var _partialCodeBlockContent = ""
    
    private var partialCodeBlockContent: String {
        get { stateLock.withLock { _partialCodeBlockContent } }
        set { stateLock.withLock { _partialCodeBlockContent = newValue } }
    }
    
    // Constants
    private static let validLanguages: Set<String> = [
        "swift", "python", "javascript", "typescript", "java",
        "kotlin", "c", "cpp", "csharp", "go", "ruby", "php",
        "rust", "scala", "dart", "r", "objectivec", "bash", "sh",
        "json", "yaml", "xml", "html", "css", "markdown", "text"
    ]
    
    // MARK: - Public Interface
    func parseChunk(_ chunk: String, isComplete: Bool = false) -> [ParsedElement] {
        return stateLock.withLock {
            var remainingText = lineBuffer + chunk
            lineBuffer = ""
            var output: [ParsedElement] = []
            
            // Special case for plain text
            if !remainingText.contains("`") && parserState == .text {
                let text = partialCodeBlockContent + remainingText
                partialCodeBlockContent = ""
                return [.text(createRegularText(text))]
            }
            
            while !remainingText.isEmpty {
                if let newlineIndex = remainingText.firstIndex(of: "\n") {
                    let line = String(remainingText[..<newlineIndex])
                    remainingText = String(remainingText[remainingText.index(after: newlineIndex)...])
                    
                    let processed = processLine(line + "\n")
                    output.append(contentsOf: processed)
                } else {
                    lineBuffer = remainingText
                    remainingText = ""
                }
            }
            
            if isComplete {
                if !partialCodeBlockContent.isEmpty {
                    output.append(.text(createRegularText(partialCodeBlockContent)))
                    partialCodeBlockContent = ""
                }
                if !lineBuffer.isEmpty {
                    output.append(contentsOf: processLine(lineBuffer))
                    lineBuffer = ""
                }
            }
            
            return output
        }
    }
    
    func reset() {
        stateLock.withLock {
            _state = .text
            _codeBlockBuffer = ""
            _languageBuffer = ""
            _pendingBackticks = ""
            _lineBuffer = ""
            _pendingDelimiter = nil
        }
    }
    
    // MARK: - Private Methods
    private func processLine(_ line: String) -> [ParsedElement] {
        var output: [ParsedElement] = []
        var remainingLine = line
        
        // Early return for completely plain text
        if !remainingLine.contains("`") && parserState == .text {
            return [.text(createRegularText(line))]
        }
        
        while !remainingLine.isEmpty {
            switch parserState {
            case .text:
                if let backtickIndex = remainingLine.firstIndex(of: "`") {
                    // Process text before backticks
                    let textBefore = String(remainingLine[..<backtickIndex])
                    if !textBefore.isEmpty {
                        output.append(.text(createRegularText(textBefore)))
                    }
                    
                    // Process backticks
                    let backtickPart = String(remainingLine[backtickIndex...])
                    if let backtickCount = countConsecutiveBackticks(backtickPart), backtickCount >= 3 {
                        let backticks = String(backtickPart.prefix(backtickCount))
                        let remainingAfterBackticks = String(backtickPart.dropFirst(backtickCount))
                        
                        parserState = .potentialCodeBlockStart(backticks: backticks)
                        remainingLine = remainingAfterBackticks
                    } else {
                        output.append(.text(processInlineCode(backtickPart)))
                        remainingLine = ""
                    }
                } else {
                    output.append(.text(createRegularText(remainingLine)))
                    remainingLine = ""
                }
                
            case .potentialCodeBlockStart(let backticks):
                if let newlineIndex = remainingLine.firstIndex(of: "\n") {
                    let languagePart = languageBuffer + String(remainingLine[..<newlineIndex])
                    languageBuffer = ""
                    let validatedLanguage = validateAndAutocorrectLanguage(languagePart)
                    
                    // Skip past the language and newline
                    remainingLine = String(remainingLine[remainingLine.index(after: newlineIndex)...])
                    parserState = .inCodeBlock(language: validatedLanguage, openingBackticks: backticks)
                } else {
                    languageBuffer += remainingLine
                    remainingLine = ""
                }
                
            case .inCodeBlock(let language, let openingBackticks):
                if let (endRange, _) = findClosingBackticks(in: remainingLine, openingBackticks: openingBackticks) {
                    let completeContent = codeBlockBuffer + String(remainingLine[..<endRange.lowerBound])
                    codeBlockBuffer = ""
                    output.append(.codeBlock(language: language, content: completeContent))
                    parserState = .text
                    remainingLine = String(remainingLine[endRange.upperBound...])
                } else {
                    // For partial code blocks, return incremental updates
                    if !codeBlockBuffer.isEmpty {
                        output.append(.codeBlock(language: "", content: codeBlockBuffer))
                        codeBlockBuffer = ""
                    }
                    output.append(.codeBlock(language: "", content: remainingLine))
                    remainingLine = ""
                }

            case .potentialCodeBlockEnd(let backticks):
                // Handle incomplete closing fence
                if remainingLine.allSatisfy({ $0 == "`" }) {
                    pendingBackticks += remainingLine
                    remainingLine = ""
                } else {
                    output.append(.codeBlock(language: "", content: backticks + remainingLine))
                    parserState = .text
                    remainingLine = ""
                }
            }
        }
        
        return output
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
    
    private func processInlineCode(_ text: String) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: TextAttributes.regular)
        let pattern = "`([^`]+)`"
        
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return result
        }
        
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            if match.range.location != NSNotFound && match.range.length > 0 {
                let codeRange = match.range(at: 1)
                
                // First reset all attributes to regular ones
                result.setAttributes(TextAttributes.regular, range: match.range)
                
                // Then apply inline code attributes just to the content
                result.setAttributes(TextAttributes.inlineCode, range: codeRange)
                
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
        
        return Self.validLanguages.contains(normalized) ? normalized : ""
    }
    
    private func countConsecutiveBackticks(_ text: String) -> Int? {
        guard let first = text.first, first == "`" else { return nil }
        return text.prefix { $0 == "`" }.count
    }
    
    private func createRegularText(_ text: String) -> NSAttributedString {
        return NSAttributedString(string: text, attributes: TextAttributes.regular)
    }
    
    private func createCodeBlockContent(_ text: String) -> NSAttributedString {
        let cleanedText = text
            .replacingOccurrences(of: "\t", with: "    ")
            .replacingOccurrences(of: "\r\n", with: "\n")
        
        return NSAttributedString(string: cleanedText, attributes: TextAttributes.codeBlock)
    }
}

// MARK: - TextAttributes
private struct TextAttributes {
    static let regular: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 14),
        .foregroundColor: NSColor.textColor,
        .backgroundColor: NSColor.clear,
        .paragraphStyle: {
            let style = NSMutableParagraphStyle()
            style.lineHeightMultiple = 1.2
            style.paragraphSpacing = 4
            style.lineBreakMode = .byWordWrapping
            style.alignment = .natural
            return style
        }()
    ]
    
    static let inlineCode: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
        .foregroundColor: NSColor.systemOrange,
        .backgroundColor: NSColor.controlBackgroundColor.withAlphaComponent(0.3),
        .baselineOffset: 0
    ]
    
    static let codeBlock: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
        .foregroundColor: NSColor.textColor,
        .backgroundColor: NSColor.textBackgroundColor,
        .paragraphStyle: {
            let style = NSMutableParagraphStyle()
            style.lineHeightMultiple = 1.2
            style.paragraphSpacing = 0
            return style
        }()
    ]
}

// MARK: - StreamRenderer
enum StreamRenderer {
    static var windowResizeObserver: Any?
    static var debounceTimer: Timer?

    private static func handleWindowResize(_ bubble: NSView, container: NSView, controller: StreamMessageController) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.allowsImplicitAnimation = true
            
            // Update all code blocks in the hierarchy
            updateAllCodeBlockHeights(in: container, controller: controller)
            container.needsLayout = true
            container.layoutSubtreeIfNeeded()
        }
    }
    
    private static func updateAllCodeBlockHeights(in view: NSView, controller: StreamMessageController) {
        // Recursively find all code block views and update their heights
        for subview in view.subviews {
            if subview.subviews.first?.subviews.first is NSTextView {
                controller.updateCodeBlockHeight(subview)
            }
            updateAllCodeBlockHeights(in: subview, controller: controller)
        }
    }

    final class StreamMessageController {
        private var _currentCodeBlock: NSView?
        let containerView: NSView
        private let stackView: NSStackView
        // let textBlock: TextBlock
        private let processingQueue = DispatchQueue(label: "stream.processor", qos: .userInteractive)
        private var displayLink: DisplayLink?
        private let codeBlockParser = CodeBlockParser()
        private let maxWidth: CGFloat
        
        // Protected state
        private let stateLock = NSRecursiveLock()
        private var _isAnimating = false
        private var _elements: [CodeBlockParser.ParsedElement] = []
        private var _lastRenderTime: CFTimeInterval = 0
        private var _currentTextBlock: TextBlock? // Track the current text block
        
        // Constants
        private let minFrameInterval: CFTimeInterval = 1/60
        
        private var isAnimating: Bool {
            get { stateLock.withLock { _isAnimating } }
            set { stateLock.withLock { _isAnimating = newValue } }
        }
        
        init(containerView: NSView, stackView: NSStackView, maxWidth: CGFloat) {
            self.containerView = containerView
            self.stackView = stackView
            self.maxWidth = maxWidth
        }
        
        func appendStreamingText(_ chunk: String, isComplete: Bool = false) {
            processingQueue.async { [weak self] in
                guard let self = self else { return }
                
                let cleanedChunk = chunk.cleanedForStream().normalizeMarkdownCodeBlocks()
                guard !cleanedChunk.isEmpty || isComplete else { return }
                
                let newElements = self.processChunk(cleanedChunk, isComplete: isComplete)
                
                DispatchQueue.main.async {
                    guard self.containerView.superview != nil else { return }
                    self.commitUpdate(newElements, isComplete: isComplete)
                }
            }
        }
        
        private func processChunk(_ chunk: String, isComplete: Bool) -> [CodeBlockParser.ParsedElement] {
            return codeBlockParser.parseChunk(chunk, isComplete: isComplete)
        }
        
        private func commitUpdate(_ elements: [CodeBlockParser.ParsedElement], isComplete: Bool) {
            stateLock.withLock {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    
                    for element in elements {
                        switch element {
                        case .text(let attributedString):
                            // If we have a current code block, we need to close it first
                            if self._currentCodeBlock != nil {
                                self._currentCodeBlock = nil
                                self._currentTextBlock = nil
                            }
                            
                            if let currentBlock = self._currentTextBlock {
                                currentBlock.appendText(attributedString)
                            } else {
                                let textBlock = self.createTextBlock()
                                textBlock.setText(attributedString)
                                self.stackView.addArrangedSubview(textBlock)
                                self._currentTextBlock = textBlock
                            }
                            
                        case .codeBlock(let language, let content):
                            // If we're not in a code block, create a new one
                            if self._currentCodeBlock == nil {
                                let codeBlock = self.createCodeBlock(language: language, content: content)
                                self.stackView.addArrangedSubview(codeBlock)
                                self._currentCodeBlock = codeBlock
                                self._currentTextBlock = nil
                            } else {
                                // Append to existing code block
                                if let textView = self._currentCodeBlock?.subviews.first?.subviews.first as? NSTextView {
                                    textView.string = textView.string + content
                                    self.updateCodeBlockHeight(self._currentCodeBlock!)
                                }
                            }
                        }
                    }
                    
                    if isComplete {
                        self.stop()
                        self._currentTextBlock = nil
                        self._currentCodeBlock = nil
                    } else {
                        self.startDisplayLinkIfNeeded()
                    }
                }
            }
        }

        func updateCodeBlockHeight(_ codeBlock: NSView) {
            guard let textView = codeBlock.subviews.first?.subviews.first as? NSTextView else { return }
            
            // Calculate available width (accounting for insets and padding)
            let availableWidth = maxWidth - 16 - 16 // Account for bubble padding and text insets
            
            let textContainer = NSTextContainer(containerSize: NSSize(width: availableWidth, height: .greatestFiniteMagnitude))
            let layoutManager = NSLayoutManager()
            layoutManager.addTextContainer(textContainer)
            
            let textStorage = NSTextStorage(string: textView.string)
            textStorage.addLayoutManager(layoutManager)
            
            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let height = ceil(usedRect.height) + 16 // Add text insets
            
            // Update or create height constraint
            if let constraint = codeBlock.constraints.first(where: { $0.firstAttribute == .height }) {
                constraint.constant = height
            } else {
                codeBlock.heightAnchor.constraint(equalToConstant: height).isActive = true
            }
            
            // Force immediate layout update
            codeBlock.needsLayout = true
            codeBlock.layoutSubtreeIfNeeded()
        }

        private func updateViews(with elements: [CodeBlockParser.ParsedElement]) {
            let oldCount = stackView.arrangedSubviews.count
            guard elements.count > oldCount else { return }

            // append only the newly-parsed elements
            for element in elements[oldCount..<elements.count] {
                switch element {
                case .text(let attributedString):
                    // If the last arranged view is a TextBlock, append into it.
                    if let last = stackView.arrangedSubviews.last as? TextBlock,
                    let storage = last.textView.textStorage {
                        storage.beginEditing()
                        storage.append(attributedString)
                        storage.endEditing()
                        last.updateHeight()
                    } else {
                        // Otherwise create a fresh TextBlock
                        let textBlock = createTextBlock()
                        // ensure the storage exists and set the attributed string
                        if let storage = textBlock.textView.textStorage {
                            storage.beginEditing()
                            storage.setAttributedString(attributedString)
                            storage.endEditing()
                        } else {
                            textBlock.textView.string = attributedString.string
                        }
                        stackView.addArrangedSubview(textBlock)
                        textBlock.updateHeight()
                    }

                case .codeBlock(let language, let content):
                    // Always create a new code block view - it splits the text flow
                    let codeBlock = createCodeBlock(language: language, content: content)
                    stackView.addArrangedSubview(codeBlock)
                }
            }

            // Force layout update
            containerView.needsLayout = true
            containerView.layoutSubtreeIfNeeded()
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

        private func createTextBlock() -> TextBlock {
            let textBlock = TextBlock(maxWidth: maxWidth)
            textBlock.translatesAutoresizingMaskIntoConstraints = false
            textBlock.setContentHuggingPriority(.defaultHigh, for: .vertical)
            textBlock.setContentCompressionResistancePriority(.required, for: .vertical)
            
            // Configure text container for proper wrapping
            textBlock.textView.textContainer?.widthTracksTextView = true
            textBlock.textView.textContainer?.lineFragmentPadding = 0
            textBlock.textView.textContainerInset = NSSize(width: 0, height: 4)
            
            return textBlock
        }

        private func createCodeBlock(language: String, content: String) -> NSView {
            let container = NSView()
            container.translatesAutoresizingMaskIntoConstraints = false
            container.setContentHuggingPriority(.required, for: .vertical)
            container.setContentCompressionResistancePriority(.required, for: .vertical)
            
            let bubble = NSView()
            bubble.translatesAutoresizingMaskIntoConstraints = false
            bubble.wantsLayer = true
            bubble.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            bubble.layer?.cornerRadius = 8
            bubble.layer?.borderWidth = 1
            bubble.layer?.borderColor = NSColor.separatorColor.cgColor
            
            let textView = NSTextView()
            textView.translatesAutoresizingMaskIntoConstraints = false
            textView.isEditable = false
            textView.isSelectable = true
            textView.drawsBackground = false
            textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            textView.textColor = NSColor.textColor
            textView.string = content
            textView.textContainerInset = NSSize(width: 8, height: 8)
            textView.textContainer?.widthTracksTextView = false
            textView.textContainer?.containerSize = NSSize(width: maxWidth - 32, height: .greatestFiniteMagnitude)
            
            
            container.addSubview(bubble)
            bubble.addSubview(textView)
            
            var constraints = [
                bubble.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                bubble.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                bubble.topAnchor.constraint(equalTo: container.topAnchor, constant: 2), // Reduced from 4
                bubble.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2), // Reduced from -4
                
                textView.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8),
                textView.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -8),
                textView.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 8),
                textView.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -8),
                
                container.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth)
            ]
            
            // Add language label only if needed
            if !language.isEmpty {
                let languageLabel = NSTextField(labelWithString: language)
                languageLabel.translatesAutoresizingMaskIntoConstraints = false
                languageLabel.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
                languageLabel.textColor = NSColor.secondaryLabelColor
                languageLabel.alignment = .right
                bubble.addSubview(languageLabel)
                
                constraints += [
                    languageLabel.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 4),
                    languageLabel.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -8),
                    textView.topAnchor.constraint(equalTo: languageLabel.bottomAnchor, constant: 2) // Reduced spacing
                ]
            }
            
            NSLayoutConstraint.activate(constraints)
            updateCodeBlockHeight(container)
            return container
        }
        
        private func processPendingUpdates() {
            stateLock.withLock {
                let currentTime = CACurrentMediaTime()
                guard currentTime - _lastRenderTime >= minFrameInterval else { return }
                
                _lastRenderTime = currentTime
                
//                DispatchQueue.main.async { [weak self] in
//                    guard let self = self,
//                          !self._fullTextBuffer.string.isEmpty,
//                          self.textBlock.superview != nil else { return }
//                    
//                    let bufferCopy = self._fullTextBuffer.copy() as! NSAttributedString
//                    self.textBlock.updateFullText(bufferCopy)
//                }
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
                _elements = []
                codeBlockParser.reset()
                
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
                }
            }
        }
    }

    class TextBlock: NSView {
        let textView: NSTextView
        private var heightConstraint: NSLayoutConstraint?
        
        init(maxWidth: CGFloat) {
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
            translatesAutoresizingMaskIntoConstraints = false
            textView.translatesAutoresizingMaskIntoConstraints = false
            textView.isEditable = false
            textView.isSelectable = true
            textView.drawsBackground = false
            
            addSubview(textView)
            
            NSLayoutConstraint.activate([
                textView.leadingAnchor.constraint(equalTo: leadingAnchor),
                textView.trailingAnchor.constraint(equalTo: trailingAnchor),
                textView.topAnchor.constraint(equalTo: topAnchor),
                textView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }

        func setText(_ attributedString: NSAttributedString) {
            textView.textStorage?.setAttributedString(attributedString)
            updateHeight()
        }

        func appendText(_ attributedString: NSAttributedString) {
            guard let storage = textView.textStorage else { return }
            storage.beginEditing()
            storage.append(attributedString)
            storage.endEditing()
            updateHeight()
        }
        
        func updateHeight() {
            guard let layoutManager = textView.layoutManager,
                let textContainer = textView.textContainer else { return }
            
            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let height = ceil(usedRect.height) + textView.textContainerInset.height * 2
            
            if let heightConstraint = heightConstraint {
                heightConstraint.constant = height
            } else {
                heightConstraint = heightAnchor.constraint(equalToConstant: height)
                heightConstraint?.isActive = true
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
        stack.spacing = 2 // Reduced from 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.distribution = .fill
        stack.alignment = .leading
        stack.setHuggingPriority(.required, for: .vertical)
        for view in stack.arrangedSubviews {
            view.setContentCompressionResistancePriority(.required, for: .vertical)
        }

        bubble.addSubview(stack)

        // let textblock = TextBlock(maxWidth: maxWidth)
        // stack.addArrangedSubview(textblock)

        // let controller = StreamMessageController(textBlock: textblock)
        let controller = StreamMessageController(containerView: container, stackView: stack, maxWidth: maxWidth)
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
        
        _ = setupWindowResizeHandler(for: bubble, container: container, controller: controller)

        return (container, controller)
    }

    private static func calculateMaxWidth() -> CGFloat {
        let screenWidth = NSScreen.main?.visibleFrame.width ?? 800
        return min(screenWidth * 0.7, 800) // 70% of screen or 800px max
    }

    private static func setupWindowResizeHandler(for bubble: NSView, container: NSView, controller: StreamMessageController) -> Any? {
        guard let window = bubble.window else { return nil }
        
        return NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak bubble, weak container, weak controller] _ in
            guard let bubble = bubble, let container = container, let controller = controller else { return }
            // Debounce the resize events
            NSObject.cancelPreviousPerformRequests(withTarget: bubble)
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0.15
            NSAnimationContext.current.allowsImplicitAnimation = true
            handleWindowResize(bubble, container: container, controller: controller)
            NSAnimationContext.endGrouping()
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

extension CodeBlockParser.ParsedElement {
    var textContent: String {
        switch self {
        case .text(let attributedString):
            return attributedString.string
        case .codeBlock(_, let content):
            return content
        }
    }
}