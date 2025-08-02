import Cocoa

// MARK: - STREAMRENDERER.swift
enum StreamRenderer {
    // MARK: - STREAMMESSAGECONTROLLER.swift
    final class StreamMessageController{
        let textBlock: TextBlock

        private var updateLock = os_unfair_lock()
        private var displayLink: DisplayLink?
        private var isAnimating = false
        private var currentAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.textColor
        ]
        private let tokenQueue = DispatchQueue(label: "com.streamrenderer.tokenqueue", qos: .userInitiated)
        
        private let accumulator = StreamAccumulator()
        private let tokenizer = TextStreamTokenizer()

        private var pendingTokens: [(token: TextStreamTokenizer.TokenType, attributedString: NSAttributedString)] = []

        // Code block state management
        private var codeBlockDepth = 0
        private var currentCodeLanguage: String?
        private var isInCodeBlock: Bool { codeBlockDepth > 0 }

        private let minFrameInterval: CFTimeInterval = 1/60 // 60fps cap
        private var lastRenderTime: CFTimeInterval = 0
        private let maxPendingTokens = 1000

        private var codeBlockAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.textColor,
            .backgroundColor: NSColor.controlBackgroundColor
        ]

        init(textBlock: TextBlock) {
            self.textBlock = textBlock
        }

        private func createAttributedString(for token: TextStreamTokenizer.TokenType) -> (TextStreamTokenizer.TokenType, NSAttributedString) {
            let attributes = isInCodeBlock ? codeBlockAttributes : currentAttributes
            
            switch token {
            case .word(let text), .punctuation(let text), 
                .whitespace(let text), .special(let text):
                return (token, NSAttributedString(string: text, attributes: attributes))
                
            case .newline:
                return (token, NSAttributedString(string: "\n", attributes: attributes))
                
            case .bold(let text):
                var boldAttributes = attributes
                boldAttributes[.font] = NSFont.boldSystemFont(ofSize: (attributes[.font] as? NSFont)?.pointSize ?? 14)
                return (token, NSAttributedString(string: text, attributes: boldAttributes))
                
            case .italic(let text):
                var italicAttributes = attributes
                if let currentFont = attributes[.font] as? NSFont {
                    italicAttributes[.font] = NSFontManager.shared.convert(
                        currentFont,
                        toHaveTrait: .italicFontMask
                    )
                } else {
                    italicAttributes[.font] = NSFontManager.shared.convert(
                        NSFont.systemFont(ofSize: 14),
                        toHaveTrait: .italicFontMask
                    )
                }
                return (token, NSAttributedString(string: text, attributes: italicAttributes))
                
            case .inlineCode(let text):
                var codeAttributes = attributes
                codeAttributes[.font] = NSFont.monospacedSystemFont(ofSize: (attributes[.font] as? NSFont)?.pointSize ?? 12, weight: .regular)
                codeAttributes[.backgroundColor] = NSColor.controlBackgroundColor.withAlphaComponent(0.3)
                return (token, NSAttributedString(string: text, attributes: codeAttributes))
                
            case .codeBlockStart(let language):
                codeBlockDepth += 1
                currentCodeLanguage = language
                let delimiter = codeBlockDepth == 1 ? "\n```\(language ?? "")\n" : "```\n"
                return (token, NSAttributedString(string: delimiter, attributes: codeBlockAttributes))
                
            case .codeBlockEnd:
                codeBlockDepth = max(0, codeBlockDepth - 1)
                let delimiter = "```\n"
                let result = (token, NSAttributedString(string: delimiter, attributes: codeBlockAttributes))
                if codeBlockDepth == 0 {
                    currentCodeLanguage = nil
                }
                return result
                
            case .codeBlockContent(let text):
                return (token, NSAttributedString(string: text, attributes: codeBlockAttributes))

            case .link(let text, let url):
                var linkAttributes = attributes
                linkAttributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                linkAttributes[.foregroundColor] = NSColor.linkColor
                if let url = url {
                    linkAttributes[.link] = url
                }
                return (token, NSAttributedString(string: text, attributes: linkAttributes))
            }
        }

        func appendStreamingText(_ newChunk: String, isComplete: Bool = false) {
            tokenQueue.async { [weak self] in
                guard let self = self else { return }
                print("\(newChunk)")

                let (tokens, _) = self.accumulator.process(chunk: newChunk)
                
                let attributedTokens = tokens.map { self.createAttributedString(for: $0) }
                
                os_unfair_lock_lock(&self.updateLock)
                self.pendingTokens += attributedTokens
                if isComplete {
                    let remaining = self.accumulator.flush()
                    if !remaining.isEmpty {
                        // let finalTokens = self.tokenizer.tokenize(remaining)
                        self.pendingTokens += remaining.map { self.createAttributedString(for: $0) }
                    }
                }
                os_unfair_lock_unlock(&self.updateLock)
                
                DispatchQueue.main.async {
                    self.startIfNeeded()
                }
            }

             // When stream ends (you'll need to detect this)
            // let remaining = self.accumulator.flush()
            // if !remaining.isEmpty {
            //     let tokens = self.tokenizer.tokenize(remaining)
            //     // ... process final chunk ...
            // }
        }

        private func processPendingUpdates() {
            dispatchPrecondition(condition: .onQueue(.main))
            let currentTime = CACurrentMediaTime()
            guard currentTime - lastRenderTime >= minFrameInterval else { return }

            var batch: [(token: TextStreamTokenizer.TokenType, attributedString: NSAttributedString)] = []
            var shouldStop = false
            
            os_unfair_lock_lock(&updateLock)
            let dynamicBatchSize = min(50, max(5, pendingTokens.count / 10 + 1))
            if dynamicBatchSize > 0 && pendingTokens.count > 0 {
                batch = Array(pendingTokens.prefix(dynamicBatchSize))
                pendingTokens.removeFirst(batch.count)
                shouldStop = pendingTokens.isEmpty
            }
            os_unfair_lock_unlock(&updateLock)

            guard !batch.isEmpty else {
                if shouldStop { stop() }
                return
            }

            let combined = NSMutableAttributedString()
            for (token, attributedString) in batch {
                if case .newline = token {
                    combined.append(NSAttributedString(string: "\n"))
                } else {
                    combined.append(attributedString)
                }
            }
            
            textBlock.appendText(combined)
            lastRenderTime = currentTime

            if shouldStop {
                stop()
            } else {
                DispatchQueue.main.async {
                    self.processPendingUpdates()
                }
            }
        }

        private func startIfNeeded() {
            guard !isAnimating else { return }
            isAnimating = true
            displayLink = DisplayLink { [weak self] in
                self?.processPendingUpdates()
            }
            displayLink?.start()
        }

        private func stop() {
            guard isAnimating else { return }
            isAnimating = false
            displayLink?.stop()
            displayLink = nil
        }
        
        func clear() {
            os_unfair_lock_lock(&updateLock)
                pendingTokens.removeAll()
                accumulator.reset()
                tokenizer.reset()
                codeBlockDepth = 0
                currentCodeLanguage = nil
            os_unfair_lock_unlock(&updateLock)
            
            DispatchQueue.main.async {
                self.textBlock.textView.string = ""
                self.textBlock.updateHeight()
            }
        }

        deinit {
            stop()
        }
    }

    class TextBlock: NSView {
        private(set) var textView: NSTextView
        private var heightConstraint: NSLayoutConstraint?
        private let maxWidth: CGFloat
    
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

        func appendText(_ attributedString: NSAttributedString) {
            textView.textStorage?.beginEditing()
            textView.textStorage?.append(attributedString)
            textView.textStorage?.endEditing()
            updateHeight()
        }

        func appendNewline() {
            appendText(NSAttributedString(string: "\n"))
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

            superview?.layoutSubtreeIfNeeded()
        }
    }

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

        // Text block here
        let textblock = TextBlock(maxWidth: maxWidth)
        stack.addArrangedSubview(textblock)

        let controller = StreamMessageController(textBlock: textblock)

        // Setup constraints
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -8),
            
            bubble.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            bubble.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
            bubble.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth),
        ])

        bubble.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8).isActive = true
        bubble.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -40).isActive = true
         
        

        return (container, controller)
    }

    // MARK: - Private Helpers
    private static func calculateMaxWidth() -> CGFloat {
        let screenWidth = NSScreen.main?.visibleFrame.width ?? 800
        return min(screenWidth * 0.7, 800) // 70% of screen or 800px max
    }
}
