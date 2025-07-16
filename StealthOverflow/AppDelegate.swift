import Cocoa
import Carbon

var isStealthVisible = true

class AppDelegate: NSObject, NSApplicationDelegate, NSTextViewDelegate {
    var chatApiService = ChatApiService()
    var chatController: ChatController!

    var hotKeyManager: HotKeyManager!
    var window: TransparentPanel!
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
        hotKeyManager = HotKeyManager()
        setupWindow()
        KeyboardHandler.monitorEscapeKey()
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.window.makeKeyAndOrderFront(nil)
            self.window.makeFirstResponder(self.textView)
        }
    }

    func setupWindow() {
        let windowManager = WindowManager()
        let result = windowManager.createWindow(delegate: nil)
        window = result.window
        
        let ui = ChatUIBuilder.buildChatUI(in: result.contentView, delegate: self, target: self, sendAction: #selector(AppDelegate.handleInput))
        messagesStack = ui.messagesStack
        textView = ui.textView
        inputScroll = ui.inputScroll
        inputHeightConstraint = ui.inputHeightConstraint

        chatController = ChatController(
            messagesStack: messagesStack,
            textView: textView,
            inputHeightConstraint: inputHeightConstraint
        )
        chatController.textDidChange()
        DispatchQueue.main.async {
            self.textView.window?.makeFirstResponder(self.textView)
        }
    }

    @objc func handleInput() {
        chatController.handleInput()
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
}
