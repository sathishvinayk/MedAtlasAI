// file chatUIbuilder.swift 
import Cocoa

struct ChatUIBuilder {
    struct ChatUI {
        let messagesStack: NSStackView
        let textView: NSTextView
        let inputScroll: NSScrollView
        let inputHeightConstraint: NSLayoutConstraint
    }

    static func buildChatUI(in container: NSView, delegate: NSTextViewDelegate, target: AnyObject, sendAction: Selector) -> ChatUI {
        let titleLabel = NSTextField(labelWithString: "Stealth Interview")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.boldSystemFont(ofSize: 14)
        titleLabel.alignment = .center
        titleLabel.textColor = .labelColor
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.lineBreakMode = .byTruncatingTail

        let divider = NSBox()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.boxType = .separator

        container.addSubview(titleLabel)
        container.addSubview(divider)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        let messagesStack = NSStackView()
        messagesStack.orientation = .vertical
        messagesStack.alignment = .leading
        messagesStack.spacing = 8
        messagesStack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        messagesStack.translatesAutoresizingMaskIntoConstraints = false
        
        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(messagesStack)
        scrollView.documentView = documentView

        let inputContainer = NSView()
        inputContainer.translatesAutoresizingMaskIntoConstraints = false
        inputContainer.wantsLayer = true
        inputContainer.layer?.cornerRadius = 12
        inputContainer.layer?.masksToBounds = true
        inputContainer.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.8).cgColor

        let inputScroll = NSScrollView()
        inputScroll.translatesAutoresizingMaskIntoConstraints = false
        inputScroll.borderType = .noBorder
        inputScroll.hasVerticalScroller = true
        inputScroll.autohidesScrollers = false
        inputScroll.drawsBackground = false
        inputScroll.backgroundColor = .clear
        inputScroll.scrollerStyle = .overlay
        inputScroll.verticalScrollElasticity = .allowed

        let textView = ChatTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 32))
        textView.minSize = NSSize(width: 0, height: 32)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.backgroundColor = .clear
        textView.delegate = delegate
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.isFieldEditor = false
        textView.allowsDocumentBackgroundColorChange = true
        textView.importsGraphics = false
        textView.usesFindBar = false
        textView.textColor = .labelColor
        textView.translatesAutoresizingMaskIntoConstraints = false

        inputScroll.documentView = textView

        let sendButton = NSButton(title: "➤", target: target, action: sendAction)
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.bezelStyle = .inline
        sendButton.font = NSFont.systemFont(ofSize: 16)
        sendButton.setButtonType(.momentaryPushIn)
        sendButton.isBordered = false
        sendButton.wantsLayer = true
        sendButton.contentTintColor = .systemBlue
        sendButton.toolTip = "Send"

        container.addSubview(scrollView)
        container.addSubview(inputContainer)
        inputContainer.addSubview(inputScroll)
        inputContainer.addSubview(sendButton)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            titleLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            divider.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            divider.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 0),
            divider.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: 0),
            divider.heightAnchor.constraint(equalToConstant: 1),

            scrollView.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            scrollView.bottomAnchor.constraint(equalTo: inputContainer.topAnchor, constant: -8),

            inputContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            inputContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            inputContainer.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),

            inputScroll.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor, constant: 14),
            inputScroll.topAnchor.constraint(equalTo: inputContainer.topAnchor, constant: 6),
            inputScroll.bottomAnchor.constraint(equalTo: inputContainer.bottomAnchor, constant: -6),
            inputScroll.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),

            sendButton.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor, constant: -12),
            sendButton.centerYAnchor.constraint(equalTo: inputContainer.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 22),
            sendButton.heightAnchor.constraint(equalToConstant: 22),

            messagesStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            messagesStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            messagesStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            messagesStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            messagesStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            textView.leadingAnchor.constraint(equalTo: inputScroll.contentView.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: inputScroll.contentView.trailingAnchor),
            textView.topAnchor.constraint(equalTo: inputScroll.contentView.topAnchor),
            textView.bottomAnchor.constraint(equalTo: inputScroll.contentView.bottomAnchor),
        ])

        let inputHeightConstraint = inputScroll.heightAnchor.constraint(equalToConstant: 120)
        inputHeightConstraint.priority = .defaultHigh
        inputHeightConstraint.isActive = true

        return ChatUI(messagesStack: messagesStack, textView: textView, inputScroll: inputScroll, inputHeightConstraint: inputHeightConstraint)
    }
}
