// MuteApp.swift
// Mute - A local dictation app using NVIDIA Parakeet TDT v3
// Copyright 2024 - MIT License

import SwiftUI

@main
struct MuteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared
    
    var body: some Scene {
        // Menu bar extra
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            MenuBarLabel()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)
        
        // Settings window - can be opened via Mute menu > Settings or Cmd+,
        Settings {
            SettingsView()
                .environmentObject(appState)
        }

        // Main window
        Window("Mute App", id: "main") {
            MainAppView()
                .environmentObject(appState)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
// MARK: - Main App View (used by AppDelegate for dock icon clicks)
struct MainAppView: View {
    @EnvironmentObject var appState: AppState
    @State private var hotkeyDisplay = HotkeyConfig.load().displayString
    @State private var isHoveringCapture = false
    @State private var isHoveringDictation = false
    @State private var captureAnimating = false
    @State private var showingInsights = false
    @State private var isStartupChecking = true
    @State private var startupTimer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            // Compact Header
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Mute")
                        .font(.system(size: 18, weight: .bold))
                    Text("Local Speech-to-Text")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Settings gear
                Group {
                    if #available(macOS 14.0, *) {
                        SettingsLink {
                            settingsIconButton
                        }
                        .buttonStyle(.borderless)
                    } else {
                        Button(action: openSettings) {
                            settingsIconButton
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()
                .padding(.horizontal, 20)

            ScrollView {
                VStack(spacing: 14) {
                    // MARK: - Side by Side Cards
                    HStack(alignment: .top, spacing: 16) {
                        // MARK: - Quick Dictation Card (Left)
                        Button {
                            Task {
                                await toggleDictation()
                            }
                        } label: {
                            VStack(spacing: 0) {
                                // Icon with gradient background
                                ZStack {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: isDictating
                                                    ? [Color.red.opacity(0.2), Color.red.opacity(0.1)]
                                                    : [Color.blue.opacity(0.2), Color.cyan.opacity(0.1)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 52, height: 52)

                                    Circle()
                                        .stroke(
                                            isDictating ? Color.red.opacity(0.3) : Color.blue.opacity(0.3),
                                            lineWidth: 1.5
                                        )
                                        .frame(width: 52, height: 52)

                                    Group {
                                        if #available(macOS 14.0, *) {
                                            Image(systemName: isDictating ? "waveform" : "mic.fill")
                                                .font(.system(size: 22, weight: .medium))
                                                .foregroundStyle(
                                                    LinearGradient(
                                                        colors: isDictating
                                                            ? [Color.red, Color.red.opacity(0.8)]
                                                            : [Color.blue, Color.cyan],
                                                        startPoint: .top,
                                                        endPoint: .bottom
                                                    )
                                                )
                                                .symbolEffect(.variableColor, isActive: isDictating)
                                        } else {
                                            Image(systemName: isDictating ? "waveform" : "mic.fill")
                                                .font(.system(size: 22, weight: .medium))
                                                .foregroundStyle(
                                                    LinearGradient(
                                                        colors: isDictating
                                                            ? [Color.red, Color.red.opacity(0.8)]
                                                            : [Color.blue, Color.cyan],
                                                        startPoint: .top,
                                                        endPoint: .bottom
                                                    )
                                                )
                                        }
                                    }
                                }
                                .padding(.top, 4)
                                .padding(.bottom, 14)

                                // Title
                                Text("Quick Dictation")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .padding(.bottom, 6)

                                // Description
                                Text("Instant voice to text")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .padding(.bottom, 16)

                                // Action button with gradient
                                HStack(spacing: 8) {
                                    Image(systemName: isDictating ? "stop.fill" : "mic.fill")
                                        .font(.system(size: 13, weight: .semibold))
                                    Text(isDictating ? "Stop" : "Start")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(
                                            LinearGradient(
                                                colors: isDictating
                                                    ? [Color.red, Color.red.opacity(0.85)]
                                                    : [Color.blue, Color.blue.opacity(0.85)],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                        .shadow(color: isDictating ? Color.red.opacity(0.3) : Color.blue.opacity(0.3), radius: 8, y: 4)
                                )
                                .padding(.bottom, 12)

                                // Hotkey badge
                                Text(hotkeyDisplay)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color(NSColor.separatorColor).opacity(0.15))
                                    )
                                    .padding(.bottom, 8)

                                Spacer()

                                // Status footer
                                HStack(spacing: 6) {
                                    if isDictating {
                                        Circle()
                                            .fill(Color.red)
                                            .frame(width: 8, height: 8)
                                            .shadow(color: Color.red.opacity(0.5), radius: 4)
                                        Text("Recording...")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.red)
                                    } else {
                                        Image(systemName: appState.transcriptionBackend == .groqWhisper ? "cloud" : "cpu")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                        Text(dictationEngineDisplayName)
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(18)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(
                                ZStack {
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color(NSColor.controlBackgroundColor))

                                    // Subtle gradient overlay
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(
                                            LinearGradient(
                                                colors: isDictating
                                                    ? [Color.red.opacity(0.05), Color.clear]
                                                    : [Color.blue.opacity(0.03), Color.clear],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                }
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(
                                        LinearGradient(
                                            colors: isDictating
                                                ? [Color.red.opacity(0.5), Color.red.opacity(0.2)]
                                                : [Color.blue.opacity(isHoveringDictation ? 0.5 : 0.3), Color.blue.opacity(isHoveringDictation ? 0.3 : 0.1)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: isDictating || isHoveringDictation ? 2 : 1
                                    )
                            )
                            .shadow(color: Color.black.opacity(0.04), radius: 6, y: 3)
                            .scaleEffect(isHoveringDictation ? 1.02 : 1.0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHoveringDictation)
                        }
                        .buttonStyle(.borderless)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            isHoveringDictation = hovering
                        }

                        // MARK: - Capture to Notes Card (Right)
                        Button {
                            Task {
                                await appState.toggleCaptureMode()
                            }
                        } label: {
                            VStack(spacing: 0) {
                                // Icon with gradient background
                                ZStack {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: appState.isCaptureMode
                                                    ? [Color.red.opacity(0.2), Color.red.opacity(0.1)]
                                                    : [Color.purple.opacity(0.2), Color.pink.opacity(0.1)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 52, height: 52)

                                    Circle()
                                        .stroke(
                                            appState.isCaptureMode ? Color.red.opacity(0.3) : Color.purple.opacity(0.3),
                                            lineWidth: 1.5
                                        )
                                        .frame(width: 52, height: 52)

                                    Group {
                                        if #available(macOS 14.0, *) {
                                            Image(systemName: appState.isCaptureMode ? "waveform" : "note.text")
                                                .font(.system(size: 22, weight: .medium))
                                                .foregroundStyle(
                                                    LinearGradient(
                                                        colors: appState.isCaptureMode
                                                            ? [Color.red, Color.red.opacity(0.8)]
                                                            : [Color.purple, Color.pink],
                                                        startPoint: .top,
                                                        endPoint: .bottom
                                                    )
                                                )
                                                .symbolEffect(.variableColor, isActive: appState.isCaptureMode)
                                        } else {
                                            Image(systemName: appState.isCaptureMode ? "waveform" : "note.text")
                                                .font(.system(size: 22, weight: .medium))
                                                .foregroundStyle(
                                                    LinearGradient(
                                                        colors: appState.isCaptureMode
                                                            ? [Color.red, Color.red.opacity(0.8)]
                                                            : [Color.purple, Color.pink],
                                                        startPoint: .top,
                                                        endPoint: .bottom
                                                    )
                                                )
                                        }
                                    }
                                }
                                .padding(.top, 4)
                                .padding(.bottom, 14)

                                // Title
                                Text("Capture to Notes")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .padding(.bottom, 6)

                                // Description (only show download prompt when backend connected and models list is loaded)
                                if !isStartupChecking && appState.backendStatus == .connected && !appState.backendManager.availableModels.isEmpty && !isCaptureModelDownloaded {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.down.circle.fill")
                                            .font(.system(size: 10))
                                        Text("Download model in Settings")
                                    }
                                    .font(.system(size: 12))
                                    .foregroundColor(.orange)
                                    .padding(.bottom, 16)
                                } else {
                                    Text(appState.isCaptureMode ? "Recording to Notes..." : "Long-form transcription")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                        .padding(.bottom, 16)
                                }

                                // Action button with gradient
                                HStack(spacing: 8) {
                                    Image(systemName: appState.isCaptureMode ? "stop.fill" : "play.fill")
                                        .font(.system(size: 13, weight: .semibold))
                                    Text(appState.isCaptureMode ? "Stop" : "Start")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(
                                            LinearGradient(
                                                colors: appState.isCaptureMode
                                                    ? [Color.red, Color.red.opacity(0.85)]
                                                    : [Color.purple, Color.purple.opacity(0.85)],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                        .shadow(color: appState.isCaptureMode ? Color.red.opacity(0.3) : Color.purple.opacity(0.3), radius: 8, y: 4)
                                )
                                .padding(.bottom, 12)

                                // Apple Notes badge
                                HStack(spacing: 5) {
                                    Image(systemName: "apple.logo")
                                        .font(.system(size: 10))
                                    Text("Notes")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color(NSColor.separatorColor).opacity(0.15))
                                )
                                .padding(.bottom, 8)

                                Spacer()

                                // Status footer
                                HStack(spacing: 6) {
                                    if appState.isCaptureMode {
                                        Circle()
                                            .fill(Color.red)
                                            .frame(width: 8, height: 8)
                                            .scaleEffect(captureAnimating ? 1.3 : 1.0)
                                            .opacity(captureAnimating ? 0.6 : 1.0)
                                            .shadow(color: Color.red.opacity(0.5), radius: 4)
                                        Text("Recording...")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.red)
                                    } else {
                                        Image(systemName: "cpu")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                        Text(modelDisplayName(appState.captureNotesModel))
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(18)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(
                                ZStack {
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color(NSColor.controlBackgroundColor))

                                    // Subtle gradient overlay
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(
                                            LinearGradient(
                                                colors: appState.isCaptureMode
                                                    ? [Color.red.opacity(0.05), Color.clear]
                                                    : [Color.purple.opacity(0.03), Color.clear],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                }
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(
                                        LinearGradient(
                                            colors: appState.isCaptureMode
                                                ? [Color.red.opacity(0.5), Color.red.opacity(0.2)]
                                                : [Color.purple.opacity(isHoveringCapture ? 0.5 : 0.3), Color.purple.opacity(isHoveringCapture ? 0.3 : 0.1)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: appState.isCaptureMode || isHoveringCapture ? 2 : 1
                                    )
                            )
                            .shadow(color: Color.black.opacity(0.04), radius: 6, y: 3)
                            .scaleEffect(isHoveringCapture ? 1.02 : 1.0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHoveringCapture)
                        }
                        .buttonStyle(.borderless)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            isHoveringCapture = hovering
                        }
                        .onChange(of: appState.isCaptureMode) { isCapturing in
                            if isCapturing {
                                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                                    captureAnimating = true
                                }
                            } else {
                                captureAnimating = false
                            }
                        }
                    }

                    // MARK: - Status Banner (Connecting, Loading, or Error)
                    if isStartupChecking {
                        // During startup period - show appropriate loading state
                        HStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(width: 20, height: 20)

                            Text(startupStatusText)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)

                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(NSColor.controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                        )
                    } else if !appState.backendManager.availableModels.isEmpty && appState.modelStatus != .ready {
                        // Model not ready error (only after startup grace period and models list loaded)
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.orange.opacity(0.15))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.orange)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Model Required")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Download a model in Settings → Model tab")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Group {
                                if #available(macOS 14.0, *) {
                                    SettingsLink {
                                        Text("Open Settings")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(Color.orange)
                                            )
                                    }
                                    .buttonStyle(.borderless)
                                } else {
                                    Button(action: openSettings) {
                                        Text("Open Settings")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(Color.orange)
                                            )
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                        .padding(18)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.orange.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.04), radius: 6, y: 3)
                    }

                    // MARK: - Usage Stats
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            HStack(spacing: 6) {
                                Image(systemName: "chart.bar.fill")
                                    .font(.system(size: 11))
                                Text("Activity")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(.secondary)

                            Spacer()

                            Button(action: { showingInsights = true }) {
                                HStack(spacing: 5) {
                                    Image(systemName: "chart.line.uptrend.xyaxis")
                                        .font(.system(size: 10, weight: .medium))
                                    Text("Insights")
                                        .font(.system(size: 11, weight: .medium))
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 8, weight: .bold))
                                }
                                .foregroundColor(.blue)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(Color.blue.opacity(0.1))
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.borderless)
                        }

                        HStack(spacing: 10) {
                            StatCard(
                                value: appState.todayDictations,
                                label: "Today",
                                icon: "sun.max.fill",
                                color: .orange
                            )

                            StatCard(
                                value: appState.weekDictations,
                                label: "This Week",
                                icon: "calendar",
                                color: .blue
                            )

                            StatCard(
                                value: appState.totalDictations,
                                label: "All Time",
                                icon: "infinity",
                                color: .purple
                            )
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.04), radius: 6, y: 3)
                    .sheet(isPresented: $showingInsights) {
                        InsightsView()
                            .environmentObject(appState)
                    }

                    // MARK: - Keyboard Shortcuts
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 6) {
                            Image(systemName: "keyboard")
                                .font(.system(size: 11))
                            Text("Shortcuts")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.secondary)

                        VStack(spacing: 8) {
                            HStack {
                                Text("Start/Stop Recording")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(hotkeyDisplay)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(Color(NSColor.separatorColor).opacity(0.15))
                                    )
                            }

                            HStack {
                                Text("Open Settings")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("⌘,")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(Color(NSColor.separatorColor).opacity(0.15))
                                    )
                            }
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.04), radius: 6, y: 3)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }

            Divider()
                .padding(.horizontal, 20)

            // Status Footer
            HStack(spacing: 8) {
                Circle()
                    .fill(footerStatusColor)
                    .frame(width: 8, height: 8)

                Text(footerStatusText)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Spacer()

                Text("v1.3.0")
                    .font(.system(size: 10))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 520, height: 760)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            startStartupTimer()
        }
        .onDisappear {
            startupTimer?.invalidate()
        }
        .onChange(of: appState.backendStatus) { newStatus in
            // If connected, end startup checking early
            if newStatus == .connected && appState.modelStatus == .ready {
                isStartupChecking = false
                startupTimer?.invalidate()
            }
        }
        .onChange(of: appState.modelStatus) { newStatus in
            // If model ready and connected, end startup checking early
            if newStatus == .ready && appState.backendStatus == .connected {
                isStartupChecking = false
                startupTimer?.invalidate()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .hotkeyDidChange)) { _ in
            hotkeyDisplay = HotkeyConfig.load().displayString
        }
    }

    private func startStartupTimer() {
        // Reset state on appear
        isStartupChecking = true
        startupTimer?.invalidate()

        // After 15 seconds, show actual errors if still not ready
        startupTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false) { _ in
            DispatchQueue.main.async {
                isStartupChecking = false
            }
        }
    }

    private var startupStatusText: String {
        switch appState.backendStatus {
        case .disconnected:
            return "Starting backend..."
        case .connecting:
            return "Connecting..."
        case .connected:
            if appState.backendManager.availableModels.isEmpty {
                return "Loading models..."
            } else if appState.modelStatus != .ready {
                return "Loading model..."
            } else {
                return "Preparing..."
            }
        case .error:
            return "Connection error..."
        }
    }

    private var footerStatusColor: Color {
        if isStartupChecking {
            return .orange // Startup state
        }
        return backendStatusColor
    }

    private var footerStatusText: String {
        if isStartupChecking {
            return startupStatusText
        }
        return backendStatusText
    }

    private var backendStatusColor: Color {
        switch appState.backendStatus {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected: return .gray
        case .error: return .red
        }
    }

    private var backendStatusText: String {
        switch appState.backendStatus {
        case .connected: return "Backend Connected"
        case .connecting: return "Connecting..."
        case .disconnected: return "Disconnected"
        case .error: return "Connection Error"
        }
    }

    private var settingsIconButton: some View {
        Image(systemName: "gearshape")
            .font(.system(size: 16))
            .foregroundColor(.secondary)
            .frame(width: 32, height: 32)
            .background(
                Circle()
                    .fill(Color(NSColor.controlBackgroundColor))
            )
    }

    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 13.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    private var isCaptureModelDownloaded: Bool {
        let modelInfo = appState.backendManager.availableModels.first { $0.id == appState.captureNotesModel }
        return modelInfo?.downloaded ?? false
    }

    private var isDictating: Bool {
        if case .recording = appState.recordingState, !appState.isCaptureMode {
            return true
        }
        return false
    }

    private func toggleDictation() async {
        switch appState.recordingState {
        case .idle, .done, .error:
            await appState.startRecording()
        case .recording:
            if !appState.isCaptureMode {
                await appState.stopRecording()
            }
        case .processing:
            break
        }
    }

    private var dictationEngineDisplayName: String {
        if appState.transcriptionBackend == .groqWhisper {
            return "Groq Whisper"
        } else {
            return modelDisplayName(appState.dictationModel)
        }
    }

    private func modelDisplayName(_ modelId: String) -> String {
        switch modelId {
        case "parakeet": return "Parakeet"
        case "base": return "Whisper Base"
        case "small": return "Whisper Small"
        case "medium": return "Whisper Medium"
        case "large-v3-turbo": return "Whisper Turbo"
        default: return modelId
        }
    }

}

