import Cocoa
import Carbon

var isStealthVisible = true

class AppDelegate: NSObject, NSApplicationDelegate, NSTextViewDelegate {
    var chatApiService = ChatApiService()
    var chatController: ChatController!
    var messageManager: MessageManager!

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
    }

    func setupWindow() {
        let windowManager = WindowManager()
        let result = windowManager.createWindow(delegate: nil)
        window = result.window
        
        let ui = ChatUIBuilder.buildChatUI(in: result.contentView, delegate: self, target: self, sendAction: #selector(handleInput))
        messagesStack = ui.messagesStack
        textView = ui.textView
        inputScroll = ui.inputScroll
        inputHeightConstraint = ui.inputHeightConstraint
        messageManager = MessageManager(messagesStack: messagesStack)

        chatController = ChatController(
            textView: textView,
            messagesStack: messagesStack,
            inputHeightConstraint: inputHeightConstraint
        ) { message, isUser in
            self.messageManager.addMessage(message, isUser: isUser)
        }

        textDidChange(Notification(name: NSText.didChangeNotification))
        
        DispatchQueue.main.async {
            self.textView.window?.makeFirstResponder(self.textView)
        }
    }

    @objc func handleInput() {
        chatController.handleInput()
    }

    func textDidChange(_ notification: Notification) {
        chatController.updateInputHeight()
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
}
