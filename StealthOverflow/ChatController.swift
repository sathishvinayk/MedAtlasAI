import Cocoa

class ChatController {
    private let chatApiService = ChatApiService()
    private let textView: NSTextView?
    private weak var messagesStack: NSStackView?
    private let inputHeightConstraint: NSLayoutConstraint?
    private var typingIndicator: TypingIndicatorView?
    private weak var sendButton: NSButton?
    private weak var stopButton: NSButton?
    private var isStreaming = false

    // Thread-safe controller management
    private let controllerAccessQueue = DispatchQueue(label: "com.controller.access", attributes: .concurrent)
    private var _currentStreamingTextController: StreamRenderer.StreamMessageController?
    
    private var currentStreamingTextController: StreamRenderer.StreamMessageController? {
        get { controllerAccessQueue.sync { _currentStreamingTextController } }
        set { controllerAccessQueue.async(flags: .barrier) { self._currentStreamingTextController = newValue } }
    }

    init(
        messagesStack: NSStackView, 
        textView: NSTextView, 
        inputHeightConstraint: NSLayoutConstraint?,
        sendButton: NSButton?,
        stopButton: NSButton?
    ) {
        self.messagesStack = messagesStack
        self.textView = textView
        self.inputHeightConstraint = inputHeightConstraint
        self.sendButton = sendButton
        self.stopButton = stopButton
    }

    func handleInput() {
        guard let textView = textView else { return }
        let text = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        addMessage(text, isUser: true)
        textView.string = "" // Clear the input
        textDidChange()

        toggleSendStopButtons(showStop: true)

        // // Disable send button immediately
        // DispatchQueue.main.async { [weak self] in
        //     self?.updateUIForStreamingState(isStreaming: true)
        // }

        startStreamingResponse(for: text)
    }

    private func startStreamingResponse(for prompt: String) {
        guard !isStreaming else { return } // Prevent multiple concurrent streams
        isStreaming = true

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

    func stopStreaming() {
        guard isStreaming else { return }
        chatApiService.cancelCurrentRequest()
        isStreaming = false

        toggleSendStopButtons(showStop: false)
        
        // Remove typing indicator
        DispatchQueue.main.async { [weak self] in
            self?.typingIndicator?.removeFromSuperview()
            self?.typingIndicator = nil
        }
    }

    private func toggleSendStopButtons(showStop: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.sendButton?.isHidden = showStop
            self.stopButton?.isHidden = !showStop
            
            // Update send button state if showing
            if !showStop {
                let hasText = !(self.textView?.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? false)
                self.sendButton?.isEnabled = hasText
                self.sendButton?.contentTintColor = hasText ? .systemBlue : .disabledControlTextColor
            }
        }
    }

    private func updateUIForStreamingState(isStreaming: Bool) {
        stopButton?.isHidden = !isStreaming
        typingIndicator?.removeFromSuperview()
        typingIndicator = nil
        
        // Update send button based on text content and streaming state
        let hasText = !(textView?.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? false)
        sendButton?.isEnabled = !isStreaming && hasText
        sendButton?.contentTintColor = sendButton?.isEnabled == true ? .systemBlue : .disabledControlTextColor
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
        print("chunk -> \(chunk)")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if chunk == "[STREAM_DONE]" {
                self.handleStreamCompletion()
                return
            }
            
            // Safely get controller reference
            let controller = self.currentStreamingTextController
            
            if controller == nil {
                self.initializeStreamingController()
                // Get new controller reference after initialization
                self.currentStreamingTextController?.appendStreamingText(chunk)
                return
            }
            
            self.typingIndicator?.removeFromSuperview()
            self.typingIndicator = nil
            
            // Thread-safe append with main thread guarantee
            controller?.appendStreamingText(chunk)
        }
    }

    private func handleStreamCompletion() {
        isStreaming = false
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.toggleSendStopButtons(showStop: false)

            // Ensure send button is properly disabled since we cleared the text
            self.sendButton?.isEnabled = false
            self.sendButton?.contentTintColor = .disabledControlTextColor
            
            // Capture controller reference strongly for this operation
            let controller = self.currentStreamingTextController
            controller?.appendStreamingText("", isComplete: true)
            
            self.typingIndicator?.removeFromSuperview()
            self.typingIndicator = nil
            
            // Delayed cleanup with identity check
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak controller] in
                if let current = self?.currentStreamingTextController, current === controller {
                    self?.currentStreamingTextController = nil
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

            // Only update send button if not currently streaming
            if !self.isStreaming {
                let hasText = !textView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                self.sendButton?.isEnabled = hasText
                self.sendButton?.contentTintColor = hasText ? .systemBlue : .disabledControlTextColor
            }
        }
    }
}
