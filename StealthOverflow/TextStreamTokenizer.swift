import NaturalLanguage

final class TextStreamTokenizer {
    enum TokenType: Equatable {
        case word(String)
        case punctuation(String)
        case whitespace(String)
        case newline
        case special(String)
    }
    
    func tokenize(_ text: String) -> [TokenType] {
        var tokens: [TokenType] = []
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text

        var currentIndex = text.startIndex
        
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            // Capture inter-token gap before this token
            if currentIndex < range.lowerBound {
                let inBetween = String(text[currentIndex..<range.lowerBound])
                tokens.append(contentsOf: classifyRawText(inBetween))
            }

            let token = String(text[range])
            tokens.append(classify(token))

            currentIndex = range.upperBound
            return true
        }

        // Handle trailing leftover
        if currentIndex < text.endIndex {
            let trailing = String(text[currentIndex...])
            tokens.append(contentsOf: classifyRawText(trailing))
        }

        return tokens
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
            
            // Enhanced character classification
            let charType: TokenType
            if isEmoji(char) {
                charType = .special(charStr)  // or .emoji(charStr) if you add that case
            } else if isSymbol(char) {
                charType = .special(charStr)  // or .symbol(charStr)
            } else {
                charType = classifyCharacter(char, charStr: charStr)
            }
            
            switch charType {
            case .punctuation, .special:
                flushAccumulators(&tokens, &currentWhitespace, &currentWord)
                tokens.append(charType)
                
            case .word:
                currentWord.append(char)
                
            case .whitespace, .newline:
                assertionFailure("Should have been handled by whitespace fast-path")
            }
        }
        
        flushAccumulators(&tokens, &currentWhitespace, &currentWord)
        return tokens
    }

    // Character classification helpers
    private func isEmoji(_ char: Character) -> Bool {
        let scalar = char.unicodeScalars.first!
        return scalar.properties.isEmoji
    }

    private func isSymbol(_ char: Character) -> Bool {
        return char.unicodeScalars.contains { scalar in
            CharacterSet.symbols.contains(scalar) ||
            CharacterSet.nonBaseCharacters.contains(scalar) ||
            (scalar.properties.generalCategory == .otherSymbol)
        }
    }

    // Optimized character classification
    private func classifyCharacter(_ char: Character, charStr: String) -> TokenType {
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
