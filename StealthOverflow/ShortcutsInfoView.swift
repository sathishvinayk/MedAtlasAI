import Cocoa
class EnhancedKeyCapView: NSView {
    private let label = NSTextField(labelWithString: "")
    
    init(key: String, fontSize: CGFloat = 12, width: CGFloat? = nil) {
        super.init(frame: .zero)
        setupEnhancedKeyCap(key: key, fontSize: fontSize, width: width)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    private func setupEnhancedKeyCap(key: String, fontSize: CGFloat, width: CGFloat?) {
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 1

        // Border with subtle shadow
        layer?.borderColor = NSColor.white.withAlphaComponent(0.4).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOffset = CGSize(width: 0, height: -1)
        layer?.shadowRadius = 1
        layer?.shadowOpacity = 0.3
        
        label.stringValue = key
        label.font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.isBezeled = false
        label.isEditable = false
        label.drawsBackground = false
        label.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(label)
        
        let keyWidth = width ?? (label.intrinsicContentSize.width + 16)
        
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthAnchor.constraint(equalToConstant: keyWidth),
            heightAnchor.constraint(equalToConstant: 26)
        ])
    }
}

class EnhancedShortcutsInfoView: NSView {
    private let titleLabel = NSTextField(labelWithString: "KEYBOARD SHORTCUTS")
    
    override init(frame: NSRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        // Configure title
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        titleLabel.textColor = NSColor.white.withAlphaComponent(0.7)
        
        // Create enhanced key cap views
        let commandKey = EnhancedKeyCapView(key: "⌘", fontSize: 14, width: 32)
        let plusLabel = NSTextField(labelWithString: "+")
        let xKey = EnhancedKeyCapView(key: "X", fontSize: 12, width: 28)
        let hideLabel = NSTextField(labelWithString: "Hide/Unhide")
        
        let escKey = EnhancedKeyCapView(key: "Esc", fontSize: 10, width: 40)
        let quitLabel = NSTextField(labelWithString: "Quit")

        // Add movement shortcuts
        let moveCommandKey = EnhancedKeyCapView(key: "⌘", fontSize: 14, width: 32)
        let arrowsLabel = NSTextField(labelWithString: "↑↓←→")
        arrowsLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        let moveLabel = NSTextField(labelWithString: "Move Window")
        
        // Configure labels
        [plusLabel, hideLabel, quitLabel, arrowsLabel, moveLabel].forEach { label in
            label.font = NSFont.systemFont(ofSize: 12, weight: .regular)
            label.textColor = NSColor.white.withAlphaComponent(0.8)
            label.isBezeled = false
            label.isEditable = false
            label.drawsBackground = false
        }
        
        plusLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        
        // Rows
        let commandRow = NSStackView(views: [commandKey, plusLabel, xKey, hideLabel])
        commandRow.orientation = .horizontal
        commandRow.spacing = 6
        commandRow.alignment = .centerY
        
        let escRow = NSStackView(views: [escKey, quitLabel])
        escRow.orientation = .horizontal
        escRow.spacing = 6
        escRow.alignment = .centerY

        let moveRow = NSStackView(views: [moveCommandKey, arrowsLabel, moveLabel])
        moveRow.orientation = .horizontal
        moveRow.spacing = 6
        moveRow.alignment = .centerY
        
        // Main stack
        let mainStack = NSStackView(views: [titleLabel, commandRow, escRow, moveRow])
        mainStack.orientation = .vertical
        mainStack.spacing = 10
        mainStack.alignment = .leading
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(mainStack)
        
        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            mainStack.topAnchor.constraint(equalTo: topAnchor),
            mainStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        // Add subtle shadow to title
        titleLabel.wantsLayer = true
        titleLabel.shadow = NSShadow()
        titleLabel.shadow?.shadowColor = NSColor.black.withAlphaComponent(0.8)
        titleLabel.shadow?.shadowBlurRadius = 0
        titleLabel.shadow?.shadowOffset = NSSize(width: 0.5, height: -0.5)
    }
}
