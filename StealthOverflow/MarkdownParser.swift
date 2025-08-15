import Cocoa

class MarkdownProcessor {
    static func countConsecutiveBackticks(_ text: String) -> Int? {
        guard let first = text.first, first == "`" else { return nil }
        return text.prefix { $0 == "`" }.count
    }
    
    static func processInlineMarkdown(_ text: String) -> NSAttributedString {
         let result = NSMutableAttributedString(string: text, attributes: TextAttributes.regular)
    
        // Processing order matters - most specific to least specific
        
        // 1. Process bold-italic (***text*** or ___text___)
        processMarkdownPattern(
            in: result,
            pattern: "\\*{3}(.+?)\\*{3}|_{3}(.+?)_{3}",
            attributes: TextAttributes.boldItalic,
            groupIndex: 1
        )
        
        // 2. Process bold (**text** or __text__)
        processMarkdownPattern(
            in: result,
            pattern: "\\*{2}(.+?)\\*{2}|_{2}(.+?)_{2}",
            attributes: TextAttributes.bold,
            groupIndex: 1
        )
        
        // 3. Process italic (*text* or _text_)
        processMarkdownPattern(
            in: result,
            pattern: "\\*(.+?)\\*|_(.+?)_",
            attributes: TextAttributes.italic,
            groupIndex: 1
        )
        
        // 4. Process inline code (`code`)
        processMarkdownPattern(
            in: result,
            pattern: "`([^`]+)`",
            attributes: TextAttributes.inlineCode,
            groupIndex: 1
        )
        
        return result
    }
    
    private static func processMarkdownPattern(
        in string: NSMutableAttributedString,
        pattern: String,
        attributes: [NSAttributedString.Key: Any],
        groupIndex: Int
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        
        let matches = regex.matches(
            in: string.string,
            range: NSRange(location: 0, length: string.length)
        )
        
        for match in matches.reversed() {
            if match.range.location != NSNotFound {
                let contentRange = match.range(at: groupIndex)
                if contentRange.location != NSNotFound {
                    string.setAttributes(attributes, range: contentRange)
                    string.replaceCharacters(in: match.range, with: string.attributedSubstring(from: contentRange))
                }
            }
        }
    }
}
