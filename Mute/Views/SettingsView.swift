// SettingsView.swift
// Mute

import SwiftUI
import AppKit
import AVFoundation
import Carbon.HIToolbox

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            TranscriptionSettingsTab()
                .tabItem {
                    Label("Transcription", systemImage: "waveform")
                }

            EngineSettingsTab()
                .tabItem {
                    Label("Model", systemImage: "cpu")
                }

            AdvancedSettingsTab()
                .tabItem {
                    Label("Advanced", systemImage: "wrench.and.screwdriver")
                }

            AboutTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 520, height: 520)
        .environmentObject(appState)
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

            var newConfig = HotkeyConfig(
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
                var newConfig = HotkeyConfig(
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

// MARK: - Transcription Settings Tab
struct TranscriptionSettingsTab: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Capture to Notes Section
                VStack(alignment: .leading, spacing: 10) {
                    SettingsSectionHeader(title: "Capture to Notes", icon: "note.text")

                    SettingsCard {
                        VStack(alignment: .leading, spacing: 14) {
                            SettingsToggleRow(
                                title: "Continuous capture mode",
                                description: "Transcribe and save periodically while recording",
                                isOn: $appState.continuousCaptureMode
                            )

                            if appState.continuousCaptureMode {
                            }

                            Divider()

                            SettingsToggleRow(
                                title: "Identify speakers",
                                description: "Label different speakers in the transcription",
                                isOn: $appState.enableDiarization
                            )

                            if appState.enableDiarization {
                                // Info box for diarization
                                HStack(spacing: 8) {
                                    Image(systemName: "person.2.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(.purple)
                                    Text("Works best with 2-4 distinct speakers. May increase processing time.")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.purple.opacity(0.1))
                                )
                            }
                        }
                    }
                }

            }
            .padding(20)
        }
    }
}

// MARK: - Engine Settings Tab (Unified Cloud + Model)
struct EngineSettingsTab: View {
    @EnvironmentObject var appState: AppState
    @State private var apiKeyInput: String = ""
    @State private var showingAPIKey: Bool = false
    @State private var hasStoredKey: Bool = false
    @State private var maskedKey: String? = nil

    private var isCloudMode: Bool {
        TranscriptionBackend(rawValue: appState.transcriptionBackendRaw) == .groqWhisper
    }

    // Fallback Whisper models if backend hasn't provided them yet
    private var whisperModels: [(id: String, name: String)] {
        let backendModels = appState.backendManager.availableModels.filter { $0.id != "parakeet" }
        if !backendModels.isEmpty {
            return backendModels.map { ($0.id, $0.name) }
        }
        // Fallback list
        return [
            ("base", "Whisper Base"),
            ("small", "Whisper Small"),
            ("medium", "Whisper Medium"),
            ("large-v3-turbo", "Whisper Large V3 Turbo")
        ]
    }

