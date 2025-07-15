import Cocoa

class ChatController {
    private let chatApiService = ChatApiService()
    private let textView: NSTextView
    private let messagesStack: NSStackView
    private let inputHeightConstraint: NSLayoutConstraint
    private let onNewMessage: (String, Bool) -> Void

    init(textView: NSTextView, messagesStack: NSStackView, inputHeightConstraint: NSLayoutConstraint, onNewMessage: @escaping (String, Bool) -> Void) {
        self.textView = textView
        self.messagesStack = messagesStack
        self.inputHeightConstraint = inputHeightConstraint
        self.onNewMessage = onNewMessage
    }

    func handleInput() {
        let text = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        onNewMessage("You: \(text)", true)
        textView.string = ""
        updateInputHeight()

        chatApiService.fetchGPTResponse(for: text) { response in
            DispatchQueue.main.async {
                self.onNewMessage("GPT: \(response)", false)
            }
        }
    }

    func updateInputHeight() {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let newHeight = usedRect.height + textView.textContainerInset.height * 2
        let clampedHeight = min(max(newHeight, 32), 120)

        inputHeightConstraint.constant = clampedHeight
    }
}
