import Cocoa

class MessageManager {
    private let messagesStack: NSStackView

    init(messagesStack: NSStackView) {
        self.messagesStack = messagesStack
    }

    func addMessage(_ message: String, isUser: Bool) {
        let messageView = MessageRenderer.renderMessage(message, isUser: isUser)
        messagesStack.addArrangedSubview(messageView)

        if let bubble = messageView.subviews.first(where: { $0.subviews.count > 0 })?.subviews.first {
            bubble.translatesAutoresizingMaskIntoConstraints = false
            bubble.widthAnchor.constraint(lessThanOrEqualTo: messagesStack.widthAnchor, multiplier: 0.8).isActive = true
        }
    }
}
