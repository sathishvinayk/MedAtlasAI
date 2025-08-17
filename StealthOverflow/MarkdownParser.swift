import Cocoa

class MarkdownProcessor {
    static func processInlineMarkdown(_ text: String) -> NSAttributedString {
        let attributedString = NSMutableAttributedString(string: text, attributes: TextAttributes.regular)
        
        // Process bold text (**bold** or __bold__)
        processBoldText(in: attributedString)
        
        // Then process inline code (`code`)
        processInlineCode(in: attributedString)
        
        return attributedString
    }
    
    private static func processBoldText(in attributedString: NSMutableAttributedString) {
        let boldPattern = "(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)(\\1)"
        
        guard let regex = try? NSRegularExpression(pattern: boldPattern, options: []) else { return }
        
        let matches = regex.matches(
            in: attributedString.string,
            range: NSRange(location: 0, length: attributedString.length)
        )
        
        for match in matches.reversed() {
            if match.numberOfRanges >= 3 {
                let fullRange = match.range(at: 0)
                let contentRange = match.range(at: 2)

                print("Bold text identified\(attributedString)")
                
                if contentRange.location != NSNotFound {
                    // Create bold font
                    let currentFont = attributedString.attribute(.font, at: contentRange.location, effectiveRange: nil) as? NSFont ?? NSFont.systemFont(ofSize: 14)
                    let boldFont = NSFontManager.shared.convert(currentFont, toHaveTrait: .boldFontMask)
                    
                    // Apply bold attributes
                    attributedString.addAttributes([
                        .font: boldFont,
                        .foregroundColor: NSColor.primaryText
                    ], range: contentRange)

                    print("Bold text identified\(attributedString)")
                    
                    // Remove the markdown markers
                    let content = attributedString.attributedSubstring(from: contentRange)
                    attributedString.replaceCharacters(in: fullRange, with: content)
                }
            }
        }
    }
    
    private static func processInlineCode(in attributedString: NSMutableAttributedString) {
        let pattern = "`([^`]+)`"
        
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        
        let matches = regex.matches(
            in: attributedString.string,
            range: NSRange(location: 0, length: attributedString.length)
        )
        
        for match in matches.reversed() {
            if match.range.location != NSNotFound && match.range.length > 0 {
                let codeRange = match.range(at: 1)
                attributedString.setAttributes(TextAttributes.inlineCode, range: codeRange)
                attributedString.replaceCharacters(in: match.range, with: attributedString.attributedSubstring(from: codeRange))
            }
        }
    }
    
    static func countConsecutiveBackticks(in string: String) -> Int? {
        guard let firstChar = string.first, firstChar == "`" else { return nil }
        return string.prefix(while: { $0 == "`" }).count
    }
}
