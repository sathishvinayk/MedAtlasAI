import Cocoa

class ChatController {
    private let chatApiService = ChatApiService()
    private let textView: NSTextView?
    private let messagesStack: NSStackView?
    private let inputHeightConstraint: NSLayoutConstraint?
    private var currentAssistantLabel: NSTextField?
    private var typingIndicator: TypingIndicatorView?
    private var assistantResponseBuffer = NSMutableAttributedString()

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

        startStreamingResponse(for: text)
    }

    private func startStreamingResponse(for prompt: String) {
    guard let messagesStack = messagesStack else { return }

    // Step 1: Show typing indicator
    let indicator = TypingIndicatorView()
    messagesStack.addArrangedSubview(indicator)
    typingIndicator = indicator
    currentAssistantLabel = nil // Reset any previous state

    chatApiService.fetchGPTResponse(for: prompt) { [weak self] chunk in
        DispatchQueue.main.async {
            guard let self = self else { return }

            // Step 4: Handle stream done
            if chunk == "[STREAM_DONE]" {
                self.typingIndicator?.removeFromSuperview()
                self.typingIndicator?.stopAnimating()
                self.typingIndicator = nil
                self.currentAssistantLabel = nil
                self.assistantResponseBuffer = NSMutableAttributedString()
                return
            }

            // Step 2: Ignore whitespace-only chunks
            let trimmedChunk = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedChunk.isEmpty else { return }

            // Step 2 (continued): If assistant label not yet set, create one
            if self.currentAssistantLabel == nil {
                self.typingIndicator?.removeFromSuperview()
                self.typingIndicator?.stopAnimating()
                self.typingIndicator = nil

                let (bubble, label) = MessageRenderer.renderMessage("", isUser: false)
                messagesStack.addArrangedSubview(bubble)
                self.currentAssistantLabel = label
            }

            // Step 3: Append chunk
            guard let label = self.currentAssistantLabel else { return }

            let attributedChunk = NSAttributedString(string: chunk, attributes: [
                .font: label.font ?? NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor.labelColor
            ])
            self.assistantResponseBuffer.append(attributedChunk)
            label.attributedStringValue = self.assistantResponseBuffer
        }
    }
}


    private func addMessage(_ message: String, isUser: Bool) {
        guard let messagesStack = messagesStack else { return }
        let (messageContainer, messageLabel) = MessageRenderer.renderMessage(message, isUser: isUser)
        messagesStack.addArrangedSubview(messageContainer)

        if !isUser {
            currentAssistantLabel = messageLabel
        }
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
