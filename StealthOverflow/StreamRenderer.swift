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
    
    private func processLine(_ line: String) -> [ParsedElement] {
        var output: [ParsedElement] = []
        var remainingLine = line
        
        // Early return for completely plain text
        if !remainingLine.contains("`") && 
        !remainingLine.contains("*") && 
        !remainingLine.contains("_") && 
        parserState == .text {
            print("Inside ProcessLine -> \(remainingLine)")
            return [.text(createRegularText(remainingLine))]
        }
        
        while !remainingLine.isEmpty {
            switch parserState {
            case .text:
                if let firstSpecialChar = remainingLine.firstIndex(where: { $0 == "`" || $0 == "*" || $0 == "_" }) {
                    let char = remainingLine[firstSpecialChar]
                    
                    // Process text before special character
                    let textBefore = String(remainingLine[..<firstSpecialChar])
                    if !textBefore.isEmpty {
                        output.append(.text(createRegularText(textBefore)))
                    }
                    
                    let remainingText = String(remainingLine[firstSpecialChar...])
                    
                    if char == "`" {
                        if let backtickCount = MarkdownProcessor.countConsecutiveBackticks(remainingText), backtickCount >= 3 {
                            // Code block start
                            let backticks = String(remainingText.prefix(backtickCount))
                            let remainingAfterBackticks = String(remainingText.dropFirst(backtickCount))
                            
                            // Remove any trailing whitespace from previous text
                            if output.last?.textContent.trimmingCharacters(in: .newlines).isEmpty == true {
                                _ = output.popLast()
                            }
                            
                            parserState = .potentialCodeBlockStart(backticks: backticks)
                            remainingLine = remainingAfterBackticks
                        } else {
                            // Inline code - process until end of line or closing backtick
                            let processed = processInlineCode(remainingText)
                            output.append(.text(processed))
                            remainingLine = ""
                        }
                    } else {
                        // Bold or italic markdown
                        let processed = MarkdownProcessor.processInlineMarkdown(remainingText)
                        output.append(.text(processed))
                        remainingLine = ""
                    }
                } else {
                    // No more special characters
                    output.append(.text(createRegularText(remainingLine)))
                    remainingLine = ""
                }
                
            case .potentialCodeBlockStart(let backticks):
                if let newlineIndex = remainingLine.firstIndex(of: "\n") {
                    let languagePart = languageBuffer + String(remainingLine[..<newlineIndex])
                    languageBuffer = ""
                    
                    let rawLanguage = languagePart.trimmingCharacters(in: .whitespacesAndNewlines)
                    let validatedLanguage = SyntaxHighlighter.validLanguages.contains(rawLanguage.lowercased()) ? 
                        rawLanguage.lowercased() : 
                    SyntaxHighlighter.validateAndAutocorrectLanguage(rawLanguage)
                    
                    remainingLine = String(remainingLine[remainingLine.index(after: newlineIndex)...])
                    parserState = .inCodeBlock(language: validatedLanguage, openingBackticks: backticks)
                    
                    // Skip empty lines after code block start
                    while remainingLine.first == "\n" {
                        remainingLine.removeFirst()
                    }
                } else {
                    languageBuffer += remainingLine
                    remainingLine = ""
                }
                
            case .inCodeBlock(let language, let openingBackticks):
                if let (endRange, _) = findClosingBackticks(in: remainingLine, openingBackticks: openingBackticks) {
                    // Found closing backticks - complete the code block
                    let contentBeforeEnd = String(remainingLine[..<endRange.lowerBound])
                    let completeContent = codeBlockBuffer + contentBeforeEnd
                    codeBlockBuffer = ""
                    
                    if !completeContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        output.append(.codeBlock(language: language, content: completeContent))
                    }
                    
                    parserState = .text
                    remainingLine = String(remainingLine[endRange.upperBound...])
                    
                    // Skip empty lines after code block end
                    while remainingLine.first == "\n" {
                        remainingLine.removeFirst()
                    }
                } else {
                    // No closing backticks found - accumulate partial content
                    if !remainingLine.isEmpty {
                        // Only send incremental updates if we have significant content
                        let newContent = codeBlockBuffer + remainingLine
                        if newContent.contains("\n") || newContent.count > 20 {
                            output.append(.codeBlock(language: language, content: newContent))
                            codeBlockBuffer = ""
                        } else {
                            codeBlockBuffer = newContent
                        }
                    }
                    remainingLine = ""
                }
                
            case .potentialCodeBlockEnd(let backticks):
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
    
    private func createRegularText(_ text: String) -> NSAttributedString {
        // return NSAttributedString(string: text, attributes: TextAttributes.regular)
        return MarkdownProcessor.processInlineMarkdown(text)
    }
}

// MARK: - StreamRenderer
enum StreamRenderer {
    static var windowResizeObserver: Any?
    static var debounceTimer: Timer?

    final class StreamMessageController: NSObject {
        private var resizeDebounceTimer: Timer?
        private var lastContentWidth: CGFloat = 0
        private var isResizing = false
        let containerView: NSView
        let stackView: NSStackView
        let maxWidth: CGFloat

        private var _currentCodeBlock: CodeBlock?
        // let textBlock: TextBlock
        private let processingQueue = DispatchQueue(label: "stream.processor", qos: .userInteractive)
        private var displayLink: DisplayLink?
        private let codeBlockParser = CodeBlockParser()
        
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
            self.maxWidth = maxWidth
            self.containerView = containerView
            self.stackView = stackView

            super.init()
        }

        // Update block creation methods
        private func createTextBlock() -> TextBlock {
            return TextBlock(maxWidth: self.maxWidth)  // No maxWidth needed
        }

        private func createCodeBlock(language: String) -> CodeBlock {
            return CodeBlock(language: language, maxWidth: self.maxWidth) 
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
                // DispatchQueue.main.async { [weak self] in
                    // guard let self = self, self.containerView.superview != nil else { return }
                    
                    // let contentWidth = self.containerView.bounds.width - 32
                    
                    for element in elements {
                        switch element {
                        case .text(let attributedString):
                            if self._currentCodeBlock != nil {
                                self._currentCodeBlock = nil
                                self._currentTextBlock = nil
                            }
                            
                            if let currentBlock = self._currentTextBlock {
                                currentBlock.appendText(attributedString)
                                // currentBlock.updateLayout(forWidth: contentWidth, animated: true)
                            } else {
                                let textBlock = self.createTextBlock()
                                textBlock.setText(attributedString)
                                self.stackView.addArrangedSubview(textBlock)
                                // textBlock.updateLayout(forWidth: contentWidth)
                                self._currentTextBlock = textBlock
                            }
                            
                        case .codeBlock(let language, let content):
                            if self._currentCodeBlock == nil {
                                let codeBlock = self.createCodeBlock(language: language)
                                codeBlock.setText(content)
                                self.stackView.addArrangedSubview(codeBlock)
                                self._currentCodeBlock = codeBlock
                                self._currentTextBlock = nil
                            } else {
                                if let textView = self._currentCodeBlock {
                                    textView.appendText(content)
                                    // textView.string = textView.string + content
                                    // self._currentCodeBlock?.updateLayout(forWidth: contentWidth)
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
                // }
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

        private func processPendingUpdates() {}
        
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

    // MARK: - CodeBlock (updated implementation)
    class CodeBlock: NSView {
        private let bubbleView = NSView()
        private let language: String  // ADD THIS
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

        init(language: String, maxWidth: CGFloat) {
            self.language = language 
            self.maxWidth = maxWidth

            print("Codeblock language -> \(language)")

            let textStorage = NSTextStorage()
            let layoutManager = NSLayoutManager()
            textStorage.addLayoutManager(layoutManager)
            let textContainer = NSTextContainer(size: NSSize(width: self.maxWidth, height: CGFloat.greatestFiniteMagnitude))
            layoutManager.addTextContainer(textContainer)

            self.textView = NSTextView(frame: .zero, textContainer: textContainer)
            super.init(frame: .zero)
            
            setupView()
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        private func setupView() {
            bubbleView.translatesAutoresizingMaskIntoConstraints = false
            bubbleView.wantsLayer = true
            bubbleView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            bubbleView.layer?.cornerRadius = 6
            bubbleView.layer?.borderWidth = 1
            bubbleView.layer?.borderColor = NSColor.separatorColor.cgColor

            // Create the language label
            let languageLabel = NSTextField(labelWithString: language.isEmpty ? "code" : language)
            languageLabel.translatesAutoresizingMaskIntoConstraints = false
            languageLabel.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
            languageLabel.textColor = NSColor.secondaryLabelColor
            languageLabel.alignment = .right


            // TextView setup
            textView.translatesAutoresizingMaskIntoConstraints = false
            textView.isEditable = false
            textView.isSelectable = true
            textView.drawsBackground = false
            textView.textContainerInset = NSSize(width: 8, height: 8)
            textView.textContainer?.lineFragmentPadding = 0
            textView.textContainer?.widthTracksTextView = true
            textView.isHorizontallyResizable = false

            textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            textView.textColor = NSColor.textColor
            
            addSubview(bubbleView)
            bubbleView.addSubview(textView)
            bubbleView.addSubview(languageLabel)
            
            NSLayoutConstraint.activate([
                bubbleView.leadingAnchor.constraint(equalTo: leadingAnchor),
                bubbleView.trailingAnchor.constraint(equalTo: trailingAnchor),
                bubbleView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
                bubbleView.bottomAnchor.constraint(equalTo: bottomAnchor),

                // Language label constraints
                languageLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 4),
                languageLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -8),
                languageLabel.leadingAnchor.constraint(greaterThanOrEqualTo: bubbleView.leadingAnchor, constant: 8),
                

                textView.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 8),
                textView.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -8),
                textView.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 8),
                textView.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -8),
            
                widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth)
            ])
        }

        func appendText(_ newText: String) {
            guard let storage = textView.textStorage else { return }
            // Preserve base attributes while adding syntax highlighting
            let highlightedText = SyntaxHighlighter.highlight(
                newText, 
                language: language,
                baseAttributes: TextAttributes.codeBlock
            )
            
            storage.beginEditing()
            storage.append(highlightedText)
            storage.endEditing()

            // Trigger layout without recursion
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                context.allowsImplicitAnimation = false
                self.updateHeight()
            }
        }
        
        func setText(_ content: String) {
            let highlightedText = SyntaxHighlighter.highlight(
                content, 
                language: language,
                baseAttributes: TextAttributes.codeBlock
            )
            textView.textStorage?.setAttributedString(highlightedText)
            updateHeight()
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

    // MARK: - TextBlock (Fixed)
    class TextBlock: NSView {
        private(set) var textView: NSTextView
        private var heightConstraint: NSLayoutConstraint?
        private let maxWidth: CGFloat
        private var isUpdatingLayout: Bool = false
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
            // self.maxWidth = calculateMaxWidth()
            self.maxWidth = maxWidth

            // Initialize with zero width - will resize dynamically
            let textStorage = NSTextStorage()
            let layoutManager = NSLayoutManager()
            textStorage.addLayoutManager(layoutManager)
            let textContainer = NSTextContainer(size: NSSize(width: self.maxWidth, height: CGFloat.greatestFiniteMagnitude))
            layoutManager.addTextContainer(textContainer)    
            
            self.textView = NSTextView(frame: .zero, textContainer: textContainer)

            super.init(frame: .zero)
            setupView()
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        private func setupView() {
            textView.translatesAutoresizingMaskIntoConstraints = false
            textView.isEditable = false
            textView.isSelectable = true
            textView.drawsBackground = false
            textView.backgroundColor = .clear
            textView.textContainerInset = NSSize(width: 8, height: 8)
            textView.textContainer?.lineFragmentPadding = 0
            textView.textContainer?.widthTracksTextView = true
            textView.isHorizontallyResizable = false
            textView.textColor = .labelColor
            textView.isRichText = true
            textView.usesFontPanel = false
            textView.allowsDocumentBackgroundColorChange = false
            
            addSubview(textView)
            
            NSLayoutConstraint.activate([
                textView.leadingAnchor.constraint(equalTo: leadingAnchor),
                textView.trailingAnchor.constraint(equalTo: trailingAnchor),
                textView.topAnchor.constraint(equalTo: topAnchor),
                textView.bottomAnchor.constraint(equalTo: bottomAnchor),
                widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth)
            ])
        }

        func appendText(_ newText: NSAttributedString) {
            guard let textStorage = textView.textStorage else { return }
    
            // Store current selection
            let currentSelection = textView.selectedRange()
            
            textStorage.beginEditing()
            
            // Append the new text while preserving ALL attributes
            textStorage.append(newText)
            textStorage.endEditing()
            
            // Restore selection
            textView.setSelectedRange(currentSelection)
            updateHeight()
            
            // Trigger layout without recursion
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                context.allowsImplicitAnimation = false
                self.updateHeight()
            }
        }
        
        func setText(_ attributedString: NSAttributedString) {
            textView.textStorage?.setAttributedString(attributedString)
            self.updateHeight()
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
        stack.spacing = 2 // Reduced from 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.distribution = .fill
        stack.alignment = .leading

        bubble.addSubview(stack)

        let controller = StreamMessageController(
            containerView: container, 
            stackView: stack, 
            maxWidth: maxWidth
        )

        let bubbleWidth = bubble.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -10)
        bubbleWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -6),
            stack.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -6),
            
            bubble.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            bubble.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),

            bubbleWidth,
            bubble.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            bubble.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth),

            bubble.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            bubble.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -8),
        ])

        _ = setupWindowResizeHandler(for: bubble, container: container)

        return (container, controller)
    }

    private static func calculateMaxWidth() -> CGFloat {
        let screenWidth = NSScreen.main?.visibleFrame.width ?? 800
        return min(screenWidth * 1, 800) // 70% of screen or 800px max
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
                    constraint.constant = -5 // Maintain the 10pt offset
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
