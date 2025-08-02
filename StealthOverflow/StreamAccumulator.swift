// StreamAccumulator.swift
import Cocoa
import NaturalLanguage

final class StreamAccumulator {
    // Pre-compiled regexes
    static let numberPunctuationRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"^(\d+)([.)])\s*(.*)$"#)
    }()
    
    static let listMarkerRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"^(\d+|[a-z]|[ivx]+)[.)]"#, options: .caseInsensitive)
    }()
    
    static let urlRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"https?://(?:www\.)?[^\s]+"#)
    }()

    private var buffer = ""
    private var isInCodeBlock = false
    private var currentLanguage: String?
    private let lock = NSLock()
    
    func process(chunk: String) -> (tokens: [TextStreamTokenizer.TokenType], remainder: String) {
        lock.lock()
        defer { lock.unlock() }
        
        buffer += chunk
        var tokens: [TextStreamTokenizer.TokenType] = []
        var processedCount = 0
        
        while processedCount < buffer.count {
            let remaining = buffer.dropFirst(processedCount)
            
            if isInCodeBlock {
                if let endRange = findCodeBlockEnd(in: remaining) {
                    let content = String(remaining[..<endRange.lowerBound])
                    if !content.isEmpty {
                        tokens.append(.codeBlockContent(content))
                    }
                    tokens.append(.codeBlockEnd)
                    processedCount += remaining.distance(from: remaining.startIndex, to: endRange.upperBound)
                    isInCodeBlock = false
                    currentLanguage = nil
                } else {
                    break
                }
            } else {
                if let (startRange, language) = findCodeBlockStart(in: remaining) {
                    let beforeText = String(remaining[..<startRange.lowerBound])
                    if !beforeText.isEmpty {
                        tokens += tokenizeNormalText(beforeText)
                    }
                    
                    currentLanguage = language
                    tokens.append(.codeBlockStart(language: currentLanguage))
                    isInCodeBlock = true
                    processedCount += remaining.distance(from: remaining.startIndex, to: startRange.upperBound)
                } else {
                    break
                }
            }
        }
        
        if processedCount > 0 {
            buffer.removeFirst(processedCount)
        }
        return (tokens, buffer)
    }
    
    private func findCodeBlockStart(in text: Substring) -> (Range<String.Index>, String?)? {
        guard let startRange = text.range(of: "```") else { return nil }
        
        let afterTicks = text[startRange.upperBound...]
        guard let newlineRange = afterTicks.firstIndex(of: "\n") else { return nil }
        
        let languagePart = text[startRange.upperBound..<newlineRange]
        let language = String(languagePart)
            .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "`")))
        
        return (startRange.lowerBound..<newlineRange, language.isEmpty ? nil : language)
    }
    
    private func findCodeBlockEnd(in text: Substring) -> Range<String.Index>? {
        return text.range(of: "```")
    }
    
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        buffer = ""
        isInCodeBlock = false
        currentLanguage = nil
    }
    
    func flush() -> [TextStreamTokenizer.TokenType] {
        lock.lock()
        defer { lock.unlock() }
        
        var tokens: [TextStreamTokenizer.TokenType] = []
        if !buffer.isEmpty {
            if isInCodeBlock {
                tokens.append(.codeBlockContent(buffer))
            } else {
                tokens += tokenizeNormalText(buffer)
            }
        }
        reset()
        return tokens
    }
    
    private func tokenizeNormalText(_ text: String) -> [TextStreamTokenizer.TokenType] {
        var tokens: [TextStreamTokenizer.TokenType] = []
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        
        var lastIndex = text.startIndex
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            if lastIndex < range.lowerBound {
                let whitespace = String(text[lastIndex..<range.lowerBound])
                tokens.append(TextStreamTokenizer.TokenType.classify(whitespace))
            }
            
            let token = String(text[range])
            tokens.append(TextStreamTokenizer.TokenType.classify(token))
            lastIndex = range.upperBound
            return true
        }
        
        if lastIndex < text.endIndex {
            let whitespace = String(text[lastIndex..<text.endIndex])
            tokens.append(TextStreamTokenizer.TokenType.classify(whitespace))
        }
        
        return tokens
    }
}

extension TextStreamTokenizer.TokenType {
    static func classify(_ text: String) -> Self {
        guard !text.isEmpty else { return .whitespace(text) }
        
        if text.isNewline {
            return .newline
        } else if text.isWhitespace {
            return .whitespace(text)
        } else if text.isPunctuation {
            return .punctuation(text)
        } else if text.isInlineCode {
            return .inlineCode(text.trimmingCharacters(in: ["`"]))
        } else if text.isURL {
            return .link(text: text, url: URL(string: text))
        } else if let (numberToken, wordToken) = splitNumberPunctuationToken(text) {
            return numberToken
        } else {
            return .word(text)
        }
    }
    
    private static func splitNumberPunctuationToken(_ text: String) -> (Self, Self)? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = StreamAccumulator.numberPunctuationRegex.firstMatch(in: text, range: range),
              match.numberOfRanges >= 3,
              let numberRange = Range(match.range(at: 1), in: text),
              let punctuationRange = Range(match.range(at: 2), in: text) else {
            return nil
        }
        
        let number = String(text[numberRange])
        let punctuation = String(text[punctuationRange])
        let remaining = match.numberOfRanges > 2 ? 
            String(text[Range(match.range(at: 3), in: text)!]) : ""
        
        return (.special(number + punctuation), remaining.isEmpty ? .whitespace(" ") : .word(remaining))
    }
}

extension String {
    var isNewline: Bool {
        self == "\n" || self == "\r\n"
    }
    
    var isWhitespace: Bool {
        !isEmpty && trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var isPunctuation: Bool {
        guard count == 1, let scalar = unicodeScalars.first else { return false }
        return CharacterSet.punctuationCharacters.contains(scalar)
    }
    
    var isInlineCode: Bool {
        count >= 2 && hasPrefix("`") && hasSuffix("`")
    }
    
    var isURL: Bool {
        let range = NSRange(startIndex..., in: self)
        return StreamAccumulator.urlRegex.firstMatch(in: self, range: range) != nil
    }
}
