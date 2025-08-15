import Cocoa

class CodeBlock: NSView {
    private let bubbleView = NSView()
    private let language: String
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
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.allowsImplicitAnimation = true
            self.updateHeight()
        }
    }
    
    override func layout() {
        super.layout()
        
        let availableWidth = max(bounds.width - 52, 150)
        textView.textContainer?.containerSize = NSSize(
            width: availableWidth,
            height: .greatestFiniteMagnitude
        )
        updateHeight()
    }

    init(language: String, maxWidth: CGFloat) {
        self.language = language 
        self.maxWidth = maxWidth

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

        let languageLabel = NSTextField(labelWithString: language.isEmpty ? "code" : language)
        languageLabel.translatesAutoresizingMaskIntoConstraints = false
        languageLabel.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        languageLabel.textColor = NSColor.secondaryLabelColor
        languageLabel.alignment = .right

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
        let highlightedText = SyntaxHighlighter.highlight(
            newText, 
            language: language,
            baseAttributes: TextAttributes.codeBlock
        )
        
        storage.beginEditing()
        storage.append(highlightedText)
        storage.endEditing()

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
        
        layoutManager.ensureLayout(for: container)
        let usedRect = layoutManager.usedRect(for: container)
        let totalHeight = ceil(usedRect.height) + textView.textContainerInset.height * 2
        
        if let heightConstraint = heightConstraint {
            heightConstraint.constant = totalHeight
        } else {
            heightConstraint = heightAnchor.constraint(equalToConstant: totalHeight)
            heightConstraint?.isActive = true
        }
        
        if let superview = superview, superview.inLiveResize {
            superview.needsLayout = true
        }
    }
}