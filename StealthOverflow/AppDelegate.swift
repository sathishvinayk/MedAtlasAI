import Cocoa
import Carbon

var isStealthVisible = true

#if DEBUG
func injectHotReload() {
    Bundle(path: "/Applications/InjectionIII.app/Contents/Resources/macOSInjection.bundle")?.load()
    print("✅ InjectionIII loaded")
}
#endif

class AppDelegate: NSObject, NSApplicationDelegate, NSTextViewDelegate {
    private var startupWindowManager: StartupWindowManager!
    private var windowManager: WindowManager!
    // private var windowMovementManager: WindowMovementManager! // Add this
    private let moveDistance: CGFloat = 10.0 // Pixels to move per key press

    // Add this enum for direction
    enum MoveDirection {
        case up, down, left, right
    }
    
    var sendButton: NSButton!
    var stopButton: NSButton!

    var chatApiService = ChatApiService()
    var chatController: ChatController!

    var hotKeyManager: HotKeyManager!
    var window: NSWindow!
    var messagesStack: NSStackView!
    var textView: NSTextView!
    var inputScroll: NSScrollView!
    var inputHeightConstraint: NSLayoutConstraint!

    func moveWindow(direction: MoveDirection) {
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

    private func getScreenForWindow(_ window: NSWindow) -> NSScreen? {
        // Find which screen the window is currently on
        let windowCenter = NSPoint(
            x: window.frame.midX,
            y: window.frame.midY
        )
        
        return NSScreen.screens.first { $0.frame.contains(windowCenter) }
    }

    func toggleStealthMode() {
        isStealthVisible.toggle()
        if isStealthVisible {
            NSApplication.shared.unhide(nil) // Unhide the entire app
            window.orderFrontRegardless()
        } else {
            NSApplication.shared.hide(nil) // Hide the entire app
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        injectHotReload()
        #endif

        FontManager.shared.registerFontsSynchronously()
        hotKeyManager = HotKeyManager()
        // windowMovementManager = WindowMovementManager() // Initialize here
        setupStartupWindow()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, 
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            if let window = self.window {
                window.makeKeyAndOrderFront(nil)
                if self.chatController != nil {
                    window.makeFirstResponder(self.textView)
                }
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {}

    func setupStartupWindow() {
        startupWindowManager = StartupWindowManager()
        startupWindowManager?.onStartChat = { [weak self] in
            self?.setupChatWindow()
        }
        
        window = startupWindowManager.createStartupWindow()
        window?.makeKeyAndOrderFront(nil)
        // Enable movement ONLY for startup window
        // if let window = window {
        //     windowMovementManager.enableWindowMovement(for: window)
        // }
    }

    func setupChatWindow() {
        // Ensure we're on main thread
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.setupChatWindow()
            }
            return
        }
        
        // windowMovementManager.disableWindowMovement()
        
        // Clean up startup window
        startupWindowManager?.close()
        startupWindowManager = nil

        // Reset UI references before creating new window
        self.textView = nil
        self.sendButton = nil
        self.stopButton = nil
        
        windowManager = WindowManager()
        let result = windowManager.createWindow(delegate: self)
        window = result.window
        
        let ui = ChatUIBuilder.buildChatUI(
            in: result.contentView, 
            delegate: self, 
            target: self, 
            sendAction: #selector(AppDelegate.handleInput),
            stopAction: #selector(AppDelegate.handleStop)
        )
        messagesStack = ui.messagesStack
        textView = ui.textView
        inputScroll = ui.inputScroll
        inputHeightConstraint = ui.inputHeightConstraint
        sendButton = ui.sendButton
        stopButton = ui.stopButton

        chatController = ChatController(
            messagesStack: messagesStack,
            textView: textView,
            inputHeightConstraint: inputHeightConstraint,
            sendButton: sendButton,
            stopButton: stopButton
        )
        chatController.textDidChange()
        DispatchQueue.main.async {
            self.textView.window?.makeFirstResponder(self.textView)
        }
    }

    @objc func handleInput() {
        chatController.handleInput()
        updateSendButtonState()
    }

     @objc func handleStop() {
        chatController.stopStreaming()
    }

    private func updateSendButtonState() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                let textView = self.textView,
                let sendButton = self.sendButton else {
                return
            }
            
            let hasText = !textView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            sendButton.isEnabled = hasText
            sendButton.contentTintColor = hasText ? .systemBlue : .disabledControlTextColor
        }
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            let event = NSApp.currentEvent
            let isShiftPressed = event?.modifierFlags.contains(.shift) ?? false

            if !isShiftPressed {
                handleInput()
                return true
            }
            // Allow newline with Shift+Enter
        }
        return false
    }   
    func textDidChange(_ notification: Notification) {
        chatController.textDidChange()
    }

    // Add cleanup in deinit if needed
    deinit {
        // windowMovementManager.disableWindowMovement()
    }
}
