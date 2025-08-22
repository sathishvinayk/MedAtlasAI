// Extensions.swift
import Cocoa

extension Notification.Name {
    static let accessibilityPermissionGranted = Notification.Name("AccessibilityPermissionGranted")
    static let accessibilityPermissionRevoked = Notification.Name("AccessibilityPermissionRevoked")
}

extension NSColor {
    static let appBackground = NSColor(red: 3/255, green: 7/255, blue: 18/255, alpha: 1.0)
    static let inputContainerColor = NSColor(red: 10/255, green: 15/255, blue: 30/255, alpha: 0.9)
    static let primaryText = NSColor(red: 220/255, green: 220/255, blue: 220/255, alpha: 1.0)
    static let codeBlockBackground = NSColor(red: 8/255, green: 12/255, blue: 28/255, alpha: 1.0)
    static let codeBlockBorder = NSColor(red: 20/255, green: 25/255, blue: 50/255, alpha: 1.0)
    static let codeTextColor = NSColor(red: 220/255, green: 220/255, blue: 240/255, alpha: 1.0)
    static let userMessageBackground = NSColor(red: 15/255, green: 20/255, blue: 40/255, alpha: 1.0)
    static let userMessageText = NSColor(red: 230/255, green: 230/255, blue: 240/255, alpha: 1.0)
    static let userMessageBorderColor = NSColor(red: 30/255, green: 35/255, blue: 60/255, alpha: 1.0)
}

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