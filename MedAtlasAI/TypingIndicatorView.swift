import Cocoa

class TypingIndicatorView: NSView {
    private let dots = [NSTextField(labelWithString: "."), 
                    NSTextField(labelWithString: "."), 
                    NSTextField(labelWithString: ".")]
    private var timer: Timer?
    private var currentDot = 0

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
        layer?.cornerRadius = 14

        let stackView = NSStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .horizontal
        stackView.spacing = 4
        stackView.alignment = .bottom
        
        for dot in dots {
            dot.font = NSFont.systemFont(ofSize: 30)
            dot.textColor = .white
            stackView.addArrangedSubview(dot)
        }
        
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 30)
        ])
    }

    private func startAnimating() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            // Animate all dots in a wave pattern
            for (index, dot) in self.dots.enumerated() {
                dot.layer?.removeAllAnimations()
                
                let jumpAnimation = CABasicAnimation(keyPath: "position.y")
                jumpAnimation.fromValue = dot.frame.origin.y
                jumpAnimation.toValue = dot.frame.origin.y - 10
                jumpAnimation.duration = 0.2
                jumpAnimation.autoreverses = true
                jumpAnimation.beginTime = CACurrentMediaTime() + Double(index) * 0.1
                dot.layer?.add(jumpAnimation, forKey: "wave")
            }
        }
    }
    
    func stopAnimating() {
        timer?.invalidate()
        timer = nil
        for dot in dots {
            dot.layer?.removeAllAnimations()
        }
    }
}
