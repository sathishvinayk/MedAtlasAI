import Cocoa

extension NSColor {
    static let codeKeyword = NSColor.systemPurple
    static let codeString = NSColor.systemGreen
    static let codeNumber = NSColor.systemOrange
    static let codeComment = NSColor.systemGray
    static let codeType = NSColor.systemBlue
    static let codeAttribute = NSColor.systemOrange
    static let codeTag = NSColor.systemBlue
    static let codeVariable = NSColor.systemOrange
}

enum LanguageSyntax: String, CaseIterable {
    case swift, python, javascript, typescript, java, 
         kotlin, c, cpp, csharp, go, ruby, php,
         rust, scala, dart, r, objectivec, bash, sh,
         json, yaml, xml, html, css, markdown, text,
         pascal, haskell  // Added Pascal and Haskell
    
    var displayName: String {
        switch self {
        case .cpp: return "C++"
        case .csharp: return "C#"
        case .objectivec: return "Objective-C"
        case .sh: return "Shell"
        case .haskell: return "Haskell"
        default: return self.rawValue.capitalized
        }
    }
    
    var fileExtensions: [String] {
        switch self {
        case .swift: return ["swift"]
        case .python: return ["py"]
        case .javascript: return ["js"]
        case .typescript: return ["ts"]
        case .java: return ["java"]
        case .kotlin: return ["kt"]
        case .c: return ["c", "h"]
        case .cpp: return ["cpp", "hpp", "cc", "h"]
        case .csharp: return ["cs"]
        case .go: return ["go"]
        case .ruby: return ["rb"]
        case .php: return ["php"]
        case .rust: return ["rs"]
        case .scala: return ["scala"]
        case .dart: return ["dart"]
        case .r: return ["r"]
        case .objectivec: return ["m", "mm"]
        case .bash, .sh: return ["sh", "bash"]
        case .json: return ["json"]
        case .yaml: return ["yaml", "yml"]
        case .xml: return ["xml"]
        case .html: return ["html", "htm"]
        case .css: return ["css"]
        case .markdown: return ["md", "markdown"]
        case .text: return ["txt"]
        case .pascal: return ["pas", "pp", "p"]
        case .haskell: return ["hs", "lhs"]
        }
    }
}

