import Cocoa

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
    
    init(maxWidth: CGFloat) {
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
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 0, height: 6)
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
        let currentSelection = textView.selectedRange()
        
        textStorage.beginEditing()
        textStorage.append(newText)
        textStorage.endEditing()
        
        textView.setSelectedRange(currentSelection)
        updateHeight()
        
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