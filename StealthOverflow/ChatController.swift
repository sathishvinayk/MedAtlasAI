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
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
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
        }
    }
}
