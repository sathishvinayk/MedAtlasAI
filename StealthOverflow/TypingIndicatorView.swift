import Cocoa

class TypingIndicatorView: NSView {
    private let label = NSTextField(labelWithString: "")
    private var timer: Timer?
    private var dotCount = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
        startAnimating()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        startAnimating()
    }

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = .clear

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 30)
        label.textColor = .white
        label.alignment = .left
        label.lineBreakMode = .byWordWrapping

        addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 30)
        ])
    }

    private func startAnimating() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            self.dotCount = (self.dotCount + 1) % 4
            // self.label.stringValue = "Assistant is typing" + String(repeating: ".", count: self.dotCount)
            self.label.stringValue = String(repeating: ".", count: self.dotCount)
        }
    }

    func stopAnimating() {
        timer?.invalidate()
        timer = nil
    }
}
