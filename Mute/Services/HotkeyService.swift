// HotkeyService.swift
// Mute

import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts

// MARK: - KeyboardShortcuts Name Extensions

extension KeyboardShortcuts.Name {
    static let toggleRecording = Self(
        "toggleRecording",
        default: .init(.f5)
    )
    static let cancelRecording = Self(
        "cancelRecording",
        default: .init(.escape)
    )
    static let cycleDictationMode = Self("cycleDictationMode")
}

// MARK: - HotkeyService

@MainActor
final class HotkeyService {
    static let shared = HotkeyService()

    // NSEvent monitors for modifier-only / two-key combos (fallback path)
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var lastModifierState: NSEvent.ModifierFlags = []

    private var stopGlobalEventMonitor: Any?
    private var stopLocalEventMonitor: Any?

    private var modesGlobalMonitor: Any?
    private var modesLocalMonitor: Any?
    private var modesLastModifierState: NSEvent.ModifierFlags = []
    private var modesFirstKeyDown: Bool = false
    private var modesSecondKeyDown: Bool = false

    /// Whether the toggle-recording hotkey uses NSEvent fallback (modifier-only)
    private(set) var toggleRecordingUsesNSEvent = false
    /// Whether the stop hotkey uses NSEvent fallback
    private(set) var stopHotkeyUsesNSEvent = false
    /// Whether the modes hotkey uses NSEvent fallback (modifier-only or two-key)
    private(set) var modesHotkeyUsesNSEvent = false

    private init() {}

    // MARK: - Setup

    func setupAllHotkeys() {
        migrateExistingConfigs()
        setupToggleRecordingHotkey()
        setupStopHotkey()
        setupModesHotkey()
    }

    func teardownAllHotkeys() {
        KeyboardShortcuts.removeAllHandlers()
        removeToggleRecordingMonitors()
        removeStopMonitors()
        removeModesMonitors()
    }

    // MARK: - Toggle Recording Hotkey

    func reconfigureToggleRecording() {
        removeToggleRecordingMonitors()
        KeyboardShortcuts.removeHandler(for: .toggleRecording)
        setupToggleRecordingHotkey()
    }

    private func setupToggleRecordingHotkey() {
        let config = HotkeyConfig.load()

        if config.isModifierOnly {
            // Modifier-only: use NSEvent monitors (Carbon can't handle this)
            toggleRecordingUsesNSEvent = true
            setupToggleRecordingNSEventMonitors(config: config)
        } else {
            // Standard combo: sync to KeyboardShortcuts and use Carbon registration
            toggleRecordingUsesNSEvent = false
            syncHotkeyConfigToKeyboardShortcuts(config)
            KeyboardShortcuts.onKeyDown(for: .toggleRecording) {
                Task { @MainActor in
                    AppDelegate.handleHotkeyAction()
                }
            }
        }

        Logger.shared.log("Toggle recording hotkey configured: \(config.displayString) (Carbon: \(!toggleRecordingUsesNSEvent))")
    }

