import Cocoa

class MarkdownProcessor {
    static func countConsecutiveBackticks(_ text: String) -> Int? {
        guard let first = text.first, first == "`" else { return nil }
        return text.prefix { $0 == "`" }.count
    }
    
    static func processInlineMarkdown(_ text: String) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: TextAttributes.regular)
        
        // Process in specific order - most constrained first
        processEscapes(in: result)
        processCodeSpans(in: result)
        processTripleEmphasis(in: result)
        processDoubleEmphasis(in: result)
        processSingleEmphasis(in: result)
        
        return result
    }
    
    private static func processEscapes(in string: NSMutableAttributedString) {
        let pattern = #"\\([*_`])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        
        let matches = regex.matches(in: string.string, range: NSRange(location: 0, length: string.length))
        
        for match in matches.reversed() {
            guard match.range.location != NSNotFound else { continue }
            let charRange = match.range(at: 1)
            let char = string.attributedSubstring(from: charRange)
            string.replaceCharacters(in: match.range, with: char)
        }
    }
    
    private static func processCodeSpans(in string: NSMutableAttributedString) {
        let pattern = #"(`+)([^`\n]+?)\1"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        
        let matches = regex.matches(in: string.string, range: NSRange(location: 0, length: string.length))
        
        for match in matches.reversed() {
            guard match.range.location != NSNotFound,
                  match.range(at: 2).location != NSNotFound else { continue }
            
            string.addAttributes(TextAttributes.inlineCode, range: match.range(at: 2))
            let content = string.attributedSubstring(from: match.range(at: 2))
            string.replaceCharacters(in: match.range, with: content)
        }
    }
    
    private static func processTripleEmphasis(in string: NSMutableAttributedString) {
        processEmphasis(in: string, 
                       pattern: #"(\*\*\*|___)(?![\s*_])(.+?)(?<![\s*_])\1"#,
                       attributes: TextAttributes.boldItalic)
    }
    
    private static func processDoubleEmphasis(in string: NSMutableAttributedString) {
        processEmphasis(in: string, 
                       pattern: #"(\*\*|__)(?![\s*_])(.+?)(?<![\s*_])\1"#,
                       attributes: TextAttributes.bold)
    }
    
    private static func processSingleEmphasis(in string: NSMutableAttributedString) {
        processEmphasis(in: string, 
                       pattern: #"([*_])(?![\s*_])(.+?)(?<![\s*_])\1"#,
                       attributes: TextAttributes.italic)
    }
    
    private static func processEmphasis(
        in string: NSMutableAttributedString,
        pattern: String,
        attributes: [NSAttributedString.Key: Any]
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        
        let matches = regex.matches(in: string.string, range: NSRange(location: 0, length: string.length))
        
        for match in matches.reversed() {
            guard match.range.location != NSNotFound,
                  match.numberOfRanges >= 3,
                  match.range(at: 2).location != NSNotFound else { continue }
            
            string.addAttributes(attributes, range: match.range(at: 2))
            let content = string.attributedSubstring(from: match.range(at: 2))
            string.replaceCharacters(in: match.range, with: content)
        }
    }
}
