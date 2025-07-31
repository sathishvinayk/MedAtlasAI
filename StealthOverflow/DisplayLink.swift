import Cocoa

// MARK: - DisplayLink Implementation
final class DisplayLink {
    private var displayLink: CVDisplayLink?
    private var callback: (() -> Void)?
    
    init(callback: @escaping () -> Void) {
        self.callback = callback
        setupDisplayLink()
    }
    
    private func setupDisplayLink() {
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        CVDisplayLinkSetOutputCallback(displayLink!, { (displayLink, inNow, inOutputTime, flagsIn, flagsOut, userInfo) -> CVReturn in
            let displayLinkInstance = unsafeBitCast(userInfo, to: DisplayLink.self)
            DispatchQueue.main.async {
                displayLinkInstance.callback?()
            }
            return kCVReturnSuccess
        }, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
    }
    
    func start() {
        CVDisplayLinkStart(displayLink!)
    }
    
    func stop() {
        CVDisplayLinkStop(displayLink!)
    }
    
    deinit {
        stop()
        callback = nil
    }
}