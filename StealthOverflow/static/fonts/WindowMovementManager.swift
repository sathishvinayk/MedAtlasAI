import Cocoa

class WindowMovementManager {
    private var currentWindow: NSWindow?
    private var moveStep: CGFloat = 10.0
    private var eventMonitor: Any?
    
    func enableWindowMovement(for window: NSWindow) {
        // Disable previous window movement first
        disableWindowMovement()
        
        self.currentWindow = window
        startMonitoringKeys()
    }
    
    func disableWindowMovement() {
        stopMonitoringKeys()
        currentWindow = nil
    }
    
    private func startMonitoringKeys() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, 
                  let window = self.currentWindow,
                  window.isKeyWindow else { return event }
            
            // Check for Command + Arrow keys
            let modifiers = event.modifierFlags
            let isCommandPressed = modifiers.contains(.command)
            let hasOtherModifiers = modifiers.contains(.shift) || modifiers.contains(.option) || modifiers.contains(.control)
            
            if isCommandPressed && !hasOtherModifiers {
                switch event.keyCode {
                case 123: // Left arrow
                    self.moveWindow(dx: -self.moveStep, dy: 0)
                    return nil
                case 124: // Right arrow
                    self.moveWindow(dx: self.moveStep, dy: 0)
                    return nil
                case 125: // Down arrow
                    self.moveWindow(dx: 0, dy: -self.moveStep)
                    return nil
                case 126: // Up arrow
                    self.moveWindow(dx: 0, dy: self.moveStep)
                    return nil
                default:
                    break
                }
            }
            
            return event
        }
    }
    
    private func stopMonitoringKeys() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    
    private func moveWindow(dx: CGFloat, dy: CGFloat) {
        guard let window = currentWindow else { return }
        
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
    }
    
    deinit {
        disableWindowMovement()
    }
}