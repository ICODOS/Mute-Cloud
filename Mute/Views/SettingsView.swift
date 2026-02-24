// SettingsView.swift
// Mute

import SwiftUI
import AppKit
import AVFoundation
import Carbon.HIToolbox

// MARK: - Settings Tab Enum
/// Represents the available tabs in the Settings window.
/// Used by `SettingsTabCoordinator` to navigate to a specific tab programmatically.
enum SettingsTab: Int, Hashable, CaseIterable {
    case general = 0
    case transcription = 1
    case modes = 2
    case advanced = 3
    case about = 4
}

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(SettingsTab.general)

            TranscriptionSettingsTab()
                .tabItem {
                    Label("Transcription", systemImage: "waveform")
                }
                .tag(SettingsTab.transcription)

            ModesSettingsTab()
                .tabItem {
                    Label("Modes", systemImage: "wand.and.stars")
                }
                .tag(SettingsTab.modes)

            AdvancedSettingsTab()
                .tabItem {
                    Label("Advanced", systemImage: "wrench.and.screwdriver")
                }
                .tag(SettingsTab.advanced)

            AboutTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(SettingsTab.about)
        }
        .frame(width: 520, height: 520)
        .environmentObject(appState)
        .onAppear {
            // Check if a specific tab was requested
            if let requestedTab = SettingsTabCoordinator.shared.requestedTab {
                selectedTab = requestedTab
                SettingsTabCoordinator.shared.requestedTab = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsTabRequested)) { notification in
            // Handle tab change requests while settings is already open
            if let tab = notification.userInfo?["tab"] as? SettingsTab {
                selectedTab = tab
            }
        }
    }
}

// MARK: - Settings Tab Coordinator
/// Coordinates which tab to show when the Settings window opens.
///
/// Works in conjunction with `SettingsCoordinator`:
/// 1. `SettingsCoordinator.requestOpenSettings(tab:)` calls `requestTab(_:)` if a tab is specified
/// 2. This stores the requested tab and posts a notification
/// 3. `SettingsView.onAppear` reads `requestedTab` and selects it
/// 4. If Settings is already open, the notification triggers tab selection via `.onReceive`
///
/// ## Usage
/// Typically called via `SettingsCoordinator`, not directly:
/// ```swift
/// SettingsCoordinator.shared.requestOpenSettings(tab: .modes)
/// ```
@MainActor
final class SettingsTabCoordinator {
    static let shared = SettingsTabCoordinator()

    /// The tab to select when Settings opens. Set to nil after being consumed.
    var requestedTab: SettingsTab?

    private init() {}

    /// Requests that the Settings window show a specific tab.
    /// - Parameter tab: The tab to display.
    /// - Note: Also posts `.settingsTabRequested` notification for when Settings is already open.
    func requestTab(_ tab: SettingsTab) {
        requestedTab = tab
        // Post notification in case Settings is already open
        NotificationCenter.default.post(
            name: .settingsTabRequested,
            object: nil,
            userInfo: ["tab": tab]
        )
    }
}

// MARK: - Settings Section Header
struct SettingsSectionHeader: View {
    let title: String
    let icon: String
    var iconColor: Color = .accentColor

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(iconColor)
                .frame(width: 20)

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
        }
        .padding(.bottom, 4)
    }
}

// MARK: - Settings Card
struct SettingsCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - General Settings Tab
struct GeneralSettingsTab: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var deviceMonitor = AudioDeviceMonitor.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Hotkey Section
                VStack(alignment: .leading, spacing: 10) {
                    SettingsSectionHeader(title: "Hotkeys", icon: "keyboard")

                    SettingsCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Toggle Recording")
                                        .font(.system(size: 13, weight: .medium))
                                    Text("Press to start/stop recording")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                HotkeyButton()
                            }

                            Divider()

                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Cancel Recording")
                                        .font(.system(size: 13, weight: .medium))
                                    Text("Press to cancel without transcription")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                StopHotkeyButton()
                            }

                            Divider()

                            ModesHotkeyRow()
                        }
                    }
                }

                // Audio Input Section
                VStack(alignment: .leading, spacing: 10) {
                    SettingsSectionHeader(title: "Input Device", icon: "mic")

                    SettingsCard {
                        VStack(alignment: .leading, spacing: 14) {
                            // Start/Stop Recording device
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Start/Stop Recording")
                                        .font(.system(size: 13, weight: .medium))
                                    Text("Audio source for dictation")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Picker("", selection: $appState.selectedAudioDeviceUID) {
                                    Text("System Default").tag("")
                                    ForEach(deviceMonitor.inputDevices, id: \.uid) { device in
                                        Text(device.name).tag(device.uid)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(maxWidth: 200)
                            }

                            Divider()

                            // Capture to Notes device
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Capture to Notes")
                                        .font(.system(size: 13, weight: .medium))
                                    Text("Audio source for note capture")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Picker("", selection: $appState.captureNotesAudioDeviceUID) {
                                    Text("System Default").tag("")
                                    ForEach(deviceMonitor.inputDevices, id: \.uid) { device in
                                        Text(device.name).tag(device.uid)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(maxWidth: 200)
                            }
                        }
                    }
                }

                // Behavior Section
                VStack(alignment: .leading, spacing: 10) {
                    SettingsSectionHeader(title: "Behavior", icon: "slider.horizontal.3")

                    SettingsCard {
                        VStack(alignment: .leading, spacing: 14) {
                            SettingsToggleRow(
                                title: "Paste text on stop",
                                description: "Automatically paste transcription when recording stops",
                                isOn: $appState.pasteOnStop
                            )

                            Divider()

                            SettingsToggleRow(
                                title: "Show overlay indicator",
                                description: "Display recording status in corner of screen",
                                isOn: $appState.showOverlay
                            )

                            Divider()

                            SettingsToggleRow(
                                title: "Preserve clipboard",
                                description: "Restore previous clipboard content after pasting",
                                isOn: $appState.preserveClipboard
                            )
                        }
                    }
                }
            }
            .padding(20)
        }
        .onAppear {
            // Refresh device list when view appears (backup for listener)
            deviceMonitor.refreshDevices()
        }
    }
}

