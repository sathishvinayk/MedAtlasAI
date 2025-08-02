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

        // assistantResponseBuffer = NSMutableAttributedString()
        // currentStreamingTextController?.clear()
        currentStreamingTextController = nil

        chatApiService.fetchGPTResponse(for: prompt) { [weak self] chunk in
            DispatchQueue.main.async {
                guard let self = self else { return }

                if chunk == "[STREAM_DONE]" {
                    // self.finalizeStream()
                }

                self.processStreamChunk(chunk)
            }
        }
    }

     private func initializeStreamingController() {
        let (bubble, controller) = StreamRenderer.renderStreamingMessage()
        messagesStack?.addArrangedSubview(bubble)
        currentStreamingTextController = controller
        typingIndicator?.removeFromSuperview()
        typingIndicator = nil
    }
    private func finalizeStream() {
        typingIndicator?.removeFromSuperview()
        typingIndicator = nil
        currentStreamingTextController?.appendStreamingText("", isComplete: true)
    }

    private func processStreamChunk(_ chunk: String) {  // Explicit String return
        // print("\(chunk)")
        if currentStreamingTextController == nil {
            initializeStreamingController()
        }
        currentStreamingTextController?.appendStreamingText(chunk)
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