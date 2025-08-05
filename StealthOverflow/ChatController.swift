import Cocoa

class ChatController {
    private let chatApiService = ChatApiService()
    private let textView: NSTextView?
    private weak var messagesStack: NSStackView?
    private let inputHeightConstraint: NSLayoutConstraint?
    private var typingIndicator: TypingIndicatorView?

    // Thread-safe controller management
    private let controllerAccessQueue = DispatchQueue(label: "com.controller.access", attributes: .concurrent)
    private var _currentStreamingTextController: StreamRenderer.StreamMessageController?
    
    private var currentStreamingTextController: StreamRenderer.StreamMessageController? {
        get { controllerAccessQueue.sync { _currentStreamingTextController } }
        set { controllerAccessQueue.async(flags: .barrier) { self._currentStreamingTextController = newValue } }
    }

    private var assistantResponseBuffer = NSMutableAttributedString()

    private var isInCodeBlock = false
    private var codeBlockBuffer = ""

    init(messagesStack: NSStackView, textView: NSTextView, inputHeightConstraint: NSLayoutConstraint?) {
        self.messagesStack = messagesStack
        self.textView = textView
        self.inputHeightConstraint = inputHeightConstraint
    }
    private func processChunk(_ chunk: String) {
        let remainingChunk = chunk
        
        if isInCodeBlock {
            if let closingRange = remainingChunk.range(of: "```") {
                // Found closing ```
                let codeContent = remainingChunk[..<closingRange.lowerBound]
                codeBlockBuffer += codeContent
                
                // Force as code block if we were in code block mode
                assistantResponseBuffer.append(NSAttributedString(string: "```\n" + codeBlockBuffer + "\n```"))
                codeBlockBuffer = ""
                isInCodeBlock = false
                
                // Process remaining text
                let remainingText = String(remainingChunk[closingRange.upperBound...])
                if !remainingText.isEmpty {
                    assistantResponseBuffer.append(NSAttributedString(string: remainingText))
                }
            } else {
                codeBlockBuffer += remainingChunk
            }
        } else {
            // First check for triple backticks
            if let openingRange = remainingChunk.range(of: "```") {
                // Check if it's really triple (not inline)
                let potentialTriple = remainingChunk[openingRange.lowerBound...]
                if potentialTriple.count >= 3 && potentialTriple.starts(with: "```") {
                    // Handle code block
                    let textBefore = remainingChunk[..<openingRange.lowerBound]
                    if !textBefore.isEmpty {
                        assistantResponseBuffer.append(NSAttributedString(string: String(textBefore)))
                    }
                    
                    isInCodeBlock = true
                    codeBlockBuffer = ""
                    
                    let afterTicks = remainingChunk.index(openingRange.lowerBound, offsetBy: 3)
                    let remaining = String(remainingChunk[afterTicks...])
                    if !remaining.isEmpty {
                        processStreamChunk(remaining)
                    }
                    return
                }
            }
            
            // Handle inline code
            let processed = remainingChunk.replacingOccurrences(
                of: "`([^`]+)`",
                with: "`$1`",
                options: .regularExpression
            )
            assistantResponseBuffer.append(NSAttributedString(string: processed))
        }
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

        DispatchQueue.main.async {
            let indicator = TypingIndicatorView()
            messagesStack.addArrangedSubview(indicator)
            self.typingIndicator = indicator
            self.currentStreamingTextController = nil
        }

        chatApiService.fetchGPTResponse(for: prompt) { [weak self] chunk in
            self?.processStreamChunk(chunk)
        }
    }

    private func initializeStreamingController() {
        assert(Thread.isMainThread, "Must initialize on main thread")
        let (bubble, controller) = StreamRenderer.renderStreamingMessage()
        messagesStack?.addArrangedSubview(bubble)
        currentStreamingTextController = controller
        typingIndicator?.removeFromSuperview()
        typingIndicator = nil
    }

    private func processStreamChunk(_ chunk: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if chunk == "[STREAM_DONE]" {
                self.handleStreamCompletion()
                return
            }
            self.processChunk(chunk)
            
            // Safely get controller reference
            if self.currentStreamingTextController == nil {
                self.initializeStreamingController()
            }
            
            self.typingIndicator?.removeFromSuperview()
            self.typingIndicator = nil
            
            // Thread-safe append with main thread guarantee
            self.currentStreamingTextController?.appendStreamingText(self.assistantResponseBuffer.string, isComplete: false)
        }
    }

    private func handleStreamCompletion() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
             // Get the current controller strongly
            guard let controller = self.currentStreamingTextController else {
                self.typingIndicator?.removeFromSuperview()
                self.typingIndicator = nil
                return
            }
            
            // Send the final accumulated text
            controller.appendStreamingText(self.assistantResponseBuffer.string, isComplete: true)
            
            // Clear the local buffer after sending
            self.assistantResponseBuffer = NSMutableAttributedString()
            
            self.typingIndicator?.removeFromSuperview()
            self.typingIndicator = nil
            
             // Delayed cleanup with identity check
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak controller] in
                guard let self = self else { return }
                if let currentController = self.currentStreamingTextController, currentController === controller {
                    self.currentStreamingTextController = nil
                }
            }
        }
    }

    private func addMessage(_ message: String, isUser: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let messagesStack = self.messagesStack else { return }
            let (container, _) = MessageRenderer.renderMessage(message, isUser: isUser)
            messagesStack.addArrangedSubview(container)
        }
    }

    func textDidChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let textView = self.textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let newHeight = usedRect.height + textView.textContainerInset.height * 2
            self.inputHeightConstraint?.constant = min(max(newHeight, 32), 120)
        }
    }
}
