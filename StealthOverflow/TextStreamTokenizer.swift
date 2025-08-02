// TextStreamTokenizer.swift
import NaturalLanguage

final class TextStreamTokenizer {
    enum StyleType { case bold, italic, inlineCode }
    
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
            case .word(let str), .special(let str):
                let range = NSRange(str.startIndex..., in: str)
                return StreamAccumulator.listMarkerRegex.firstMatch(in: str, range: range) != nil
            case .punctuation(let str):
                return ["•", "▪", "‣", "-", "*"].contains(str)
            default: return false
            }
        }
        var isNewline: Bool {
            if case .newline = self { return true }
            return false
        }
    }

    private let accumulator = StreamAccumulator()
    private let tokenizerQueue = DispatchQueue(label: "com.text.tokenizer.queue")
    
    func tokenize(_ text: String, isComplete: Bool = false) -> [TokenType] {
        tokenizerQueue.sync {
            let (tokens, _) = processChunk(text, isComplete: isComplete)
            return LayoutProcessor().process(tokens: tokens)
        }
    }
    
    func reset() {
        tokenizerQueue.sync {
            accumulator.reset()
        }
    }

    private func processChunk(_ text: String, isComplete: Bool) -> (tokens: [TokenType], remainder: String) {
        let (rawTokens, remainder) = accumulator.process(chunk: text)
        let finalTokens = isComplete ? rawTokens + accumulator.flush() : rawTokens
        return (finalTokens, remainder)
    }

    struct LayoutProcessor {
        func process(tokens: [TokenType]) -> [TokenType] {
            var processed: [TokenType] = []
            var buffer: [TokenType] = []
            var lastWasNewline = true
            var inCodeBlock = false
            
            for token in tokens {
                switch token {
                case .codeBlockStart:
                    inCodeBlock = true
                    flushBuffer(&processed, &buffer)
                    processed.append(token)
                case .codeBlockEnd:
                    inCodeBlock = false
                    flushBuffer(&processed, &buffer)
                    processed.append(token)
                case .codeBlockContent where inCodeBlock:
                    buffer.append(token)
                default:
                    buffer.append(token)
                    lastWasNewline = token.isNewline ? true : !token.isSingleSpace
                    
                    if shouldInsertNewline(buffer: buffer, lastWasNewline: lastWasNewline) {
                        if !processed.isEmpty && processed.last != .newline {
                            processed.append(.newline)
                        }
                        processed.append(contentsOf: buffer)
                        processed.append(.newline)
                        buffer.removeAll()
                        lastWasNewline = true
                    }
                }
            }
            flushBuffer(&processed, &buffer)
            return processed
        }

        private func flushBuffer(_ processed: inout [TokenType], _ buffer: inout [TokenType]) {
            guard !buffer.isEmpty else { return }
            processed.append(contentsOf: buffer)
            buffer.removeAll()
        }
        
        private func shouldInsertNewline(buffer: [TokenType], lastWasNewline: Bool) -> Bool {
            guard !buffer.isEmpty else { return false }
            
            // Check for list patterns
            if buffer.count >= 2 {
                let pattern1 = buffer[0].isListMarker && buffer[1].isSingleSpace
                let pattern2 = buffer[0].isColon && buffer[1].isListMarker
                return pattern1 || pattern2
            }
            
            return lastWasNewline && buffer[0].isListMarker
        }
    }
}