import Foundation
import NaturalLanguage

final class CodeBlockAccumulator {
    // MARK: - State Tracking
    private var buffer = ""
    private var isInCodeBlock = false
    private var currentLanguage: String?
    private var pendingBackticks = ""
    
    // MARK: - Thread Safety
    private let lock = NSLock()
    
    // MARK: - Constants
    private static let codeBlockPattern = #"(?<ticks>`{3,})(?<language>[a-z]*)?"#
    private static let codeBlockRegex = try! NSRegularExpression(
        pattern: codeBlockPattern,
        options: .caseInsensitive
    )
    
    // MARK: - Public Interface
    func process(chunk: String) -> [TokenType] {
        lock.lock()
        defer { lock.unlock() }
        
        buffer += chunk
        var tokens: [TokenType] = []
        
        while !buffer.isEmpty {
            if isInCodeBlock {
                tokens += processCodeBlockContent()
            } else {
                tokens += processNormalText()
            }
            
            // Stop if waiting for more chunks to complete a block
            if isInCodeBlock && !buffer.contains("```") {
                break
            }
        }
        
        return tokens
    }
    
    func flush() -> [TokenType] {
        lock.lock()
        defer { lock.unlock() }
        
        var tokens: [TokenType] = []
        if !buffer.isEmpty {
            if isInCodeBlock {
                tokens.append(.codeBlockContent(buffer))
                // Note: No .codeBlockEnd for incomplete blocks
            } else {
                tokens += tokenizeNormalText(buffer)
            }
        }
        reset()
        return tokens
    }
    
    // MARK: - Private Processing
    private func processCodeBlockContent() -> [TokenType] {
        var tokens: [TokenType] = []
        
        guard let endRange = buffer.range(of: "```") else {
            // No closing backticks found yet
            return tokens
        }
        
        // Extract content before end markers
        let content = String(buffer[..<endRange.lowerBound])
        if !content.isEmpty {
            tokens.append(.codeBlockContent(content))
        }
        tokens.append(.codeBlockEnd)
        
        // Remove processed portion
        buffer = String(buffer[endRange.upperBound...])
        isInCodeBlock = false
        currentLanguage = nil
        
        return tokens
    }
    
    private func processNormalText() -> [TokenType] {
        var tokens: [TokenType] = []
        
        guard let match = Self.codeBlockRegex.firstMatch(
            in: buffer,
            range: NSRange(buffer.startIndex..., in: buffer)
        ) else {
            // No code blocks found, tokenize safe portions
            if let safeText = extractSafeNormalText() {
                tokens += tokenizeNormalText(safeText)
            }
            return tokens
        }
        
        // Handle text before code block
        let beforeRange = Range(match.range, in: buffer)!
        let beforeText = String(buffer[..<beforeRange.lowerBound])
        if !beforeText.isEmpty {
            tokens += tokenizeNormalText(beforeText)
        }
        
        // Process code block start
        let ticksRange = Range(match.range(withName: "ticks"), in: buffer)!
        let languageRange = Range(match.range(withName: "language"), in: buffer)
        let language = languageRange.map { String(buffer[$0]) }?.trimmingCharacters(in: .whitespaces)
        
        // Update state
        currentLanguage = language?.isEmpty ?? true ? nil : language
        let afterTicks = buffer[ticksRange.upperBound...]
        
        if let firstNewline = afterTicks.firstIndex(of: "\n") {
            // Complete code block start
            buffer = String(afterTicks[firstNewline...])
            tokens.append(.codeBlockStart(language: currentLanguage))
            isInCodeBlock = true
        } else {
            // Partial block start - wait for more chunks
            pendingBackticks = String(buffer[ticksRange])
            buffer = String(afterTicks)
        }
        
        return tokens
    }
    
    private func extractSafeNormalText() -> String? {
        guard !buffer.isEmpty else { return nil }
        
        // Don't tokenize if we might have partial backticks
        guard !buffer.contains("`") else { return nil }
        
        let safeText = buffer
        buffer = ""
        return safeText
    }
    
    // MARK: - Tokenization
    private func tokenizeNormalText(_ text: String) -> [TokenType] {
        var tokens: [TokenType] = []
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let token = String(text[range])
            tokens.append(classifyToken(token))
            return true
        }
        
        return tokens
    }
    
    private func classifyToken(_ token: String) -> TokenType {
        // Your existing token classification logic
        if token.isWhitespace {
            return token.contains("\n") ? .newline : .whitespace(token)
        } else if token.isPunctuation {
            return .punctuation(token)
        } else {
            return .word(token)
        }
    }
    
    // MARK: - Reset
    private func reset() {
        buffer = ""
        isInCodeBlock = false
        currentLanguage = nil
        pendingBackticks = ""
    }
}

// MARK: - Token Types
enum TokenType {
    case word(String)
    case punctuation(String)
    case whitespace(String)
    case newline
    case codeBlockStart(language: String?)
    case codeBlockContent(String)
    case codeBlockEnd
}

// MARK: - String Extensions
private extension String {
    var isWhitespace: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var isPunctuation: Bool {
        !isEmpty && unicodeScalars.allSatisfy {
            CharacterSet.punctuationCharacters.contains($0)
        }
    }
}