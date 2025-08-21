import Cocoa
import Carbon

class WindowMovementManager {
    private var window: NSWindow?
    private var moveStep: CGFloat = 10.0
    private var eventMonitor: Any?
    
    // Configuration
    var moveDistance: CGFloat = 20.0
    
    enum MoveDirection {
        case up, down, left, right
    }
    
    // NEW: Public method to move all visible windows (replacement for the original function)
    func moveAllVisibleWindows(direction: MoveDirection) {
        let windows = NSApplication.shared.windows
        print("=== WINDOW MOVEMENT DEBUG ===")
        print("Found \(windows.count) windows:")
        
        for (index, window) in windows.enumerated() {
            let windowType = window.isKind(of: NSPanel.self) ? "PANEL" : "WINDOW"
            print("\(index): '\(window.title)' - type: \(windowType), visible: \(window.isVisible), frame: \(window.frame)")
        }
        
        // Get ALL visible windows (including both startup and chat windows)
        let visibleWindows = windows.filter { $0.isVisible }
        print("Moving \(visibleWindows.count) visible windows")
        
        if visibleWindows.isEmpty {
            print("No visible windows to move")
            return
        }
        
        for window in visibleWindows {
            print("\n--- Moving: '\(window.title)' ---")
            print("Current position: \(window.frame.origin)")
            
            var newOrigin = window.frame.origin
            
            switch direction {
            case .up:
                newOrigin.y += moveDistance
                print("Direction: UP (+\(moveDistance)px)")
            case .down:
                newOrigin.y -= moveDistance
                print("Direction: DOWN (-\(moveDistance)px)")
            case .left:
                newOrigin.x -= moveDistance
                print("Direction: LEFT (-\(moveDistance)px)")
            case .right:
                newOrigin.x += moveDistance
                print("Direction: RIGHT (+\(moveDistance)px)")
            }
            
            print("Target position: \(newOrigin)")
            
            // For each window, check bounds on its current screen
            if let screen = getScreenForWindow(window)?.visibleFrame {
                let windowSize = window.frame.size
                let originalOrigin = newOrigin
                
                newOrigin.x = max(screen.minX, min(newOrigin.x, screen.maxX - windowSize.width))
                newOrigin.y = max(screen.minY, min(newOrigin.y, screen.maxY - windowSize.height))
                
                if newOrigin != originalOrigin {
                    print("Adjusted for screen bounds: \(newOrigin)")
                }
            }
            
            window.setFrameOrigin(newOrigin)
            print("Final position: \(window.frame.origin)")
        }
        
        print("=== MOVEMENT COMPLETE ===\n")
    }
    
    // Helper method to get screen for window
    private func getScreenForWindow(_ window: NSWindow) -> NSScreen? {
        return NSScreen.screens.first { screen in
            screen.frame.contains(window.frame.origin)
        } ?? window.screen
    }
    
    deinit {
    
    }
}