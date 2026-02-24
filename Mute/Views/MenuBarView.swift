// MenuBarView.swift
// Mute

import SwiftUI
import UniformTypeIdentifiers

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var modeManager = TranscriptionModeManager.shared
    @State private var hotkeyDisplay = HotkeyConfig.load().displayString
    @State private var isHoveringRecord = false
    @State private var isHoveringSettings = false
    @State private var isHoveringQuit = false
    @State private var isHoveringImport = false
    @State private var showingFilePicker = false

    var body: some View {
        VStack(spacing: 0) {
            // Header with status
            headerSection

            // Main content area
            VStack(spacing: 12) {
                // Recording button
                recordingButton

                // Last transcription preview
                if !appState.finalText.isEmpty && appState.recordingState == .done && !appState.isCaptureMode {
                    transcriptionPreview
                }

                // Error message
                if case .error(let message) = appState.recordingState {
                    errorSection(message: message)
                }

                // Stats section
                statsSection

                // Audio file import
                audioImportSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()
                .padding(.horizontal, 12)

            // Footer with settings and quit
            footerSection
        }
        .frame(width: 320)
        .background(Color(NSColor.windowBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: .hotkeyDidChange)) { _ in
            hotkeyDisplay = HotkeyConfig.load().displayString
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
    }

    // MARK: - Header Section
    private var headerSection: some View {
        HStack(spacing: 10) {
            // Status indicator
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.2))
                    .frame(width: 32, height: 32)

                Circle()
                    .fill(statusColor)
                    .frame(width: 12, height: 12)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Mute")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)

                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Mode picker
            modePicker

            // Hotkey badge
            Text(hotkeyDisplay)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    // MARK: - Mode Picker
    private var modePicker: some View {
        Menu {
            Button(action: { modeManager.setActiveMode(nil) }) {
                HStack {
                    Text("None")
                    if modeManager.activeModeId == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }

            if !modeManager.modes.filter({ !$0.isBuiltIn }).isEmpty {
                Divider()

                ForEach(modeManager.modes.filter { !$0.isBuiltIn }) { mode in
                    Button(action: { modeManager.setActiveMode(mode.id) }) {
                        HStack {
                            Text(mode.name)
                            if modeManager.activeModeId == mode.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Divider()

            Button(action: openModesSettings) {
                HStack {
                    Image(systemName: "gear")
                    Text("Manage Modes...")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 9))
                Text(modeManager.activeMode?.name ?? "None")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(.purple)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.purple.opacity(0.15))
            .cornerRadius(6)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func openModesSettings() {
        // Open settings window directly to the Modes tab
        SettingsCoordinator.shared.requestOpenSettings(tab: .modes)
    }

    // MARK: - Recording Button
    private var recordingButton: some View {
        Button(action: toggleRecording) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(recordingButtonColor.opacity(0.15))
                        .frame(width: 40, height: 40)

                    Image(systemName: appState.recordingState == .recording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(recordingButtonColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(appState.recordingState == .recording ? "Stop Recording" : "Start Recording")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)

                    Text(appState.recordingState == .recording ? "Click or press hotkey" : "Press hotkey to record")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if appState.recordingState == .processing {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 20, height: 20)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHoveringRecord ? Color(NSColor.controlBackgroundColor) : Color(NSColor.controlBackgroundColor).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(recordingButtonColor.opacity(appState.recordingState == .recording ? 0.5 : 0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(appState.recordingState == .processing)
        .onHover { hovering in
            isHoveringRecord = hovering
        }
    }

    private var recordingButtonColor: Color {
        switch appState.recordingState {
        case .recording: return .red
        case .processing: return .orange
        default: return .accentColor
        }
    }

    // MARK: - Transcription Preview
    private var transcriptionPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "text.quote")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text("Last Transcription")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Text(appState.finalText.prefix(120) + (appState.finalText.count > 120 ? "..." : ""))
                .font(.system(size: 12))
                .foregroundColor(.primary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.green.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.green.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Stats Section
    private var statsSection: some View {
        HStack(spacing: 8) {
            miniStatCard(value: appState.todayDictations, label: "Today", icon: "sun.max.fill", color: .orange)
            miniStatCard(value: appState.weekDictations, label: "Week", icon: "calendar", color: .blue)
            miniStatCard(value: appState.totalDictations, label: "Total", icon: "infinity", color: .purple)
        }
    }

    private func miniStatCard(value: Int, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(color)

            Text("\(value)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Audio Import Section
    private var audioImportSection: some View {
        Button(action: {
            if appState.isTranscribingFile {
                appState.cancelFileTranscription()
            } else {
                showingFilePicker = true
            }
        }) {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(appState.isTranscribingFile ? Color.red.opacity(0.15) : Color.green.opacity(0.15))
                        .frame(width: 36, height: 36)

                    if appState.isTranscribingFile {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.red)
                    } else {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.green)
                    }
                }

                // Text
                VStack(alignment: .leading, spacing: 2) {
                    Text(appState.isTranscribingFile ? "Cancel Transcription" : "Import Audio File")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)

                    if appState.isTranscribingFile && !appState.fileTranscriptionProgress.isEmpty {
                        Text(appState.fileTranscriptionProgress)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    } else {
                        Text("Transcribe to Notes")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Arrow or cancel icon
                if appState.isTranscribingFile {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.green.opacity(0.6))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHoveringImport
                        ? (appState.isTranscribingFile ? Color.red.opacity(0.12) : Color.green.opacity(0.12))
                        : (appState.isTranscribingFile ? Color.red.opacity(0.06) : Color.green.opacity(0.06)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(appState.isTranscribingFile ? Color.red.opacity(0.2) : Color.green.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHoveringImport = hovering
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let fileURL = urls.first else { return }

            appState.isTranscribingFile = true
            appState.fileTranscriptionProgress = "Starting..."

            let task = Task {
                defer {
                    Task { @MainActor in
                        appState.setFileTranscriptionTask(nil)
                    }
                }

                do {
                    guard fileURL.startAccessingSecurityScopedResource() else {
                        throw AudioFileTranscriberError.fileNotFound
                    }
                    defer { fileURL.stopAccessingSecurityScopedResource() }

                    // Check for cancellation before starting
                    try Task.checkCancellation()

                    try await AudioFileTranscriber.shared.transcribeToNotes(
                        fileURL: fileURL,
                        mode: modeManager.activeMode,
                        language: appState.cloudTranscriptionLanguage.isEmpty ? nil : appState.cloudTranscriptionLanguage,
                        prompt: appState.cloudTranscriptionPrompt.isEmpty ? nil : appState.cloudTranscriptionPrompt,
                        progressHandler: { progress in
                            Task { @MainActor in
                                appState.fileTranscriptionProgress = progress
                            }
                        }
                    )

                    await MainActor.run {
                        appState.isTranscribingFile = false
                        appState.fileTranscriptionProgress = ""
                    }
                } catch is CancellationError {
                    // User cancelled - show cancelled state
                    Logger.shared.log("File transcription cancelled by user", level: .info)

                    await MainActor.run {
                        appState.fileTranscriptionError = true
                        appState.fileTranscriptionProgress = "Cancelled"
                        appState.fileTranscriptionProgressValue = 0.0
                    }

                    // Keep cancelled state visible briefly
                    await withCheckedContinuation { continuation in
                        Task.detached {
                            try? await Task.sleep(nanoseconds: 2_500_000_000)
                            continuation.resume()
                        }
                    }

                    await MainActor.run {
                        appState.fileTranscriptionError = false
                        appState.isTranscribingFile = false
                        appState.fileTranscriptionProgress = ""
                    }
                } catch {
                    Logger.shared.log("File transcription failed: \(error)", level: .error)

                    // Provide user-friendly error message
                    let userMessage: String
                    if error.localizedDescription.contains("timeout") || error.localizedDescription.contains("timed out") {
                        userMessage = "Transcription timed out"
                    } else if error.localizedDescription.contains("API") || error.localizedDescription.contains("key") {
                        userMessage = "API error - check settings"
                    } else if error.localizedDescription.contains("network") || error.localizedDescription.contains("connection") {
                        userMessage = "Network error"
                    } else {
                        userMessage = "Transcription failed"
                    }

                    await MainActor.run {
                        appState.fileTranscriptionError = true
                        appState.fileTranscriptionProgress = userMessage
                        appState.fileTranscriptionProgressValue = 0.0
                    }

                    // Keep error visible - use detached task to avoid inheriting cancellation
                    await withCheckedContinuation { continuation in
                        Task.detached {
                            try? await Task.sleep(nanoseconds: 2_500_000_000)
                            continuation.resume()
                        }
                    }

                    await MainActor.run {
                        appState.fileTranscriptionError = false
                        appState.isTranscribingFile = false
                        appState.fileTranscriptionProgress = ""
                    }
                }
            }
            appState.setFileTranscriptionTask(task)

        case .failure(let error):
            Logger.shared.log("File picker error: \(error)", level: .error)
        }
    }

    // MARK: - Error Section
    private func errorSection(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundColor(.orange)

            Text(message)
                .font(.system(size: 11))
                .foregroundColor(.primary)
                .lineLimit(2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.1))
        )
    }

    // MARK: - Footer Section
    private var footerSection: some View {
        HStack(spacing: 8) {
            // Settings button
            Button(action: {
                SettingsCoordinator.shared.requestOpenSettings()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "gear")
                        .font(.system(size: 12))
                    Text("Settings")
                        .font(.system(size: 12))
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minWidth: 80, minHeight: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHoveringSettings ? Color(NSColor.controlBackgroundColor) : Color.clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHoveringSettings = hovering
            }

            Spacer()

            // Quit button
            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "power")
                        .font(.system(size: 12))
                    Text("Quit")
                        .font(.system(size: 12))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHoveringQuit ? Color(NSColor.controlBackgroundColor) : Color.clear)
                )
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHoveringQuit = hovering
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers
    private var statusColor: Color {
        switch appState.recordingState {
        case .idle: return .gray
        case .recording: return .red
        case .processing: return .orange
        case .done: return .green
        case .error: return .orange
        }
    }

    private var statusText: String {
        switch appState.recordingState {
        case .idle: return "Ready to record"
        case .recording: return "Recording..."
        case .processing: return "Processing audio..."
        case .done: return "Transcription complete"
        case .error: return "An error occurred"
        }
    }

    // MARK: - Actions
    private func toggleRecording() {
        Task {
            switch appState.recordingState {
            case .idle, .done, .error:
                await appState.startRecording()
            case .recording:
                await appState.stopRecording()
            case .processing:
                break
            }
        }
    }
}
