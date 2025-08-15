// Extensions.swift
import Cocoa

extension String {
    func cleanedForStream() -> String {
        var cleaned = replacingOccurrences(of: "\0", with: "")
        cleaned = cleaned.filter { char in
            // Only filter out specific control characters
            for scalar in char.unicodeScalars {
                let value = scalar.value
                // Keep newlines and tabs
                if scalar == "\n" || scalar == "\t" {
                    return true
                }
                // Remove other control characters
                if value < 32 || (value >= 0x7F && value <= 0x9F) {
                    return false
                }
            }
            return true
        }
        return cleaned
    }

    func normalizeMarkdownCodeBlocks() -> String {
        var result = self
        
        // Fix double/malformed code blocks
        result = result.replacingOccurrences(
            of: #"```(\w*)\s*```(\w+)"#,
            with: "```$2",
            options: .regularExpression
        )
        
        // Fix single-letter language specifiers
        result = result.replacingOccurrences(
            of: #"```(\w)\s"#,
            with: "```$1",
            options: .regularExpression
        )
        
        // Ensure newlines around code blocks
        result = result.replacingOccurrences(
            of: #"(?<!\n)```(\w*)"#,
            with: "\n```$1",
            options: .regularExpression
        )
        
        return result
    }
}

extension NSLock {
    func withLock<T>(_ block: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try block()
    }
}

extension NSRecursiveLock {
    func withLock<T>(_ block: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try block()
    }
}

extension Unicode.Scalar {
    var isPrintableASCII: Bool {
        return value >= 32 && value <= 126  // ASCII printable range
    }
}

extension CodeBlockParser.ParsedElement {
    var textContent: String {
        switch self {
        case .text(let attributedString):
            return attributedString.string
        case .codeBlock(_, let content):
            return content
        }
    }
}