// MARK: - Settings Toggle Row
struct SettingsToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

// MARK: - Custom Hotkey Button
struct HotkeyButton: View {
    @State private var isRecording = false
    @State private var hotkeyConfig = HotkeyConfig.load()
    @State private var keyDownMonitor: Any?
    @State private var flagsMonitor: Any?
    @State private var lastFlags: NSEvent.ModifierFlags = []

    var body: some View {
        Button(action: {
            if isRecording {
                stopRecording()
            } else {
                startRecording()
            }
        }) {
            HStack(spacing: 8) {
                if isRecording {
                    Image(systemName: "keyboard")
                        .foregroundColor(.white)
                    Text("Press any key...")
                        .foregroundColor(.white)
                } else {
                    Text(hotkeyConfig.displayString)
                        .fontWeight(.medium)
                        .font(.system(size: 13, design: .rounded))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minWidth: 120)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isRecording ? Color.accentColor : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isRecording ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func startRecording() {
        isRecording = true
        lastFlags = NSEvent.modifierFlags

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let keyCode = event.keyCode

            if keyCode == UInt16(kVK_Escape) {
                self.stopRecording()
                return nil
            }

            let modifierKeyCodes: Set<UInt16> = [
                UInt16(kVK_Shift), UInt16(kVK_RightShift),
                UInt16(kVK_Command), UInt16(kVK_RightCommand),
                UInt16(kVK_Option), UInt16(kVK_RightOption),
                UInt16(kVK_Control), UInt16(kVK_RightControl),
                UInt16(kVK_Function), UInt16(kVK_CapsLock)
            ]
            if modifierKeyCodes.contains(keyCode) {
                return event
            }

            let newConfig = HotkeyConfig(
                keyCode: keyCode,
                command: modifiers.contains(.command),
                option: modifiers.contains(.option),
                control: modifiers.contains(.control),
                shift: modifiers.contains(.shift),
                isModifierOnly: false
            )

            newConfig.save()
            self.hotkeyConfig = newConfig
            self.stopRecording()

            return nil
        }

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let keyCode = event.keyCode
            let currentFlags = event.modifierFlags

            let isKeyDown: Bool
            switch keyCode {
            case UInt16(kVK_Shift), UInt16(kVK_RightShift):
                isKeyDown = currentFlags.contains(.shift) && !self.lastFlags.contains(.shift)
            case UInt16(kVK_Command), UInt16(kVK_RightCommand):
                isKeyDown = currentFlags.contains(.command) && !self.lastFlags.contains(.command)
            case UInt16(kVK_Option), UInt16(kVK_RightOption):
                isKeyDown = currentFlags.contains(.option) && !self.lastFlags.contains(.option)
            case UInt16(kVK_Control), UInt16(kVK_RightControl):
                isKeyDown = currentFlags.contains(.control) && !self.lastFlags.contains(.control)
            case UInt16(kVK_Function):
                isKeyDown = currentFlags.contains(.function) && !self.lastFlags.contains(.function)
            case UInt16(kVK_CapsLock):
                isKeyDown = currentFlags.contains(.capsLock) && !self.lastFlags.contains(.capsLock)
            default:
                self.lastFlags = currentFlags
                return event
            }

            self.lastFlags = currentFlags

            if isKeyDown {
                let newConfig = HotkeyConfig(
                    keyCode: keyCode,
                    command: false,
                    option: false,
                    control: false,
                    shift: false,
                    isModifierOnly: true
                )

                newConfig.save()
                self.hotkeyConfig = newConfig
                self.stopRecording()
                return nil
            }

            return event
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = keyDownMonitor {
            NSEvent.removeMonitor(monitor)
            keyDownMonitor = nil
        }
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            flagsMonitor = nil
        }
    }
}

// MARK: - Stop Hotkey Button
struct StopHotkeyButton: View {
    @State private var isRecording = false
    @State private var hotkeyConfig = StopHotkeyConfig.load()
    @State private var keyDownMonitor: Any?

