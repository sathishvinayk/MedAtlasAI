// file MessageRenderer.swift
import Cocoa

let maxWidth: CGFloat = 480  // or whatever width you use for your bubbles

func makeCodeBlockView(code: String, maxWidth: CGFloat) -> NSView {
    let container = NSView()
    container.wantsLayer = true
    container.layer?.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 1.0).cgColor
    container.layer?.cornerRadius = 6
    container.translatesAutoresizingMaskIntoConstraints = false

    let codeLabel = NSTextField(labelWithString: code)
    codeLabel.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    codeLabel.translatesAutoresizingMaskIntoConstraints = false
    codeLabel.textColor = NSColor.white
    codeLabel.backgroundColor = .clear
    codeLabel.isSelectable = true
    codeLabel.lineBreakMode = .byWordWrapping
    codeLabel.maximumNumberOfLines = 0
    // codeLabel.preferredMaxLayoutWidth = maxWidth - 40
    codeLabel.usesSingleLineMode = false

    container.addSubview(codeLabel)
    
    codeLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
    codeLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

    container.translatesAutoresizingMaskIntoConstraints = false

    NSLayoutConstraint.activate([
        codeLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
        codeLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
        codeLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
        codeLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),

        container.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth)
        // codeLabel.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth - 40),
        // container.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth)
    ])

    return container
}

enum MessageRenderer {
    static func renderMessage(_ message: String, isUser: Bool) -> (NSView, NSView) {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.masksToBounds = false
        container.setContentHuggingPriority(.defaultLow, for: .horizontal)
        container.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let bubble = NSView()
        let maxBubbleWidth = NSScreen.main?.frame.width ?? 500
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bubble.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        bubble.wantsLayer = true
        bubble.layer?.backgroundColor = isUser
            ? NSColor.systemBlue.withAlphaComponent(0.8).cgColor
            : NSColor.controlBackgroundColor.withAlphaComponent(0.6).cgColor
        bubble.layer?.cornerRadius = 10
        bubble.layer?.masksToBounds = true

        container.addSubview(bubble)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.distribution = .fill
        stack.alignment = .leading
        // stack.setHuggingPriority(.required, for: .horizontal)
        stack.setHuggingPriority(.defaultLow, for: .horizontal)
        stack.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        bubble.addSubview(stack)

        // Parse the message for code blocks (```)
        let segments = splitMarkdown(message)

        for segment in segments {
            if segment.isCode {
                let codeView = makeCodeBlockView(code: segment.content, maxWidth: maxBubbleWidth)
                stack.addArrangedSubview(codeView)
            }
            else {
                let label = NSTextField(wrappingLabelWithString: segment.content)
                label.translatesAutoresizingMaskIntoConstraints = false
                // label.preferredMaxLayoutWidth = maxWidth - 40
                label.font = NSFont.systemFont(ofSize: 14)
                label.textColor = isUser ? .white : .labelColor
                label.backgroundColor = .clear
                label.isBezeled = false
                label.drawsBackground = false
                label.isEditable = false
                label.isSelectable = false
                label.lineBreakMode = .byWordWrapping
                label.maximumNumberOfLines = 0
                label.alignment = .left
                // label.setContentHuggingPriority(.defaultLow, for: .horizontal)
                // label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

                stack.addArrangedSubview(label)
                NSLayoutConstraint.activate([
                    stack.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8),
                    stack.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: 8),
                    stack.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12),
                    stack.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -12),

                    bubble.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
                    bubble.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14),
                ])
            }
        }

        // NSLayoutConstraint.activate([
        //     bubble.topAnchor.constraint(equalTo: container.topAnchor, constant: 0),
        //     bubble.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: 0),

        //     // bubble.heightAnchor.constraint(greaterThanOrEqualToConstant: 30)
        // ])

        if isUser {
            bubble.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor).isActive = true
            bubble.trailingAnchor.constraint(equalTo: container.trailingAnchor).isActive = true
        } else {
            bubble.leadingAnchor.constraint(equalTo: container.leadingAnchor).isActive = true
            bubble.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20).isActive = true
        }

        return (container, bubble)
    }

    // MARK: - Markdown splitter helper

    struct MessageSegment {
        let content: String
        let isCode: Bool
    }

    static func splitMarkdown(_ text: String) -> [MessageSegment] {
        var segments: [MessageSegment] = []
        var current = ""
        var insideCodeBlock = false

        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if insideCodeBlock {
                    segments.append(.init(content: current, isCode: true))
                    current = ""
                } else {
                    if !current.isEmpty {
                        segments.append(.init(content: current, isCode: false))
                        current = ""
                    }
                }
                insideCodeBlock.toggle()
                continue
            }

            current += line + "\n"
        }

        if !current.isEmpty {
            segments.append(.init(content: current, isCode: insideCodeBlock))
        }

        return segments
    }
}
