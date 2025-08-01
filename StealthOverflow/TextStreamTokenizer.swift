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
        var result: [TokenType] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byComposedCharacterSequences) { substring, _, _, _ in
            result.append(self.classify(substring!))
        }
        return result
    }
}

// MARK: - Extensions
private extension String {
    var isWhitespace: Bool {
        return trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var isPunctuation: Bool {
        guard count == 1, let scalar = unicodeScalars.first else { return false }
        return CharacterSet.punctuationCharacters.contains(scalar)
    }
    
    var isSpecialPattern: Bool {
        let patterns = [
            #"https?://\S+"#,
            #"`{1,3}.*?`{1,3}"#
        ]
        return patterns.contains { range(of: $0, options: .regularExpression) != nil }
    }
}
