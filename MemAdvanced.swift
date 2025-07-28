// import Cocoa
// import CoreVideo
// import QuartzCore

// // MARK: - Layout Constants
// struct LayoutConstants {
//     static let maxBubbleWidthRatio: CGFloat = 0.65
//     static let bubblePadding: CGFloat = 8
//     static let bubbleMargin: CGFloat = 16
//     static let codeFontSize: CGFloat = 13
//     static let textFontSize: CGFloat = 14
//     static let inlineCodeBackgroundLight = NSColor(white: 0.95, alpha: 1)
//     static let inlineCodeBackgroundDark = NSColor(white: 0.2, alpha: 1)
// }

// // MARK: - DisplayLink Abstraction
// final class DisplayLink {
//     private var timer: Timer?
//     private var cvLink: CVDisplayLink?
//     private var callback: (() -> Void)?
//     private var caDisplayLink: Any?
    
//     init(callback: @escaping () -> Void) {
//         self.callback = callback
//         setupDisplayLink()
//     }
    
//     private func setupDisplayLink() {
//         if #available(macOS 15.0, *) {
//             setupCADisplayLink()
//         } else {
//             setupCVDisplayLink()
//         }
//     }
    
//     @available(macOS 15.0, *)
//     private func setupCADisplayLink() {
//         if let window = NSApplication.shared.mainWindow {
//             caDisplayLink = window.displayLink(target: self, selector: #selector(displayLinkCallback))
//             (caDisplayLink as? CADisplayLink)?.add(to: .current, forMode: .default)
//             return
//         }
        
//         if let screen = NSScreen.main {
//             caDisplayLink = screen.displayLink(target: self, selector: #selector(displayLinkCallback))
//             (caDisplayLink as? CADisplayLink)?.add(to: .current, forMode: .default)
//             return
//         }
        
//         startFallbackTimer()
//     }
    
//     private func setupCVDisplayLink() {
//         var link: CVDisplayLink?
//         let status = CVDisplayLinkCreateWithActiveCGDisplays(&link)
//         guard status == kCVReturnSuccess, let displayLink = link else {
//             startFallbackTimer()
//             return
//         }
        
//         cvLink = displayLink
//         caDisplayLink = displayLink
        
//         let callback: @convention(c) (CVDisplayLink, UnsafePointer<CVTimeStamp>,
//                                     UnsafePointer<CVTimeStamp>, CVOptionFlags,
//                                     UnsafeMutablePointer<CVOptionFlags>,
//                                     UnsafeMutableRawPointer?) -> CVReturn = {
//             _, _, _, _, _, context in
//             let unmanaged = Unmanaged<DisplayLink>.fromOpaque(context!)
//             unmanaged.takeUnretainedValue().callback?()
//             return kCVReturnSuccess
//         }
        
//         CVDisplayLinkSetOutputCallback(displayLink, callback, Unmanaged.passUnretained(self).toOpaque())
//         CVDisplayLinkStart(displayLink)
//     }
    
//     @objc private func displayLinkCallback(_ sender: Any) {
//         callback?()
//     }
    
//     private func startFallbackTimer() {
//         timer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
//             self?.callback?()
//         }
//     }
    
//     func invalidate() {
//         if let link = cvLink {
//             CVDisplayLinkStop(link)
//             cvLink = nil
//         }
        
//         if #available(macOS 15.0, *) {
//             (caDisplayLink as? CADisplayLink)?.invalidate()
//         }
        
//         timer?.invalidate()
//         timer = nil
//         caDisplayLink = nil
//     }
    
//     deinit {
//         invalidate()
//     }
// }

// // MARK: - Streaming Text Controller
// final class StreamingTextController {
//     private var queue = [NSAttributedString]()
//     private let textView: NSTextView
//     private var displayLink: DisplayLink?
//     private let lock = NSLock()
//     private var hasPendingUpdates = false
//     private var lastRenderTime: CFTimeInterval = 0
//     private let minFrameInterval: CFTimeInterval = 1.0 / 60.0
    
//     init(textView: NSTextView) {
//         self.textView = textView
//         configureTextView()
//         self.displayLink = DisplayLink { [weak self] in
//             self?.processPendingUpdates()
//         }
//     }
    
//     private func configureTextView() {
//         textView.isEditable = false
//         textView.drawsBackground = false
//         textView.textContainerInset = NSSize(width: 6, height: 6)
        
//         if textView.textStorage == nil {
//             textView.layoutManager?.replaceTextStorage(NSTextStorage())
//         }
//     }
    
//     func appendStreamingText(_ string: String, attributes: [NSAttributedString.Key: Any]) {
//         let attributed = NSAttributedString(string: string, attributes: attributes)
//         lock.lock()
//         queue.append(attributed)
//         hasPendingUpdates = true
//         lock.unlock()
//     }
    
//     private func processPendingUpdates() {
//         let currentTime = CACurrentMediaTime()
//         if currentTime - lastRenderTime < minFrameInterval { return }
        
