import Cocoa

final class StreamMessageController: NSObject {
    private var resizeDebounceTimer: Timer?
    private var lastContentWidth: CGFloat = 0
    private var isResizing = false
    let containerView: NSView
    let stackView: NSStackView
    let maxWidth: CGFloat

    private var _currentCodeBlock: CodeBlock?
    private let processingQueue = DispatchQueue(label: "stream.processor", qos: .userInteractive)
    private var displayLink: DisplayLink?
    private let codeBlockParser = CodeBlockParser()
    
    private let stateLock = NSRecursiveLock()
    private var _isAnimating = false
    private var _elements: [CodeBlockParser.ParsedElement] = []
    private var _lastRenderTime: CFTimeInterval = 0
    private var _currentTextBlock: TextBlock?
    
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

    private func createTextBlock() -> TextBlock {
        return TextBlock(maxWidth: self.maxWidth)
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
            for element in elements {
                switch element {
                case .text(let attributedString):
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
                    if self._currentCodeBlock == nil {
                        let codeBlock = self.createCodeBlock(language: language)
                        codeBlock.setText(content)
                        self.stackView.addArrangedSubview(codeBlock)
                        self._currentCodeBlock = codeBlock
                        self._currentTextBlock = nil
                    } else {
                        if let textView = self._currentCodeBlock {
                            textView.appendText(content)
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