// AppDelegate.swift
// Mute

import AppKit
import SwiftUI
import Carbon.HIToolbox

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayPanel: OverlayPanel?
    private var settingsWindow: NSWindow?
    private static var modesOverlayHideWorkItem: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Show app in Dock (regular app, not menu-bar-only)
        NSApp.setActivationPolicy(.regular)

        // Setup global hotkeys via HotkeyService (uses Carbon registration for standard combos)
        HotkeyService.shared.setupAllHotkeys()

        // Setup overlay panel
        setupOverlayPanel()

        // Request microphone permission early
        Task {
            await AppState.shared.permissionManager.requestMicrophonePermission()
        }

        // Activate app and bring to front
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.activate(ignoringOtherApps: true)
        }

        // Listen for hotkey changes — delegate to HotkeyService
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotkeyDidChange),
            name: .hotkeyDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(stopHotkeyDidChange),
            name: .stopHotkeyDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(modesHotkeyDidChange),
            name: .modesHotkeyDidChange,
            object: nil
        )

        // Listen for settings open requests
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openSettingsWindow),
            name: .openSettingsRequested,
            object: nil
        )
    }

    @objc private func hotkeyDidChange() {
        HotkeyService.shared.reconfigureToggleRecording()
    }

    @objc private func stopHotkeyDidChange() {
        HotkeyService.shared.reconfigureStopHotkey()
    }

    @objc private func modesHotkeyDidChange() {
        HotkeyService.shared.reconfigureModesHotkey()
    }

    /// Opens the Settings window by programmatically invoking the Settings menu item.
    @objc private func openSettingsWindow() {
        // Close any MenuBarExtra popup windows first (they can block settings from appearing)
        for window in NSApp.windows {
            let className = String(describing: type(of: window))
            if className.contains("MenuBarExtra") || className.contains("_NSPopover") {
                window.close()
            }
        }

        // Activate app and open settings with a slight delay for proper window handling
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            // Find and invoke the Settings menu item action
            if let mainMenu = NSApp.mainMenu,
               let appMenuItem = mainMenu.items.first,
               let appMenu = appMenuItem.submenu {
                for item in appMenu.items {
                    let title = item.title.lowercased()
                    if title.contains("settings") || title.contains("preferences") {
                        if let action = item.action {
                            NSApp.sendAction(action, to: item.target, from: item)
                        }
                        return
                    }
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Clean up overlay timer and panel
        Self.modesOverlayHideWorkItem?.cancel()
        Self.modesOverlayHideWorkItem = nil
        overlayPanel?.close()

        // Clean up all hotkey registrations
        HotkeyService.shared.teardownAllHotkeys()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Don't quit when window is closed - keep running in menu bar
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Logger.shared.log("Dock icon clicked, hasVisibleWindows: \(flag)")
        showMainWindow()
        return true
    }

    // Also handle when app is activated (clicked in Dock)
    func applicationDidBecomeActive(_ notification: Notification) {
        // Re-setup modes hotkey global monitor if accessibility was granted after initial setup
        HotkeyService.shared.reSetupModesIfNeeded()

        let visibleWindows = NSApp.windows.filter {
            $0.isVisible && $0.level == .normal && !$0.className.contains("MenuBarExtra")
        }
        if visibleWindows.isEmpty {
            showMainWindow()
        }
    }

    func showMainWindow() {
        if let existingWindow = NSApp.windows.first(where: { $0.title == "Mute App" && $0.isVisible }) {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        createWindowManually()
    }

    private func createWindowManually() {
        let mainView = MainAppView()
            .environmentObject(AppState.shared)

        let hostingController = NSHostingController(rootView: mainView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Mute App"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 520, height: 760))
        window.center()
        window.isReleasedWhenClosed = false

        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        Logger.shared.log("Main app window opened")
    }

    private func setupOverlayPanel() {
        overlayPanel = OverlayPanel()
        AppState.shared.overlayPanel = overlayPanel
    }

    // MARK: - Hotkey Action Callbacks (called by HotkeyService)

    static func handleHotkeyAction() {
        Task { @MainActor in
            let state = AppState.shared

            // Don't interfere with Capture to Notes mode
            if state.isCaptureMode {
                Logger.shared.log("Hotkey pressed during Capture to Notes mode - ignoring")
                return
            }

            switch state.recordingState {
            case .idle:
                await state.startRecording()
            case .recording:
                await state.stopRecording()
            case .processing:
                Logger.shared.log("Hotkey pressed during processing - ignoring")
            case .done, .error:
                await state.startRecording()
            }
        }
    }

    static func handleStopHotkeyAction() {
        Task { @MainActor in
            let state = AppState.shared

            // Don't interfere with Capture to Notes mode
            if state.isCaptureMode {
                Logger.shared.log("Stop hotkey pressed during Capture to Notes mode - ignoring")
                return
            }

            if state.recordingState == .recording {
                Logger.shared.log("Stop hotkey pressed - cancelling recording")
                state.cancelRecording()
            }
        }
    }

    static func handleModesHotkeyAction() {
        Task { @MainActor in
            let config = ModesHotkeyConfig.load()
            let modeName = TranscriptionModeManager.shared.cycleToNextDictationMode()
            Logger.shared.log("Modes hotkey pressed (\(config.displayString)) - cycled to mode: \(modeName)")
            AppState.shared.overlayPanel?.show(state: .modeChanged, text: modeName)

            // Cancel any pending hide from a previous press
            modesOverlayHideWorkItem?.cancel()

            let workItem = DispatchWorkItem {
                AppState.shared.overlayPanel?.hide()
            }
            modesOverlayHideWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
        }
    }
}

// MARK: - Hotkey Configuration
struct HotkeyConfig: Codable {
    var keyCode: UInt16
    var command: Bool
    var option: Bool
    var control: Bool
    var shift: Bool
    var isModifierOnly: Bool  // True if hotkey is just a modifier key (e.g., right shift)

    static let defaultConfig = HotkeyConfig(
        keyCode: UInt16(kVK_F5),  // F5 key
        command: false,
        option: false,
        control: false,
        shift: false,
        isModifierOnly: false
    )

    static func load() -> HotkeyConfig {
        if let data = UserDefaults.standard.data(forKey: "hotkeyConfig"),
           let config = try? JSONDecoder().decode(HotkeyConfig.self, from: data) {
            return config
        }
        return defaultConfig
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "hotkeyConfig")
            NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
        }
    }

    var displayString: String {
        if isModifierOnly {
            return modifierKeyName
        }

        var parts: [String] = []
        if control { parts.append("⌃") }
        if option { parts.append("⌥") }
        if shift { parts.append("⇧") }
        if command { parts.append("⌘") }
        parts.append(keyName)
        return parts.joined()
    }

    private var modifierKeyName: String {
        switch keyCode {
        case UInt16(kVK_RightShift): return "Right ⇧"
        case UInt16(kVK_Shift): return "Left ⇧"
        case UInt16(kVK_RightCommand): return "Right ⌘"
        case UInt16(kVK_Command): return "Left ⌘"
        case UInt16(kVK_RightOption): return "Right ⌥"
        case UInt16(kVK_Option): return "Left ⌥"
        case UInt16(kVK_RightControl): return "Right ⌃"
        case UInt16(kVK_Control): return "Left ⌃"
        case UInt16(kVK_Function): return "Fn"
        case UInt16(kVK_CapsLock): return "⇪ Caps"
        default: return "Modifier"
        }
    }

    var keyName: String {
        let keyNames: [UInt16: String] = [
            UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3",
            UInt16(kVK_F4): "F4", UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6",
            UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8", UInt16(kVK_F9): "F9",
            UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12",
            UInt16(kVK_F13): "F13", UInt16(kVK_F14): "F14", UInt16(kVK_F15): "F15",
            UInt16(kVK_F16): "F16", UInt16(kVK_F17): "F17", UInt16(kVK_F18): "F18",
            UInt16(kVK_F19): "F19", UInt16(kVK_F20): "F20",
            UInt16(kVK_Space): "Space", UInt16(kVK_Return): "Return",
            UInt16(kVK_Tab): "Tab", UInt16(kVK_Delete): "Delete",
            UInt16(kVK_ForwardDelete): "Fwd Del",
            UInt16(kVK_Escape): "Esc", UInt16(kVK_Home): "Home",
            UInt16(kVK_End): "End", UInt16(kVK_PageUp): "PgUp",
            UInt16(kVK_PageDown): "PgDn",
            UInt16(kVK_LeftArrow): "←", UInt16(kVK_RightArrow): "→",
            UInt16(kVK_UpArrow): "↑", UInt16(kVK_DownArrow): "↓",
            // Letters
            UInt16(kVK_ANSI_A): "A", UInt16(kVK_ANSI_B): "B", UInt16(kVK_ANSI_C): "C",
            UInt16(kVK_ANSI_D): "D", UInt16(kVK_ANSI_E): "E", UInt16(kVK_ANSI_F): "F",
            UInt16(kVK_ANSI_G): "G", UInt16(kVK_ANSI_H): "H", UInt16(kVK_ANSI_I): "I",
            UInt16(kVK_ANSI_J): "J", UInt16(kVK_ANSI_K): "K", UInt16(kVK_ANSI_L): "L",
            UInt16(kVK_ANSI_M): "M", UInt16(kVK_ANSI_N): "N", UInt16(kVK_ANSI_O): "O",
            UInt16(kVK_ANSI_P): "P", UInt16(kVK_ANSI_Q): "Q", UInt16(kVK_ANSI_R): "R",
            UInt16(kVK_ANSI_S): "S", UInt16(kVK_ANSI_T): "T", UInt16(kVK_ANSI_U): "U",
            UInt16(kVK_ANSI_V): "V", UInt16(kVK_ANSI_W): "W", UInt16(kVK_ANSI_X): "X",
            UInt16(kVK_ANSI_Y): "Y", UInt16(kVK_ANSI_Z): "Z",
            // Numbers
            UInt16(kVK_ANSI_0): "0", UInt16(kVK_ANSI_1): "1", UInt16(kVK_ANSI_2): "2",
            UInt16(kVK_ANSI_3): "3", UInt16(kVK_ANSI_4): "4", UInt16(kVK_ANSI_5): "5",
            UInt16(kVK_ANSI_6): "6", UInt16(kVK_ANSI_7): "7", UInt16(kVK_ANSI_8): "8",
            UInt16(kVK_ANSI_9): "9",
            // Punctuation
            UInt16(kVK_ANSI_Minus): "-", UInt16(kVK_ANSI_Equal): "=",
            UInt16(kVK_ANSI_LeftBracket): "[", UInt16(kVK_ANSI_RightBracket): "]",
            UInt16(kVK_ANSI_Semicolon): ";", UInt16(kVK_ANSI_Quote): "'",
            UInt16(kVK_ANSI_Comma): ",", UInt16(kVK_ANSI_Period): ".",
            UInt16(kVK_ANSI_Slash): "/", UInt16(kVK_ANSI_Backslash): "\\",
            UInt16(kVK_ANSI_Grave): "`",
        ]
        return keyNames[keyCode] ?? "Key \(keyCode)"
    }
}

// MARK: - Notification Names
extension Notification.Name {
    // MARK: Hotkey Notifications
    /// Posted when the global hotkey configuration changes.
    static let hotkeyDidChange = Notification.Name("hotkeyDidChange")
    /// Posted when the stop hotkey configuration changes.
    static let stopHotkeyDidChange = Notification.Name("stopHotkeyDidChange")
    /// Posted when the modes hotkey configuration changes.
    static let modesHotkeyDidChange = Notification.Name("modesHotkeyDidChange")

    // MARK: Settings Notifications
    /// Posted to request opening the Settings window.
    static let openSettingsRequested = Notification.Name("openSettingsRequested")
    /// Posted to request switching to a specific Settings tab.
    /// UserInfo contains "tab" key with `SettingsTab` value.
    static let settingsTabRequested = Notification.Name("settingsTabRequested")
}

// MARK: - Modes Hotkey Configuration
/// Configuration for the hotkey that cycles dictation modes.
/// Supports single keys, key+modifiers, modifier-only, or two-key combinations.
struct ModesHotkeyConfig: Codable {
    var keyCode: UInt16
    var secondKeyCode: UInt16  // For two-key combos (e.g., Left⇧ + Right⇧)
    var command: Bool
    var option: Bool
    var control: Bool
    var shift: Bool
    var isModifierOnly: Bool
    var isTwoKeyCombo: Bool

    /// keyCode of 0 means no hotkey is configured
    var isEnabled: Bool {
        keyCode != 0
    }

    static let defaultConfig = ModesHotkeyConfig(
        keyCode: 0,  // No hotkey by default
        secondKeyCode: 0,
        command: false,
        option: false,
        control: false,
        shift: false,
        isModifierOnly: false,
        isTwoKeyCombo: false
    )

    static func load() -> ModesHotkeyConfig {
        if let data = UserDefaults.standard.data(forKey: "modesHotkeyConfig"),
           let config = try? JSONDecoder().decode(ModesHotkeyConfig.self, from: data) {
            return config
        }
        return defaultConfig
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "modesHotkeyConfig")
            NotificationCenter.default.post(name: .modesHotkeyDidChange, object: nil)
        }
    }

    static func clear() {
        defaultConfig.save()
    }

    var displayString: String {
        guard isEnabled else { return "None" }

        if isTwoKeyCombo {
            return "\(modifierKeyName(for: keyCode)) + \(modifierKeyName(for: secondKeyCode))"
        }

        if isModifierOnly {
            return modifierKeyName(for: keyCode)
        }

        var parts: [String] = []
        if control { parts.append("⌃") }
        if option { parts.append("⌥") }
        if shift { parts.append("⇧") }
        if command { parts.append("⌘") }
        parts.append(keyName(for: keyCode))
        return parts.joined()
    }

    func modifierKeyName(for code: UInt16) -> String {
        switch code {
        case UInt16(kVK_RightShift): return "Right ⇧"
        case UInt16(kVK_Shift): return "Left ⇧"
        case UInt16(kVK_RightCommand): return "Right ⌘"
        case UInt16(kVK_Command): return "Left ⌘"
        case UInt16(kVK_RightOption): return "Right ⌥"
        case UInt16(kVK_Option): return "Left ⌥"
        case UInt16(kVK_RightControl): return "Right ⌃"
        case UInt16(kVK_Control): return "Left ⌃"
        case UInt16(kVK_Function): return "Fn"
        case UInt16(kVK_CapsLock): return "⇪ Caps"
        default: return "Modifier"
        }
    }

    func keyName(for code: UInt16) -> String {
        let keyNames: [UInt16: String] = [
            UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3",
            UInt16(kVK_F4): "F4", UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6",
            UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8", UInt16(kVK_F9): "F9",
            UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12",
            UInt16(kVK_F13): "F13", UInt16(kVK_F14): "F14", UInt16(kVK_F15): "F15",
            UInt16(kVK_F16): "F16", UInt16(kVK_F17): "F17", UInt16(kVK_F18): "F18",
            UInt16(kVK_F19): "F19", UInt16(kVK_F20): "F20",
            UInt16(kVK_Space): "Space", UInt16(kVK_Return): "Return",
            UInt16(kVK_Tab): "Tab", UInt16(kVK_Delete): "Delete",
            UInt16(kVK_ForwardDelete): "Fwd Del",
            UInt16(kVK_Escape): "Esc", UInt16(kVK_Home): "Home",
            UInt16(kVK_End): "End", UInt16(kVK_PageUp): "PgUp",
            UInt16(kVK_PageDown): "PgDn",
            UInt16(kVK_LeftArrow): "←", UInt16(kVK_RightArrow): "→",
            UInt16(kVK_UpArrow): "↑", UInt16(kVK_DownArrow): "↓",
            UInt16(kVK_ANSI_A): "A", UInt16(kVK_ANSI_B): "B", UInt16(kVK_ANSI_C): "C",
            UInt16(kVK_ANSI_D): "D", UInt16(kVK_ANSI_E): "E", UInt16(kVK_ANSI_F): "F",
            UInt16(kVK_ANSI_G): "G", UInt16(kVK_ANSI_H): "H", UInt16(kVK_ANSI_I): "I",
            UInt16(kVK_ANSI_J): "J", UInt16(kVK_ANSI_K): "K", UInt16(kVK_ANSI_L): "L",
            UInt16(kVK_ANSI_M): "M", UInt16(kVK_ANSI_N): "N", UInt16(kVK_ANSI_O): "O",
            UInt16(kVK_ANSI_P): "P", UInt16(kVK_ANSI_Q): "Q", UInt16(kVK_ANSI_R): "R",
            UInt16(kVK_ANSI_S): "S", UInt16(kVK_ANSI_T): "T", UInt16(kVK_ANSI_U): "U",
            UInt16(kVK_ANSI_V): "V", UInt16(kVK_ANSI_W): "W", UInt16(kVK_ANSI_X): "X",
            UInt16(kVK_ANSI_Y): "Y", UInt16(kVK_ANSI_Z): "Z",
            UInt16(kVK_ANSI_0): "0", UInt16(kVK_ANSI_1): "1", UInt16(kVK_ANSI_2): "2",
            UInt16(kVK_ANSI_3): "3", UInt16(kVK_ANSI_4): "4", UInt16(kVK_ANSI_5): "5",
            UInt16(kVK_ANSI_6): "6", UInt16(kVK_ANSI_7): "7", UInt16(kVK_ANSI_8): "8",
            UInt16(kVK_ANSI_9): "9",
            UInt16(kVK_ANSI_Minus): "-", UInt16(kVK_ANSI_Equal): "=",
            UInt16(kVK_ANSI_LeftBracket): "[", UInt16(kVK_ANSI_RightBracket): "]",
            UInt16(kVK_ANSI_Semicolon): ";", UInt16(kVK_ANSI_Quote): "'",
            UInt16(kVK_ANSI_Comma): ",", UInt16(kVK_ANSI_Period): ".",
            UInt16(kVK_ANSI_Slash): "/", UInt16(kVK_ANSI_Backslash): "\\",
            UInt16(kVK_ANSI_Grave): "`",
        ]
        return keyNames[code] ?? "Key \(code)"
    }
}