//         var toRender: [NSAttributedString] = []
//         lock.lock()
//         if hasPendingUpdates {
//             toRender = queue
//             queue.removeAll()
//             hasPendingUpdates = false
//         }
//         lock.unlock()
        
//         guard !toRender.isEmpty else { return }
        
//         DispatchQueue.main.async {
//             let storage = self.textView.textStorage ?? NSTextStorage()
//             for str in toRender {
//                 storage.append(str)
//             }
            
//             if self.textView.textStorage == nil {
//                 self.textView.layoutManager?.replaceTextStorage(storage)
//             }
            
//             self.textView.scrollRangeToVisible(NSRange(location: self.textView.string.count, length: 0))
//             self.lastRenderTime = currentTime
//         }
//     }
    
//     deinit {
//         displayLink?.invalidate()
//     }
// }

// // MARK: - Code Block View
// final class CodeBlockView: NSView {
//     private let textView = NSTextView()
//     private let streamingController: StreamingTextController
//     private var heightConstraint: NSLayoutConstraint?
//     private var observer: NSObjectProtocol?
    
//     init(code: String, maxWidth: CGFloat) {
//         self.streamingController = StreamingTextController(textView: textView)
//         super.init(frame: .zero)
//         setupTextView(maxWidth: maxWidth)
//         streamingController.appendStreamingText(code, attributes: [
//             .font: NSFont.monospacedSystemFont(ofSize: LayoutConstants.codeFontSize, weight: .regular),
//             .foregroundColor: NSColor.textColor
//         ])
//         setupObserver()
//         updateHeight()
//     }
    
//     private func setupTextView(maxWidth: CGFloat) {
//         textView.isEditable = false
//         textView.drawsBackground = true
//         textView.backgroundColor = NSColor.textBackgroundColor
//         textView.textContainerInset = NSSize(width: 8, height: 8)
//         textView.font = .monospacedSystemFont(ofSize: LayoutConstants.codeFontSize, weight: .regular)
//         textView.textColor = .textColor
//         textView.translatesAutoresizingMaskIntoConstraints = false
//         textView.textContainer?.widthTracksTextView = true
//         textView.textContainer?.lineFragmentPadding = 0
//         textView.isHorizontallyResizable = false
//         textView.isVerticallyResizable = true
        
//         addSubview(textView)
//         NSLayoutConstraint.activate([
//             textView.leadingAnchor.constraint(equalTo: leadingAnchor),
//             textView.trailingAnchor.constraint(equalTo: trailingAnchor),
//             textView.topAnchor.constraint(equalTo: topAnchor),
//             textView.bottomAnchor.constraint(equalTo: bottomAnchor),
//             widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth)
//         ])
        
//         wantsLayer = true
//         layer?.cornerRadius = 6
//         layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        
//         heightConstraint = heightAnchor.constraint(equalToConstant: 1)
//         heightConstraint?.isActive = true
//     }
    
//     private func setupObserver() {
//         observer = NotificationCenter.default.addObserver(
//             forName: NSTextView.didChangeNotification,
//             object: textView,
//             queue: .main
//         ) { [weak self] _ in
//             self?.updateHeight()
//         }
//     }
    
//     private func updateHeight() {
//         guard let container = textView.textContainer,
//               let layoutManager = textView.layoutManager else { return }
        
//         layoutManager.ensureLayout(for: container)
//         let usedRect = layoutManager.usedRect(for: container)
//         let totalHeight = ceil(usedRect.height) + textView.textContainerInset.height * 2
//         heightConstraint?.constant = totalHeight
//     }
    
//     deinit {
//         if let observer = observer {
//             NotificationCenter.default.removeObserver(observer)
//         }
//     }
    
//     required init?(coder: NSCoder) {
//         fatalError("init(coder:) has not been implemented")
//     }
// }

// final class TextBlockView: NSView {
//     private let textView = NSTextView()
//     private let controller: StreamingTextController
//     private var heightConstraint: NSLayoutConstraint?
    
//     init(maxWidth: CGFloat) {
//         self.controller = StreamingTextController(textView: textView)
//         super.init(frame: .zero)
//         setupTextView(maxWidth: maxWidth)
//     }
    
//     private func setupTextView(maxWidth: CGFloat) {
//         textView.isEditable = false
//         textView.drawsBackground = false
//         textView.textContainerInset = NSSize(width: 8, height: 8)
//         textView.font = .systemFont(ofSize: LayoutConstants.textFontSize)
//         textView.textColor = .labelColor
//         textView.translatesAutoresizingMaskIntoConstraints = false
//         textView.textContainer?.widthTracksTextView = true
//         textView.textContainer?.lineFragmentPadding = 0
//         textView.isHorizontallyResizable = false
//         textView.isVerticallyResizable = true
        
//         addSubview(textView)
//         NSLayoutConstraint.activate([
//             textView.leadingAnchor.constraint(equalTo: leadingAnchor),
//             textView.trailingAnchor.constraint(equalTo: trailingAnchor),
//             textView.topAnchor.constraint(equalTo: topAnchor),
//             textView.bottomAnchor.constraint(equalTo: bottomAnchor),
//             widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth)
//         ])
        