    var body: some View {
        Button(action: {
            if isRecording {
                stopRecording()
            } else {
                startRecording()
            }
        }) {
            HStack(spacing: 8) {
                if isRecording {
                    Image(systemName: "keyboard")
                        .foregroundColor(.white)
                    Text("Press any key...")
                        .foregroundColor(.white)
                } else {
                    Text(hotkeyConfig.displayString)
                        .fontWeight(.medium)
                        .font(.system(size: 13, design: .rounded))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minWidth: 120)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isRecording ? Color.accentColor : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isRecording ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func startRecording() {
        isRecording = true

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let keyCode = event.keyCode

            // Cancel recording with a second Escape press if Escape is being set
            if keyCode == UInt16(kVK_Escape) && !modifiers.isEmpty {
                // Allow Escape with modifiers to be set
            } else if keyCode == UInt16(kVK_Escape) {
                // First Escape sets it, second cancels
                let config = StopHotkeyConfig(
                    keyCode: keyCode,
                    command: false,
                    option: false,
                    control: false,
                    shift: false
                )
                config.save()
                self.hotkeyConfig = config
                self.stopRecording()
                return nil
            }

            let config = StopHotkeyConfig(
                keyCode: keyCode,
                command: modifiers.contains(.command),
                option: modifiers.contains(.option),
                control: modifiers.contains(.control),
                shift: modifiers.contains(.shift)
            )

            config.save()
            self.hotkeyConfig = config
            self.stopRecording()

            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = keyDownMonitor {
            NSEvent.removeMonitor(monitor)
            keyDownMonitor = nil
        }
    }
}

// MARK: - Modes Hotkey Row
struct ModesHotkeyRow: View {
    @State private var hasAccessibility = AXIsProcessTrusted()
    @State private var hotkeyConfig = ModesHotkeyConfig.load()
    @State private var accessibilityPollTimer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cycle Dictation Mode")
                        .font(.system(size: 13, weight: .medium))
                    Text("Cycle through enabled modes")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()

                ModesHotkeyButton()
            }

            if hotkeyConfig.isEnabled && !hasAccessibility {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 12))
                    Text("Accessibility permission required for global shortcut")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                    Spacer()
                    Button("Grant Access") {
                        requestAccessibilityAndPoll()
                    }
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.orange.opacity(0.1))
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .modesHotkeyDidChange)) { _ in
            hotkeyConfig = ModesHotkeyConfig.load()
            hasAccessibility = AXIsProcessTrusted()
        }
        .onDisappear {
            accessibilityPollTimer?.invalidate()
            accessibilityPollTimer = nil
        }
    }

    private func requestAccessibilityAndPoll() {
        // Prompt the system accessibility dialog
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)

        // Poll for the permission change
        accessibilityPollTimer?.invalidate()
        accessibilityPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if AXIsProcessTrusted() {
                timer.invalidate()
                accessibilityPollTimer = nil
                hasAccessibility = true
                NotificationCenter.default.post(name: .modesHotkeyDidChange, object: nil)
            }
        }
    }
}

// MARK: - Modes Hotkey Button
struct ModesHotkeyButton: View {
    @State private var isRecording = false
    @State private var hotkeyConfig = ModesHotkeyConfig.load()
    @State private var keyDownMonitor: Any?
    @State private var flagsMonitor: Any?
    @State private var lastFlags: NSEvent.ModifierFlags = []
    // For two-key combo recording
    @State private var firstModifierKeyCode: UInt16? = nil
    @State private var recordingHint: String = "Press key or combo..."

