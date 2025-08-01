import NaturalLanguage

final class TextStreamTokenizer {
    enum StyleType {
        case bold
        case italic
        case inlineCode
    }
    enum TokenType: Equatable {
        case word(String)
        case punctuation(String)
        case whitespace(String)
        case newline
        case special(String)
        case bold(String)
        case italic(String)
        case inlineCode(String)
        case link(text: String, url: URL?)
        case codeBlockStart(language: String?)
        case codeBlockEnd
        case codeBlockContent(String)

        var isColon: Bool {
            if case .punctuation(let str) = self { return str == ":" }
            return false
        }
        
        var isSingleSpace: Bool {
            if case .whitespace(let str) = self { return str == " " }
            return false
        }
        
        var isListMarker: Bool {
            switch self {
            case .word(let str):
                // Match patterns like: 1., 2., a., b., i., ii.
                if str.range(of: #"^(\d+|[a-z]|[ivx]+)\."#, options: .regularExpression) != nil {
                    return true
                }
                // Match patterns like: 1), a), i)
                if str.range(of: #"^(\d+|[a-z]|[ivx]+)\)"#, options: .regularExpression) != nil {
                    return true
                }
                return false
                
            case .special(let str):
                return str.range(of: #"^(\d+|[a-z]|[ivx]+)[.)]"#, options: .regularExpression) != nil
                
            case .punctuation(let str):
                return ["•", "▪", "‣", "-", "*"].contains(str)
                
            default:
                return false
            }
        }
        
        var isNumberFollowedByPunctuation: Bool {
            if case .word(let str) = self {
                return str.range(of: #"^\d+[.)]"#, options: .regularExpression) != nil
            }
            if case .special(let str) = self {
                return str.range(of: #"^\d+[.)]"#, options: .regularExpression) != nil
            }
            return false
        }
    }

    // Add these state variables
    private var pendingBackticks = ""
    private var inCodeBlock = false
    
    struct LayoutProcessor {
        private let tokenizer: TextStreamTokenizer
        init(tokenizer: TextStreamTokenizer) {
            self.tokenizer = tokenizer
        }

        func process(tokens: [TokenType]) -> [TokenType] {
            var processed: [TokenType] = []
            var buffer: [TokenType] = []
            var lastWasNewline = true
            var inCodeBlock = false
            
            for token in tokens {
                // Handle code block boundaries
                if case .codeBlockStart = token {
                    inCodeBlock = true
                    flushBuffer(&processed, &buffer)
                    processed.append(token)
                    continue
                } else if case .codeBlockEnd = token {
                    inCodeBlock = false
                    flushBuffer(&processed, &buffer)
                    processed.append(token)
                    continue
                }
                
                // In code block, just collect content
                if inCodeBlock {
                    if case .codeBlockContent = token {
                        buffer.append(token)
                    }
                    continue
                }

                if case .word(let str) = token, let splitTokens = tokenizer.splitNumberPunctuationToken(str) {
                    buffer.append(splitTokens.0)
                    buffer.append(splitTokens.1)
                    continue
                }
                
                buffer.append(token)
                
                if shouldInsertNewline(buffer: buffer, lastWasNewline: lastWasNewline) {
                    if !processed.isEmpty && processed.last != .newline {
                        processed.append(.newline)
                    }
                    processed.append(contentsOf: buffer)
                    processed.append(.newline)
                    buffer.removeAll()
                    lastWasNewline = true
                } else {
                    if case .newline = token {
                        lastWasNewline = true
                    } else if !token.isSingleSpace {
                        lastWasNewline = false
                    }
                }
            }
            flushBuffer(&processed, &buffer)
            return processed
        }

        private func flushBuffer(_ processed: inout [TokenType], _ buffer: inout [TokenType]) {
            if !buffer.isEmpty {
                processed.append(contentsOf: buffer)
                buffer.removeAll()
            }
        }
        
        private func shouldInsertNewline(buffer: [TokenType], lastWasNewline: Bool) -> Bool {
            guard !buffer.isEmpty else { return false }

            if buffer.count >= 2 {
                let pattern1 = buffer[0].isListMarker && buffer[1].isSingleSpace
                let pattern2 = buffer[0].isNumberFollowedByPunctuation
                let pattern3 = buffer.count >= 3 &&
                            buffer[0].isColon &&
                            buffer[1].isSingleSpace &&
                            (buffer[2].isListMarker || buffer[2].isNumberFollowedByPunctuation)
                let pattern4 = buffer[0].isColon &&
                            buffer[1].isListMarker

                return pattern1 || pattern2 || pattern3 || pattern4
            }

            return lastWasNewline && (buffer[0].isListMarker || buffer[0].isNumberFollowedByPunctuation)
        }
    }

    func tokenize(_ text: String) -> [TokenType] {
        var tokens: [TokenType] = []
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var currentIndex = text.startIndex
        var inLink = false

        // Combine with any pending backticks from previous chunks
        let fullText = pendingBackticks + text
        currentIndex = fullText.startIndex
        pendingBackticks = ""
        
        while currentIndex < fullText.endIndex {
            let remainingText = fullText[currentIndex...]
            
            if inCodeBlock {
                // Handle code block content
                if let endRange = remainingText.range(of: "```") {
                    let content = String(fullText[currentIndex..<endRange.lowerBound])
                    if !content.isEmpty {
                        tokens.append(.codeBlockContent(content))
                    }
                    tokens.append(.codeBlockEnd)
                    currentIndex = endRange.upperBound
                    inCodeBlock = false
                    continue
                } else {
                    // No closing backticks found in this chunk
                    tokens.append(.codeBlockContent(String(remainingText)))
                    currentIndex = fullText.endIndex
                    continue
                }
            }
            
            // Check for potential code block start (may be split across chunks)
            if remainingText.hasPrefix("`") {
                let backtickCount = countConsecutiveBackticks(in: remainingText)
                
                // Need at least 3 backticks to start a code block
                if backtickCount >= 3 {
                    let markerEnd = fullText.index(currentIndex, offsetBy: 3)
                    let afterMarker = fullText[markerEnd...]
                    let language: String?
                    
                    if let newlineRange = afterMarker.range(of: "\n") {
                        language = String(fullText[markerEnd..<newlineRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                        currentIndex = newlineRange.upperBound
                    } else {
                        language = nil
                        currentIndex = markerEnd
                    }
                    
                    tokens.append(.codeBlockStart(language: language))
                    inCodeBlock = true
                    continue
                } else {
                    // Not enough backticks for code block - might be split across chunks
                    // Save them for next chunk
                    pendingBackticks = String(fullText[currentIndex..<fullText.index(currentIndex, offsetBy: backtickCount)])
                    currentIndex = fullText.index(currentIndex, offsetBy: backtickCount)
                    continue
                }
            }
            
            // Rest of your existing markdown parsing logic...
            // (Handle links, bold, italic, etc.)
            
            // Process regular text
            let nextChar = fullText[currentIndex]
            if nextChar.isNewline {
                tokens.append(.newline)
                currentIndex = fullText.index(after: currentIndex)
                continue
            } else if nextChar.isWhitespace {
                tokens.append(.whitespace(String(nextChar)))
                currentIndex = fullText.index(after: currentIndex)
                continue
            } else {
                // Use the tokenizer for word boundaries
                guard currentIndex < fullText.endIndex else { break }
                
                // Get token ranges from the tokenizer
                let tokenRanges = tokenizer.tokens(for: currentIndex..<fullText.endIndex)
                
                // Safely get the first token range
                if let range = tokenRanges.first(where: { $0.lowerBound == currentIndex }) {
                    // Ensure the range is within bounds
                    guard range.upperBound <= fullText.endIndex else {
                        // If range is out of bounds, fallback to single character
                        let char = String(fullText[currentIndex])
                        tokens.append(.word(char))
                        currentIndex = fullText.index(after: currentIndex)
                        continue
                    }
                    
                    let token = String(fullText[range])
                    tokens.append(classify(token))
                    currentIndex = range.upperBound
                } else {
                    // Fallback: treat as single character
                    guard currentIndex < fullText.endIndex else { break }
                    let nextIndex = fullText.index(after: currentIndex)
                    
                    // Check if nextIndex is valid
                    if nextIndex <= fullText.endIndex {
                        let char = String(fullText[currentIndex..<nextIndex])
                        tokens.append(.word(char))
                        currentIndex = nextIndex
                    } else {
                        // Handle the last character case
                        let char = String(fullText[currentIndex])
                        tokens.append(.word(char))
                        currentIndex = fullText.endIndex
                    }
                }
            }
        }
        
        return LayoutProcessor(tokenizer: self).process(tokens: tokens)
    }

     private func countConsecutiveBackticks(in text: Substring) -> Int {
        var count = 0
        var index = text.startIndex
        while index < text.endIndex && text[index] == "`" {
            count += 1
            index = text.index(after: index)
        }
        return count
    }
    
    func resetTokenizerState() {
        pendingBackticks = ""
        inCodeBlock = false
    }

    private func processStyledText(prefix: String, style: StyleType, in text: String, from index: String.Index, into tokens: inout [TokenType]) -> String.Index {
        let markerRange = text[index...].range(of: prefix)!
        let contentStart = markerRange.upperBound
        
        if let endRange = text[contentStart...].range(of: prefix) {
            let content = String(text[contentStart..<endRange.lowerBound])
            switch style {
            case .bold: tokens.append(.bold(content))
            case .italic: tokens.append(.italic(content))
            case .inlineCode: tokens.append(.inlineCode(content))
            }
            return endRange.upperBound
        } else {
            // Unclosed marker, treat as regular text
            tokens.append(.word(prefix))
            return markerRange.upperBound
        }
    }
    private func processLinkContent(_ linkContent: String, into tokens: inout [TokenType]) {
        let parts = linkContent.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        if parts.count == 2 {
            let urlText = String(parts[0])
            let linkText = String(parts[1])
            if let url = URL(string: urlText) {
                tokens.append(.link(text: linkText, url: url))
                return
            }
        }
        // Fallback for malformed links
        tokens.append(.word("(\(linkContent))"))
    }

    private func classify(_ token: String) -> TokenType {
        if token.isWhitespace {
            return token.contains("\n") ? .newline : .whitespace(token)
        } else if token.isPunctuation {
            return .punctuation(token)
        } else if token.isSpecialPattern {
            return .special(token)
        } else {
            return .word(token)
        }
    }

    private func classifyRawText(_ text: String) -> [TokenType] {
        var tokens: [TokenType] = []
        var currentWhitespace = ""
        var currentWord = ""
        var iterator = PeekingIterator(text.makeIterator())
        
        while let char = iterator.next() {
            let charStr = String(char)
            
            if char.isWhitespace {
                if char == "\n" {
                    flushAccumulators(&tokens, &currentWhitespace, &currentWord)
                    tokens.append(.newline)
                    continue
                }

                if !currentWord.isEmpty {
                    if let (numberToken, remainingToken) = splitNumberPunctuationToken(currentWord) {
                        tokens.append(numberToken)
                        if case .word(let remaining) = remainingToken, !remaining.isEmpty {
                            tokens.append(remainingToken)
                        }
                    } else {
                        tokens.append(classify(currentWord))
                    }
                    currentWord = ""
                }
                currentWhitespace.append(char)
                continue
            }
            
            let charType = classifyCharacter(char, charStr: charStr)
            
            switch charType {
            case .punctuation(let punct):
                if !currentWord.isEmpty, currentWord.range(of: #"^\d+$"#, options: .regularExpression) != nil {
                    currentWord.append(punct)
                    tokens.append(.special(currentWord))
                    currentWord = ""
                } else {
                    flushAccumulators(&tokens, &currentWhitespace, &currentWord)
                    tokens.append(charType)
                }
                
            case .special, .word:
                currentWord.append(char)
                
            default:
                continue
            }
        }
        
        flushAccumulators(&tokens, &currentWhitespace, &currentWord)
        return tokens
    }
    
    private func splitNumberPunctuationToken(_ str: String) -> (TokenType, TokenType)? {
        guard let regex = try? NSRegularExpression(pattern: #"^(\d+)([.)])\s*(.*)$"#) else {
            return nil
        }
        
        let nsRange = NSRange(str.startIndex..<str.endIndex, in: str)
        guard let match = regex.firstMatch(in: str, options: [], range: nsRange),
              match.numberOfRanges >= 3 else {
            return nil
        }
        
        var numberPart = ""
        var punctuation = ""
        var remaining = ""
        
        if let numberRange = Range(match.range(at: 1), in: str) {
            numberPart = String(str[numberRange])
        }
        
        if let punctuationRange = Range(match.range(at: 2), in: str) {
            punctuation = String(str[punctuationRange])
        }
        
        if match.numberOfRanges > 2, let remainingRange = Range(match.range(at: 3), in: str) {
            remaining = String(str[remainingRange])
        }
        
        guard !numberPart.isEmpty && !punctuation.isEmpty else {
            return nil
        }
        
        let numberToken: TokenType = .special(numberPart + punctuation)
        let wordToken: TokenType = remaining.isEmpty ? .whitespace(" ") : .word(remaining)
        
        return (numberToken, wordToken)
    }
    
    private func isEmoji(_ char: Character) -> Bool {
        return char.unicodeScalars.contains { scalar in
            scalar.properties.isEmoji || 
            scalar.properties.isEmojiPresentation
        }
    }

    private func isEmojiSequence(_ char: Character) -> Bool {
        let scalars = char.unicodeScalars
        guard scalars.count > 1 else { return false }
        
        return scalars.contains { scalar in
            scalar.properties.isEmoji ||
            scalar.properties.isEmojiPresentation ||
            scalar.value == 0x200D
        }
    }

    private func classifyCharacter(_ char: Character, charStr: String) -> TokenType {
        if isEmoji(char) || isEmojiSequence(char) {
            return .special(charStr)
        }
        
        if char.unicodeScalars.count == 1, 
           let scalar = char.unicodeScalars.first,
           CharacterSet.punctuationCharacters.contains(scalar) {
            return .punctuation(charStr)
        }
        
        return classify(charStr)
    }

    private func flushAccumulators(_ tokens: inout [TokenType],
                                  _ whitespace: inout String,
                                  _ word: inout String) {
        if !whitespace.isEmpty {
            tokens.append(.whitespace(whitespace))
            whitespace = ""
        }

        if !word.isEmpty {
            tokens.append(classify(word))
            word = ""
        }
    }
}

// MARK: - Extensions
private extension String {
    var isWhitespace: Bool {
        return trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isPunctuation: Bool {
        return !isEmpty && unicodeScalars.allSatisfy { CharacterSet.punctuationCharacters.contains($0) }
    }
    
    var isSpecialPattern: Bool {
        let patterns = [
            #"https?://\S+"#,
            #"`{1,3}[^`\n]+`{1,3}"#,
            #"\*{1,2}[^*\n]+\*{1,2}"#,
            #"\[.*?\]\(.*?\)"#
        ]
        return patterns.contains { range(of: $0, options: .regularExpression) != nil }
    }
}

private extension Character {
    var isWhitespace: Bool {
        return isNewline || unicodeScalars.allSatisfy { CharacterSet.whitespaces.contains($0) }
    }
    
    var isNewline: Bool {
        return unicodeScalars.allSatisfy { CharacterSet.newlines.contains($0) }
    }
}

struct PeekingIterator<T: IteratorProtocol>: IteratorProtocol {
    private var iterator: T
    private var peeked: T.Element?
    
    init(_ base: T) {
        self.iterator = base
    }
    
    mutating func next() -> T.Element? {
        if let peeked = peeked {
            self.peeked = nil
            return peeked
        }
        return iterator.next()
    }
    
    mutating func peek() -> T.Element? {
        if peeked == nil {
            peeked = iterator.next()
        }
        return peeked
    }
}
