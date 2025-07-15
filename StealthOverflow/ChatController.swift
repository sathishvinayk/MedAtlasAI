import Cocoa

class ChatController {
    private let chatApiService = ChatApiService()
    private let textView: NSTextView?
    private let messagesStack: NSStackView?
    private let inputHeightConstraint: NSLayoutConstraint?
    

    init( messagesStack: NSStackView, textView: NSTextView, 
        inputHeightConstraint: NSLayoutConstraint?
    ) {
        self.messagesStack = messagesStack
        self.textView = textView 
        self.inputHeightConstraint = inputHeightConstraint
    }

    func handleInput() {
        guard let textView = textView else { return }
        let text = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        addMessage("You: \(text)", isUser:true)
        textView.string = ""
        textDidChange()

        chatApiService.fetchGPTResponse(for: text) { response in
            DispatchQueue.main.async {
                self.addMessage("GPT: \(response)", isUser:false)
            }
        }
    }

    private func addMessage(_ message: String, isUser: Bool) {
        guard let messagesStack = messagesStack else { return }
        let messageView = MessageRenderer.renderMessage(message, isUser: isUser)
        messagesStack.addArrangedSubview(messageView)
    }

    func textDidChange() {
        guard let textView = textView,
            let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer else { return }

        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let newHeight = usedRect.height + textView.textContainerInset.height * 2
        let clampedHeight = min(max(newHeight, 32), 120)

        inputHeightConstraint?.constant = clampedHeight
    }
}