// MARK: - Stop Hotkey Configuration
struct StopHotkeyConfig: Codable {
    var keyCode: UInt16
    var command: Bool
    var option: Bool
    var control: Bool
    var shift: Bool

    static let defaultConfig = StopHotkeyConfig(
        keyCode: UInt16(kVK_Escape),  // Escape key
        command: false,
        option: false,
        control: false,
        shift: false
    )

    static func load() -> StopHotkeyConfig {
        if let data = UserDefaults.standard.data(forKey: "stopHotkeyConfig"),
           let config = try? JSONDecoder().decode(StopHotkeyConfig.self, from: data) {
            return config
        }
        return defaultConfig
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "stopHotkeyConfig")
            NotificationCenter.default.post(name: .stopHotkeyDidChange, object: nil)
        }
    }

    var displayString: String {
        var parts: [String] = []
        if control { parts.append("⌃") }
        if option { parts.append("⌥") }
        if shift { parts.append("⇧") }
        if command { parts.append("⌘") }
        parts.append(keyName)
        return parts.joined()
    }

    var keyName: String {
        let keyNames: [UInt16: String] = [
            UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3",
            UInt16(kVK_F4): "F4", UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6",
            UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8", UInt16(kVK_F9): "F9",
            UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12",
            UInt16(kVK_Space): "Space", UInt16(kVK_Return): "Return",
            UInt16(kVK_Tab): "Tab", UInt16(kVK_Delete): "Delete",
            UInt16(kVK_Escape): "Esc", UInt16(kVK_Home): "Home",
            UInt16(kVK_End): "End", UInt16(kVK_PageUp): "PgUp",
            UInt16(kVK_PageDown): "PgDn",
            UInt16(kVK_LeftArrow): "←", UInt16(kVK_RightArrow): "→",
            UInt16(kVK_UpArrow): "↑", UInt16(kVK_DownArrow): "↓",
            UInt16(kVK_ANSI_A): "A", UInt16(kVK_ANSI_B): "B", UInt16(kVK_ANSI_C): "C",
            UInt16(kVK_ANSI_D): "D", UInt16(kVK_ANSI_E): "E", UInt16(kVK_ANSI_F): "F",
            UInt16(kVK_ANSI_G): "G", UInt16(kVK_ANSI_H): "H", UInt16(kVK_ANSI_I): "I",
            UInt16(kVK_ANSI_J): "J", UInt16(kVK_ANSI_K): "K", UInt16(kVK_ANSI_L): "L",
            UInt16(kVK_ANSI_M): "M", UInt16(kVK_ANSI_N): "N", UInt16(kVK_ANSI_O): "O",
            UInt16(kVK_ANSI_P): "P", UInt16(kVK_ANSI_Q): "Q", UInt16(kVK_ANSI_R): "R",
            UInt16(kVK_ANSI_S): "S", UInt16(kVK_ANSI_T): "T", UInt16(kVK_ANSI_U): "U",
            UInt16(kVK_ANSI_V): "V", UInt16(kVK_ANSI_W): "W", UInt16(kVK_ANSI_X): "X",
            UInt16(kVK_ANSI_Y): "Y", UInt16(kVK_ANSI_Z): "Z",
            UInt16(kVK_ANSI_0): "0", UInt16(kVK_ANSI_1): "1", UInt16(kVK_ANSI_2): "2",
            UInt16(kVK_ANSI_3): "3", UInt16(kVK_ANSI_4): "4", UInt16(kVK_ANSI_5): "5",
            UInt16(kVK_ANSI_6): "6", UInt16(kVK_ANSI_7): "7", UInt16(kVK_ANSI_8): "8",
            UInt16(kVK_ANSI_9): "9",
        ]
        return keyNames[keyCode] ?? "Key \(keyCode)"
    }
}