    var body: some View {
        Button(action: {
            if isRecording {
                stopRecording()
            } else {
                startRecording()
            }
        }) {
            HStack(spacing: 8) {
                if isRecording {
                    Image(systemName: "keyboard")
                        .foregroundColor(.white)
                    Text(recordingHint)
                        .foregroundColor(.white)
                } else {
                    Text(hotkeyConfig.displayString)
                        .fontWeight(.medium)
                        .font(.system(size: 13, design: .rounded))

                    // Integrated clear button
                    if hotkeyConfig.isEnabled {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary.opacity(0.7))
                            .onTapGesture {
                                ModesHotkeyConfig.clear()
                                hotkeyConfig = ModesHotkeyConfig.load()
                            }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minWidth: 120)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isRecording ? Color.accentColor : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isRecording ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func startRecording() {
        isRecording = true
        lastFlags = NSEvent.modifierFlags
        firstModifierKeyCode = nil
        recordingHint = "Press key or combo..."

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let keyCode = event.keyCode

            // Escape cancels recording (without modifiers)
            if keyCode == UInt16(kVK_Escape) && modifiers.isEmpty {
                self.stopRecording()
                return nil
            }

            // Skip if it's just a modifier key (handled by flagsMonitor)
            let modifierKeyCodes: Set<UInt16> = [
                UInt16(kVK_Shift), UInt16(kVK_RightShift),
                UInt16(kVK_Command), UInt16(kVK_RightCommand),
                UInt16(kVK_Option), UInt16(kVK_RightOption),
                UInt16(kVK_Control), UInt16(kVK_RightControl),
                UInt16(kVK_Function), UInt16(kVK_CapsLock)
            ]
            if modifierKeyCodes.contains(keyCode) {
                return event
            }

            // Record the key + modifiers
            let newConfig = ModesHotkeyConfig(
                keyCode: keyCode,
                secondKeyCode: 0,
                command: modifiers.contains(.command),
                option: modifiers.contains(.option),
                control: modifiers.contains(.control),
                shift: modifiers.contains(.shift),
                isModifierOnly: false,
                isTwoKeyCombo: false
            )

            newConfig.save()
            self.hotkeyConfig = newConfig
            self.stopRecording()

            return nil
        }

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let keyCode = event.keyCode
            let currentFlags = event.modifierFlags

            // Check if this is a modifier key
            let modifierKeyCodes: Set<UInt16> = [
                UInt16(kVK_Shift), UInt16(kVK_RightShift),
                UInt16(kVK_Command), UInt16(kVK_RightCommand),
                UInt16(kVK_Option), UInt16(kVK_RightOption),
                UInt16(kVK_Control), UInt16(kVK_RightControl),
                UInt16(kVK_Function), UInt16(kVK_CapsLock)
            ]

            guard modifierKeyCodes.contains(keyCode) else {
                self.lastFlags = currentFlags
                return event
            }

            let isKeyDown = self.isModifierKeyDown(keyCode: keyCode, currentFlags: currentFlags)
            self.lastFlags = currentFlags

            if isKeyDown {
                if let firstKey = self.firstModifierKeyCode {
                    // Second modifier pressed - record as two-key combo
                    if keyCode != firstKey {
                        let newConfig = ModesHotkeyConfig(
                            keyCode: firstKey,
                            secondKeyCode: keyCode,
                            command: false,
                            option: false,
                            control: false,
                            shift: false,
                            isModifierOnly: false,
                            isTwoKeyCombo: true
                        )

                        newConfig.save()
                        self.hotkeyConfig = newConfig
                        self.stopRecording()
                        return nil
                    }
                } else {
                    // First modifier pressed - wait for second or use as single
                    self.firstModifierKeyCode = keyCode
                    self.recordingHint = "\(self.modifierName(keyCode)) + ..."

                    // Schedule a delayed save for single modifier if no second key pressed
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        // Only save if still recording and no second key was pressed
                        if self.isRecording && self.firstModifierKeyCode == keyCode {
                            let newConfig = ModesHotkeyConfig(
                                keyCode: keyCode,
                                secondKeyCode: 0,
                                command: false,
                                option: false,
                                control: false,
                                shift: false,
                                isModifierOnly: true,
                                isTwoKeyCombo: false
                            )

                            newConfig.save()
                            self.hotkeyConfig = newConfig
                            self.stopRecording()
                        }
                    }
                }
            }

            return event
        }
    }

    private func isModifierKeyDown(keyCode: UInt16, currentFlags: NSEvent.ModifierFlags) -> Bool {
        switch keyCode {
        case UInt16(kVK_Shift), UInt16(kVK_RightShift):
            return currentFlags.contains(.shift) && !lastFlags.contains(.shift)
        case UInt16(kVK_Command), UInt16(kVK_RightCommand):
            return currentFlags.contains(.command) && !lastFlags.contains(.command)
        case UInt16(kVK_Option), UInt16(kVK_RightOption):
            return currentFlags.contains(.option) && !lastFlags.contains(.option)
        case UInt16(kVK_Control), UInt16(kVK_RightControl):
            return currentFlags.contains(.control) && !lastFlags.contains(.control)
        case UInt16(kVK_Function):
            return currentFlags.contains(.function) && !lastFlags.contains(.function)
        case UInt16(kVK_CapsLock):
            return currentFlags.contains(.capsLock) && !lastFlags.contains(.capsLock)
        default:
            return false
        }
    }

    private func modifierName(_ keyCode: UInt16) -> String {
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
        default: return "Key"
        }
    }

    private func stopRecording() {
        isRecording = false
        firstModifierKeyCode = nil
        recordingHint = "Press key or combo..."
        if let monitor = keyDownMonitor {
            NSEvent.removeMonitor(monitor)
            keyDownMonitor = nil
        }
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            flagsMonitor = nil
        }
    }
}

