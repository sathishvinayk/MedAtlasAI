import Cocoa

enum MessageRenderer {
    static func renderMessage(_ message: String, isUser: Bool) -> NSView {
        let label = NSTextField(wrappingLabelWithString: message)
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

        let bubble = NSView()
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.wantsLayer = true
        bubble.layer?.backgroundColor = isUser
            ? NSColor.systemBlue.withAlphaComponent(0.8).cgColor
            : NSColor.controlBackgroundColor.withAlphaComponent(0.6).cgColor
        bubble.layer?.cornerRadius = 14
        bubble.layer?.masksToBounds = true
        bubble.addSubview(label)

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(bubble)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -8),
            label.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -12),

            bubble.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            bubble.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
        ])

        if isUser {
            bubble.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor).isActive = true
            bubble.trailingAnchor.constraint(equalTo: container.trailingAnchor).isActive = true
        } else {
            bubble.leadingAnchor.constraint(equalTo: container.leadingAnchor).isActive = true
            bubble.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -20).isActive = true
        }

        return container
    }
}
