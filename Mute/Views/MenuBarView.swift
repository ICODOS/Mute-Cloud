// MenuBarView.swift
// Mute

import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @State private var hotkeyDisplay = HotkeyConfig.load().displayString
    @State private var isHoveringRecord = false
    @State private var isHoveringSettings = false
    @State private var isHoveringQuit = false

    var body: some View {
        VStack(spacing: 0) {
            // Header with status
            headerSection

            // Main content area
            VStack(spacing: 12) {
                // Recording button
                recordingButton

                // Model download section (if needed)
                if appState.modelStatus != .ready {
                    modelSection
                }

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

    // MARK: - Model Section
    private var modelSection: some View {
        VStack(spacing: 8) {
            Button(action: {
                Task {
                    await appState.downloadModel()
                }
            }) {
                HStack(spacing: 10) {
                    if appState.modelStatus == .downloading {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.accentColor)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(appState.modelStatus == .downloading ? "Downloading..." : "Download Model")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)

                        if appState.modelStatus == .downloading {
                            Text("\(Int(appState.modelDownloadProgress * 100))% complete")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        } else {
                            Text("Required for transcription")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor.opacity(0.1))
                )
            }
            .buttonStyle(.plain)
            .disabled(appState.modelStatus == .downloading)

            if appState.modelStatus == .downloading {
                ProgressView(value: appState.modelDownloadProgress)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
            }
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
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                NSApp.activate(ignoringOtherApps: true)
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
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHoveringSettings ? Color(NSColor.controlBackgroundColor) : Color.clear)
                )
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