    private func setupToggleRecordingNSEventMonitors(config: HotkeyConfig) {
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.checkModifierHotkey(event: event, config: config)
        }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            if self?.checkModifierHotkey(event: event, config: config) == true {
                return nil
            }
            return event
        }
    }

    private func removeToggleRecordingMonitors() {
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        lastModifierState = []
    }

    @discardableResult
    private func checkModifierHotkey(event: NSEvent, config: HotkeyConfig) -> Bool {
        let keyCode = event.keyCode
        let currentFlags = event.modifierFlags

        guard keyCode == config.keyCode else {
            lastModifierState = currentFlags
            return false
        }

        let isKeyDown = isModifierKeyDown(keyCode: keyCode, currentFlags: currentFlags, lastFlags: lastModifierState)
        lastModifierState = currentFlags

        if isKeyDown {
            AppDelegate.handleHotkeyAction()
            return true
        }
        return false
    }

    // MARK: - Stop Hotkey

    func reconfigureStopHotkey() {
        removeStopMonitors()
        KeyboardShortcuts.removeHandler(for: .cancelRecording)
        setupStopHotkey()
    }

    private func setupStopHotkey() {
        let config = StopHotkeyConfig.load()

        // Stop hotkey is always a standard key combo (never modifier-only)
        stopHotkeyUsesNSEvent = false
        syncStopHotkeyConfigToKeyboardShortcuts(config)
        KeyboardShortcuts.onKeyDown(for: .cancelRecording) {
            Task { @MainActor in
                AppDelegate.handleStopHotkeyAction()
            }
        }

        Logger.shared.log("Stop hotkey configured: \(config.displayString) (Carbon)")
    }

    private func removeStopMonitors() {
        if let monitor = stopGlobalEventMonitor {
            NSEvent.removeMonitor(monitor)
            stopGlobalEventMonitor = nil
        }
        if let monitor = stopLocalEventMonitor {
            NSEvent.removeMonitor(monitor)
            stopLocalEventMonitor = nil
        }
    }

    // MARK: - Modes Hotkey

    func reconfigureModesHotkey() {
        removeModesMonitors()
        KeyboardShortcuts.removeHandler(for: .cycleDictationMode)
        setupModesHotkey()
    }

    private func setupModesHotkey() {
        let config = ModesHotkeyConfig.load()

        guard config.isEnabled else {
            modesHotkeyUsesNSEvent = false
            Logger.shared.log("Modes hotkey: None configured")
            return
        }

        if config.isTwoKeyCombo || config.isModifierOnly {
            // Two-key or modifier-only: use NSEvent monitors (needs accessibility)
            modesHotkeyUsesNSEvent = true
            setupModesNSEventMonitors(config: config)
        } else {
            // Standard combo: use Carbon via KeyboardShortcuts
            modesHotkeyUsesNSEvent = false
            syncModesHotkeyConfigToKeyboardShortcuts(config)
            KeyboardShortcuts.onKeyDown(for: .cycleDictationMode) {
                Task { @MainActor in
                    AppDelegate.handleModesHotkeyAction()
                }
            }
        }

        Logger.shared.log("Modes hotkey configured: \(config.displayString) (Carbon: \(!modesHotkeyUsesNSEvent))")
    }

    private func setupModesNSEventMonitors(config: ModesHotkeyConfig) {
        let hasAccessibility = AXIsProcessTrusted()
        if !hasAccessibility {
            Logger.shared.log("Modes hotkey: Accessibility not granted, global monitor skipped", level: .warning)
        }

        if hasAccessibility {
            modesGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.checkModesTwoKeyOrModifierHotkey(event: event, config: config)
            }
        }
        modesLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            if self?.checkModesTwoKeyOrModifierHotkey(event: event, config: config) == true {
                return nil
            }
            return event
        }
    }

    func removeModesMonitors() {
        if let monitor = modesGlobalMonitor {
            NSEvent.removeMonitor(monitor)
            modesGlobalMonitor = nil
        }
        if let monitor = modesLocalMonitor {
            NSEvent.removeMonitor(monitor)
            modesLocalMonitor = nil
        }
        modesLastModifierState = []
        modesFirstKeyDown = false
        modesSecondKeyDown = false
    }

    /// Re-setup modes global monitor when accessibility is granted after initial setup
    func reSetupModesIfNeeded() {
        if AXIsProcessTrusted() && modesHotkeyUsesNSEvent && modesGlobalMonitor == nil {
            let config = ModesHotkeyConfig.load()
            if config.isEnabled {
                removeModesMonitors()
                setupModesHotkey()
            }
        }
    }

    @discardableResult
    private func checkModesTwoKeyOrModifierHotkey(event: NSEvent, config: ModesHotkeyConfig) -> Bool {
        let keyCode = event.keyCode
        let currentFlags = event.modifierFlags

        if config.isTwoKeyCombo {
            if keyCode == config.keyCode {
                modesFirstKeyDown = isModifierKeyDown(keyCode: keyCode, currentFlags: currentFlags, lastFlags: nil)
            } else if keyCode == config.secondKeyCode {
                modesSecondKeyDown = isModifierKeyDown(keyCode: keyCode, currentFlags: currentFlags, lastFlags: nil)
            }

            let relevantModifier = getModifierFlag(for: config.keyCode)
            if !currentFlags.contains(relevantModifier) {
                modesFirstKeyDown = false
                modesSecondKeyDown = false
            }

            if modesFirstKeyDown && modesSecondKeyDown {
                modesFirstKeyDown = false
                modesSecondKeyDown = false
                AppDelegate.handleModesHotkeyAction()
                return true
            }
        } else {
            guard keyCode == config.keyCode else {
                modesLastModifierState = currentFlags
                return false
            }

            let isKeyDown = isModifierKeyDown(keyCode: keyCode, currentFlags: currentFlags, lastFlags: modesLastModifierState)
            modesLastModifierState = currentFlags

            if isKeyDown {
                AppDelegate.handleModesHotkeyAction()
                return true
            }
        }

        return false
    }

    // MARK: - Config ↔ KeyboardShortcuts Sync

    private func syncHotkeyConfigToKeyboardShortcuts(_ config: HotkeyConfig) {
        guard !config.isModifierOnly else { return }
        if let shortcut = shortcut(fromKeyCode: config.keyCode, command: config.command, option: config.option, control: config.control, shift: config.shift) {
            KeyboardShortcuts.setShortcut(shortcut, for: .toggleRecording)
        }
    }

    private func syncStopHotkeyConfigToKeyboardShortcuts(_ config: StopHotkeyConfig) {
        if let shortcut = shortcut(fromKeyCode: config.keyCode, command: config.command, option: config.option, control: config.control, shift: config.shift) {
            KeyboardShortcuts.setShortcut(shortcut, for: .cancelRecording)
        }
    }

    private func syncModesHotkeyConfigToKeyboardShortcuts(_ config: ModesHotkeyConfig) {
        guard !config.isModifierOnly, !config.isTwoKeyCombo else { return }
        if let shortcut = shortcut(fromKeyCode: config.keyCode, command: config.command, option: config.option, control: config.control, shift: config.shift) {
            KeyboardShortcuts.setShortcut(shortcut, for: .cycleDictationMode)
        }
    }

    private func shortcut(fromKeyCode keyCode: UInt16, command: Bool, option: Bool, control: Bool, shift: Bool) -> KeyboardShortcuts.Shortcut? {
        var carbonMods = 0
        if command { carbonMods |= cmdKey }
        if option  { carbonMods |= optionKey }
        if control { carbonMods |= controlKey }
        if shift   { carbonMods |= shiftKey }
        return KeyboardShortcuts.Shortcut(carbonKeyCode: Int(keyCode), carbonModifiers: carbonMods)
    }

    // MARK: - Migration

    private func migrateExistingConfigs() {
        guard !UserDefaults.standard.bool(forKey: "hotkeyMigrationV2Complete") else { return }

        // Migrate toggle recording hotkey
        let hotkeyConfig = HotkeyConfig.load()
        if !hotkeyConfig.isModifierOnly {
            syncHotkeyConfigToKeyboardShortcuts(hotkeyConfig)
        }

        // Migrate stop hotkey
        let stopConfig = StopHotkeyConfig.load()
        syncStopHotkeyConfigToKeyboardShortcuts(stopConfig)

        // Migrate modes hotkey
        let modesConfig = ModesHotkeyConfig.load()
        if modesConfig.isEnabled && !modesConfig.isModifierOnly && !modesConfig.isTwoKeyCombo {
            syncModesHotkeyConfigToKeyboardShortcuts(modesConfig)
        }

        UserDefaults.standard.set(true, forKey: "hotkeyMigrationV2Complete")
        Logger.shared.log("Hotkey migration v2 complete")
    }

    // MARK: - Modifier Key Helpers

    private func isModifierKeyDown(keyCode: UInt16, currentFlags: NSEvent.ModifierFlags, lastFlags: NSEvent.ModifierFlags?) -> Bool {
        let last = lastFlags ?? modesLastModifierState
        switch keyCode {
        case UInt16(kVK_Shift), UInt16(kVK_RightShift):
            return currentFlags.contains(.shift) && (lastFlags == nil || !last.contains(.shift))
        case UInt16(kVK_Command), UInt16(kVK_RightCommand):
            return currentFlags.contains(.command) && (lastFlags == nil || !last.contains(.command))
        case UInt16(kVK_Option), UInt16(kVK_RightOption):
            return currentFlags.contains(.option) && (lastFlags == nil || !last.contains(.option))
        case UInt16(kVK_Control), UInt16(kVK_RightControl):
            return currentFlags.contains(.control) && (lastFlags == nil || !last.contains(.control))
        case UInt16(kVK_Function):
            return currentFlags.contains(.function) && (lastFlags == nil || !last.contains(.function))
        case UInt16(kVK_CapsLock):
            return currentFlags.contains(.capsLock) && (lastFlags == nil || !last.contains(.capsLock))
        default:
            return false
        }
    }

    private func getModifierFlag(for keyCode: UInt16) -> NSEvent.ModifierFlags {
        switch keyCode {
        case UInt16(kVK_Shift), UInt16(kVK_RightShift):
            return .shift
        case UInt16(kVK_Command), UInt16(kVK_RightCommand):
            return .command
        case UInt16(kVK_Option), UInt16(kVK_RightOption):
            return .option
        case UInt16(kVK_Control), UInt16(kVK_RightControl):
            return .control
        case UInt16(kVK_Function):
            return .function
        case UInt16(kVK_CapsLock):
            return .capsLock
        default:
            return []
        }
    }
}
