// file MessageRenderer.swift
import Cocoa

enum MessageRenderer {
    static func renderMessage(_ message: String, isUser: Bool) -> (NSView, NSView?) {
        let bubble = NSStackView()
        bubble.orientation = .vertical
        bubble.spacing = 6
        bubble.edgeInsets = NSEdgeInsets(top: 8 , left: 6, bottom: -4, right: 12)
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.wantsLayer = true
        bubble.layer?.backgroundColor = isUser
            ? NSColor.systemBlue.withAlphaComponent(0.85).cgColor
            : NSColor.controlBackgroundColor.withAlphaComponent(0.7).cgColor
        bubble.layer?.cornerRadius = 8
        bubble.layer?.masksToBounds = true

        let parsedBlocks = MarkdownParser.parse(message.isEmpty ? "..." : message)

        for block in parsedBlocks {
            switch block {
            case .text(let text):
                let label = NSTextField(wrappingLabelWithString: text)
                label.translatesAutoresizingMaskIntoConstraints = false
                label.font = NSFont.systemFont(ofSize: 14)
                label.textColor = isUser ? .white : .labelColor
                label.maximumNumberOfLines = 0
                label.backgroundColor = .clear
                label.isBezeled = false
                label.drawsBackground = false
                label.isEditable = false
                label.isSelectable = true
                label.lineBreakMode = .byWordWrapping
                
                // Add these constraints to control vertical spacing
                let wrapper = NSView()
                wrapper.translatesAutoresizingMaskIntoConstraints = false
                wrapper.addSubview(label)
                
                NSLayoutConstraint.activate([
                    label.topAnchor.constraint(equalTo: wrapper.topAnchor),
                    label.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
                    label.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
                    label.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor) // Reduced bottom spacing
                ])
                
                bubble.addArrangedSubview(wrapper)

            case .code(let code):
                let textView = NSTextView()
                textView.string = code.trimmingCharacters(in: .whitespacesAndNewlines)
                textView.isEditable = false
                textView.isSelectable = true
                textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
                textView.backgroundColor = NSColor(calibratedWhite: 0.15, alpha: 1)
                textView.textColor = .white
                textView.drawsBackground = true
                
                // Configure text container
                textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, 
                                                            height: CGFloat.greatestFiniteMagnitude)
                textView.textContainer?.widthTracksTextView = false
                // textView.textContainer?.heightTracksTextView = false
                
                // Calculate the required height
                textView.layoutManager?.ensureLayout(for: textView.textContainer!)
                let textSize = textView.layoutManager?.usedRect(for: textView.textContainer!).size ?? .zero
                
                // Calculate natural size
                let padding: CGFloat = 16
                let height = textSize.height + padding
                
                // Add directly to bubble (no scroll view)
                bubble.addArrangedSubview(textView)
                    textView.heightAnchor.constraint(equalToConstant: height).isActive = true
            }
        }

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(bubble)

        NSLayoutConstraint.activate([
            bubble.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            bubble.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: 0),
            bubble.heightAnchor.constraint(greaterThanOrEqualToConstant: 30)
        ])

        if isUser {
            bubble.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor).isActive = true
            bubble.trailingAnchor.constraint(equalTo: container.trailingAnchor).isActive = true
        } else {
            bubble.leadingAnchor.constraint(equalTo: container.leadingAnchor).isActive = true
            bubble.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -20).isActive = true
        }

        return (container, bubble)
    }
}

extension String {
    func height(withConstrainedWidth width: CGFloat, font: NSFont) -> CGFloat {
        let constraintRect = CGSize(width: width, height: .greatestFiniteMagnitude)
        let boundingBox = self.boundingRect(
            with: constraintRect,
            options: .usesLineFragmentOrigin,
            attributes: [.font: font],
            context: nil
        )
        return ceil(boundingBox.height)
    }
}