//         // Initial height constraint
//         heightConstraint = heightAnchor.constraint(equalToConstant: 1)
//         heightConstraint?.isActive = true
//     }
    
//     func appendStreamingText(_ text: String, attributes: [NSAttributedString.Key: Any]) {
//         controller.appendStreamingText(text, attributes: attributes)
//         updateHeight()
//     }
    
//     private func updateHeight() {
//         guard let container = textView.textContainer,
//               let layoutManager = textView.layoutManager else { return }
        
//         layoutManager.ensureLayout(for: container)
//         let usedRect = layoutManager.usedRect(for: container)
//         let totalHeight = ceil(usedRect.height) + textView.textContainerInset.height * 2
//         heightConstraint?.constant = totalHeight
//     }
    
//     override func layout() {
//         super.layout()
//         updateHeight()
//     }
    
//     required init?(coder: NSCoder) {
//         fatalError("init(coder:) has not been implemented")
//     }
// }

// // MARK: - Message Segment
// enum MessageSegment {
//     case text(String)
//     case inlineCode(String)
//     case codeBlock(String)
// }

// // MARK: - Message Renderer
// enum MessageRenderer {
//     static func renderMessage(_ message: String, isUser: Bool) -> (NSView, NSView) {
//         let maxWidth = calculateMaxWidth()
//         let bubble = NSStackView()
//         bubble.orientation = .vertical
//         bubble.spacing = 6
//         bubble.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
//         bubble.wantsLayer = true
//         bubble.layer?.backgroundColor = (isUser ? NSColor.systemBlue : NSColor.controlBackgroundColor).cgColor
//         bubble.layer?.cornerRadius = 12
        
//         let container = NSView()
//         container.addSubview(bubble)
//         bubble.translatesAutoresizingMaskIntoConstraints = false
//         NSLayoutConstraint.activate([
//             bubble.topAnchor.constraint(equalTo: container.topAnchor),
//             bubble.bottomAnchor.constraint(equalTo: container.bottomAnchor),
//             isUser ?
//                 bubble.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -LayoutConstants.bubbleMargin)
//               : bubble.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: LayoutConstants.bubbleMargin),
//             bubble.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth)
//         ])
        
//         let segments = splitMarkdown(message)
//         let textBlock = TextBlockView(maxWidth: maxWidth - 24) // Account for bubble padding
        
//         for segment in segments {
//             switch segment {
//             case .text(let str):
//                 textBlock.appendStreamingText(str, attributes: [
//                     .font: NSFont.systemFont(ofSize: LayoutConstants.textFontSize),
//                     .foregroundColor: NSColor.labelColor
//                 ])
//             case .inlineCode(let code):
//                 let bgColor = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
//                     ? LayoutConstants.inlineCodeBackgroundDark
//                     : LayoutConstants.inlineCodeBackgroundLight
//                 textBlock.appendStreamingText(code, attributes: [
//                     .font: NSFont.monospacedSystemFont(ofSize: LayoutConstants.codeFontSize, weight: .medium),
//                     .backgroundColor: bgColor,
//                     .foregroundColor: NSColor.labelColor
//                 ])
//             case .codeBlock(let code):
//                 bubble.addArrangedSubview(textBlock)
//                 bubble.addArrangedSubview(CodeBlockView(code: code, maxWidth: maxWidth - 24))
//                 return (container, bubble)
//             }
//         }
        
//         bubble.addArrangedSubview(textBlock)
//         return (container, bubble)
//     }
    
//     private static func calculateMaxWidth() -> CGFloat {
//         let screenWidth = NSScreen.main?.visibleFrame.width ?? 800
//         return min(screenWidth * LayoutConstants.maxBubbleWidthRatio, 800)
//     }
    
//     static func splitMarkdown(_ message: String) -> [MessageSegment] {
//         var result: [MessageSegment] = []
//         let lines = message.components(separatedBy: "\n")
//         var isCodeBlock = false
//         var codeBuffer = ""
        
//         for line in lines {
//             if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
//                 if isCodeBlock {
//                     result.append(.codeBlock(codeBuffer))
//                     codeBuffer = ""
//                 }
//                 isCodeBlock.toggle()
//                 continue
//             }
            
//             if isCodeBlock {
//                 codeBuffer += line + "\n"
//             } else {
//                 var currentText = ""
//                 var isInInlineCode = false
//                 var inlineBuffer = ""
                
//                 for char in line {
//                     if char == "`" {
//                         if isInInlineCode {
//                             result.append(.text(currentText))
//                             result.append(.inlineCode(inlineBuffer))
//                             currentText = ""
//                             inlineBuffer = ""
//                         }
//                         isInInlineCode.toggle()
//                     } else {
//                         if isInInlineCode {
//                             inlineBuffer.append(char)
//                         } else {
//                             currentText.append(char)
//                         }
//                     }
//                 }
                
//                 if !currentText.isEmpty {
//                     result.append(.text(currentText + "\n"))
//                 }
//             }
//         }
        
//         return result
//     }
// }
