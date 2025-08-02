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
        private let accumulator = StreamAccumulator()
        private let tokenQueue = DispatchQueue(label: "com.streamrenderer.tokenqueue", qos: .userInitiated)

        private let tokenizer = TextStreamTokenizer()
        private var pendingTokens: [(token: TextStreamTokenizer.TokenType, attributedString: NSAttributedString)] = []

        private let minFrameInterval: CFTimeInterval = 1/60 // 60fps cap
        private var lastRenderTime: CFTimeInterval = 0
        private let maxPendingTokens = 1000

        private var isInCodeBlock = false
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
                
            case .codeBlockStart:
                isInCodeBlock = true
                return (token, NSAttributedString(string: "\n```\n", attributes: codeBlockAttributes))
                
            case .codeBlockEnd:
                isInCodeBlock = false
                return (token, NSAttributedString(string: "```\n", attributes: codeBlockAttributes))
                
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

        func appendStreamingText(_ newChunk: String, 
            attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor.textColor]) 
        {
            currentAttributes = attributes
            tokenQueue.async { [weak self] in
                guard let self = self else { return }
                print("chunk\(newChunk)")

                let readyChunks = self.accumulator.process(chunk: newChunk)
                for chunk in readyChunks {
                    print("Processing meaningful chunk: \(chunk.prefix(100))...")

                    let tokens = tokenizer.tokenize(newChunk)
                    let attributedTokens = tokens.map { 
                        self.createAttributedString(for: $0)
                    }

                    os_unfair_lock_lock(&updateLock)
                    // Check if we're approaching the limit
                    if pendingTokens.count + attributedTokens.count > maxPendingTokens {
                        // Option 1: Drop oldest tokens to make space
                        let overflow = (pendingTokens.count + attributedTokens.count) - maxPendingTokens
                        if overflow < pendingTokens.count {
                            pendingTokens.removeFirst(overflow)
                        } else {
                            pendingTokens.removeAll()
                        }
                        
                        // Option 2: Alternatively, you could choose to ignore the new tokens
                        // when the buffer is full by returning early here
                    }

                    self.pendingTokens += attributedTokens
                    os_unfair_lock_unlock(&updateLock)
                    
                    DispatchQueue.main.async {
                        self.startIfNeeded()
                    }
                }
            }
        }

        private func processPendingUpdates() {
            dispatchPrecondition(condition: .onQueue(.main))
            let currentTime = CACurrentMediaTime()
            guard currentTime - lastRenderTime >= minFrameInterval else { return }

            var batch: [(token: TextStreamTokenizer.TokenType, attributedString: NSAttributedString)] = []

            os_unfair_lock_lock(&updateLock)
                let dynamicBatchSize = min(5, max(1, pendingTokens.count / 20 + 1))
                let batchSize = min(dynamicBatchSize, pendingTokens.count)
                if batchSize > 0 {
                    batch = Array(pendingTokens.prefix(batchSize))
                    pendingTokens.removeFirst(batchSize)
                    // print("Processing batch of \(batchSize) tokens:")
                }
                let shouldStop = pendingTokens.isEmpty
            os_unfair_lock_unlock(&updateLock)

            guard !batch.isEmpty else {
                stop()
                return
            }

            for (token, attributedString) in batch {
                if case .newline = token {
                    self.textBlock.appendNewline()
                } else {
                    self.textBlock.appendText(attributedString)
                }
            }
            self.lastRenderTime = currentTime

            // If we still have a large backlog, schedule immediately
            os_unfair_lock_lock(&updateLock)
            let hasLargeBacklog = pendingTokens.count > maxPendingTokens / 2
            os_unfair_lock_unlock(&updateLock)
            
            if hasLargeBacklog {
                DispatchQueue.main.async {
                    self.processPendingUpdates()
                }
            } else if shouldStop {
                stop()
            }
        }

        private func startIfNeeded() {
            guard !isAnimating else { return }
            stop()

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

        deinit {
            stop()
        }
    }

    class TextBlock: NSView {
        private var textView: NSTextView
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
            // print("attributedString -> \(attributedString)")
            dispatchPrecondition(condition: .onQueue(.main))
            // Check if this is a code block delimiter to add visual separation
            if attributedString.string == "```\n" || attributedString.string == "\n```\n" {
                let separator = NSAttributedString(string: "\n", attributes: [
                    .font: NSFont.systemFont(ofSize: 4)
                ])
                textView.textStorage?.append(separator)
            }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.1
                context.allowsImplicitAnimation = true
                textView.textStorage?.append(attributedString)
                updateHeight()
            })
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

