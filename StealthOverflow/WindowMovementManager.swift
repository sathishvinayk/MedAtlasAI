import Cocoa
import Carbon

class WindowMovementManager {
    private var window: NSWindow?
    private var moveStep: CGFloat = 10.0
    private var eventMonitor: Any?
    private var hotKeyManager: HotKeyManager?
    
    func enableWindowMovement(for window: NSWindow) {
        self.window = window
        startGlobalKeyMonitoring()
    }
    
    func disableWindowMovement() {
        stopGlobalKeyMonitoring()
        window = nil
    }
    
    private func startGlobalKeyMonitoring() {
        // Use global monitor for key events
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }
        
        // Also monitor local events for when window has focus
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
            return event
        }
    }
    
    private func stopGlobalKeyMonitoring() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    
    private func handleKeyEvent(_ event: NSEvent) {
        guard let window = window, window.isVisible else { return }
        
        // Check for Command + Arrow keys
        if event.modifierFlags.contains(.command) {
            switch event.keyCode {
            case 123: // Left arrow
                moveWindow(dx: -moveStep, dy: 0)
            case 124: // Right arrow
                moveWindow(dx: moveStep, dy: 0)
            case 125: // Down arrow
                moveWindow(dx: 0, dy: -moveStep)
            case 126: // Up arrow
                moveWindow(dx: 0, dy: moveStep)
            default:
                break
            }
        }
    }
    
    private func moveWindow(dx: CGFloat, dy: CGFloat) {
        guard let window = window else { return }
        
        var newFrame = window.frame
        newFrame.origin.x += dx
        newFrame.origin.y += dy
        
        // Ensure window stays within screen bounds
        if let screen = window.screen {
            let screenFrame = screen.visibleFrame
            newFrame.origin.x = max(screenFrame.minX, min(newFrame.origin.x, screenFrame.maxX - newFrame.width))
            newFrame.origin.y = max(screenFrame.minY, min(newFrame.origin.y, screenFrame.maxY - newFrame.height))
        }
        
        window.setFrame(newFrame, display: true)
        
        // Provide visual feedback
        provideMovementFeedback()
    }
    
    private func provideMovementFeedback() {
        // Optional: Add visual feedback when window moves
        guard let window = window else { return }
        
        // Briefly change alpha to show movement
        let originalAlpha = window.alphaValue
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            window.animator().alphaValue = 0.9
        } completionHandler: {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.1
                window.animator().alphaValue = originalAlpha
            }
        }
    }
    
    deinit {
        disableWindowMovement()
    }
}