// MARK: - Transcription Settings Tab
struct TranscriptionSettingsTab: View {
    @EnvironmentObject var appState: AppState
    @State private var apiKeyInput: String = ""
    @State private var showingAPIKey: Bool = false
    @State private var hasStoredKey: Bool = false
    @State private var maskedKey: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // API Key Section
                VStack(alignment: .leading, spacing: 10) {
                    SettingsSectionHeader(title: "Groq API Key", icon: "key.fill")

                    SettingsCard {
                        VStack(alignment: .leading, spacing: 12) {
                            // Privacy notice
                            HStack(spacing: 8) {
                                Image(systemName: "cloud.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.blue)
                                Text("Audio is sent to Groq servers for transcription. Requires internet.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.blue.opacity(0.1))
                            )

                            Divider()

                            // API Key status and input
                            HStack {
                                Circle()
                                    .fill(hasStoredKey ? Color.green : Color.orange)
                                    .frame(width: 8, height: 8)

                                if hasStoredKey, let masked = maskedKey {
                                    Text("API Key: \(masked)")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("No API key configured")
                                        .font(.system(size: 12))
                                        .foregroundColor(.orange)
                                }

                                Spacer()

                                if hasStoredKey {
                                    Button(action: clearAPIKey) {
                                        Text("Clear")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            HStack(spacing: 8) {
                                if showingAPIKey {
                                    TextField("gsk_...", text: $apiKeyInput)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 12, design: .monospaced))
                                } else {
                                    SecureField("gsk_...", text: $apiKeyInput)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 12, design: .monospaced))
                                }

                                Button(action: { showingAPIKey.toggle() }) {
                                    Image(systemName: showingAPIKey ? "eye.slash" : "eye")
                                        .font(.system(size: 12))
                                }
                                .buttonStyle(.plain)

                                Button(action: saveAPIKey) {
                                    Text("Save")
                                        .font(.system(size: 11, weight: .medium))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(apiKeyInput.isEmpty ? Color.gray.opacity(0.3) : Color.accentColor)
                                        .foregroundColor(.white)
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                                .disabled(apiKeyInput.isEmpty)
                            }

                            // Get API key help
                            HStack(spacing: 4) {
                                Link(destination: URL(string: "https://console.groq.com/keys")!) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.up.right.square")
                                            .font(.system(size: 10))
                                        Text("Get API key from Groq Console")
                                            .font(.system(size: 11))
                                    }
                                    .foregroundColor(.accentColor)
                                }
                            }

                            // Billing note
                            HStack(spacing: 8) {
                                Image(systemName: "dollarsign.circle")
                                    .font(.system(size: 11))
                                    .foregroundColor(.green)
                                Text("Groq bills min. 10s per request. Free tier: 25 MB max.")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Language & Prompt Section
                VStack(alignment: .leading, spacing: 10) {
                    SettingsSectionHeader(title: "Transcription Options", icon: "text.bubble")

                    SettingsCard {
                        VStack(alignment: .leading, spacing: 14) {
                            // Language hint
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Language")
                                        .font(.system(size: 13, weight: .medium))
                                    Text("Hint for better accuracy")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Picker("", selection: $appState.cloudTranscriptionLanguage) {
                                    Text("Auto-detect").tag("")
                                    Text("English").tag("en")
                                    Text("German").tag("de")
                                    Text("Spanish").tag("es")
                                    Text("French").tag("fr")
                                    Text("Italian").tag("it")
                                    Text("Portuguese").tag("pt")
                                    Text("Dutch").tag("nl")
                                    Text("Polish").tag("pl")
                                    Text("Japanese").tag("ja")
                                    Text("Chinese").tag("zh")
                                    Text("Korean").tag("ko")
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(width: 130)
                            }

                            Divider()

                            // Context prompt
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Context Prompt")
                                    .font(.system(size: 13, weight: .medium))
                                TextField("Spelling hints, technical terms...", text: $appState.cloudTranscriptionPrompt)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12))
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .onAppear {
            refreshKeyStatus()
        }
    }

    // MARK: - Helper Functions
    private func saveAPIKey() {
        guard !apiKeyInput.isEmpty else { return }
        let success = KeychainManager.shared.setGroqAPIKey(apiKeyInput)
        if success {
            Logger.shared.log("Groq API key saved to Keychain")
            apiKeyInput = ""
            refreshKeyStatus()
        } else {
            Logger.shared.log("Failed to save Groq API key", level: .error)
        }
    }

    private func clearAPIKey() {
        KeychainManager.shared.deleteGroqAPIKey()
        Logger.shared.log("Groq API key removed from Keychain")
        refreshKeyStatus()
    }

    private func refreshKeyStatus() {
        hasStoredKey = KeychainManager.shared.hasGroqAPIKey
        maskedKey = KeychainManager.shared.getMaskedGroqAPIKey()
    }
}

// MARK: - Advanced Settings Tab
struct AdvancedSettingsTab: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Developer Section
                VStack(alignment: .leading, spacing: 10) {
                    SettingsSectionHeader(title: "Developer", icon: "hammer")

                    SettingsCard {
                        SettingsToggleRow(
                            title: "Developer Mode",
                            description: "Show additional debugging information and logs",
                            isOn: $appState.developerMode
                        )
                    }
                }

                // Logs Section (Developer Mode only)
                if appState.developerMode {
                    VStack(alignment: .leading, spacing: 10) {
                        SettingsSectionHeader(title: "Logs", icon: "doc.text")

                        LogViewerSection()
                    }
                }

                // Permissions Section
                VStack(alignment: .leading, spacing: 10) {
                    SettingsSectionHeader(title: "Permissions", icon: "lock.shield")

                    SettingsCard {
                        VStack(spacing: 12) {
                            PermissionRow(permission: .microphone)
                            Divider()
                            PermissionRow(permission: .accessibility)
                            Divider()

                            Button(action: {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                            }) {
                                HStack {
                                    Image(systemName: "gear")
                                        .font(.system(size: 12))
                                    Text("Open System Settings")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundColor(.accentColor)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(20)
        }
    }
}

// MARK: - Permission Row
struct PermissionRow: View {
    enum Permission {
        case microphone
        case accessibility
    }

    let permission: Permission
    @State private var status: String = "Checking..."
    @State private var isGranted: Bool = false

    var body: some View {
        HStack {
            Image(systemName: permission == .microphone ? "mic.fill" : "accessibility")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 24)

            Text(permission == .microphone ? "Microphone" : "Accessibility")
                .font(.system(size: 13))

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(isGranted ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(status)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            checkPermission()
        }
    }

    private func checkPermission() {
        Task {
            switch permission {
            case .microphone:
                let granted = await AppState.shared.permissionManager.hasMicrophonePermission()
                await MainActor.run {
                    status = granted ? "Granted" : "Not Granted"
                    isGranted = granted
                }
            case .accessibility:
                let granted = AppState.shared.permissionManager.hasAccessibilityPermission()
                status = granted ? "Granted" : "Not Granted"
                isGranted = granted
            }
        }
    }
}

// MARK: - Log Viewer Section
struct LogViewerSection: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button(action: {
                        appState.refreshLogs()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10))
                            Text("Refresh")
                                .font(.system(size: 11))
                        }
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        Logger.shared.clearLogs()
                        appState.refreshLogs()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                            Text("Clear")
                                .font(.system(size: 11))
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text("\(appState.logs.suffix(100).count) entries")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(appState.logs.suffix(100)) { log in
                            HStack(alignment: .top, spacing: 6) {
                                Text(log.timestamp, style: .time)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 70, alignment: .leading)

                                Text("[\(log.level.rawValue)]")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(logLevelColor(log.level))
                                    .frame(width: 50, alignment: .leading)

                                Text(log.message)
                                    .font(.system(size: 10, design: .monospaced))
                                    .lineLimit(nil)
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(height: 140)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
            }
        }
        .onAppear {
            appState.refreshLogs()
        }
    }

    private func logLevelColor(_ level: Logger.LogLevel) -> Color {
        switch level {
        case .debug: return .gray
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
}

// MARK: - About Tab
struct AboutTab: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // App Icon and Info
            VStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 100)

                VStack(spacing: 6) {
                    Text("Mute")
                        .font(.system(size: 24, weight: .bold))

                    Text("Version 1.4.2")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)

                    Text("Speech to Text Productivity Engine")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
                .frame(height: 24)

            // Licenses Section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "doc.text")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("Licenses")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    LicenseRow(name: "Groq Cloud API", license: "Proprietary")
                    LicenseRow(name: "KeyboardShortcuts", license: "MIT")
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .padding(.horizontal, 40)

            Spacer()

            // Privacy Notice
            HStack(spacing: 6) {
                Image(systemName: "cloud.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.blue)
                Text("Audio is sent to Groq for transcription. Requires internet and API key.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - License Row
struct LicenseRow: View {
    let name: String
    let license: String

    var body: some View {
        HStack {
            Text(name)
                .font(.system(size: 11))
                .foregroundColor(.primary)
            Spacer()
            Text(license)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Modes Settings Tab
struct ModesSettingsTab: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var modeManager = TranscriptionModeManager.shared
    @State private var showingModeEditor = false
    @State private var editingMode: TranscriptionMode?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Quick Dictation Mode Section
                VStack(alignment: .leading, spacing: 10) {
                    SettingsSectionHeader(title: "Quick Dictation Mode", icon: "mic.fill", iconColor: .blue)

                    SettingsCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Transform Mode")
                                        .font(.system(size: 13, weight: .medium))
                                    Text("Applied when using hotkey dictation")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Picker("", selection: Binding(
                                    get: { modeManager.dictationModeId },
                                    set: { modeManager.setDictationMode($0) }
                                )) {
                                    Text("None").tag(nil as UUID?)
                                    ForEach(modeManager.modes.filter { !$0.isBuiltIn }) { mode in
                                        Text(mode.name).tag(mode.id as UUID?)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(width: 160)
                            }
                        }
                    }
                }

                // Audio File Transcription Mode Section
                VStack(alignment: .leading, spacing: 10) {
                    SettingsSectionHeader(title: "Audio File Mode", icon: "waveform.badge.plus", iconColor: .green)

                    SettingsCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Transform Mode")
                                        .font(.system(size: 13, weight: .medium))
                                    Text("Applied when transcribing audio files")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Picker("", selection: Binding(
                                    get: { modeManager.fileTranscriptionModeId },
                                    set: { modeManager.setFileTranscriptionMode($0) }
                                )) {
                                    Text("None").tag(nil as UUID?)
                                    ForEach(modeManager.modes.filter { !$0.isBuiltIn }) { mode in
                                        Text(mode.name).tag(mode.id as UUID?)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(width: 160)
                            }
                        }
                    }
                }

                // Your Modes Section
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SettingsSectionHeader(title: "Your Modes", icon: "list.bullet.rectangle", iconColor: .purple)
                        Spacer()
                    }

                    SettingsCard {
                        VStack(alignment: .leading, spacing: 0) {
                            let userModes = modeManager.modes.filter { !$0.isBuiltIn }

                            if userModes.isEmpty {
                                HStack {
                                    Image(systemName: "wand.and.stars")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                    Text("No modes created yet")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 8)
                            } else {
                                // Column headers
                                HStack(spacing: 8) {
                                    Text("Order")
                                        .fixedSize()
                                        .frame(width: 34)
                                    Text("Cycle")
                                        .fixedSize()
                                        .frame(width: 34)
                                    Text("Mode")
                                        .fixedSize()
                                    Spacer()
                                }
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.top, 4)
                                .padding(.bottom, 2)

                                ReorderableModeList(
                                    modes: userModes,
                                    dictationModeId: modeManager.dictationModeId,
                                    fileTranscriptionModeId: modeManager.fileTranscriptionModeId,
                                    cyclingModeIds: modeManager.cyclingModeIds,
                                    onEdit: { mode in
                                        editingMode = mode
                                        showingModeEditor = true
                                    },
                                    onDelete: { mode in
                                        modeManager.deleteMode(id: mode.id)
                                    },
                                    onMove: { source, destination in
                                        modeManager.moveModes(from: source, to: destination)
                                    },
                                    onToggleCycling: { mode in
                                        modeManager.toggleCycling(for: mode.id)
                                    }
                                )
                            }

                            Divider()
                                .padding(.vertical, 8)

                            // Add Mode button
                            Button(action: {
                                editingMode = nil
                                showingModeEditor = true
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.accentColor)
                                    Text("Add Mode")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // How Modes Work Section
                VStack(alignment: .leading, spacing: 10) {
                    SettingsSectionHeader(title: "How Modes Work", icon: "questionmark.circle", iconColor: .blue)

                    SettingsCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top, spacing: 10) {
                                Text("1.")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.accentColor)
                                Text("Record audio as usual with your hotkey")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }

                            HStack(alignment: .top, spacing: 10) {
                                Text("2.")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.accentColor)
                                Text("Groq Whisper transcribes your speech to text")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }

                            HStack(alignment: .top, spacing: 10) {
                                Text("3.")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.accentColor)
                                Text("The selected mode's GPT model transforms the text using your prompt")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }

                            HStack(alignment: .top, spacing: 10) {
                                Text("4.")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.accentColor)
                                Text("Transformed text is pasted into your app")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .sheet(isPresented: $showingModeEditor) {
            ModeEditorSheet(
                mode: editingMode,
                onSave: { name, prompt, modelId, temperature, maxTokens in
                    if let existingMode = editingMode {
                        modeManager.updateMode(
                            id: existingMode.id,
                            name: name,
                            prompt: prompt,
                            modelId: modelId,
                            temperature: temperature,
                            maxTokens: maxTokens
                        )
                    } else {
                        modeManager.createMode(
                            name: name,
                            prompt: prompt,
                            modelId: modelId,
                            temperature: temperature,
                            maxTokens: maxTokens
                        )
                    }
                    showingModeEditor = false
                },
                onCancel: {
                    showingModeEditor = false
                }
            )
        }
    }
}

// MARK: - Reorderable Mode List
struct ReorderableModeList: View {
    let modes: [TranscriptionMode]
    let dictationModeId: UUID?
    let fileTranscriptionModeId: UUID?
    let cyclingModeIds: Set<UUID>
    let onEdit: (TranscriptionMode) -> Void
    let onDelete: (TranscriptionMode) -> Void
    let onMove: (IndexSet, Int) -> Void
    let onToggleCycling: (TranscriptionMode) -> Void

    var body: some View {
        ForEach(Array(modes.enumerated()), id: \.element.id) { index, mode in
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    // Drag handle
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.5))
                        .frame(width: 34)

                    // Cycling toggle
                    Button(action: { onToggleCycling(mode) }) {
                        Image(systemName: cyclingModeIds.contains(mode.id) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 14))
                            .foregroundColor(cyclingModeIds.contains(mode.id) ? .purple : .secondary.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .frame(width: 34)
                    .help("Include in hotkey cycling")

                    // Mode content
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mode.name)
                            .font(.system(size: 13, weight: .medium))

                        HStack(spacing: 6) {
                            Text(TransformationModel(rawValue: mode.modelId)?.displayName ?? mode.modelId)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)

                            if mode.id == dictationModeId {
                                HStack(spacing: 3) {
                                    Image(systemName: "mic.fill")
                                        .font(.system(size: 8))
                                    Text("Dictation")
                                        .font(.system(size: 9, weight: .medium))
                                }
                                .foregroundColor(.blue)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(4)
                            }

                            if mode.id == fileTranscriptionModeId {
                                HStack(spacing: 3) {
                                    Image(systemName: "waveform")
                                        .font(.system(size: 8))
                                    Text("Audio File")
                                        .font(.system(size: 9, weight: .medium))
                                }
                                .foregroundColor(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(4)
                            }
                        }
                    }

                    Spacer()

                    // Edit button
                    Button(action: { onEdit(mode) }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)

                    // Delete button
                    Button(action: { onDelete(mode) }) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .draggable(mode.id.uuidString) {
                    // Drag preview
                    HStack {
                        Image(systemName: "line.3.horizontal")
                        Text(mode.name)
                    }
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                }
                .dropDestination(for: String.self) { items, _ in
                    guard let droppedId = items.first,
                          let droppedUUID = UUID(uuidString: droppedId),
                          let sourceIndex = modes.firstIndex(where: { $0.id == droppedUUID }),
                          sourceIndex != index else {
                        return false
                    }
                    onMove(IndexSet(integer: sourceIndex), index > sourceIndex ? index + 1 : index)
                    return true
                }

                if index < modes.count - 1 {
                    Divider()
                        .padding(.leading, 28)
                }
            }
        }
    }
}