extension LanguageSyntax {
    var patterns: [(pattern: String, attributes: [NSAttributedString.Key: Any])] {
        let basePatterns: [(pattern: String, attributes: [NSAttributedString.Key: Any])] = [
            // Strings (all languages)
            (pattern: #""(?:[^"\\]|\\.)*""#, 
             attributes: [.foregroundColor: NSColor.codeString]),
            (pattern: #"'(?:[^'\\]|\\.)*'"#, 
             attributes: [.foregroundColor: NSColor.codeString]),
            
            // Numbers
            (pattern: #"\b\d+(\.\d+)?\b"#, 
             attributes: [.foregroundColor: NSColor.codeNumber]),
            
            // Comments
            (pattern: #"//.*|/\*.*?\*/|#.*"#, 
             attributes: [.foregroundColor: NSColor.codeComment]),
        ]
        
        var languageSpecific: [(pattern: String, attributes: [NSAttributedString.Key: Any])] = []
        
        switch self {
        case .swift:
            languageSpecific = [
                (pattern: #"\b(func|let|var|class|struct|enum|if|else|for|while|switch|case|return|break|continue|guard|in|try|catch|throw|as|is|nil|self|Self|protocol|extension|import)\b"#, 
                 attributes: [.foregroundColor: NSColor.codeKeyword]),
                (pattern: #"\b(Int|String|Double|Bool|Array|Dictionary|Optional|Any|Void)\b"#, 
                 attributes: [.foregroundColor: NSColor.codeType])
            ]
            
        case .python:
            languageSpecific = [
                (pattern: #"\b(def|class|if|elif|else|for|while|try|except|finally|with|import|from|as|lambda|return|yield|break|continue|pass|raise|and|or|not|is|in|None|True|False)\b"#, 
                 attributes: [.foregroundColor: NSColor.codeKeyword]),
                (pattern: #"\b(int|str|float|bool|list|dict|tuple|set)\b"#, 
                 attributes: [.foregroundColor: NSColor.codeType])
            ]
            
        case .javascript, .typescript:
            languageSpecific = [
                (pattern: #"\b(function|class|const|let|var|if|else|for|while|try|catch|finally|throw|return|break|continue|switch|case|default|import|export|from|as|await|async|yield|typeof|instanceof|in|of|this|new)\b"#, 
                 attributes: [.foregroundColor: NSColor.codeKeyword]),
                (pattern: #"\b(null|undefined|true|false|NaN|Infinity)\b"#, 
                 attributes: [.foregroundColor: NSColor.codeNumber])
            ]
            
        case .java, .kotlin, .csharp:
            languageSpecific = [
                (pattern: #"\b(public|private|protected|class|interface|enum|fun|val|var|if|else|for|while|do|try|catch|finally|throw|return|break|continue|switch|case|default|import|package|new|this|super|extends|implements|static|final|abstract|void|int|long|float|double|boolean|char|byte|short)\b"#, 
                 attributes: [.foregroundColor: NSColor.codeKeyword])
            ]
            
        case .c, .cpp, .rust:
            languageSpecific = [
                (pattern: #"\b(int|float|double|char|void|bool|auto|const|mutable|unsigned|signed|short|long|struct|enum|union|typedef|template|typename|namespace|using|extern|static|register|volatile)\b"#, 
                 attributes: [.foregroundColor: NSColor.codeType]),
                (pattern: #"\b(if|else|for|while|do|switch|case|default|break|continue|return|goto|try|catch|throw|noexcept|constexpr|decltype|auto|sizeof|alignof|alignas|concept|requires)\b"#, 
                 attributes: [.foregroundColor: NSColor.codeKeyword])
            ]
            
        case .go:
            languageSpecific = [
                (pattern: #"\b(func|package|import|var|const|type|struct|interface|map|chan|if|else|for|range|switch|case|default|fallthrough|continue|break|return|go|defer|select)\b"#, 
                 attributes: [.foregroundColor: NSColor.codeKeyword])
            ]
            
        case .ruby:
            languageSpecific = [
                (pattern: #"\b(def|class|module|if|elsif|else|unless|for|while|until|do|begin|rescue|ensure|retry|raise|return|break|next|redo|yield|super|self|nil|true|false|and|or|not)\b"#, 
                 attributes: [.foregroundColor: NSColor.codeKeyword])
            ]
            
        case .php:
            languageSpecific = [
                (pattern: #"\b(function|class|interface|trait|namespace|use|if|else|elseif|for|foreach|while|do|switch|case|default|break|continue|return|throw|try|catch|finally|yield|fn)\b"#, 
                 attributes: [.foregroundColor: NSColor.codeKeyword]),
                (pattern: #"\$(this|\w+)"#, 
                 attributes: [.foregroundColor: NSColor.codeVariable])
            ]
            
        case .bash, .sh:
            languageSpecific = [
                (pattern: #"\b(if|then|else|elif|fi|for|while|until|do|done|case|esac|function|select|time)\b"#, 
                 attributes: [.foregroundColor: NSColor.codeKeyword]),
                (pattern: #"\$\{\w+\}|\$\w+"#, 
                 attributes: [.foregroundColor: NSColor.codeVariable])
            ]
            
        case .html, .xml:
            languageSpecific = [
                (pattern: #"<\/?\w+|\/?>"#, 
                 attributes: [.foregroundColor: NSColor.codeTag]),
                (pattern: #"\b\w+="#, 
                 attributes: [.foregroundColor: NSColor.codeAttribute])
            ]
            
        case .css:
            languageSpecific = [
                (pattern: #"\.\w+|\#\w+"#, 
                 attributes: [.foregroundColor: NSColor.codeAttribute]),
                (pattern: #"\b(\w+-)*\w+\s*:"#, 
                 attributes: [.foregroundColor: NSColor.codeKeyword])
            ]
            
        case .json:
            languageSpecific = [
                (pattern: #""\w+":"#, 
                 attributes: [.foregroundColor: NSColor.codeKeyword])
            ]
            
        case .yaml:
            languageSpecific = [
                (pattern: #"^\s*\w+:"#, 
                 attributes: [.foregroundColor: NSColor.codeKeyword])
            ]
            
        case .pascal:
            languageSpecific = [
                (pattern: #"\b(program|unit|uses|interface|implementation|begin|end|procedure|function|var|const|type|array|of|record|if|then|else|while|do|for|to|downto|repeat|until|case|with)\b"#, 
                 attributes: [.foregroundColor: NSColor.codeKeyword]),
                (pattern: #"\b(integer|string|boolean|real|char)\b"#, 
                 attributes: [.foregroundColor: NSColor.codeType])
            ]
            
        case .haskell:
            languageSpecific = [
                (pattern: #"\b(module|where|import|qualified|as|hiding|data|type|newtype|class|instance|deriving|let|in|do|case|of|if|then|else|infix[lr]?)\b"#, 
                 attributes: [.foregroundColor: NSColor.codeKeyword]),
                (pattern: #"\b(Int|Integer|Float|Double|Bool|Char|String|Maybe|Either|IO)\b"#, 
                 attributes: [.foregroundColor: NSColor.codeType]),
                (pattern: #"->|=>|\|\||&&|>>=|>>|\+\+|\$\$"#, 
                 attributes: [.foregroundColor: NSColor.codeKeyword])
            ]
            
        default:
            break
        }
        
        return basePatterns + languageSpecific
    }
}

class SyntaxHighlighter {
    static func highlight(_ code: String, language: String, baseAttributes: [NSAttributedString.Key: Any] = TextAttributes.codeBlock) -> NSAttributedString {
        let result = NSMutableAttributedString(string: code, attributes: baseAttributes)
        
        guard let lang = LanguageSyntax(rawValue: language.lowercased()) else {
            return result
        }
        
        for (pattern, highlightAttrs) in lang.patterns {
            do {
                let regex = try NSRegularExpression(pattern: pattern)
                let matches = regex.matches(in: code, range: NSRange(location: 0, length: code.utf16.count))
                
                for match in matches {
                    var combined = baseAttributes
                    highlightAttrs.forEach { combined[$0.key] = $0.value }
                    result.addAttributes(combined, range: match.range)
                }
            } catch {
                print("Regex error: \(error)")
            }
        }
        
        return result
    }
}

extension Dictionary where Key == NSAttributedString.Key {
    static func withColor(_ color: NSColor) -> [NSAttributedString.Key: Any] {
        return [.foregroundColor: color]
    }
}