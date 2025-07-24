// file markdownParser.swift
import Foundation

enum MessageBlock {
    case text(String)
    case code(String)
}

struct MarkdownParser {
    static func parse(_ input: String) -> [MessageBlock] {
        var blocks: [MessageBlock] = []
        var current = ""
        var isCodeBlock = false
        var backtickCount = 0
        
        let lines = input.components(separatedBy: .newlines)
        var i = 0
        
        while i < lines.count {
            let line = lines[i]
            
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if isCodeBlock {
                    // End of code block
                    if !current.isEmpty {
                        blocks.append(.code(current))
                        current = ""
                    }
                } else {
                    // Start of code block
                    if !current.isEmpty {
                        blocks.append(.text(current))
                        current = ""
                    }
                }
                isCodeBlock.toggle()
                i += 1
            } else if isCodeBlock {
                // Inside code block - preserve all content exactly
                current += line + "\n"
                i += 1
            } else {
                // Regular text
                current += line + "\n"
                i += 1
            }
        }
        
        // Add remaining content
        if !current.isEmpty {
            blocks.append(isCodeBlock ? .code(current) : .text(current))
        }
        
        return blocks
    }
}