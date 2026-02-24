// MuteApp.swift
// Mute - A local dictation app using NVIDIA Parakeet TDT v3
// Copyright 2024 - MIT License

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Settings Coordinator
/// Coordinates opening the Settings window from any context in the app.
///
/// ## Why This Exists
/// Opening Settings programmatically in a SwiftUI app with MenuBarExtra is challenging:
/// - `@Environment(\.openSettings)` doesn't work reliably in MenuBarExtra/popover contexts
/// - `NSApp.sendAction(Selector(("showSettingsWindow:")))` doesn't work with SwiftUI Settings scene on macOS 14+
/// - The only reliable method is to programmatically invoke the Settings menu item
///
/// ## How It Works
/// 1. Call `requestOpenSettings(tab:)` from anywhere in the app
/// 2. Optionally specify a `SettingsTab` to open directly to that tab
/// 3. A notification is posted to `AppDelegate` which handles the actual opening
/// 4. `AppDelegate.openSettingsWindow()` finds and invokes the Settings menu item
/// 5. `SettingsView.onAppear` checks `SettingsTabCoordinator` for a requested tab
///
/// ## Usage
/// ```swift
/// // Open Settings to default tab
/// SettingsCoordinator.shared.requestOpenSettings()
///
/// // Open Settings directly to Modes tab
/// SettingsCoordinator.shared.requestOpenSettings(tab: .modes)
/// ```
@MainActor
final class SettingsCoordinator {
    static let shared = SettingsCoordinator()

    private init() {}

