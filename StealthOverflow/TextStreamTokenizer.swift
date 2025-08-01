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
            case .word(let str) where str.range(of: #"^\d+\."#, options: .regularExpression) != nil:
                return true
            case .punctuation(let str) where ["•", "▪", "‣"].contains(str):
                return true
            default:
                return false
            }
        }
    }
    struct LayoutProcessor {
        func process(tokens: [TokenType]) -> [TokenType] {
            var processed: [TokenType] = []
            var buffer: [TokenType] = []
            
            for token in tokens {
                buffer.append(token)
                
                if shouldInsertNewline(after: buffer) {
                    processed.append(contentsOf: buffer)
                    processed.append(.newline)
                    buffer.removeAll()
                }
            }
            
            processed.append(contentsOf: buffer)
            return processed
        }
        
        private func shouldInsertNewline(after tokens: [TokenType]) -> Bool {
            guard tokens.count >= 3 else { return false }
            let lastThree = Array(tokens.suffix(3)) // Convert to new array
            return lastThree[0].isColon &&
                   lastThree[1].isSingleSpace &&
                   lastThree[2].isListMarker
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

        // ✅ Critical fix: Process tokens through layout processor
        return LayoutProcessor().process(tokens: tokens)
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
        var iterator = text.makeIterator()
        
        while let char = iterator.next() {
            // Handle grapheme clusters properly
            let charStr = String(char)
            
            // Fast-path for whitespace/newline
            if char.isWhitespace {
                if char == "\n" {
                    flushAccumulators(&tokens, &currentWhitespace, &currentWord)
                    tokens.append(.newline)
                    continue
                }
                
                if !currentWord.isEmpty {
                    tokens.append(classify(currentWord))
                    currentWord = ""
                }
                currentWhitespace.append(char)
                continue
            }
            
            // Classify the character
            let charType = classifyCharacter(char, charStr: charStr)
            
            switch charType {
            case .punctuation, .special:
                flushAccumulators(&tokens, &currentWhitespace, &currentWord)
                tokens.append(charType)
                
            case .word:
                currentWord.append(char)

            case .whitespace, .newline:
                // These cases should already be handled by the fast-path above
                assertionFailure("Should have been handled by whitespace fast-path")
                continue
            }
        }
        
        flushAccumulators(&tokens, &currentWhitespace, &currentWord)
        return tokens
    }
    private func isEmoji(_ char: Character) -> Bool {
        // Check the entire grapheme cluster
        return char.unicodeScalars.contains { scalar in
            scalar.properties.isEmoji || 
            scalar.properties.isEmojiPresentation
        }
    }

    private func isEmojiSequence(_ char: Character) -> Bool {
        // For complex emoji sequences
        let scalars = char.unicodeScalars
        guard scalars.count > 1 else { return false }
        
        return scalars.contains { scalar in
            scalar.properties.isEmoji ||
            scalar.properties.isEmojiPresentation ||
            scalar.value == 0x200D // ZWJ (zero-width joiner)
        }
    }

    // Optimized character classification
    private func classifyCharacter(_ char: Character, charStr: String) -> TokenType {
         // Handle emoji first
        if isEmoji(char) || isEmojiSequence(char) {
            return .special(charStr)
        }
        // Fast path for ASCII punctuation
        if char.unicodeScalars.count == 1, 
        let scalar = char.unicodeScalars.first,
        CharacterSet.punctuationCharacters.contains(scalar) {
            return .punctuation(charStr)
        }
        
        // Full classification for complex characters
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
