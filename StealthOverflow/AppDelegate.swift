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
    private var windowMovementManager: WindowMovementManager! // Add this

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

    func toggleStealthMode() {
        isStealthVisible.toggle()
        if isStealthVisible {
            window.orderFrontRegardless()
        } else {
            window.orderOut(nil)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        injectHotReload()
        #endif

        FontManager.shared.registerFontsSynchronously()
        hotKeyManager = HotKeyManager()
        windowMovementManager = WindowMovementManager() // Initialize here
        setupStartupWindow()
        KeyboardHandler.monitorEscapeKey()

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

    func setupStartupWindow() {
        startupWindowManager = StartupWindowManager()
        startupWindowManager?.onStartChat = { [weak self] in
            self?.setupChatWindow()
        }
        
        window = startupWindowManager.createStartupWindow()
        window?.makeKeyAndOrderFront(nil)
        // Enable movement ONLY for startup window
        if let window = window {
            windowMovementManager.enableWindowMovement(for: window)
        }
    }

    func setupChatWindow() {
        // Ensure we're on main thread
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.setupChatWindow()
            }
            return
        }
        
        windowMovementManager.disableWindowMovement()
        
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
        windowMovementManager.disableWindowMovement()
    }
}
