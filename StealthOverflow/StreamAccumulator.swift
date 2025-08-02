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
    private var codeBlockLanguage: String?
    private var pendingCodeBlockContent = ""
    private let lock = NSLock()
    
    func process(chunk: String) -> (tokens: [TextStreamTokenizer.TokenType], remainder: String) {
        lock.lock()
        defer { lock.unlock() }
        
        buffer += chunk
        var tokens: [TextStreamTokenizer.TokenType] = []
        var processedCount = 0

        // Create a local copy for thread-safe string operations
        let processingBuffer = buffer
        let bufferLength = processingBuffer.count
        
        while processedCount < bufferLength {
            let remaining = processingBuffer.dropFirst(processedCount)
            
            if isInCodeBlock {
                // Look for closing ```
                if let endRange = findCodeBlockEnd(in: remaining) {
                    let content = String(remaining[..<endRange.lowerBound])
                    if !content.isEmpty {
                        pendingCodeBlockContent += content
                        tokens.append(.codeBlockContent(pendingCodeBlockContent))
                        pendingCodeBlockContent = ""
                    }
                    tokens.append(.codeBlockEnd)
                    processedCount += remaining.distance(from: remaining.startIndex, to: endRange.upperBound)
                    isInCodeBlock = false
                    codeBlockLanguage = nil
                } else {
                    // No closing found - buffer everything
                    pendingCodeBlockContent += remaining
                    processedCount += remaining.count
                    break
                }
            } else {
                // Look for opening ```
                if let (startRange, language) = findCodeBlockStart(in: remaining) {
                    let beforeCode = String(remaining[..<startRange.lowerBound])
                    if !beforeCode.isEmpty {
                        tokens += tokenizeNormalText(beforeCode)
                    }

                    codeBlockLanguage = language
                    tokens.append(.codeBlockStart(language: codeBlockLanguage))
                    isInCodeBlock = true
                    
                    // Check for language specifier
                    let afterTicks = String(remaining[startRange.upperBound...])
                    let languageEnd = afterTicks.firstIndex(where: { $0.isNewline }) ?? afterTicks.endIndex
                    let language = String(afterTicks[..<languageEnd]).trimmingCharacters(in: .whitespaces)
      
                    // Calculate how much we processed
                    let processedUpTo = afterTicks.index(languageEnd, offsetBy: 1, limitedBy: afterTicks.endIndex) ?? languageEnd
                    processedCount += remaining.distance(from: remaining.startIndex, to: startRange.upperBound)
                    processedCount += afterTicks.distance(from: afterTicks.startIndex, to: processedUpTo)
                } else {
                    // Tokenize the remaining text
                    let textToTokenize = String(remaining)
                    tokens += tokenizeNormalText(textToTokenize)
                    processedCount += remaining.count
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
        // Make string operations thread-safe by working on a local copy
        let localText = String(text)
        guard let startRange = localText.range(of: "```") else { return nil }
        
        let afterTicks = localText[startRange.upperBound...]
        guard let newlineRange = afterTicks.firstIndex(of: "\n") else { return nil }
        
        let languagePart = localText[startRange.upperBound..<newlineRange]
        let language = String(languagePart)
            .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "`")))
        
        // Convert ranges back to the original substring's indices
        let lowerBound = text.index(text.startIndex, offsetBy: localText.distance(from: localText.startIndex, to: startRange.lowerBound))
        let upperBound = text.index(text.startIndex, offsetBy: localText.distance(from: localText.startIndex, to: newlineRange))
        
        return (lowerBound..<upperBound, language.isEmpty ? nil : language)
    }

    private func findCodeBlockEnd(in text: Substring) -> Range<String.Index>? {
        return text.range(of: "```")
    }
    
    func reset() {
        buffer = ""
        isInCodeBlock = false
        codeBlockLanguage = nil
        pendingCodeBlockContent = ""
    }
    func flush() -> [TextStreamTokenizer.TokenType] {
        lock.lock()
        defer { lock.unlock() }
        
        var tokens: [TextStreamTokenizer.TokenType] = []
        if !buffer.isEmpty {
            if isInCodeBlock {
                // If we're still in a code block at flush, close it
                tokens.append(.codeBlockContent(pendingCodeBlockContent + buffer))
                tokens.append(.codeBlockEnd)
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
        } else if let (numberToken, _) = splitNumberPunctuationToken(text) {
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
        
        return (.special(number + punctuation), .word(remaining))
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
