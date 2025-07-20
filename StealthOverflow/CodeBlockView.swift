import AppKit

class CodeStyledTextView: NSView {
    private let textView = NSTextView()

    init(text: String) {
        super.init(frame: .zero)
        setupTextView(with: text)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupTextView(with text: String) {
        textView.isEditable = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.font = NSFont.systemFont(ofSize: 14)

        // Detect and style inline code blocks
        let attributed = NSMutableAttributedString(string: text)
        let fullRange = NSRange(location: 0, length: attributed.length)
        attributed.addAttribute(.font, value: NSFont.systemFont(ofSize: 14), range: fullRange)

        // Simple inline code styling with backticks: `code`
        let regex = try! NSRegularExpression(pattern: "`([^`]+)`")
        for match in regex.matches(in: text, range: fullRange) {
            let codeRange = match.range(at: 1)
            attributed.addAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .backgroundColor: NSColor.systemGray.withAlphaComponent(0.2)
            ], range: codeRange)
        }

        textView.textStorage?.setAttributedString(attributed)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.documentView = textView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.heightAnchor.constraint(equalTo: textView.heightAnchor)
        ])
    }
}