// MARK: - Stat Card
struct StatCard: View {
    let value: Int
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            // Icon
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(color)
            }

            // Value
            Text("\(value)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            // Label
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Feature Tag
struct FeatureTag: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(text)
                .font(.system(size: 10))
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(NSColor.tertiaryLabelColor).opacity(0.15))
        )
    }
}

// MARK: - Hotkey Row
struct HotkeyRow: View {
    let label: String
    let shortcut: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.primary)
            Spacer()
            Text(shortcut)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
        }
    }
}

struct MenuBarLabel: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: iconName)
                .symbolRenderingMode(.palette)
                .foregroundStyle(iconColor, .primary)
        }
    }
    
    private var iconName: String {
        switch appState.recordingState {
        case .idle:
            return "mic.fill"
        case .recording:
            return "mic.fill"
        case .processing:
            return "ellipsis.circle.fill"
        case .done:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }
    
    private var iconColor: Color {
        switch appState.recordingState {
        case .idle:
            return .primary
        case .recording:
            return .red
        case .processing:
            return .orange
        case .done:
            return .green
        case .error:
            return .yellow
        }
    }
}

// MARK: - Insights View
struct InsightsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Activity Insights")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()
                .padding(.horizontal, 20)

            ScrollView {
                VStack(spacing: 16) {
                    // MARK: - Streak Section
                    HStack(spacing: 12) {
                        // Current Streak
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.orange.opacity(0.2), Color.red.opacity(0.1)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 44, height: 44)
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [.orange, .red],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            }
                            Text("\(appState.currentStreak)")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                            Text("Current Streak")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.orange.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                        )

                        // Longest Streak
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(Color.yellow.opacity(0.15))
                                    .frame(width: 44, height: 44)
                                Image(systemName: "trophy.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.yellow)
                            }
                            Text("\(appState.longestStreak)")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                            Text("Longest Streak")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.yellow.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.yellow.opacity(0.2), lineWidth: 1)
                        )

                        // Best Day of Week
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(Color.purple.opacity(0.15))
                                    .frame(width: 44, height: 44)
                                Image(systemName: "calendar.badge.clock")
                                    .font(.system(size: 18))
                                    .foregroundColor(.purple)
                            }
                            if let best = appState.bestDayOfWeek {
                                Text(appState.dayName(for: best.dayIndex))
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                            } else {
                                Text("-")
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                            Text("Best Day")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.purple.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.purple.opacity(0.2), lineWidth: 1)
                        )
                    }

                    // MARK: - Weekly Chart
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "chart.bar.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.blue)
                            Text("This Week")
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                            if let best = appState.bestDayOfWeek, best.count > 0 {
                                Text("\(appState.fullDayName(for: best.dayIndex)) is your best day")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }

                        WeeklyChartView(data: appState.weeklyData, currentDayIndex: currentDayIndex())
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                    )

                    // MARK: - Stats Row
                    HStack(spacing: 12) {
                        // Average Per Day
                        VStack(spacing: 6) {
                            HStack(spacing: 4) {
                                Image(systemName: "divide")
                                    .font(.system(size: 10))
                                    .foregroundColor(.green)
                                Text("Daily Average")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            Text("\(Int(appState.averagePerDay.rounded()))")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                            Text("dictations/day")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.green.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.green.opacity(0.2), lineWidth: 1)
                        )

                        // Time Saved
                        VStack(spacing: 6) {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 10))
                                    .foregroundColor(.cyan)
                                Text("Time Saved")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            Text(formatTimeSaved(appState.timeSavedSeconds))
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                            Text("vs typing")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.cyan.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.cyan.opacity(0.2), lineWidth: 1)
                        )
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 420, height: 520)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func currentDayIndex() -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = TimeZone.current
        let weekday = calendar.component(.weekday, from: Date())
        return (weekday + 5) % 7
    }

    private func formatTimeSaved(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)s"
        } else if seconds < 3600 {
            let mins = seconds / 60
            return "\(mins)m"
        } else {
            let hours = seconds / 3600
            let mins = (seconds % 3600) / 60
            if mins == 0 {
                return "\(hours)h"
            }
            return "\(hours)h \(mins)m"
        }
    }

    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
}

