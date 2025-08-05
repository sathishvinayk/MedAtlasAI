// file MessageRenderer.swift
import Cocoa

final class CodeBlockView: NSView {
    private let textView = NSTextView()

    init(code: String, maxWidth: CGFloat) {
        print("CODE BLOCK: \(code)")
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.9).cgColor
        layer?.cornerRadius = 6

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textColor = .white
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 6)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.string = code
        textView.setContentHuggingPriority(.required, for: .vertical)
        textView.setContentCompressionResistancePriority(.required, for: .vertical)


        addSubview(textView)

        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 0),
            textView.topAnchor.constraint(equalTo: topAnchor, constant: 0),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 0),
            widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth),
        ])
        
        textView.sizeToFit()
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)

        let textHeight = textView.layoutManager?.usedRect(for: textView.textContainer!).height ?? 20
        heightAnchor.constraint(equalToConstant: textHeight + 12).isActive = true
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateHeight),
            name: NSView.frameDidChangeNotification,
            object: textView
        )
    }
    
    @objc private func updateHeight() {
        guard let container = textView.textContainer,
              let layoutManager = textView.layoutManager else { return }

        layoutManager.ensureLayout(for: container)
        let usedHeight = layoutManager.usedRect(for: container).height
        NSLayoutConstraint.deactivate(constraints.filter { $0.firstAttribute == .height })
        let height = usedHeight + textView.textContainerInset.height * 2
        heightAnchor.constraint(equalToConstant: height).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

enum MessageRenderer {
    static func renderMessage(_ message: String, isUser: Bool) -> (NSView, NSView) {
        let maxWidth = (NSScreen.main?.visibleFrame.width ?? 800) * 1
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
                let codeView = CodeBlockView(code: segment.content, maxWidth: maxWidth)
                stack.addArrangedSubview(codeView)
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
                stack.addArrangedSubview(label)
            }
        }
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 5),
            stack.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: 10),
            stack.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 8),
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