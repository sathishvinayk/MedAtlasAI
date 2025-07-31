import Cocoa

class ChatController {
    private let chatApiService = ChatApiService()
    private let textView: NSTextView?
    private weak var messagesStack: NSStackView?
    private let inputHeightConstraint: NSLayoutConstraint?

    private var typingIndicator: TypingIndicatorView?
    private var currentStreamingTextController: StreamRenderer.StreamMessageController?

    private var assistantResponseBuffer = NSMutableAttributedString()
    private var isInCodeBlock = false
    private var codeBlockBuffer = ""

    init(messagesStack: NSStackView, textView: NSTextView, inputHeightConstraint: NSLayoutConstraint?) {
        self.messagesStack = messagesStack
        self.textView = textView
        self.inputHeightConstraint = inputHeightConstraint
    }

    func handleInput() {
        guard let textView = textView else { return }
        let text = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        addMessage(text, isUser: true)
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
        assistantResponseBuffer = NSMutableAttributedString()
        isInCodeBlock = false
        codeBlockBuffer = ""
        currentStreamingTextController = nil

        chatApiService.fetchGPTResponse(for: prompt) { [weak self] chunk in
            DispatchQueue.main.async {
                guard let self = self else { return }

                if chunk == "[STREAM_DONE]" {
                    self.typingIndicator?.removeFromSuperview()
                    self.typingIndicator?.stopAnimating()
                    self.typingIndicator = nil

                //  if self.isInCodeBlock && !self.codeBlockBuffer.isEmpty {
                //      self.assistantResponseBuffer.append(NSAttributedString(string: "```\n" + self.codeBlockBuffer + "\n```"))
                //      self.codeBlockBuffer = ""
                //      self.isInCodeBlock = false
                //  }

                //  let finalText = self.assistantResponseBuffer.string.trimmingCharacters(in: .whitespacesAndNewlines)
                //  if !finalText.isEmpty {
                //      let (finalBubble, _) = MessageRenderer.renderMessage(finalText, isUser: false)
                //      self.messagesStack?.addArrangedSubview(finalBubble)
                //  }

                //  self.currentStreamingTextController?.view.removeFromSuperview()
                //  self.currentStreamingTextController = nil
                    // return
                }

                // Step 2: Ignore empty chunks
                let trimmedChunk = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedChunk.isEmpty else { return }

                // Step 3: Process chunk
                let processedChunk = self.processStreamChunk(chunk)

                // Step 4: Lazy create streaming bubble
                if self.currentStreamingTextController == nil {
                    self.typingIndicator?.removeFromSuperview()
                    self.typingIndicator?.stopAnimating()
                    self.typingIndicator = nil

                    let (bubble, controller) = StreamRenderer.renderStreamingMessage()
                    self.messagesStack?.addArrangedSubview(bubble)
                    self.currentStreamingTextController = controller
                }

                // Step 5: Append text to the live bubble
                self.currentStreamingTextController?.appendStreamingText(processedChunk)
            }
        }
    }

    private func processStreamChunk(_ chunk: String) -> String {  // Explicit String return
        var result = ""
        
        if isInCodeBlock {
            if let closingRange = chunk.range(of: "```") {
                let codeContent = chunk[..<closingRange.lowerBound]
                codeBlockBuffer += codeContent
                assistantResponseBuffer.append(NSAttributedString(string: "```\n" + codeBlockBuffer + "\n```"))
                result += "```\n" + codeBlockBuffer + "\n```"
                codeBlockBuffer = ""
                isInCodeBlock = false

                let remaining = chunk[closingRange.upperBound...]
                if !remaining.isEmpty {
                    assistantResponseBuffer.append(NSAttributedString(string: String(remaining)))
                    result += String(remaining)
                }
            } else {
                codeBlockBuffer += chunk
            }
        } else {
            if let openingRange = chunk.range(of: "```") {
                let before = chunk[..<openingRange.lowerBound]
                if !before.isEmpty {
                    assistantResponseBuffer.append(NSAttributedString(string: String(before)))
                    result += String(before)
                }

            isInCodeBlock = true
            codeBlockBuffer = ""

            let after = chunk[openingRange.upperBound...]
            if !after.isEmpty {
                result += processStreamChunk(String(after)) // recursive for nested
            }
        } else {
            assistantResponseBuffer.append(NSAttributedString(string: chunk))
            result += chunk
        }
    }
    
    return result
}

    private func addMessage(_ message: String, isUser: Bool) {
        guard let messagesStack = messagesStack else { return }
        let (container, _) = MessageRenderer.renderMessage(message, isUser: isUser)
        messagesStack.addArrangedSubview(container)
    }

    func textDidChange() {
        guard let textView = textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let newHeight = usedRect.height + textView.textContainerInset.height * 2
        inputHeightConstraint?.constant = min(max(newHeight, 32), 120)
    }
}