// MARK: - Weekly Chart View
struct WeeklyChartView: View {
    let data: [Int]
    let currentDayIndex: Int

    private let days = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        let maxValue = max(data.max() ?? 1, 1)

        HStack(alignment: .bottom, spacing: 8) {
            ForEach(0..<7, id: \.self) { index in
                VStack(spacing: 6) {
                    // Bar
                    RoundedRectangle(cornerRadius: 4)
                        .fill(barColor(for: index))
                        .frame(width: 32, height: barHeight(for: data[index], max: maxValue))
                        .overlay(
                            // Value label on top of bar
                            Text("\(data[index])")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(data[index] > 0 ? .white : .clear)
                                .offset(y: data[index] > 0 ? 0 : -10)
                            , alignment: .center
                        )

                    // Day label
                    Text(days[index])
                        .font(.system(size: 10, weight: index == currentDayIndex ? .bold : .medium))
                        .foregroundColor(index == currentDayIndex ? .primary : .secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 100)
    }

    private func barHeight(for value: Int, max: Int) -> CGFloat {
        let minHeight: CGFloat = 8
        let maxHeight: CGFloat = 70
        if value == 0 { return minHeight }
        return minHeight + (maxHeight - minHeight) * CGFloat(value) / CGFloat(max)
    }

    private func barColor(for index: Int) -> LinearGradient {
        if index == currentDayIndex {
            return LinearGradient(
                colors: [.blue, .blue.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
        } else if data[index] > 0 {
            return LinearGradient(
                colors: [.blue.opacity(0.6), .blue.opacity(0.4)],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            return LinearGradient(
                colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.2)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}
