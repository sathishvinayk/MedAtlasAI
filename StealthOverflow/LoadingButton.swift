import Cocoa

class LoadingButton: NSButton {
    private let progressIndicator = NSProgressIndicator()
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupProgressIndicator()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupProgressIndicator()
    }
    
    private func setupProgressIndicator() {
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(progressIndicator)
        
        NSLayoutConstraint.activate([
            progressIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            progressIndicator.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    
    func showLoading() {
        title = ""
        progressIndicator.startAnimation(nil)
    }
    
    func hideLoading() {
        title = "➤"
        progressIndicator.stopAnimation(nil)
    }
}