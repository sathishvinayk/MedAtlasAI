import NaturalLanguage

final class TextStreamTokenizer {
    enum TokenType: Equatable {
        case word(String)
        case punctuation(String)
        case whitespace(String)
        case newline
        case special(String)

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
    
    struct LayoutProcessor {
        private let tokenizer: TextStreamTokenizer
        init(tokenizer: TextStreamTokenizer) {
            self.tokenizer = tokenizer
        }

        func process(tokens: [TokenType]) -> [TokenType] {
            var processed: [TokenType] = []
            var buffer: [TokenType] = []
            var lastWasNewline = true
            
            for token in tokens {
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
            
            processed.append(contentsOf: buffer)
            return processed
        }
        
        // private func splitNumberPunctuationToken(_ str: String) -> (TokenType, TokenType)? {
        //     guard let regex = try? NSRegularExpression(pattern: #"^(\d+)([.)])\s*(.*)$"#) else {
        //         return nil
        //     }
            
        //     let nsRange = NSRange(str.startIndex..<str.endIndex, in: str)
        //     guard let match = regex.firstMatch(in: str, options: [], range: nsRange),
        //           match.numberOfRanges >= 3 else {
        //         return nil
        //     }
            
        //     var numberPart = ""
        //     var punctuation = ""
        //     var remaining = ""
            
        //     if let numberRange = Range(match.range(at: 1), in: str) {
        //         numberPart = String(str[numberRange])
        //     }
            
        //     if let punctuationRange = Range(match.range(at: 2), in: str) {
        //         punctuation = String(str[punctuationRange])
        //     }
            
        //     if match.numberOfRanges > 2, let remainingRange = Range(match.range(at: 3), in: str) {
        //         remaining = String(str[remainingRange])
        //     }
            
        //     guard !numberPart.isEmpty && !punctuation.isEmpty else {
        //         return nil
        //     }
            
        //     let numberToken: TokenType = .special(numberPart + punctuation)
        //     let wordToken: TokenType = remaining.isEmpty ? .whitespace(" ") : .word(remaining)
            
        //     return (numberToken, wordToken)
        // }
        
        private func shouldInsertNewline(buffer: [TokenType], lastWasNewline: Bool) -> Bool {
            guard !buffer.isEmpty else { return false }
            
            if buffer.count >= 2 {
                let pattern1 = buffer[0].isListMarker && buffer[1].isSingleSpace
                let pattern2 = buffer[0].isNumberFollowedByPunctuation
                let pattern3 = buffer.count >= 3 && 
                             buffer[0].isColon && 
                             buffer[1].isSingleSpace && 
                             (buffer[2].isListMarker || buffer[2].isNumberFollowedByPunctuation)
                
                return pattern1 || pattern2 || pattern3
            }
            
            return lastWasNewline && (buffer[0].isListMarker || buffer[0].isNumberFollowedByPunctuation)
        }
    }
    
    func tokenize(_ text: String) -> [TokenType] {
        var tokens: [TokenType] = []
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text

        var currentIndex = text.startIndex
        
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            if currentIndex < range.lowerBound {
                let inBetween = String(text[currentIndex..<range.lowerBound])
                tokens.append(contentsOf: classifyRawText(inBetween))
            }

            let token = String(text[range])
            tokens.append(classify(token))
            currentIndex = range.upperBound
            return true
        }

        if currentIndex < text.endIndex {
            let trailing = String(text[currentIndex...])
            tokens.append(contentsOf: classifyRawText(trailing))
        }

        return LayoutProcessor(tokenizer: self).process(tokens: tokens)
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
            #"`{1,3}.*?`{1,3}"#
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