    // All models including Parakeet for local dictation
    private var allLocalModels: [(id: String, name: String)] {
        var models: [(id: String, name: String)] = [("parakeet", "NVIDIA Parakeet TDT v3")]
        models.append(contentsOf: whisperModels)
        return models
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // MARK: - Dictation Engine Section
                VStack(alignment: .leading, spacing: 10) {
                    SettingsSectionHeader(title: "Dictation Engine", icon: "mic.fill")

                    SettingsCard {
                        VStack(alignment: .leading, spacing: 14) {
                            // Backend selector
                            Picker("Engine", selection: $appState.transcriptionBackendRaw) {
                                ForEach(TranscriptionBackend.allCases) { backend in
                                    Text(backend.displayName).tag(backend.rawValue)
                                }
                            }
                            .pickerStyle(.radioGroup)

                            // Show relevant options based on selection
                            if isCloudMode {
                                // Cloud mode options
                                cloudModeOptions
                            } else {
                                // Local mode options
                                localModeOptions
                            }
                        }
                    }
                }

                // MARK: - Capture to Notes Engine Section
                VStack(alignment: .leading, spacing: 10) {
                    SettingsSectionHeader(title: "Capture to Notes Engine", icon: "note.text")

                    SettingsCard {
                        VStack(alignment: .leading, spacing: 14) {
                            // Info about why only local Whisper
                            HStack(spacing: 8) {
                                Image(systemName: "info.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.blue)
                                Text("Capture to Notes requires local Whisper models for word-level timestamps.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.blue.opacity(0.1))
                            )

                            // Capture to Notes Model Picker
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Model")
                                        .font(.system(size: 13, weight: .medium))
                                    Text("Whisper models with timestamp support")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Picker("", selection: $appState.captureNotesModel) {
                                    ForEach(whisperModels, id: \.id) { model in
                                        Text(model.name).tag(model.id)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(width: 200)
                            }
                        }
                    }
                }

                // MARK: - Performance Section (only for local models)
                if !isCloudMode || true { // Always show - Capture to Notes uses local
                    VStack(alignment: .leading, spacing: 10) {
                        SettingsSectionHeader(title: "Performance", icon: "bolt.fill", iconColor: .orange)

                        SettingsCard {
                            VStack(alignment: .leading, spacing: 14) {
                                if !isCloudMode {
                                    SettingsToggleRow(
                                        title: "Keep dictation model ready",
                                        description: "Pre-load \(modelDisplayName(appState.dictationModel)) for faster Start/Stop",
                                        isOn: $appState.keepDictationModelReady
                                    )

                                    Divider()
                                }

                                SettingsToggleRow(
                                    title: "Keep capture model ready",
                                    description: "Pre-load \(modelDisplayName(appState.captureNotesModel)) for faster Capture to Notes",
                                    isOn: $appState.keepCaptureModelReady
                                )

                                if appState.keepDictationModelReady || appState.keepCaptureModelReady {
                                    Divider()

                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Keep loaded for")
                                                .font(.system(size: 13, weight: .medium))
                                            Text("Unload models after idle period")
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Picker("", selection: $appState.keepModelWarmDuration) {
                                            Text("1 hour").tag("1h")
                                            Text("4 hours").tag("4h")
                                            Text("8 hours").tag("8h")
                                            Text("16 hours").tag("16h")
                                            Text("Always").tag("permanent")
                                        }
                                        .labelsHidden()
                                        .pickerStyle(.menu)
                                        .frame(width: 120)
                                    }

                                    HStack(spacing: 8) {
                                        Image(systemName: "memorychip")
                                            .font(.system(size: 11))
                                            .foregroundColor(.orange)
                                        Text("Models use 1-3 GB RAM each when loaded.")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.orange.opacity(0.1))
                                    )
                                }
                            }
                        }
                    }
                    .onChange(of: appState.keepDictationModelReady) { _ in
                        appState.syncKeepWarmSettings()
                    }
                    .onChange(of: appState.keepCaptureModelReady) { _ in
                        appState.syncKeepWarmSettings()
                    }
                    .onChange(of: appState.keepModelWarmDuration) { _ in
                        appState.syncKeepWarmSettings()
                    }
                }

                // MARK: - Available Local Models Section
                VStack(alignment: .leading, spacing: 10) {
                    SettingsSectionHeader(title: "Available Local Models", icon: "square.stack.3d.up")

                    SettingsCard {
                        VStack(alignment: .leading, spacing: 12) {
                            // Parakeet
                            ModelStatusRow(
                                name: "NVIDIA Parakeet TDT v3",
                                description: "Fast, multilingual (25 languages)",
                                size: "~2.5 GB",
                                isLoaded: appState.modelStatus == .ready,
                                isAvailable: appState.modelStatus == .ready || appState.modelStatus == .downloaded,
                                isDownloading: appState.modelStatus == .downloading,
                                downloadProgress: appState.modelDownloadProgress,
                                onDownload: {
                                    Task { await appState.downloadModel() }
                                },
                                onLoad: {
                                    appState.backendManager.loadModel("parakeet")
                                }
                            )

                            Divider()

                            // Show Whisper models - use backend data if available, otherwise fallback
                            let whisperFromBackend = appState.backendManager.availableModels.filter { $0.id != "parakeet" }
                            if !whisperFromBackend.isEmpty {
                                // Backend connected and has Whisper models
                                ForEach(whisperFromBackend) { model in
                                    ModelStatusRow(
                                        name: model.name,
                                        description: model.description,
                                        size: model.size,
                                        isLoaded: model.loaded,
                                        isAvailable: model.downloaded,
                                        isDownloading: false,
                                        downloadProgress: 0,
                                        onDownload: nil,
                                        onLoad: {
                                            appState.backendManager.loadModel(model.id)
                                        }
                                    )
                                    if model.id != whisperFromBackend.last?.id {
                                        Divider()
                                    }
                                }
                            } else {
                                // Backend not connected or no models yet - show fallback list
                                ForEach(whisperModels, id: \.id) { model in
                                    ModelStatusRow(
                                        name: model.name,
                                        description: "OpenAI Whisper model",
                                        size: whisperModelSize(model.id),
                                        isLoaded: false,
                                        isAvailable: false,
                                        isDownloading: false,
                                        downloadProgress: 0,
                                        onDownload: nil,
                                        onLoad: {
                                            appState.backendManager.loadModel(model.id)
                                        }
                                    )
                                    if model.id != whisperModels.last?.id {
                                        Divider()
                                    }
                                }
                            }

                            // Only show "not installed" warning if backend IS connected but Whisper is not available
                            if appState.backendStatus == .connected && !appState.backendManager.whisperAvailable {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(.orange)
                                    Text("Whisper not installed. Install with: pip install openai-whisper")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.top, 4)
                            }
                        }
                    }
                }

                // MARK: - Model Actions Section
                VStack(alignment: .leading, spacing: 10) {
                    SettingsSectionHeader(title: "Model Actions", icon: "arrow.down.circle")

                    SettingsCard {
                        HStack(spacing: 12) {
                            ActionButton(
                                title: "Download",
                                icon: "arrow.down.circle.fill",
                                color: .accentColor,
                                isDisabled: appState.modelStatus == .downloading || appState.modelStatus == .ready
                            ) {
                                Task { await appState.downloadModel() }
                            }

                            ActionButton(
                                title: "Clear Cache",
                                icon: "trash",
                                color: .orange,
                                isDisabled: appState.modelStatus == .notDownloaded
                            ) {
                                appState.clearModelCache()
                            }

                            ActionButton(
                                title: "Show in Finder",
                                icon: "folder",
                                color: .secondary
                            ) {
                                showModelInFinder()
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .onAppear {
            refreshKeyStatus()
            appState.syncKeepWarmSettings()
        }
    }

    // MARK: - Local Mode Options
    @ViewBuilder
    private var localModeOptions: some View {
        Divider()

        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Model")
                    .font(.system(size: 13, weight: .medium))
                Text("Local model for dictation")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Picker("", selection: $appState.dictationModel) {
                ForEach(allLocalModels, id: \.id) { model in
                    Text(model.name).tag(model.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 180)
        }

        HStack(spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 11))
                .foregroundColor(.green)
            Text("Audio is processed entirely on-device. Nothing is sent to external servers.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.green.opacity(0.1))
        )
    }

    // MARK: - Cloud Mode Options
    @ViewBuilder
    private var cloudModeOptions: some View {
        Divider()

        // Privacy warning
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
        VStack(alignment: .leading, spacing: 12) {
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
        }

        Divider()

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

        // Context prompt
        VStack(alignment: .leading, spacing: 6) {
            Text("Context Prompt")
                .font(.system(size: 13, weight: .medium))
            TextField("Spelling hints, technical terms...", text: $appState.cloudTranscriptionPrompt)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
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

    private func showModelInFinder() {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Mute/Models")
        if let url = url {
            NSWorkspace.shared.open(url)
        }
    }

    private func modelDisplayName(_ modelId: String) -> String {
        switch modelId {
        case "parakeet": return "Parakeet"
        case "base": return "Whisper Base"
        case "large-v3-turbo": return "Whisper Turbo"
        default: return modelId
        }
    }

    private func whisperModelSize(_ modelId: String) -> String {
        switch modelId {
        case "base": return "~140 MB"
        case "small": return "~460 MB"
        case "medium": return "~1.5 GB"
        case "large-v3-turbo": return "~1.5 GB"
        default: return "~1 GB"
        }
    }
}

// MARK: - Model Status Row
struct ModelStatusRow: View {
    let name: String
    let description: String
    let size: String
    let isLoaded: Bool
    let isAvailable: Bool
    let isDownloading: Bool
    let downloadProgress: Double
    let onDownload: (() -> Void)?
    let onLoad: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            // Status indicator
            Circle()
                .fill(isLoaded ? Color.green : (isAvailable ? Color.gray : Color.orange))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 12, weight: .medium))
                HStack(spacing: 4) {
                    Text(description)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("•")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text(size)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if isDownloading {
                HStack(spacing: 6) {
                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.accentColor)
                                .frame(width: geometry.size.width * downloadProgress, height: 6)
                        }
                    }
                    .frame(width: 60, height: 6)

                    // Percentage text
                    Text("\(Int(downloadProgress * 100))%")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 32, alignment: .trailing)
                }
            } else if isLoaded {
                Text("Loaded")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(4)
            } else if isAvailable {
                // Model is downloaded - click to load into memory
                Button(action: { onLoad?() }) {
                    Text("Downloaded")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            } else {
                // Not cached - click to download (or load if download not provided)
                Button(action: {
                    if let download = onDownload {
                        download()
                    } else {
                        onLoad?()
                    }
                }) {
                    Text("Download")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Model Info Row
struct ModelInfoRow: View {
    let label: String
    let value: String
    var isPath: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, design: isPath ? .monospaced : .default))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - Action Button
struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(isDisabled ? .gray : color)

                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isDisabled ? .gray : .primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(isDisabled ? 0.5 : 1))
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
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

                // Backend Status Section
                VStack(alignment: .leading, spacing: 10) {
                    SettingsSectionHeader(title: "Backend Status", icon: "server.rack", iconColor: backendStatusColor)

                    SettingsCard {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(backendStatusColor.opacity(0.2))
                                    .frame(width: 36, height: 36)

                                Circle()
                                    .fill(backendStatusColor)
                                    .frame(width: 14, height: 14)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(backendStatusText)
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Python backend service")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button(action: {
                                Task {
                                    await appState.backendManager.restart()
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 11))
                                    Text("Restart")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color(NSColor.controlBackgroundColor))
                                )
                            }
                            .buttonStyle(.plain)
                        }
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

    private var backendStatusColor: Color {
        switch appState.backendStatus {
        case .disconnected: return .gray
        case .connecting: return .orange
        case .connected: return .green
        case .error: return .red
        }
    }

    private var backendStatusText: String {
        switch appState.backendStatus {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .error(let msg): return "Error: \(msg)"
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

                    Text("Version 1.2.0")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)

                    Text("Speech-to-text with local and cloud transcription")
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
                    LicenseRow(name: "Parakeet TDT v3 Model", license: "CC-BY-4.0")
                    LicenseRow(name: "OpenAI Whisper", license: "MIT")
                    LicenseRow(name: "Groq Cloud API", license: "Proprietary")
                    LicenseRow(name: "KeyboardShortcuts", license: "MIT")
                    LicenseRow(name: "Starscream", license: "Apache 2.0")
                    LicenseRow(name: "NeMo Toolkit", license: "Apache 2.0")
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
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                    Text("Local mode: All transcription is performed on-device.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 6) {
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.blue)
                    Text("Cloud mode: Audio is sent to Groq servers for transcription.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
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

