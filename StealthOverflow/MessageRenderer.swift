// file MessageRenderer.swift
import Cocoa

enum MessageRenderer {
    static func renderMessage(_ message: String, isUser: Bool) -> (NSView, NSView) {
        let maxWidth = (NSScreen.main?.visibleFrame.width ?? 500) * 0.65
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.masksToBounds = false
        container.setContentHuggingPriority(.defaultLow, for: .vertical)
        container.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        let bubble = NSView()
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.setContentHuggingPriority(.defaultLow, for: .vertical)
        bubble.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        bubble.wantsLayer = true
        bubble.layer?.backgroundColor = isUser
            ? NSColor.systemBlue.withAlphaComponent(0.8).cgColor
            : NSColor.controlBackgroundColor.withAlphaComponent(0.6).cgColor
        bubble.layer?.cornerRadius = 10
        bubble.layer?.masksToBounds = true
        container.addSubview(bubble)
        bubble.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth).isActive = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.distribution = .fill
        stack.alignment = .leading
        // stack.setHuggingPriority(.required, for: .horizontal)
        stack.setHuggingPriority(.defaultLow, for: .vertical)
        stack.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)

        bubble.addSubview(stack)

        // Parse the message for code blocks (```)
        let segments = splitMarkdown(message)

        for segment in segments {
            if segment.isCode {
                let container = NSView()
                container.wantsLayer = true
                container.layer?.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 1.0).cgColor
                container.layer?.cornerRadius = 6
                container.translatesAutoresizingMaskIntoConstraints = false
                
                let textView = NSTextView()
                textView.string = segment.content
                textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
                textView.textColor = .white
                textView.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 1.0)
                textView.isEditable = false
                textView.isSelectable = true
                textView.drawsBackground = true
                textView.textContainerInset = NSSize(width: 8, height: 8)
                textView.translatesAutoresizingMaskIntoConstraints = false

                textView.textContainer?.widthTracksTextView = true
                textView.textContainer?.heightTracksTextView = false

                textView.textContainer?.lineBreakMode = .byWordWrapping

                textView.setContentHuggingPriority(.defaultLow, for: .vertical)
                textView.setContentCompressionResistancePriority(.required, for: .vertical)

                container.addSubview(textView)

                textView.layoutManager?.ensureLayout(for: textView.textContainer!)
                let usedRect = textView.layoutManager?.usedRect(for: textView.textContainer!) ?? NSRect.zero
                let textHeight = usedRect.height + 16  // Add padding
                
                NSLayoutConstraint.activate([
                    textView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                    textView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                    textView.topAnchor.constraint(equalTo: container.topAnchor),
                    textView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                    textView.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth),
                    container.heightAnchor.constraint(equalToConstant: textHeight)
                ])

                // textView.layoutManager?.ensureLayout(for: textView.textContainer!)
                // let height = textView.layoutManager?.usedRect(for: textView.textContainer!).height ?? 20
                // textView.heightAnchor.constraint(greaterThanOrEqualToConstant: height + 12).isActive = true

                stack.addArrangedSubview(container)
            }
            else {
                let label = NSTextField(wrappingLabelWithString: segment.content)
                label.translatesAutoresizingMaskIntoConstraints = false
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
                label.setContentHuggingPriority(.defaultLow, for: .vertical)
                label.setContentCompressionResistancePriority(.required, for: .vertical)
                label.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth).isActive = true
//                label.preferredMaxLayoutWidth = maxWidth - 30
                
                stack.addArrangedSubview(label)
            }
        }
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: 10),
            stack.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -8),

            // bubble.heightAnchor.constraint(greaterThanOrEqualToConstant: 30)
            bubble.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
            bubble.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
        ])


        if isUser {
            bubble.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor).isActive = true
            bubble.trailingAnchor.constraint(equalTo: container.trailingAnchor).isActive = true
        } else {
            bubble.leadingAnchor.constraint(equalTo: container.leadingAnchor).isActive = true
            // bubble.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20).isActive = true
            bubble.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -20).isActive = true
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