// MARK: - Mode List Row
struct ModeListRow: View {
    let mode: TranscriptionMode
    let isActiveDictation: Bool
    let isActiveFileTranscription: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var modelDisplayName: String {
        TransformationModel(rawValue: mode.modelId)?.displayName ?? mode.modelId
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(mode.name)
                    .font(.system(size: 13, weight: .medium))

                HStack(spacing: 6) {
                    Text(modelDisplayName)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    // Active indicators
                    if isActiveDictation {
                        HStack(spacing: 3) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 8))
                            Text("Dictation")
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundColor(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
                    }

                    if isActiveFileTranscription {
                        HStack(spacing: 3) {
                            Image(systemName: "waveform")
                                .font(.system(size: 8))
                            Text("Audio File")
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundColor(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(4)
                    }
                }
            }

            Spacer()

            // Edit button
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)

            // Delete button
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundColor(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Mode Editor Sheet
struct ModeEditorSheet: View {
    let mode: TranscriptionMode?
    let onSave: (String, String, String, Double, Int) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @State private var prompt: String = ""
    @State private var selectedModel: TransformationModel = .gptOss20b
    @State private var selectedTemperature: TemperaturePreset = .creative
    @State private var selectedMaxTokens: MaxTokensPreset = .long
    @State private var showAdvanced: Bool = false

    private var isEditing: Bool {
        mode != nil
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !prompt.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isEditing ? "Edit Mode" : "New Mode")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Configure how your transcription will be transformed")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Name field
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Name", systemImage: "textformat")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)

                        TextField("e.g., Meeting Notes, Email Polish", text: $name)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(NSColor.textBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )
                    }

                    // Model picker
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Model", systemImage: "cpu")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)

                        HStack(spacing: 10) {
                            ForEach(TransformationModel.allCases.filter { $0 != .none }) { model in
                                ModelSelectionCard(
                                    model: model,
                                    isSelected: selectedModel == model,
                                    action: { selectedModel = model }
                                )
                            }
                        }
                    }

