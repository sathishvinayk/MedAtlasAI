// file MessageRenderer.swift
// This uses static width passed, so if resized smaller, then the window will not resize below 600.
// Working as of now.
import Cocoa

class SafeScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        // Always forward scrolling to parent (chat scroll view)
        nextResponder?.scrollWheel(with: event)
    }
}

func makeCodeBlockView(code: String, maxWidth: CGFloat) -> NSView {
    // Calculate available width (subtract bubble padding)
    let availableWidth = maxWidth - 32
    
    // Create the container
    let container = NSView()
    container.wantsLayer = true
    container.layer?.backgroundColor = NSColor(white: 0.1, alpha: 1.0).cgColor
    container.layer?.cornerRadius = 6
    container.translatesAutoresizingMaskIntoConstraints = false
    
    // Create the text view
    let textView = NSTextView()
    textView.string = code
    textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    textView.textColor = .white
    textView.backgroundColor = .clear
    textView.isEditable = false
    textView.isSelectable = true
    textView.textContainerInset = NSSize(width: 8, height: 8)
    
    // Configure text container properly
    textView.textContainer?.widthTracksTextView = false
    textView.textContainer?.containerSize = NSSize(width: availableWidth, height: .greatestFiniteMagnitude)
    
    // Calculate required height
    textView.layoutManager?.ensureLayout(for: textView.textContainer!)
    let usedRect = textView.layoutManager?.usedRect(for: textView.textContainer!) ?? NSRect(x: 0, y: 0, width: availableWidth, height: 20)
//    let requiredHeight = min(usedRect.height + 16, 300) // Cap at 300pt
    let requiredHeight = usedRect.height + 16

    
    // Add either scroll view or direct text view
//    if requiredHeight > 200 {
//        let scrollView = SafeScrollView()
//        scrollView.hasVerticalScroller = true
//        scrollView.hasHorizontalScroller = false
//        scrollView.autohidesScrollers = true
//        scrollView.documentView = textView
//        scrollView.drawsBackground = false
//        
//        container.addSubview(scrollView)
//        scrollView.translatesAutoresizingMaskIntoConstraints = false
//        
//        NSLayoutConstraint.activate([
//            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
//            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
//            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
//            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
//            
//            container.widthAnchor.constraint(equalToConstant: availableWidth),
//            container.heightAnchor.constraint(equalToConstant: requiredHeight)
//        ])
//    } else {
        container.addSubview(textView)
        textView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            textView.topAnchor.constraint(equalTo: container.topAnchor),
            textView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            
            container.widthAnchor.constraint(equalToConstant: availableWidth),
            container.heightAnchor.constraint(equalToConstant: requiredHeight)
        ])
//    }
    
    return container
}

enum MessageRenderer {
    static func renderMessage(_ message: String, isUser: Bool) -> (NSView, NSView) {
        let maxWidth = (NSScreen.main?.visibleFrame.width ?? 800) * 0.65
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.masksToBounds = false
        container.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        container.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

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
                let codeText = segment.content.trimmingCharacters(in: .whitespacesAndNewlines)
                let codeView = makeCodeBlockView(code: codeText, maxWidth: 600)

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
//                label.preferredMaxLayoutWidth = maxWidth - 30
                
                stack.addArrangedSubview(label)
            }
        }
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: 10),
            stack.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -8),

            // bubble.heightAnchor.constraint(greaterThanOrEqualToConstant: 30)
            bubble.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
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
