import Cocoa

import AppKit

public class DisplayLink {
    private var displayLink: AnyObject?
    private let callback: () -> Void
    private var isReady = false
    
    private var retryCount = 0
    private let maxRetryCount = 5
    private let retryInterval: TimeInterval = 0.1

    init(callback: @escaping () -> Void) {
        self.callback = callback
        setupDisplayLink()
    }

    private func setupDisplayLink() {
        if #available(macOS 15.0, *) {
            setupModernDisplayLink()
        } else {
            setupLegacyDisplayLink()
        }
    }

    @available(macOS 15.0, *)
    private func setupModernDisplayLink() {
        if let window = NSApp.mainWindow {
            let link = window.displayLink(target: self, selector: #selector(displayLinkCallback))
            self.displayLink = link
            link.add(to: .current, forMode: .common)
            isReady = true
        } else if let screen = NSScreen.main {
            let link = screen.displayLink(target: self, selector: #selector(displayLinkCallback))
            self.displayLink = link
            link.add(to: .current, forMode: .common)
            isReady = true
        } else {
            scheduleRetry()
        }
    }

    private func setupLegacyDisplayLink() {
        guard #unavailable(macOS 15.0) else { return }

        var link: CVDisplayLink?
        let status = CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard status == kCVReturnSuccess, let createdLink = link else {
            print("DisplayLink: Failed to create CVDisplayLink")
            return
        }

        let callbackStatus = CVDisplayLinkSetOutputCallback(createdLink, { (_, _, _, _, _, context) -> CVReturn in
            guard let context = context else { return kCVReturnError }
            let instance = Unmanaged<DisplayLink>.fromOpaque(context).takeUnretainedValue()
            instance.callback()
            return kCVReturnSuccess
        }, Unmanaged.passUnretained(self).toOpaque())

        guard callbackStatus == kCVReturnSuccess else {
            print("DisplayLink: Failed to set callback")
            return
        }

        let startStatus = CVDisplayLinkStart(createdLink)
        guard startStatus == kCVReturnSuccess else {
            print("DisplayLink: Failed to start")
            return
        }

        displayLink = createdLink
        isReady = true
    }

    private func scheduleRetry() {
        guard retryCount < maxRetryCount else {
            if #available(macOS 15.0, *) {
                print("DisplayLink: Max retry attempts reached")
            } else {
                print("DisplayLink: Max retry attempts reached, falling back to CVDisplayLink")
                setupLegacyDisplayLink()
            }
            return
        }

        retryCount += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + retryInterval) { [weak self] in
            self?.setupDisplayLink()
        }
    }

    @objc private func displayLinkCallback() {
        guard isReady else { return }
        callback()
    }

    func invalidate() {
        if #available(macOS 15.0, *) {
            // No action needed for modern displayLink
        } else {
            if let link = displayLink {
                CVDisplayLinkStop(link as! CVDisplayLink)
            }
        }

        displayLink = nil
        isReady = false
    }

    func start() {
        if #available(macOS 15.0, *) {
            // Modern display links start automatically
        } else {
            if CFGetTypeID(displayLink) == CVDisplayLinkGetTypeID() {
                CVDisplayLinkStop(unsafeBitCast(displayLink, to: CVDisplayLink.self))
            }   
        }
    }
    
    func stop() {
        if #available(macOS 15.0, *) {
            (displayLink as AnyObject).invalidate()
        } else {
            if CFGetTypeID(displayLink) == CVDisplayLinkGetTypeID() {
                CVDisplayLinkStop(unsafeBitCast(displayLink, to: CVDisplayLink.self))
            }
        }
    }

    deinit {
        invalidate()
    }
}