                    // Prompt field
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Prompt", systemImage: "text.bubble")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)

                        TextEditor(text: $prompt)
                            .font(.system(size: 12))
                            .frame(height: 80)
                            .padding(8)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )

                        Text("Describe how to transform the text. E.g., \"Format as bullet points\" or \"Correct grammar and make professional\"")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 2)
                    }

                    // Advanced Settings
                    VStack(alignment: .leading, spacing: 12) {
                        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showAdvanced.toggle() } }) {
                            HStack(spacing: 6) {
                                Image(systemName: showAdvanced ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .frame(width: 12)

                                Text("Advanced Settings")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.primary)

                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)

                        if showAdvanced {
                            VStack(spacing: 14) {
                                // Temperature
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Temperature")
                                            .font(.system(size: 12, weight: .medium))
                                        Text("Controls output consistency")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    Picker("", selection: $selectedTemperature) {
                                        ForEach(TemperaturePreset.allCases) { preset in
                                            Text(preset.displayName).tag(preset)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(width: 130)
                                }

                                Divider()

                                // Max Tokens
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Max Length")
                                            .font(.system(size: 12, weight: .medium))
                                        Text("Maximum response length")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    Picker("", selection: $selectedMaxTokens) {
                                        ForEach(MaxTokensPreset.allCases) { preset in
                                            Text(preset.displayName).tag(preset)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(width: 130)
                                }
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(NSColor.controlBackgroundColor))
                            )
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
                .padding(20)
            }

            Divider()

            // Footer buttons
            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 80)
                }
                .keyboardShortcut(.escape)
                .buttonStyle(.plain)
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )

                Spacer()

                Button(action: {
                    onSave(
                        name.trimmingCharacters(in: .whitespaces),
                        prompt.trimmingCharacters(in: .whitespaces),
                        selectedModel.rawValue,
                        selectedTemperature.rawValue,
                        selectedMaxTokens.rawValue
                    )
                }) {
                    Text(isEditing ? "Save Changes" : "Create Mode")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 110)
                }
                .keyboardShortcut(.return)
                .disabled(!canSave)
                .buttonStyle(.plain)
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(canSave ? Color.accentColor : Color.gray.opacity(0.3))
                )
            }
            .padding(16)
        }
        .frame(width: 440, height: 520)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            if let mode = mode {
                name = mode.name
                prompt = mode.prompt
                selectedModel = TransformationModel(rawValue: mode.modelId) ?? .gptOss20b
                selectedTemperature = TemperaturePreset.closest(to: mode.temperature)
                selectedMaxTokens = MaxTokensPreset.closest(to: mode.maxTokens)
            }
        }
    }
}

// MARK: - Model Selection Card
struct ModelSelectionCard: View {
    let model: TransformationModel
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: model == .gptOss20b ? "hare" : "tortoise")
                        .font(.system(size: 14))
                        .foregroundColor(isSelected ? .white : .accentColor)

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                    }
                }

                Spacer()

                VStack(alignment: .leading, spacing: 2) {
                    Text(model == .gptOss20b ? "GPT OSS 20B" : "GPT OSS 120B")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isSelected ? .white : .primary)

                    Text(model == .gptOss20b ? "Faster" : "Higher Quality")
                        .font(.system(size: 10))
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 70)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
