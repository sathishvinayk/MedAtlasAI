//file windowmanager.swift
import Cocoa

class WindowManager {
    private var panelWindow: NSWindow? // <-- store a reference to the window
    private var settingsPopover: NSPopover?  // store the active popover

    func createWindow(delegate: NSTextViewDelegate?) -> (window: TransparentPanel, contentView: NSView) {
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let windowWidth: CGFloat = 1000
        let windowHeight: CGFloat = 800
        let windowRect = NSRect(x: screenFrame.midX - windowWidth / 2, y: screenFrame.midY - windowHeight / 2, width: windowWidth, height: windowHeight)

        let window = TransparentPanel(
            contentRect: windowRect, 
            styleMask: [.titled, .resizable, .fullSizeContentView, .closable, .miniaturizable],
            backing: .buffered, 
            defer: false
        )
        self.panelWindow = window

        window.standardWindowButton(.closeButton)?.target = self
        window.standardWindowButton(.closeButton)?.action = #selector(closeApp)
        window.isOpaque = false
        window.hasShadow = false
        window.backgroundColor = .appBackground
        window.appearance = NSAppearance(named: .darkAqua)
        window.level = .floating
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .transient, .stationary]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // window.sharingType = .none
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        window.hidesOnDeactivate = false
        window.isMovableByWindowBackground = true
        window.styleMask.insert(.resizable)

        DispatchQueue.main.async {
            for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                if let btn = window.standardWindowButton(type) {
                    var frame = btn.frame
                    frame.origin.x += 4
                    frame.origin.y -= 4
                    btn.frame = frame
                }
            }
        }

        let containerView = NSView(frame: window.contentView!.bounds)
        containerView.autoresizingMask = [.width, .height]
        // blur.material = .underWindowBackground
        // blur.blendingMode = .behindWindow
        // containerView.state = .active
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 8
        containerView.layer?.masksToBounds = true
        // containerView.layer?.backgroundColor = NSColor.appBackground.cgColor  // Force your color

        let gearButton = NSButton(
            image: NSImage(systemSymbolName: "dial.min", accessibilityDescription: nil)!,
            target: self, 
            action: #selector(showTransparencyMenu(_:)) // 👈 change here
        )

        gearButton.bezelStyle = .inline
        gearButton.isBordered = false
        gearButton.imageScaling = .scaleProportionallyUpOrDown
        gearButton.translatesAutoresizingMaskIntoConstraints = false
        gearButton.setButtonType(.momentaryChange)
        
        window.contentView = containerView
        window.contentView?.addSubview(gearButton)
        
        let accessoryView = NSView()
        accessoryView.translatesAutoresizingMaskIntoConstraints = false
        accessoryView.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = accessoryView
        accessory.layoutAttribute = .top
        window.addTitlebarAccessoryViewController(accessory)

        if let contentView = window.contentView {
            NSLayoutConstraint.activate([
                gearButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
                gearButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
                gearButton.widthAnchor.constraint(equalToConstant: 18),
                gearButton.heightAnchor.constraint(equalToConstant: 18),
            ])
        }
        
        return (window, containerView)   
    }

    @objc func showTransparencyMenu(_ sender: NSButton) {
        let menu = NSMenu()
        
        let options = ["100%", "90%", "80%", "70%", "60%", "50%"]
        let saved = UserDefaults.standard.string(forKey: "SelectedTransparency") ?? "100%"

        for option in options {
            let item = NSMenuItem(title: option, action: #selector(transparencyMenuItemClicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option

            if option == saved {
                item.state = .on
            }

            menu.addItem(item)
        }

        // Show the menu below the button
        NSMenu.popUpContextMenu(menu, with: NSApp.currentEvent!, for: sender)
    }

    @objc func transparencyMenuItemClicked(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        
        UserDefaults.standard.set(value, forKey: "SelectedTransparency")
        applyTransparency(percentString: value)
    }


    func applyTransparency(percentString: String) {
        guard let window = NSApp.windows.first else { return }

        let number = percentString.replacingOccurrences(of: "%", with: "")
        if let percent = Double(number) {
            window.alphaValue = percent / 100.0
        }
    }

    @objc func closeApp() {
        NSApp.terminate(nil)
    }
}
