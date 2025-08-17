import Cocoa

class CodeBlockParser {
    enum ParserState: Equatable {
        case text
        case potentialCodeBlockStart(backticks: String)
        case inCodeBlock(language: String, openingBackticks: String)
        case potentialCodeBlockEnd(backticks: String)
        
        static func == (lhs: ParserState, rhs: ParserState) -> Bool {
            switch (lhs, rhs) {
            case (.text, .text):
                return true
            case let (.potentialCodeBlockStart(lbackticks), .potentialCodeBlockStart(rbackticks)):
                return lbackticks == rbackticks
            case let (.inCodeBlock(llang, lbackticks), .inCodeBlock(rlang, rbackticks)):
                return llang == rlang && lbackticks == rbackticks
            case let (.potentialCodeBlockEnd(lbackticks), .potentialCodeBlockEnd(rbackticks)):
                return lbackticks == rbackticks
            default:
                return false
            }
        }
    }

    enum ParsedElement {
        case text(NSAttributedString)
        case codeBlock(language: String, content: String)
    }
    
    private let stateLock = NSRecursiveLock()
    private var _state: ParserState = .text
    private var _codeBlockBuffer = ""
    private var _languageBuffer = ""
    private var _pendingBackticks = ""
    private var _lineBuffer = ""
    private var _pendingDelimiter: NSAttributedString?
    private var _partialCodeBlockContent = ""
    
    private var parserState: ParserState {
        get { stateLock.withLock { _state } }
        set { stateLock.withLock { _state = newValue } }
    }
    
    private var codeBlockBuffer: String {
        get { stateLock.withLock { _codeBlockBuffer } }
        set { stateLock.withLock { _codeBlockBuffer = newValue } }
    }
    
    private var languageBuffer: String {
        get { stateLock.withLock { _languageBuffer } }
        set { stateLock.withLock { _languageBuffer = newValue } }
    }
    
    private var pendingBackticks: String {
        get { stateLock.withLock { _pendingBackticks } }
        set { stateLock.withLock { _pendingBackticks = newValue } }
    }
    
    private var lineBuffer: String {
        get { stateLock.withLock { _lineBuffer } }
        set { stateLock.withLock { _lineBuffer = newValue } }
    }

    private var partialCodeBlockContent: String {
        get { stateLock.withLock { _partialCodeBlockContent } }
        set { stateLock.withLock { _partialCodeBlockContent = newValue } }
    }
    
    func parseChunk(_ chunk: String, isComplete: Bool = false) -> [ParsedElement] {
        return stateLock.withLock {
            var remainingText = lineBuffer + chunk
            lineBuffer = ""
            var output: [ParsedElement] = []
            
            if !remainingText.contains("`") && 
                !remainingText.contains("*") && 
                !remainingText.contains("_") && 
                parserState == .text {
                    print("remainingText doesn't contains ` and * and _ called\(remainingText)")
                    let text = partialCodeBlockContent + remainingText
                    partialCodeBlockContent = ""
                    
                    // Even if there are no backticks, we still need to process for bold text
                    if text.contains("**") || text.contains("__") {
                        print("text contains ** or __ called\(text)")
                        return [.text(createRegularText(text))]
                    } else {
                        return [.text(NSAttributedString(string: text, attributes: TextAttributes.regular))]
                    }
                }
            
            while !remainingText.isEmpty {
                if let newlineIndex = remainingText.firstIndex(of: "\n") {
                    print("remainingText firstIndex has newline \(newlineIndex)")
                    let line = String(remainingText[..<newlineIndex])
                    remainingText = String(remainingText[remainingText.index(after: newlineIndex)...])
                    
                    let processed = processLine(line + "\n")
                    output.append(contentsOf: processed)
                } else {
                    print("remainingText firstIndex doesn't have newline")
                    lineBuffer = remainingText
                    remainingText = ""
                }
            }
            
            if isComplete {
                if !partialCodeBlockContent.isEmpty {
                    output.append(.text(createRegularText(partialCodeBlockContent)))
                    partialCodeBlockContent = ""
                }
                if !lineBuffer.isEmpty {
                    output.append(contentsOf: processLine(lineBuffer))
                    lineBuffer = ""
                }
            }
            
            return output
        }
    }
    
    func reset() {
        stateLock.withLock {
            _state = .text
            _codeBlockBuffer = ""
            _languageBuffer = ""
            _pendingBackticks = ""
            _lineBuffer = ""
            _pendingDelimiter = nil
        }
    }
    
