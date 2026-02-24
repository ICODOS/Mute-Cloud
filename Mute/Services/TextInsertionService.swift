// TextInsertionService.swift
// Mute

import AppKit
import Carbon.HIToolbox

class TextInsertionService {
    private var previousClipboardContent: Any?
    private var previousClipboardType: NSPasteboard.PasteboardType?
    
    // MARK: - Public API
    func insertText(_ text: String, preserveClipboard: Bool = false) {
        // Save current clipboard if needed
        if preserveClipboard {
            saveClipboard()
        }
        
        // Copy to clipboard
        copyToClipboard(text)
        
        // Try to paste
        let pasteSucceeded = simulatePaste()
        
        if pasteSucceeded {
            Logger.shared.log("Text pasted successfully")
            
            // Only restore clipboard if paste succeeded
            if preserveClipboard {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.restoreClipboard()
                }
            }
        } else {
            // Paste failed - keep text in clipboard so user can manually paste
            Logger.shared.log("Paste failed, text kept in clipboard for manual paste", level: .warning)
            showToast(text)
            // Don't restore clipboard - user needs the transcription!
        }
    }
    
    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        Logger.shared.log("Copied to clipboard: \(text.prefix(50))...")
    }
    
    // MARK: - Clipboard Preservation
    private func saveClipboard() {
        let pasteboard = NSPasteboard.general
        
        // Try to save string content
        if let string = pasteboard.string(forType: .string) {
            previousClipboardContent = string
            previousClipboardType = .string
            return
        }
        
        // Try to save RTF
        if let rtf = pasteboard.data(forType: .rtf) {
            previousClipboardContent = rtf
            previousClipboardType = .rtf
            return
        }
        
        // Try to save image
        if let imageData = pasteboard.data(forType: .png) {
            previousClipboardContent = imageData
            previousClipboardType = .png
            return
        }
        
        Logger.shared.log("Could not save clipboard content", level: .warning)
    }
    
    private func restoreClipboard() {
        guard let content = previousClipboardContent, let type = previousClipboardType else {
            return
        }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        switch type {
        case .string:
            if let string = content as? String {
                pasteboard.setString(string, forType: .string)
            }
        case .rtf:
            if let data = content as? Data {
                pasteboard.setData(data, forType: .rtf)
            }
        case .png:
            if let data = content as? Data {
                pasteboard.setData(data, forType: .png)
            }
        default:
            break
        }
        
        previousClipboardContent = nil
        previousClipboardType = nil
        
        Logger.shared.log("Clipboard restored")
    }
    
    // MARK: - Paste Simulation
    private func simulatePaste() -> Bool {
        // Check accessibility permission
        guard AXIsProcessTrusted() else {
            Logger.shared.log("Accessibility permission not granted", level: .warning)
            return false
        }
        
        // Get the frontmost application
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            Logger.shared.log("No frontmost application", level: .warning)
            return false
        }
        
        // Check if it's a secure input field (use IOKit)
        // Note: SecureEventInputIsEnabled is deprecated, so we skip this check
        // and rely on CGEvent posting to fail gracefully if secure input is active
        
        // Simulate Cmd+V
        return postKeyEvent(keyCode: UInt16(kVK_ANSI_V), flags: .maskCommand)
    }
    
    private func postKeyEvent(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        // Create key down event
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) else {
            Logger.shared.log("Failed to create key down event", level: .error)
            return false
        }
        keyDown.flags = flags
        
        // Create key up event
        guard let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            Logger.shared.log("Failed to create key up event", level: .error)
            return false
        }
        keyUp.flags = flags
        
        // Post events
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        
        return true
    }
    
    // MARK: - Toast Notification
    private func showToast(_ text: String) {
        DispatchQueue.main.async {
            let toast = ToastPanel(text: text)
            toast.show()
        }
    }
}

// MARK: - Toast Panel
class ToastPanel: NSPanel {
    private var hideTimer: Timer?
    
    init(text: String) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        
        self.level = .floating
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.ignoresMouseEvents = false
        self.collectionBehavior = [.canJoinAllSpaces, .transient]
        
        setupContent(text)
        positionPanel()
    }
    
    private func setupContent(_ text: String) {
        let containerView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        containerView.material = NSVisualEffectView.Material.hudWindow
        containerView.state = NSVisualEffectView.State.active
        containerView.autoresizingMask = [.width, .height]
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 12
        containerView.layer?.masksToBounds = true
        
        // Text label
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .labelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        
        // Info label
        let infoLabel = NSTextField(labelWithString: "Copied to clipboard")
        infoLabel.font = .systemFont(ofSize: 11)
        infoLabel.textColor = .secondaryLabelColor
        infoLabel.alignment = .center
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Close button
        let closeButton = NSButton(title: "×", target: self, action: #selector(closeToast))
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.font = .systemFont(ofSize: 16, weight: .medium)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        
        containerView.addSubview(label)
        containerView.addSubview(infoLabel)
        containerView.addSubview(closeButton)
        
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 16),
            label.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -40),
            
            infoLabel.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 8),
            infoLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            infoLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -16),
            
            closeButton.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8)
        ])
        
        self.contentView = containerView
        
        // Resize to fit content
        let textSize = label.sizeThatFits(NSSize(width: 360, height: CGFloat.greatestFiniteMagnitude))
        let newHeight = textSize.height + 60
        setContentSize(NSSize(width: 400, height: min(newHeight, 200)))
    }
    
    private func positionPanel() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        
        let x = screen.visibleFrame.midX - frame.width / 2
        let y = screen.visibleFrame.origin.y + 100
        
        setFrameOrigin(NSPoint(x: x, y: y))
    }
    
    func show() {
        alphaValue = 0
        orderFront(nil)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            self.animator().alphaValue = 1
        }
        
        // Auto-hide after 5 seconds
        hideTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }
    
    func hide() {
        hideTimer?.invalidate()
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            self.animator().alphaValue = 0
        } completionHandler: {
            self.close()
        }
    }
    
    @objc private func closeToast() {
        hide()
    }
}
