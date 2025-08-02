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
                if str.range(of: #"^(\d+|[a-z]|[ivx]+)\."#, options: .regularExpression) != nil {
                    return true
                }
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

    private var pendingBackticks = ""
    private var inCodeBlock = false
    private let tokenizerQueue = DispatchQueue(label: "com.text.tokenizer.queue")
    
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

    private func tokenizeNormalText(_ text: String) -> [TokenType] {
        var tokens: [TokenType] = []
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let token = String(text[range])
            tokens.append(classify(token))
            return true
        }
        
        return tokens
    }

    func tokenize(_ text: String) -> [TokenType] {
        return tokenizerQueue.sync {
            _unsafeTokenize(text)
        }
    }

    private func _unsafeTokenize(_ text: String) -> [TokenType] {
        var tokens: [TokenType] = []
        let tokenizer = NLTokenizer(unit: .word)

         // Combine with pending backticks and ensure contiguous storage
        let fullText = (pendingBackticks + text).withCString { _ in 
            String(pendingBackticks + text)
        }
        
        // let fullText: String = {
        //     let combined = pendingBackticks + text
        //     pendingBackticks = ""
        //     return combined.withCString { _ in String(combined) }
        // }()
        
        tokenizer.string = fullText
        var currentIndex = fullText.startIndex

        // Track potential split backticks
        var potentialBackticks = pendingBackticks
        pendingBackticks = ""
        
        while currentIndex < fullText.endIndex {
            let remainingText = fullText[currentIndex...]
            
            if inCodeBlock {
                if let endRange = remainingText.range(of: "```") {
                    guard endRange.lowerBound >= remainingText.startIndex && 
                          endRange.upperBound <= remainingText.endIndex else {
                        tokens.append(.codeBlockContent(String(remainingText)))
                        currentIndex = fullText.endIndex
                        continue
                    }
                    
                    let content = String(fullText[currentIndex..<endRange.lowerBound])
                    if !content.isEmpty {
                        tokens.append(.codeBlockContent(content))
                    }
                    tokens.append(.codeBlockEnd)
                    currentIndex = endRange.upperBound
                    inCodeBlock = false
                    continue
                } else {
                    tokens.append(.codeBlockContent(String(remainingText)))
                    currentIndex = fullText.endIndex
                    continue
                }
            }

            if remainingText.first == "`" {
                let backtickCount = countConsecutiveBackticks(in: remainingText)
                let totalBackticks = potentialBackticks.count + backtickCount
                
                if totalBackticks >= 3 {
                    let backticksToUse = min(3 - potentialBackticks.count, backtickCount)
                    let backtickEnd = fullText.index(currentIndex, offsetBy: backticksToUse)
                    
                    if potentialBackticks.count + backticksToUse == 3 {
                        // We have our 3 backticks - process as code block
                        let markerEnd = fullText.index(currentIndex, offsetBy: 3 - potentialBackticks.count)
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
                        potentialBackticks = ""
                        continue
                    } else {
                        // Still need more backticks
                        pendingBackticks = potentialBackticks + String(fullText[currentIndex..<backtickEnd])
                        currentIndex = backtickEnd
                        continue
                    }
                } else {
                    // Not enough backticks yet
                    pendingBackticks = potentialBackticks + String(fullText[currentIndex..<fullText.index(currentIndex, offsetBy: backtickCount)])
                    currentIndex = fullText.index(currentIndex, offsetBy: backtickCount)
                    continue
                }
            }

            
            // if remainingText.hasPrefix("`") {
            //     let backtickCount = countConsecutiveBackticks(in: remainingText)
                
            //     if backtickCount >= 3 {
            //         guard fullText.distance(from: currentIndex, to: fullText.endIndex) >= 3 else {
            //             pendingBackticks = String(fullText[currentIndex...])
            //             currentIndex = fullText.endIndex
            //             continue
            //         }
                    
            //         let markerEnd = fullText.index(currentIndex, offsetBy: 3, limitedBy: fullText.endIndex) ?? fullText.endIndex
            //         let afterMarker = fullText[markerEnd...]
            //         let language: String?
                    
            //         if let newlineRange = afterMarker.range(of: "\n") {
            //             language = String(fullText[markerEnd..<newlineRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            //             currentIndex = newlineRange.upperBound
            //         } else {
            //             language = nil
            //             currentIndex = markerEnd
            //         }
                    
            //         tokens.append(.codeBlockStart(language: language))
            //         inCodeBlock = true
            //         continue
            //     } else {
            //         pendingBackticks = String(fullText[currentIndex..<fullText.index(currentIndex, offsetBy: backtickCount)])
            //         currentIndex = fullText.index(currentIndex, offsetBy: backtickCount)
            //         continue
            //     }
            // }
            
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
                guard currentIndex < fullText.endIndex else { break }
                
                // Create a stable text copy for this operation
                let stableText = fullText.withCString { String(cString: $0) }
                let stableIndex = stableText.index(
                    stableText.startIndex, 
                    offsetBy: fullText.distance(from: fullText.startIndex, to: currentIndex)
                )
                
                let tokenRange = makeSafeTokenRange(from: stableIndex, in: stableText)
                let tokenRanges = getValidTokenRanges(
                    tokenizer: NLTokenizer(unit: .word), 
                    range: tokenRange, 
                    in: stableText
                )
                
                if let (range, token) = getFirstValidToken(
                    from: tokenRanges, 
                    currentIndex: stableIndex, 
                    in: stableText
                ) {
                    tokens.append(token)
                    currentIndex = fullText.index(
                        currentIndex, 
                        offsetBy: stableText.distance(from: stableIndex, to: range.upperBound)
                    )
                } else {
                    currentIndex = processSingleCharacter(at: currentIndex, in: fullText, tokens: &tokens)
                }
            }
        }
        
        return LayoutProcessor(tokenizer: self).process(tokens: tokens)
    }

    private func makeSafeTokenRange(from index: String.Index, in text: String) -> Range<String.Index> {
        let maxChunkSize = 1000
        if let end = text.index(index, offsetBy: maxChunkSize, limitedBy: text.endIndex) {
            return index..<end
        }
        return index..<text.endIndex
    }
    
    private func getValidTokenRanges(
        tokenizer: NLTokenizer,
        range: Range<String.Index>,
        in text: String
    ) -> [Range<String.Index>] {
        // 1. Create a local copy of the string to ensure lifetime
        let localText = text.withCString { String(cString: $0) }
        
        // 2. Verify indices are still valid
        guard range.lowerBound >= localText.startIndex,
            range.upperBound <= localText.endIndex,
            range.lowerBound < range.upperBound else {
            return []
        }
        
        // 3. Use a new tokenizer instance to avoid thread issues
        let localTokenizer = NLTokenizer(unit: .word)
        localTokenizer.string = localText
        
        // 4. Get tokens with additional validation
        return localTokenizer.tokens(for: range).compactMap { range in
            guard range.lowerBound >= localText.startIndex,
                range.upperBound <= localText.endIndex,
                range.lowerBound < range.upperBound else {
                return nil
            }
            return range
        }
    }
    
    private func getFirstValidToken(
        from ranges: [Range<String.Index>],
        currentIndex: String.Index,
        in text: String
    ) -> (Range<String.Index>, TokenType)? {
        guard let range = ranges.first(where: { $0.lowerBound == currentIndex }),
              range.upperBound <= text.endIndex else {
            return nil
        }
        
        let tokenText = String(text[range])
        return (range, classify(tokenText))
    }
    
    private func processSingleCharacter(
        at index: String.Index,
        in text: String,
        tokens: inout [TokenType]
    ) -> String.Index {
        guard index < text.endIndex else { return text.endIndex }
        
        let nextIndex = text.index(after: index)
        guard nextIndex <= text.endIndex else {
            let char = String(text[index])
            tokens.append(.word(char))
            return text.endIndex
        }
        
        let char = String(text[index..<nextIndex])
        tokens.append(.word(char))
        return nextIndex
    }

    private func countConsecutiveBackticks(in text: Substring) -> Int {
        var count = 0
        var index = text.startIndex
        while index < text.endIndex && text[index] == "`" {
            count += 1
            index = text.index(after: index)
            if index > text.endIndex {
                return count
            }
        }
        return count
    }
    
    func resetTokenizerState() {
        pendingBackticks = ""
        inCodeBlock = false
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
}

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