    /// Opens the Settings window, optionally to a specific tab.
    /// - Parameter tab: The tab to select when Settings opens. If nil, uses the default/last tab.
    func requestOpenSettings(tab: SettingsTab? = nil) {
        // Set the requested tab if specified
        if let tab = tab {
            SettingsTabCoordinator.shared.requestTab(tab)
        }

        // Post notification to AppDelegate which handles settings opening
        // AppDelegate can reliably invoke the Settings menu item from its context
        NotificationCenter.default.post(name: .openSettingsRequested, object: nil)
    }
}

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
    @ObservedObject private var modeManager = TranscriptionModeManager.shared
    @State private var hotkeyDisplay = HotkeyConfig.load().displayString
    @State private var isHoveringCapture = false
    @State private var isHoveringDictation = false
    @State private var captureAnimating = false
    @State private var showingInsights = false
    @State private var isStartupChecking = true
    @State private var startupTimer: Timer?
    @State private var showingFilePicker = false
    @State private var isHoveringAudioImport = false
    @State private var showingModePicker = false
    @State private var showingFileModeicker = false

    private var isCloudMode: Bool {
        appState.transcriptionBackend == .groqWhisper
    }

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
                    Text("Speech to Text Productivity Engine")
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
                    HStack(alignment: .top, spacing: 14) {
                        quickDictationCard
                        captureToNotesCard
                    }

                    // MARK: - Audio File Import Section (Cloud Mode Only)
                    if appState.transcriptionBackend == .groqWhisper {
                        Button {
                            if appState.isTranscribingFile {
                                appState.cancelFileTranscription()
                            } else {
                                showingFilePicker = true
                            }
                        } label: {
                            VStack(spacing: 0) {
                                HStack(spacing: 14) {
                                    // Icon
                                    ZStack {
                                        Circle()
                                            .fill(
                                                LinearGradient(
                                                    colors: appState.fileTranscriptionError
                                                        ? [Color.red.opacity(0.3), Color.red.opacity(0.2)]
                                                        : appState.fileTranscriptionCompleted
                                                            ? [Color.green.opacity(0.3), Color.green.opacity(0.2)]
                                                            : [Color.green.opacity(0.2), Color.teal.opacity(0.1)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .frame(width: 44, height: 44)

                                        Circle()
                                            .stroke(
                                                appState.fileTranscriptionError
                                                    ? Color.red.opacity(0.5)
                                                    : appState.fileTranscriptionCompleted
                                                        ? Color.green.opacity(0.5)
                                                        : Color.green.opacity(0.3),
                                                lineWidth: 1.5
                                            )
                                            .frame(width: 44, height: 44)

                                        if appState.fileTranscriptionError {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .font(.system(size: 18, weight: .semibold))
                                                .foregroundColor(.red)
                                        } else if appState.fileTranscriptionCompleted {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 18, weight: .semibold))
                                                .foregroundColor(.green)
                                        } else if appState.isTranscribingFile {
                                            ProgressView()
                                                .scaleEffect(0.8)
                                        } else {
                                            Image(systemName: "waveform.badge.plus")
                                                .font(.system(size: 18, weight: .medium))
                                                .foregroundStyle(
                                                    LinearGradient(
                                                        colors: [Color.green, Color.teal],
                                                        startPoint: .top,
                                                        endPoint: .bottom
                                                    )
                                                )
                                        }
                                    }

                                    // Text content
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(appState.fileTranscriptionError ? "Failed" :
                                             appState.fileTranscriptionCompleted ? "Complete!" :
                                             appState.isTranscribingFile ? "Transcribing..." :
                                             "Audio File Transcription")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(appState.fileTranscriptionError ? .red :
                                                            appState.fileTranscriptionCompleted ? .green : .primary)

                                        Text(appState.isTranscribingFile || appState.fileTranscriptionError ? appState.fileTranscriptionProgress : "Transcribe any audio file to Notes")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    // Arrow or progress
                                    if !appState.isTranscribingFile {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.secondary)
                                            .opacity(isHoveringAudioImport ? 1 : 0.6)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.top, 14)
                                .padding(.bottom, 10)

                                // Subtle mode selector
                                if !appState.isTranscribingFile && !appState.fileTranscriptionCompleted {
                                    HStack(spacing: 6) {
                                        Image(systemName: "wand.and.stars")
                                            .font(.system(size: 9))
                                            .foregroundColor(.purple.opacity(0.7))

                                        Menu {
                                            Button(action: { modeManager.setFileTranscriptionMode(nil) }) {
                                                HStack {
                                                    Text("None")
                                                    if modeManager.fileTranscriptionModeId == nil {
                                                        Image(systemName: "checkmark")
                                                    }
                                                }
                                            }

                                            if !modeManager.modes.filter({ !$0.isBuiltIn }).isEmpty {
                                                Divider()
                                                ForEach(modeManager.modes.filter { !$0.isBuiltIn }) { mode in
                                                    Button(action: { modeManager.setFileTranscriptionMode(mode.id) }) {
                                                        HStack {
                                                            Text(mode.name)
                                                            if modeManager.fileTranscriptionModeId == mode.id {
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
                                                Text("Mode: \(modeManager.fileTranscriptionMode?.name ?? "None")")
                                                    .font(.system(size: 10, weight: .medium))
                                                Image(systemName: "chevron.up.chevron.down")
                                                    .font(.system(size: 8))
                                            }
                                            .foregroundColor(modeManager.fileTranscriptionMode != nil ? .purple : .secondary.opacity(0.8))
                                        }
                                        .menuStyle(.borderlessButton)

                                        Spacer()
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.bottom, 10)
                                }

                                // Subtle progress bar
                                if appState.isTranscribingFile || appState.fileTranscriptionCompleted || appState.fileTranscriptionError {
                                    GeometryReader { geometry in
                                        ZStack(alignment: .leading) {
                                            // Background track
                                            RoundedRectangle(cornerRadius: 1.5)
                                                .fill(Color.gray.opacity(0.15))
                                                .frame(height: 3)

                                            // Progress fill
                                            RoundedRectangle(cornerRadius: 1.5)
                                                .fill(
                                                    LinearGradient(
                                                        colors: appState.fileTranscriptionError
                                                            ? [Color.red, Color.red]
                                                            : appState.fileTranscriptionCompleted
                                                                ? [Color.green, Color.green]
                                                                : [Color.green, Color.teal],
                                                        startPoint: .leading,
                                                        endPoint: .trailing
                                                    )
                                                )
                                                .frame(width: geometry.size.width * (appState.fileTranscriptionError ? 1.0 : appState.fileTranscriptionProgressValue), height: 3)
                                                .shadow(color: appState.fileTranscriptionError ? Color.red.opacity(0.4) : Color.green.opacity(0.4), radius: 2, y: 0)
                                        }
                                    }
                                    .frame(height: 3)
                                    .padding(.horizontal, 14)
                                    .padding(.bottom, 10)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                            .background(
                                ZStack {
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color(NSColor.controlBackgroundColor))

                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(
                                            LinearGradient(
                                                colors: appState.fileTranscriptionError
                                                    ? [Color.red.opacity(0.08), Color.red.opacity(0.02)]
                                                    : appState.fileTranscriptionCompleted
                                                        ? [Color.green.opacity(0.08), Color.green.opacity(0.02)]
                                                        : [Color.green.opacity(0.03), Color.clear],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                }
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(
                                        LinearGradient(
                                            colors: appState.fileTranscriptionError
                                                ? [Color.red.opacity(0.5), Color.red.opacity(0.3)]
                                                : appState.fileTranscriptionCompleted
                                                    ? [Color.green.opacity(0.5), Color.green.opacity(0.3)]
                                                    : [
                                                        Color.green.opacity(isHoveringAudioImport ? 0.5 : 0.25),
                                                        Color.teal.opacity(isHoveringAudioImport ? 0.3 : 0.1)
                                                    ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ),
                                        lineWidth: appState.fileTranscriptionError ? 1.5 : appState.fileTranscriptionCompleted ? 1.5 : (isHoveringAudioImport ? 1.5 : 1)
                                    )
                            )
                            .shadow(color: Color.black.opacity(0.04), radius: 6, y: 3)
                            .scaleEffect(isHoveringAudioImport && !appState.isTranscribingFile ? 1.01 : 1.0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHoveringAudioImport)
                            .animation(.easeInOut(duration: 0.3), value: appState.isTranscribingFile)
                            .animation(.easeInOut(duration: 0.3), value: appState.fileTranscriptionCompleted)
                            .animation(.easeInOut(duration: 0.3), value: appState.fileTranscriptionError)
                        }
                        .buttonStyle(.borderless)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            isHoveringAudioImport = hovering
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
                    } else if !isCloudMode && !appState.backendManager.availableModels.isEmpty && appState.modelStatus != .ready {
                        // Model not ready error (only in local mode, after startup grace period and models list loaded)
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
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [
                .wav, .mp3, .mpeg4Audio, .aiff,
                .init(filenameExtension: "m4a")!,
                .init(filenameExtension: "flac")!,
                .init(filenameExtension: "ogg")!,
                .init(filenameExtension: "webm")!
            ],
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
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

    private func openModesSettings() {
        SettingsCoordinator.shared.requestOpenSettings(tab: .modes)
    }

    private func openSettings() {
        SettingsCoordinator.shared.requestOpenSettings()
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

    // MARK: - Quick Dictation Card
    private var quickDictationCard: some View {
        quickDictationCardContent
            .onHover { hovering in
                isHoveringDictation = hovering
            }
    }

    private var quickDictationCardContent: some View {
        VStack(spacing: 0) {
            // Tappable area for dictation (icon, title, description, button)
            VStack(spacing: 0) {
                // Icon with subtle glow
                ZStack {
                    // Subtle outer glow
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: isDictating
                                    ? [Color.red.opacity(0.15), Color.red.opacity(0)]
                                    : [Color.blue.opacity(0.12), Color.blue.opacity(0)],
                                center: .center,
                                startRadius: 22,
                                endRadius: 36
                            )
                        )
                        .frame(width: 60, height: 60)

                    // Inner circle
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: isDictating
                                    ? [Color.red.opacity(0.12), Color.red.opacity(0.06)]
                                    : [Color.blue.opacity(0.1), Color.cyan.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)

                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: isDictating
                                    ? [Color.red.opacity(0.4), Color.red.opacity(0.15)]
                                    : [Color.blue.opacity(0.3), Color.cyan.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                        .frame(width: 52, height: 52)

                    quickDictationIcon
                }
                .padding(.top, 8)
                .padding(.bottom, 12)

                // Title
                Text("Quick Dictation")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .padding(.bottom, 4)

                // Description
                Text("Instant voice to text")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 14)

                // Action button
                quickDictationButton
            }
            .contentShape(Rectangle())
            .onTapGesture {
                Task {
                    await toggleDictation()
                }
            }

            // Hotkey badge and mode selector row (NOT tappable for dictation)
            HStack(spacing: 6) {
                // Hotkey badge
                HStack(spacing: 4) {
                    Image(systemName: "command")
                        .font(.system(size: 9, weight: .medium))
                    Text(hotkeyDisplay)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                }
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, minHeight: 26, maxHeight: 26)
                .background(
                    Capsule()
                        .fill(Color(NSColor.separatorColor).opacity(0.15))
                )
                .overlay(
                    Capsule()
                        .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1)
                )

                // Mode selector (cloud mode only)
                if isCloudMode && !isDictating {
                    dictationModeSelector
                }
            }
            .frame(maxWidth: isCloudMode && !isDictating ? 220 : nil)
            .padding(.bottom, 6)

            Spacer()

            // Status footer
            quickDictationFooter
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(quickDictationBackground)
        .overlay(quickDictationOverlay)
        .shadow(color: isDictating ? Color.red.opacity(0.15) : Color.black.opacity(0.06), radius: 12, y: 4)
        .scaleEffect(isHoveringDictation ? 1.015 : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isHoveringDictation)
    }

    @ViewBuilder
    private var quickDictationIcon: some View {
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
                .shadow(color: isDictating ? Color.red.opacity(0.3) : Color.blue.opacity(0.25), radius: 4)
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
                .shadow(color: isDictating ? Color.red.opacity(0.3) : Color.blue.opacity(0.25), radius: 4)
        }
    }

    private var quickDictationButton: some View {
        HStack(spacing: 6) {
            Image(systemName: isDictating ? "stop.fill" : "mic.fill")
                .font(.system(size: 12, weight: .semibold))
            Text(isDictating ? "Stop" : "Start")
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
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
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.2), Color.white.opacity(0)],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            }
            .shadow(color: isDictating ? Color.red.opacity(0.4) : Color.blue.opacity(0.35), radius: 8, y: 3)
        )
        .padding(.bottom, 10)
    }

    private var quickDictationFooter: some View {
        HStack(spacing: 5) {
            if isDictating {
                Circle()
                    .fill(Color.red)
                    .frame(width: 7, height: 7)
                    .shadow(color: Color.red.opacity(0.6), radius: 4)
                Text("Recording...")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.red)
            } else {
                Image(systemName: appState.transcriptionBackend == .groqWhisper ? "cloud.fill" : "cpu")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary.opacity(0.7))
                Text(dictationEngineDisplayName)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
    }

    private var quickDictationBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(NSColor.controlBackgroundColor))

            RoundedRectangle(cornerRadius: 18)
                .fill(
                    LinearGradient(
                        colors: isDictating
                            ? [Color.red.opacity(0.06), Color.red.opacity(0.02), Color.clear]
                            : [Color.blue.opacity(0.04), Color.blue.opacity(0.01), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.15), Color.clear],
                        startPoint: .top,
                        endPoint: .center
                    ),
                    lineWidth: 1
                )
                .padding(1)
        }
    }

    private var quickDictationOverlay: some View {
        RoundedRectangle(cornerRadius: 18)
            .stroke(
                LinearGradient(
                    colors: isDictating
                        ? [Color.red.opacity(0.6), Color.red.opacity(0.25)]
                        : [Color.blue.opacity(isHoveringDictation ? 0.55 : 0.3), Color.blue.opacity(isHoveringDictation ? 0.25 : 0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: isDictating || isHoveringDictation ? 1.5 : 1
            )
    }

    // MARK: - Capture to Notes Card
    private var captureToNotesCard: some View {
        captureToNotesCardContent
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

    private var captureToNotesCardContent: some View {
        VStack(spacing: 0) {
            // Tappable area for capture mode
            VStack(spacing: 0) {
                // Icon with subtle glow
                ZStack {
                    // Subtle outer glow
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: appState.isCaptureMode
                                    ? [Color.red.opacity(0.15), Color.red.opacity(0)]
                                    : [Color.purple.opacity(0.12), Color.purple.opacity(0)],
                                center: .center,
                                startRadius: 22,
                                endRadius: 36
                            )
                        )
                        .frame(width: 60, height: 60)

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: appState.isCaptureMode
                                    ? [Color.red.opacity(0.12), Color.red.opacity(0.06)]
                                    : [Color.purple.opacity(0.1), Color.pink.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)

                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: appState.isCaptureMode
                                    ? [Color.red.opacity(0.4), Color.red.opacity(0.15)]
                                    : [Color.purple.opacity(0.3), Color.pink.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                        .frame(width: 52, height: 52)

                    captureToNotesIcon
                }
                .padding(.top, 8)
                .padding(.bottom, 12)

                Text("Capture to Notes")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .padding(.bottom, 4)

                captureToNotesDescription

                captureToNotesButton
            }
            .contentShape(Rectangle())
            .onTapGesture {
                Task {
                    await appState.toggleCaptureMode()
                }
            }

            // Apple Notes badge
            HStack(spacing: 4) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 9))
                Text("Notes")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 10)
            .frame(minHeight: 26, maxHeight: 26)
            .background(
                Capsule()
                    .fill(Color(NSColor.separatorColor).opacity(0.15))
            )
            .overlay(
                Capsule()
                    .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1)
            )
            .padding(.bottom, 6)

            Spacer()

            captureToNotesFooter
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(captureToNotesBackground)
        .overlay(captureToNotesOverlay)
        .shadow(color: appState.isCaptureMode ? Color.red.opacity(0.15) : Color.black.opacity(0.06), radius: 12, y: 4)
        .scaleEffect(isHoveringCapture ? 1.015 : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isHoveringCapture)
    }

    @ViewBuilder
    private var captureToNotesIcon: some View {
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
                .shadow(color: appState.isCaptureMode ? Color.red.opacity(0.3) : Color.purple.opacity(0.25), radius: 4)
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
                .shadow(color: appState.isCaptureMode ? Color.red.opacity(0.3) : Color.purple.opacity(0.25), radius: 4)
        }
    }

    @ViewBuilder
    private var captureToNotesDescription: some View {
        if !isStartupChecking && appState.backendStatus == .connected && !appState.backendManager.availableModels.isEmpty && !isCaptureModelDownloaded {
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 9))
                Text("Download model in Settings")
            }
            .font(.system(size: 11))
            .foregroundColor(.orange)
            .padding(.bottom, 14)
        } else {
            Text(appState.isCaptureMode ? "Recording to Notes..." : "Long-form transcription")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.bottom, 14)
        }
    }

    private var captureToNotesButton: some View {
        HStack(spacing: 6) {
            Image(systemName: appState.isCaptureMode ? "stop.fill" : "play.fill")
                .font(.system(size: 12, weight: .semibold))
            Text(appState.isCaptureMode ? "Stop" : "Start")
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
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
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.2), Color.white.opacity(0)],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            }
            .shadow(color: appState.isCaptureMode ? Color.red.opacity(0.4) : Color.purple.opacity(0.35), radius: 8, y: 3)
        )
        .padding(.bottom, 10)
    }

    private var captureToNotesFooter: some View {
        HStack(spacing: 5) {
            if appState.isCaptureMode {
                Circle()
                    .fill(Color.red)
                    .frame(width: 7, height: 7)
                    .scaleEffect(captureAnimating ? 1.3 : 1.0)
                    .opacity(captureAnimating ? 0.6 : 1.0)
                    .shadow(color: Color.red.opacity(0.6), radius: 4)
                Text("Recording...")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.red)
            } else {
                Image(systemName: "cpu")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary.opacity(0.7))
                Text(modelDisplayName(appState.captureNotesModel))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
    }

    private var captureToNotesBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(NSColor.controlBackgroundColor))

            RoundedRectangle(cornerRadius: 18)
                .fill(
                    LinearGradient(
                        colors: appState.isCaptureMode
                            ? [Color.red.opacity(0.06), Color.red.opacity(0.02), Color.clear]
                            : [Color.purple.opacity(0.04), Color.purple.opacity(0.01), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.15), Color.clear],
                        startPoint: .top,
                        endPoint: .center
                    ),
                    lineWidth: 1
                )
                .padding(1)
        }
    }

    private var captureToNotesOverlay: some View {
        RoundedRectangle(cornerRadius: 18)
            .stroke(
                LinearGradient(
                    colors: appState.isCaptureMode
                        ? [Color.red.opacity(0.6), Color.red.opacity(0.25)]
                        : [Color.purple.opacity(isHoveringCapture ? 0.55 : 0.3), Color.purple.opacity(isHoveringCapture ? 0.25 : 0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: appState.isCaptureMode || isHoveringCapture ? 1.5 : 1
            )
    }

    // MARK: - Dictation Mode Selector
    private var dictationModeSelector: some View {
        HStack(spacing: 4) {
            Image(systemName: modeManager.dictationMode != nil ? "wand.and.stars" : "text.quote")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(modeManager.dictationMode != nil ? .purple : .secondary)
            Text(modeManager.dictationMode?.name ?? "Raw")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundColor(modeManager.dictationMode != nil ? .purple : .secondary)
            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 26, maxHeight: 26)
        .background(
            Capsule()
                .fill(Color(NSColor.separatorColor).opacity(0.15))
        )
        .overlay(
            Capsule()
                .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1)
        )
        .contentShape(Capsule())
        .onTapGesture {
            showingModePicker = true
        }
        .popover(isPresented: $showingModePicker, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                modePickerButton(label: "Raw transcription", isSelected: modeManager.dictationModeId == nil) {
                    modeManager.setDictationMode(nil)
                    showingModePicker = false
                }

                if !modeManager.modes.filter({ !$0.isBuiltIn }).isEmpty {
                    Divider()
                        .padding(.vertical, 4)
                    ForEach(modeManager.modes.filter { !$0.isBuiltIn }) { mode in
                        modePickerButton(label: mode.name, isSelected: modeManager.dictationModeId == mode.id) {
                            modeManager.setDictationMode(mode.id)
                            showingModePicker = false
                        }
                    }
                }

                Divider()
                    .padding(.vertical, 4)
                modePickerButton(label: "Manage Modes...", icon: "gear", isSelected: false) {
                    showingModePicker = false
                    openModesSettings()
                }
            }
            .padding(8)
            .frame(minWidth: 160)
        }
    }

    private func modePickerButton(label: String, icon: String? = nil, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Text(label)
                    .font(.system(size: 12))
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.primary.opacity(0.001))
        )
    }

    // MARK: - File Transcription Mode Selector
    private var fileTranscriptionModeSelector: some View {
        HStack(spacing: 4) {
            Image(systemName: modeManager.fileTranscriptionMode != nil ? "wand.and.stars" : "text.quote")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(modeManager.fileTranscriptionMode != nil ? .purple : .secondary)
            Text(modeManager.fileTranscriptionMode?.name ?? "Raw")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundColor(modeManager.fileTranscriptionMode != nil ? .purple : .secondary)
            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 26, maxHeight: 26)
        .background(
            Capsule()
                .fill(Color(NSColor.separatorColor).opacity(0.15))
        )
        .overlay(
            Capsule()
                .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1)
        )
        .contentShape(Capsule())
        .onTapGesture {
            showingFileModeicker = true
        }
        .popover(isPresented: $showingFileModeicker, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                modePickerButton(label: "Raw transcription", isSelected: modeManager.fileTranscriptionModeId == nil) {
                    modeManager.setFileTranscriptionMode(nil)
                    showingFileModeicker = false
                }

                if !modeManager.modes.filter({ !$0.isBuiltIn }).isEmpty {
                    Divider()
                        .padding(.vertical, 4)
                    ForEach(modeManager.modes.filter { !$0.isBuiltIn }) { mode in
                        modePickerButton(label: mode.name, isSelected: modeManager.fileTranscriptionModeId == mode.id) {
                            modeManager.setFileTranscriptionMode(mode.id)
                            showingFileModeicker = false
                        }
                    }
                }

                Divider()
                    .padding(.vertical, 4)
                modePickerButton(label: "Manage Modes...", icon: "gear", isSelected: false) {
                    showingFileModeicker = false
                    openModesSettings()
                }
            }
            .padding(8)
            .frame(minWidth: 160)
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let fileURL = urls.first else { return }

            // Check if file is available locally (iCloud files might need downloading)
            let fileManager = FileManager.default

            // Check ubiquitous item download status for iCloud files
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey, .ubiquitousItemIsDownloadingKey])

                if let downloadStatus = resourceValues.ubiquitousItemDownloadingStatus {
                    if downloadStatus == .notDownloaded {
                        Logger.shared.log("File not downloaded from iCloud: \(fileURL.lastPathComponent)", level: .error)
                        appState.isTranscribingFile = true
                        appState.fileTranscriptionError = true
                        appState.fileTranscriptionProgress = "Download file from iCloud first"
                        appState.fileTranscriptionProgressValue = 0.0
                        Task {
                            try? await Task.sleep(nanoseconds: 2_500_000_000)
                            await MainActor.run {
                                appState.fileTranscriptionError = false
                                appState.isTranscribingFile = false
                                appState.fileTranscriptionProgress = ""
                            }
                        }
                        return
                    } else if resourceValues.ubiquitousItemIsDownloading == true {
                        Logger.shared.log("File is still downloading from iCloud: \(fileURL.lastPathComponent)", level: .warning)
                        appState.isTranscribingFile = true
                        appState.fileTranscriptionError = true
                        appState.fileTranscriptionProgress = "Wait for iCloud download to complete"
                        appState.fileTranscriptionProgressValue = 0.0
                        Task {
                            try? await Task.sleep(nanoseconds: 2_500_000_000)
                            await MainActor.run {
                                appState.fileTranscriptionError = false
                                appState.isTranscribingFile = false
                                appState.fileTranscriptionProgress = ""
                            }
                        }
                        return
                    }
                }
            } catch {
                // Not an iCloud file or can't check status - continue normally
                Logger.shared.log("Could not check iCloud status (likely local file): \(error.localizedDescription)", level: .debug)
            }

            // Start accessing security-scoped resource
            guard fileURL.startAccessingSecurityScopedResource() else {
                Logger.shared.log("Failed to access security-scoped resource for: \(fileURL.path)", level: .error)
                Task { @MainActor in
                    appState.isTranscribingFile = true
                    appState.fileTranscriptionError = true
                    appState.fileTranscriptionProgress = "Cannot access file"
                    appState.fileTranscriptionProgressValue = 0.0
                }
                Task {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    await MainActor.run {
                        appState.fileTranscriptionError = false
                        appState.isTranscribingFile = false
                        appState.fileTranscriptionProgress = ""
                    }
                }
                return
            }

            // Verify file exists and is readable
            guard fileManager.isReadableFile(atPath: fileURL.path) else {
                Logger.shared.log("File is not readable: \(fileURL.path)", level: .error)
                fileURL.stopAccessingSecurityScopedResource()
                Task { @MainActor in
                    appState.isTranscribingFile = true
                    appState.fileTranscriptionError = true
                    appState.fileTranscriptionProgress = "File not readable"
                    appState.fileTranscriptionProgressValue = 0.0
                }
                Task {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    await MainActor.run {
                        appState.fileTranscriptionError = false
                        appState.isTranscribingFile = false
                        appState.fileTranscriptionProgress = ""
                    }
                }
                return
            }

            let task = Task {
                defer {
                    fileURL.stopAccessingSecurityScopedResource()
                    Task { @MainActor in
                        appState.setFileTranscriptionTask(nil)
                    }
                }

                // Reset progress state
                await MainActor.run {
                    appState.isTranscribingFile = true
                    appState.fileTranscriptionProgress = "Preparing..."
                    appState.fileTranscriptionProgressValue = 0.0
                    appState.fileTranscriptionCompleted = false
                    appState.fileTranscriptionError = false
                }

                do {
                    // Check for cancellation before starting
                    try Task.checkCancellation()

                    let transcriber = AudioFileTranscriber.shared
                    let activeMode = modeManager.fileTranscriptionMode

                    try await transcriber.transcribeToNotes(
                        fileURL: fileURL,
                        mode: activeMode,
                        language: appState.cloudTranscriptionLanguage.isEmpty ? nil : appState.cloudTranscriptionLanguage
                    ) { progress in
                        Task { @MainActor in
                            appState.fileTranscriptionProgress = progress
                            // Update progress value based on stage
                            switch progress {
                            case "Preparing audio...":
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    appState.fileTranscriptionProgressValue = 0.15
                                }
                            case "Transcribing...":
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    appState.fileTranscriptionProgressValue = 0.4
                                }
                            case "Transforming...":
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    appState.fileTranscriptionProgressValue = 0.7
                                }
                            case "Saving to Notes...":
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    appState.fileTranscriptionProgressValue = 0.9
                                }
                            default:
                                break
                            }
                        }
                    }

                    // Show completion state
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            appState.fileTranscriptionProgressValue = 1.0
                            appState.fileTranscriptionProgress = "Done!"
                            appState.fileTranscriptionCompleted = true
                        }
                    }

                    // Keep success state visible briefly
                    try? await Task.sleep(nanoseconds: 1_500_000_000)

                    // Reset state
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            appState.isTranscribingFile = false
                            appState.fileTranscriptionProgress = ""
                            appState.fileTranscriptionProgressValue = 0.0
                            appState.fileTranscriptionCompleted = false
                        }
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
                    Logger.shared.log("Audio file transcription error: \(error.localizedDescription)", level: .error)

                    // Provide a user-friendly error message
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
            Logger.shared.log("File picker error: \(error.localizedDescription)", level: .error)

            // Show error to user
            Task { @MainActor in
                appState.isTranscribingFile = true
                appState.fileTranscriptionError = true
                appState.fileTranscriptionProgress = "Could not open file"
                appState.fileTranscriptionProgressValue = 0.0
            }
            Task {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                await MainActor.run {
                    appState.fileTranscriptionError = false
                    appState.isTranscribingFile = false
                    appState.fileTranscriptionProgress = ""
                }
            }
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