    private func processLine(_ line: String) -> [ParsedElement] {
        print("processline being called\(line)")
        var output: [ParsedElement] = []
        var remainingLine = line
        
        if !remainingLine.contains("`") && 
           !remainingLine.contains("*") && 
           !remainingLine.contains("_") && 
           parserState == .text {
            print("Inside ProcessLine -> \(remainingLine)")
            return [.text(createRegularText(remainingLine))]
        }
        
        while !remainingLine.isEmpty {
            switch parserState {
            case .text:
                if let firstSpecialChar = remainingLine.firstIndex(where: { $0 == "`" || $0 == "*" || $0 == "_" }) {
                    let char = remainingLine[firstSpecialChar]
                    
                    let textBefore = String(remainingLine[..<firstSpecialChar])
                    if !textBefore.isEmpty {
                        output.append(.text(createRegularText(textBefore)))
                    }
                    
                    let remainingText = String(remainingLine[firstSpecialChar...])
                    
                    if char == "`" {
                        print("First character is matching with (`) alone\(char)")
                        if let backtickCount = MarkdownProcessor.countConsecutiveBackticks(in: remainingText), backtickCount >= 3 {
                            let backticks = String(remainingText.prefix(backtickCount))
                            let remainingAfterBackticks = String(remainingText.dropFirst(backtickCount))
                            
                            if output.last?.textContent.trimmingCharacters(in: .newlines).isEmpty == true {
                                _ = output.popLast()
                            }
                            
                            parserState = .potentialCodeBlockStart(backticks: backticks)
                            remainingLine = remainingAfterBackticks
                        } else {
                            print("countConsecutiveBackticks not satisfied\(char)")
                            let processed = processInlineCode(remainingText)
                            output.append(.text(processed))
                            remainingLine = ""
                        }
                    } else {
                        print("First character is matching with (`), (*) or (_)\(char)")
                        let processed = MarkdownProcessor.processInlineMarkdown(remainingText)
                        output.append(.text(processed))
                        remainingLine = ""
                    }
                } else {
                    print("First character is not matching (`), (*) or (_)\(remainingLine)")
                    output.append(.text(createRegularText(remainingLine)))
                    remainingLine = ""
                }
                
            case .potentialCodeBlockStart(let backticks):
                if let newlineIndex = remainingLine.firstIndex(of: "\n") {
                    let languagePart = languageBuffer + String(remainingLine[..<newlineIndex])
                    languageBuffer = ""
                    
                    let rawLanguage = languagePart.trimmingCharacters(in: .whitespacesAndNewlines)
                    let validatedLanguage = SyntaxHighlighter.validLanguages.contains(rawLanguage.lowercased()) ? 
                        rawLanguage.lowercased() : 
                    SyntaxHighlighter.validateAndAutocorrectLanguage(rawLanguage)
                    
                    remainingLine = String(remainingLine[remainingLine.index(after: newlineIndex)...])
                    parserState = .inCodeBlock(language: validatedLanguage, openingBackticks: backticks)
                    
                    while remainingLine.first == "\n" {
                        remainingLine.removeFirst()
                    }
                } else {
                    languageBuffer += remainingLine
                    remainingLine = ""
                }
                
            case .inCodeBlock(let language, let openingBackticks):
                if let (endRange, _) = findClosingBackticks(in: remainingLine, openingBackticks: openingBackticks) {
                    let contentBeforeEnd = String(remainingLine[..<endRange.lowerBound])
                    let completeContent = codeBlockBuffer + contentBeforeEnd
                    codeBlockBuffer = ""
                    
                    if !completeContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        output.append(.codeBlock(language: language, content: completeContent))
                    }
                    
                    parserState = .text
                    remainingLine = String(remainingLine[endRange.upperBound...])
                    
                    while remainingLine.first == "\n" {
                        remainingLine.removeFirst()
                    }
                } else {
                    let newContent = codeBlockBuffer + remainingLine
                    if newContent.contains("\n") || newContent.count > 20 {
                        output.append(.codeBlock(language: language, content: newContent))
                        codeBlockBuffer = ""
                    } else {
                        codeBlockBuffer = newContent
                    }
                    remainingLine = ""
                }
                
            case .potentialCodeBlockEnd(let backticks):
                if remainingLine.allSatisfy({ $0 == "`" }) {
                    pendingBackticks += remainingLine
                    remainingLine = ""
                } else {
                    output.append(.codeBlock(language: "", content: backticks + remainingLine))
                    parserState = .text
                    remainingLine = ""
                }
            }
        }
        
        return output
    }
    
    private func findClosingBackticks(in text: String, openingBackticks: String) -> (Range<String.Index>, String)? {
        let minBackticks = max(3, openingBackticks.count)
        let pattern = #"(?:^|\n)(`{\#(minBackticks),})(?=\s|$)"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let ticksRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        
        let backticks = String(text[ticksRange])
        return (ticksRange, backticks)
    }
    
    private func processInlineCode(_ text: String) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: TextAttributes.regular)
        let pattern = "`([^`]+)`"
        
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return result
        }
        
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            if match.range.location != NSNotFound && match.range.length > 0 {
                let codeRange = match.range(at: 1)
                result.setAttributes(TextAttributes.regular, range: match.range)
                result.setAttributes(TextAttributes.inlineCode, range: codeRange)
                result.replaceCharacters(in: match.range, with: result.attributedSubstring(from: codeRange))
            }
        }
        
        return result
    }
    
    private func createRegularText(_ text: String) -> NSAttributedString {
        return MarkdownProcessor.processInlineMarkdown(text)
    }
}