// MARK: - Logger
class Logger {
    static let shared = Logger()

    private var logs: [LogEntry] = []
    private let maxLogs = 1000
    private let logFileURL: URL?
    private let fileQueue = DispatchQueue(label: "com.mute.logger.file", qos: .utility)
    private let maxFileSize: UInt64 = 5 * 1024 * 1024  // 5 MB
    private let dateFormatter: DateFormatter

    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let level: LogLevel
        let message: String
    }

    enum LogLevel: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
    }

    private init() {
        // Setup date formatter
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        // Setup log file in Application Support
        let fileManager = FileManager.default
        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let muteDir = appSupport.appendingPathComponent("Mute")

            // Create directory if needed
            try? fileManager.createDirectory(at: muteDir, withIntermediateDirectories: true)

            logFileURL = muteDir.appendingPathComponent("app.log")

            // Write startup marker
            let startupMessage = "\n=== Mute App Started at \(dateFormatter.string(from: Date())) ===\n"
            writeToFile(startupMessage)
        } else {
            logFileURL = nil
        }
    }

    func log(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        let entry = LogEntry(timestamp: Date(), level: level, message: message)
        let fileName = URL(fileURLWithPath: file).lastPathComponent

        DispatchQueue.main.async {
            self.logs.append(entry)
            if self.logs.count > self.maxLogs {
                self.logs.removeFirst(self.logs.count - self.maxLogs)
            }
        }

        // Format log line
        let timestamp = dateFormatter.string(from: entry.timestamp)
        let logLine = "[\(timestamp)] [\(entry.level.rawValue)] [\(fileName):\(line)] \(message)"

        // Print to console for debugging
        print(logLine)

        // Write to file
        writeToFile(logLine + "\n")
    }

    private func writeToFile(_ text: String) {
        guard let fileURL = logFileURL else { return }

        fileQueue.async {
            // Check file size and rotate if needed
            self.rotateLogIfNeeded()

            // Append to file
            if let data = text.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
                        fileHandle.seekToEndOfFile()
                        fileHandle.write(data)
                        try? fileHandle.close()
                    }
                } else {
                    try? data.write(to: fileURL)
                }
            }
        }
    }

    private func rotateLogIfNeeded() {
        guard let fileURL = logFileURL else { return }
        let fileManager = FileManager.default

        guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
              let fileSize = attributes[.size] as? UInt64,
              fileSize > maxFileSize else {
            return
        }

        // Rotate: app.log -> app.log.1, app.log.1 -> app.log.2, etc.
        let backupCount = 3
        for i in stride(from: backupCount - 1, through: 1, by: -1) {
            let oldPath = fileURL.deletingLastPathComponent()
                .appendingPathComponent("app.log.\(i)")
            let newPath = fileURL.deletingLastPathComponent()
                .appendingPathComponent("app.log.\(i + 1)")
            try? fileManager.removeItem(at: newPath)
            try? fileManager.moveItem(at: oldPath, to: newPath)
        }

        // Move current log to .1
        let backupPath = fileURL.deletingLastPathComponent()
            .appendingPathComponent("app.log.1")
        try? fileManager.removeItem(at: backupPath)
        try? fileManager.moveItem(at: fileURL, to: backupPath)
    }

    func getLogs() -> [LogEntry] {
        return logs
    }

    func clearLogs() {
        logs.removeAll()
    }

    /// Returns the path to the log file directory
    func getLogDirectory() -> URL? {
        return logFileURL?.deletingLastPathComponent()
    }
}
