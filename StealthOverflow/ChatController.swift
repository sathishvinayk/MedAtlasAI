// file chatcontroller.swift
import Cocoa

class ChatController {
    private let chatApiService = ChatApiService()
    private let textView: NSTextView?
    private let messagesStack: NSStackView?
    private let inputHeightConstraint: NSLayoutConstraint?
    private var currentAssistantBubble: NSView?
    private var typingIndicator: TypingIndicatorView?
    private var assistantResponseBuffer = NSMutableAttributedString()

    private var isInCodeBlock = false
    private var codeBlockBuffer = ""

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
    private func processStreamChunk(_ chunk: String) {
        var remainingChunk = chunk
        
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
    private func startStreamingResponse(for prompt: String) {
        guard let messagesStack = messagesStack else { return }

        // Step 1: Show typing indicator
        let indicator = TypingIndicatorView()
        messagesStack.addArrangedSubview(indicator)
        typingIndicator = indicator
        currentAssistantBubble = nil // Reset any previous state
        assistantResponseBuffer = NSMutableAttributedString()

        var placeholderBubble: NSView?

        chatApiService.fetchGPTResponse(for: prompt) { [weak self] chunk in
            DispatchQueue.main.async {
                guard let self = self else { return }

                // Step 4: Stream completed
                if chunk == "[STREAM_DONE]" {
                    // Handle any remaining buffered code content
                    if self.isInCodeBlock && !self.codeBlockBuffer.isEmpty {
                        self.assistantResponseBuffer.append(NSAttributedString(string: "```\n" + self.codeBlockBuffer + "\n```"))
                        self.codeBlockBuffer = ""
                        self.isInCodeBlock = false
                    }
                    self.typingIndicator?.removeFromSuperview()
                    self.typingIndicator?.stopAnimating()
                    self.typingIndicator = nil

                    if let placeholder = placeholderBubble {
                        self.messagesStack?.removeArrangedSubview(placeholder)
                        placeholder.removeFromSuperview()
                        placeholderBubble = nil
                    }

                    // Insert final bubble if needed
                    let finalText = self.assistantResponseBuffer.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !finalText.isEmpty {
                        let (bubble, _) = MessageRenderer.renderMessage(finalText, isUser: false)
                        self.messagesStack?.addArrangedSubview(bubble)
                        self.currentAssistantBubble = bubble
                    }

                    return
                }

                self.processStreamChunk(chunk)

                // Step 2: Skip empty chunks
                let trimmedChunk = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedChunk.isEmpty else { return }

                // Step 3: First time — create placeholder bubble
                if placeholderBubble == nil {
                    self.typingIndicator?.removeFromSuperview()
                    self.typingIndicator?.stopAnimating()
                    self.typingIndicator = nil

                    let (bubble, _) = MessageRenderer.renderMessage("...", isUser: false)
                    messagesStack.addArrangedSubview(bubble)
                    placeholderBubble = bubble
                }

                // Optional: live update placeholder if you want to show partial stream
                if let bubble = placeholderBubble {
                    self.messagesStack?.removeArrangedSubview(bubble)
                    bubble.removeFromSuperview()
                    
                    // Use the properly processed buffer
                    let (newBubble, _) = MessageRenderer.renderMessage(
                        self.assistantResponseBuffer.string, 
                        isUser: false
                    )
                    self.messagesStack?.addArrangedSubview(newBubble)
                    placeholderBubble = newBubble
                }
            }
        }
    }


    private func addMessage(_ message: String, isUser: Bool) {
        guard let messagesStack = messagesStack else { return }
        let (messageContainer, messageLabel) = MessageRenderer.renderMessage(message, isUser: isUser)
        messagesStack.addArrangedSubview(messageContainer)

        if !isUser {
            currentAssistantBubble = messageLabel
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
