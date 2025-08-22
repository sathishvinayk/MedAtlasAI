import Cocoa
import CoreText

class FontManager {
    static let shared = FontManager()
    
    private var registeredFonts = Set<String>()
    private let fontNames = [
        "Oxanium-Regular",
        "Oxanium-Medium", 
        "Oxanium-SemiBold",
        "Oxanium-Bold",
        "Oxanium-ExtraBold",
        "Lato-Italic"
    ]
    
    private init() {
        // Private initializer for singleton
    }
    
    func registerOxaniumFonts(completion: (() -> Void)? = nil) {
        // Ensure font registration happens on main thread
        DispatchQueue.main.async {
            self.registerFontsSynchronously()
            completion?()
        }
    }
    
    func registerFontsSynchronously() {
        guard Thread.isMainThread else {
            fatalError("Font registration must be called on main thread")
        }
        
        for fontName in fontNames {
            if registeredFonts.contains(fontName) {
                continue // Skip already registered fonts
            }
            
            if let fontURL = Bundle.main.url(forResource: fontName, withExtension: "ttf") {
                var error: Unmanaged<CFError>?
                
                // Use the modern API
                if CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &error) {
                    print("Successfully registered font: \(fontName)")
                    registeredFonts.insert(fontName)
                } else {
                    print("Failed to register font \(fontName): \(error?.takeUnretainedValue().localizedDescription ?? "Unknown error")")
                }
            } else {
                print("Could not find font file: \(fontName).ttf")
            }
        }
    }
    
    func isFontRegistered(_ fontName: String) -> Bool {
        return registeredFonts.contains(fontName)
    }
    
    func getAllRegisteredFonts() -> [String] {
        return Array(registeredFonts)
    }
    
    // Optional: Preload fonts to ensure they're available
    func preloadFonts() {
        for fontName in fontNames {
            _ = NSFont(name: fontName, size: 12) // This will trigger font loading if not already loaded
        }
    }
}