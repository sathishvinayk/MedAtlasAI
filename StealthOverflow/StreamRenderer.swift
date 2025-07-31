import Cocoa

// MARK: - STREAMRENDERER.swift
enum StreamRenderer {
    // MARK: - STREAMMESSAGECONTROLLER.swift
    final class StreamMessageController{
        let textBlock: TextBlock
        private var attributedCharacterQueue: [NSAttributedString] = []
        private var fullAttributedString = NSMutableAttributedString()

        private let updateLock = NSLock()
        private var displayLink: DisplayLink?
        private var isAnimating = false
        private var framesSinceLastUpdate = 0
        private let framesPerCharacter = 2 // Adjust for speed (lower = faster)
        private var currentAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.textColor
        ]
        private var pendingChunks: [NSAttributedString] = []
        private let minFrameInterval: CFTimeInterval = 1/60 // 60fps cap
        private var lastRenderTime: CFTimeInterval = 0

        private var unprocessedText: String = ""
        private let wordSeparators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        private var lastChunkSize = 0

        init(textBlock: TextBlock) {
            self.textBlock = textBlock
        }

        func appendStreamingText(_ newChunk: String, 
            attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor.textColor]) 
        {
            updateLock.lock()
            defer { updateLock.unlock() }

            let pattern = #"(\s+|[^\s]+)"#  // Match words + spaces separately

            let regex = try! NSRegularExpression(pattern: pattern, options: [])
            let range = NSRange(newChunk.startIndex..., in: newChunk)
            let matches = regex.matches(in: newChunk, options: [], range: range)
            // let attributed = NSAttributedString(string: newChunk, attributes: attributes)
            
            for match in matches {
                if let wordRange = Range(match.range, in: newChunk) {
                    let token = String(newChunk[wordRange])
                    let attributed = NSAttributedString(string: token, attributes: attributes)
                    pendingChunks.append(attributed)
                }
            }
            
            startIfNeeded()
        }

        private func processPendingUpdates() {
            let currentTime = CACurrentMediaTime()
            guard currentTime - lastRenderTime >= minFrameInterval else { return }

            updateLock.lock()
            guard !pendingChunks.isEmpty else {
                updateLock.unlock()
                stop()
                return
            }

            // Pop the next chunk
            let nextChunk = pendingChunks.removeFirst()
            updateLock.unlock()

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.1
                    context.allowsImplicitAnimation = true
                    self.textBlock.appendText(nextChunk)
                })
                
                self.lastRenderTime = currentTime
            }
        }

        private func startIfNeeded() {
            guard !isAnimating else { return }
            isAnimating = true
            framesSinceLastUpdate = 0

            displayLink = DisplayLink { [weak self] in
                self?.frameUpdate()
            }
            displayLink?.start()
        }

        private func frameUpdate(){
            processPendingUpdates()
        }

        private func stop() {
            isAnimating = false
            displayLink?.stop()
            displayLink = nil
        }
    }

    class TextBlock: NSView {
        let textView: NSTextView
        private var heightConstraint: NSLayoutConstraint?
        private let maxWidth: CGFloat
    
        init(maxWidth: CGFloat) {
            self.maxWidth = maxWidth
            self.textView = NSTextView()
            super.init(frame: .zero)
            setupTextView()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private func setupTextView() {
            let textStorage = NSTextStorage()
            let layoutManager = NSLayoutManager()
            textStorage.addLayoutManager(layoutManager)
            
            let textContainer = NSTextContainer(containerSize: NSSize(width: maxWidth, height: .greatestFiniteMagnitude))
            layoutManager.addTextContainer(textContainer)
            textView.layoutManager?.replaceTextStorage(textStorage)

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
            print("Appending text: \(attributedString.string)") // Debug print
            if textView.textStorage == nil {
                textView.layoutManager?.replaceTextStorage(NSTextStorage())
            }
            
            textView.textStorage?.append(attributedString)
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.1
                context.allowsImplicitAnimation = true
                // textView.scrollToEndOfDocument(nil) 
            })

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

