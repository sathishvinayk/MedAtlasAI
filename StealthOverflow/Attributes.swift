import Cocoa
// MARK: - TextAttributes
struct TextAttributes {
    static let regular: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 14),
        .foregroundColor: NSColor.textColor,
        .backgroundColor: NSColor.clear,
        .paragraphStyle: {
            let style = NSMutableParagraphStyle()
            style.lineHeightMultiple = 1.2
            style.paragraphSpacing = 1
            style.lineBreakMode = .byWordWrapping
            style.alignment = .natural
            return style
        }()
    ]
    static let bold: [NSAttributedString.Key: Any] = [
        .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize),
        .foregroundColor: NSColor.textColor
    ]

    static let italic: [NSAttributedString.Key: Any] = [
        .font: NSFontManager.shared.convert(NSFont.systemFont(ofSize: NSFont.systemFontSize), 
                   toHaveTrait: .italicFontMask),
        .foregroundColor: NSColor.textColor
    ]
    
    static let boldItalic: [NSAttributedString.Key: Any] = [
        .font: NSFontManager.shared.convert(NSFont.boldSystemFont(ofSize: NSFont.systemFontSize), 
                   toHaveTrait: .italicFontMask),
        .foregroundColor: NSColor.textColor
    ]
    
    static let inlineCode: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
        .foregroundColor: NSColor.systemOrange,
        .backgroundColor: NSColor.controlBackgroundColor.withAlphaComponent(0.3),
        .baselineOffset: 0
    ]
    
    static let codeBlock: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
        .foregroundColor: NSColor.textColor,
        // .backgroundColor: NSColor.textBackgroundColor,
        .backgroundColor: NSColor.clear,
        .paragraphStyle: {
            let style = NSMutableParagraphStyle()
            style.lineHeightMultiple = 1.2
            style.paragraphSpacing = 0
            return style
        }()
    ]
}