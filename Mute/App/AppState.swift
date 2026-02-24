// AppState.swift
// Mute

import Foundation
import SwiftUI
import Combine

// MARK: - Recording State
enum RecordingState: Equatable {
    case idle
    case recording
    case processing
    case done
    case error(String)

    static func == (lhs: RecordingState, rhs: RecordingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.recording, .recording), (.processing, .processing), (.done, .done):
            return true
        case (.error(let l), .error(let r)):
            return l == r
        default:
            return false
        }
    }
}

// MARK: - App State
@MainActor
class AppState: ObservableObject {
    static let shared = AppState()

    // MARK: - Published Properties
    @Published var recordingState: RecordingState = .idle
    @Published var finalText: String = ""
    @Published var errorMessage: String?
    @Published var logs: [Logger.LogEntry] = []

    // MARK: - Capture Mode
    @Published var isCaptureMode: Bool = false
    @Published var captureNoteId: String?
    private var pendingCaptureNoteId: String?  // Stores note ID when stopping capture, before final transcription

    // MARK: - Processing Timeout
    private var processingTimeoutTask: Task<Void, Never>?
    private var recordingStartTime: Date?

    // MARK: - Settings
    @AppStorage("pasteOnStop") var pasteOnStop: Bool = true
    @AppStorage("showOverlay") var showOverlay: Bool = true
    @AppStorage("preserveClipboard") var preserveClipboard: Bool = false
    @AppStorage("developerMode") var developerMode: Bool = false
    @AppStorage("selectedAudioDevice") var selectedAudioDeviceUID: String = ""
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    @AppStorage("captureNotesAudioDevice") var captureNotesAudioDeviceUID: String = ""  // Separate device for Capture to Notes

    // MARK: - Cloud Transcription Settings
    /// Optional language hint for cloud transcription (e.g., "en", "de")
    @AppStorage("cloudTranscriptionLanguage") var cloudTranscriptionLanguage: String = ""

    /// Optional prompt/context for cloud transcription (spelling hints, etc.)
    @AppStorage("cloudTranscriptionPrompt") var cloudTranscriptionPrompt: String = ""

    // MARK: - Usage Stats
    @AppStorage("totalDictations") var totalDictations: Int = 0
    @AppStorage("todayDictations") private var _todayDictations: Int = 0
    @AppStorage("todayDateString") private var todayDateString: String = ""
    @AppStorage("weekDictations") private var weekDictationsData: Data = Data()
    @AppStorage("weekStartDateString") private var weekStartDateString: String = ""

    // MARK: - Insights Stats
    @AppStorage("currentStreak") private var _currentStreak: Int = 0
    @AppStorage("longestStreak") var longestStreak: Int = 0
    @AppStorage("personalBestDay") var personalBestDay: Int = 0
    @AppStorage("lastDictationDate") private var lastDictationDate: String = ""
    @AppStorage("firstUseDate") private var firstUseDate: String = ""
    @AppStorage("totalWordsEstimate") var totalWordsEstimate: Int = 0

    /// Today's dictation count (refreshes automatically when day changes)
    var todayDictations: Int {
        get {
            refreshDayIfNeeded()
            return _todayDictations
        }
        set {
            _todayDictations = newValue
        }
    }

    /// Current streak (refreshes automatically, resets if day was missed)
    var currentStreak: Int {
        get {
            refreshStreakIfNeeded()
            return _currentStreak
        }
        set {
            _currentStreak = newValue
        }
    }

    // MARK: - Managers
    let audioManager = AudioCaptureManager()
    let textInsertionService = TextInsertionService()
    let permissionManager = PermissionManager()
    let notesIntegrationService = NotesIntegrationService()

    // MARK: - Cloud Transcription
    let groqProvider = GroqWhisperProvider.shared
    let groqChatProvider = GroqChatProvider.shared
    private var cloudAudioFileManager: AudioFileManager?
    private var cloudTranscriptionTask: Task<Void, Never>?
    private var fileTranscriptionTask: Task<Void, Never>?

    // MARK: - Transcription Modes
    let modeManager = TranscriptionModeManager.shared

    // MARK: - File Transcription State
    @Published var isTranscribingFile: Bool = false
    @Published var fileTranscriptionProgress: String = ""
    @Published var fileTranscriptionProgressValue: Double = 0.0
    @Published var fileTranscriptionCompleted: Bool = false
    @Published var fileTranscriptionError: Bool = false

    // MARK: - Overlay
    weak var overlayPanel: OverlayPanel?

    // MARK: - Private
    private var cancellables = Set<AnyCancellable>()
    private var doneTimer: Timer?

    // MARK: - Initialization
    private init() {
        // Refresh usage stats on launch (reset day/week counters if needed)
        refreshDayIfNeeded()
        refreshWeekIfNeeded()

        // Migrate insights stats if they're new (zeros but we have existing dictations)
        migrateInsightsIfNeeded()

        setupBindings()
    }

    private func migrateInsightsIfNeeded() {
        // Only migrate if we have dictations but insights are all zeros
        guard totalDictations > 0 else { return }

        // Check if week data has values for future days (indicates corrupted data)
        let todayIndex = currentDayOfWeek()
        var counts = (try? JSONDecoder().decode([Int].self, from: weekDictationsData)) ?? [0, 0, 0, 0, 0, 0, 0]

        // Check for values in days after today (which shouldn't exist yet this week)
        var hasFutureData = false
        for i in (todayIndex + 1)..<7 {
            if counts[i] > 0 {
                hasFutureData = true
                break
            }
        }

        // If we have future data, reset the week but keep today's count
        if hasFutureData {
            let todayCount = _todayDictations
            counts = [0, 0, 0, 0, 0, 0, 0]
            if todayIndex >= 0 && todayIndex < 7 {
                counts[todayIndex] = todayCount
            }
            if let data = try? JSONEncoder().encode(counts) {
                weekDictationsData = data
            }
            weekStartDateString = currentWeekStartString()
            Logger.shared.log("Migrated corrupted week data, reset to today's count: \(todayCount)")
        }

        // Set first use date if not set (estimate: assume started recently)
        if firstUseDate.isEmpty {
            // Estimate first use date based on total dictations and average of ~5/day
            let estimatedDays = max(1, totalDictations / 5)
            let calendar = Calendar.current
            if let estimatedStart = calendar.date(byAdding: .day, value: -estimatedDays, to: Date()) {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                formatter.timeZone = TimeZone.current
                firstUseDate = formatter.string(from: estimatedStart)
            }
        }

        // Set streak to 1 if we have dictations today
        if _currentStreak == 0 && _todayDictations > 0 {
            _currentStreak = 1
            lastDictationDate = currentDateString()
        }

        // Set longest streak to at least current streak
        if longestStreak < _currentStreak {
            longestStreak = _currentStreak
        }

        // Set personal best from today if it's higher
        if personalBestDay == 0 && _todayDictations > 0 {
            personalBestDay = _todayDictations
        }

        // Estimate total words if not set (~25 words per dictation average)
        if totalWordsEstimate == 0 {
            totalWordsEstimate = totalDictations * 25
        }
    }

    private func setupBindings() {
        // Monitor audio device changes - reset selected device if it disconnects
        AudioDeviceMonitor.shared.$inputDevices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                self?.validateSelectedAudioDevices(availableDevices: devices)
            }
            .store(in: &cancellables)
    }

    // MARK: - Audio Device Validation
    /// Validates that selected audio devices are still available, resets to default if not
    private func validateSelectedAudioDevices(availableDevices: [AudioDevice]) {
        let availableUIDs = Set(availableDevices.map { $0.uid })

        // Check dictation device
        if !selectedAudioDeviceUID.isEmpty && !availableUIDs.contains(selectedAudioDeviceUID) {
            Logger.shared.log("Selected dictation device '\(selectedAudioDeviceUID)' no longer available, resetting to System Default")
            selectedAudioDeviceUID = ""
        }

        // Check capture notes device
        if !captureNotesAudioDeviceUID.isEmpty && !availableUIDs.contains(captureNotesAudioDeviceUID) {
            Logger.shared.log("Selected capture device '\(captureNotesAudioDeviceUID)' no longer available, resetting to System Default")
            captureNotesAudioDeviceUID = ""
        }
    }

    // MARK: - Recording Control
    func startRecording() async {
        // Allow starting from idle, done, or any error state
        switch recordingState {
        case .idle, .done, .error:
            break  // OK to proceed
        default:
            Logger.shared.log("Cannot start recording in state: \(recordingState)")
            return
        }

        // Cancel any lingering processing timeout from previous recording
        processingTimeoutTask?.cancel()
        processingTimeoutTask = nil

        // Check permissions
        let hasMicPermission = await permissionManager.hasMicrophonePermission()
        if !hasMicPermission {
            let granted = await permissionManager.requestMicrophonePermission()
            if !granted {
                errorMessage = "Microphone permission is required"
                recordingState = .error("No microphone permission")
                return
            }
        }

        // Reset state
        finalText = ""
        errorMessage = nil

        // Cancel any existing cloud transcription task
        cloudTranscriptionTask?.cancel()
        cloudTranscriptionTask = nil

        // Validate Groq configuration
        let validation = groqProvider.validateConfiguration()
        if !validation.isValid {
            Logger.shared.log("Groq configuration invalid: \(validation.errorMessage ?? "unknown")", level: .error)
            errorMessage = validation.errorMessage
            recordingState = .error(validation.errorMessage ?? "Groq not configured")
            return
        }
        cloudAudioFileManager = AudioFileManager()
        Logger.shared.log("Cloud transcription enabled - recording audio for Groq upload")

        // Update state to show we're recording
        recordingState = .recording
        recordingStartTime = Date()

        // Show overlay
        if showOverlay {
            overlayPanel?.show(state: .recording)
        }

        let deviceUID = isCaptureMode ? captureNotesAudioDeviceUID : selectedAudioDeviceUID
        let cloudAudioManager = self.cloudAudioFileManager

        do {
            let audioStartTime = Date()

            // Start audio capture - callback saves audio for cloud transcription
            try audioManager.startCapture(
                deviceUID: deviceUID.isEmpty ? nil : deviceUID,
                chunkSizeMs: 400
            ) { audioData in
                cloudAudioManager?.appendAudioData(audioData)
            }

            let initTime = Date().timeIntervalSince(audioStartTime) * 1000
            Logger.shared.log("Cloud recording started in \(Int(initTime))ms - audio being buffered for upload")
        } catch {
            Logger.shared.log("Failed to start recording: \(error)", level: .error)
            audioManager.stopCapture()
            recordingState = .error(error.localizedDescription)
            overlayPanel?.show(state: .error)
        }
    }

    func stopRecording() async {
        guard recordingState == .recording else {
            Logger.shared.log("Cannot stop recording in state: \(recordingState)")
            return
        }

        // Update state
        recordingState = .processing

        // Update overlay
        if showOverlay {
            overlayPanel?.show(state: .processing)
        }

        // Stop audio capture
        audioManager.stopCapture()

        // Always use cloud transcription
        await stopRecordingCloud()
    }

    /// Stop recording and send to Groq cloud API
    private func stopRecordingCloud() async {
        Logger.shared.log("Recording stopped, starting cloud transcription...")

        // Capture references for the task
        let audioFileManager = cloudAudioFileManager
        let language = cloudTranscriptionLanguage.isEmpty ? nil : cloudTranscriptionLanguage
        let prompt = cloudTranscriptionPrompt.isEmpty ? nil : cloudTranscriptionPrompt

        // Cancel any existing cloud transcription task
        cloudTranscriptionTask?.cancel()

        // Start cloud transcription in a task
        cloudTranscriptionTask = Task { [weak self] in
            guard let self = self else { return }

            var tempFileURL: URL?

            do {
                // Check if we have audio data
                guard let fileManager = audioFileManager else {
                    throw TranscriptionError.unknown(message: "No audio data recorded")
                }

                let duration = fileManager.duration
                Logger.shared.log(String(format: "Cloud transcription: %.1f seconds of audio recorded", duration))

                // Note: Groq bills minimum 10 seconds per request
                if duration < 10 {
                    Logger.shared.log("Note: Groq bills minimum 10 seconds per request. Short recordings (<10s) will be billed as 10 seconds.", level: .info)
                }

                // Write audio to WAV file
                guard let fileURL = try fileManager.writeToWAVFile() else {
                    throw TranscriptionError.unknown(message: "No audio data to transcribe")
                }
                tempFileURL = fileURL

                // Check for cancellation
                try Task.checkCancellation()

                // Send to Groq for transcription
                let text = try await self.groqProvider.transcribe(
                    audioFileURL: fileURL,
                    language: language,
                    prompt: prompt
                )

                // Check for cancellation before updating UI
                try Task.checkCancellation()

                // Update UI on main actor
                await MainActor.run {
                    self.handleFinalTranscription(text)
                }

            } catch is CancellationError {
                Logger.shared.log("Cloud transcription cancelled", level: .info)
                await MainActor.run {
                    self.recordingState = .idle
                    self.overlayPanel?.hide()
                }
            } catch let error as TranscriptionError {
                Logger.shared.log("Cloud transcription error: \(error.localizedDescription)", level: .error)
                await MainActor.run {
                    self.handleError(error.localizedDescription)
                }
            } catch {
                Logger.shared.log("Cloud transcription error: \(error)", level: .error)
                await MainActor.run {
                    self.handleError("Transcription failed: \(error.localizedDescription)")
                }
            }

            // Clean up temp file
            if let url = tempFileURL {
                AudioFileManager.deleteTemporaryFile(url)
            }

            // Clean up cloud audio manager
            await MainActor.run {
                self.cloudAudioFileManager = nil
            }
        }

        // Set timeout for cloud transcription (2 minutes for large files)
        processingTimeoutTask?.cancel()
        processingTimeoutTask = Task {
            try? await Task.sleep(nanoseconds: 120_000_000_000) // 120 seconds
            guard !Task.isCancelled else { return }
            if recordingState == .processing {
                Logger.shared.log("Cloud transcription timeout", level: .warning)
                cloudTranscriptionTask?.cancel()
                recordingState = .error("Transcription timeout - please try again")
                overlayPanel?.show(state: .error)
            }
        }
    }

    func cancelRecording() {
        guard recordingState == .recording || recordingState == .processing else {
            Logger.shared.log("Cannot cancel recording in state: \(recordingState)")
            return
        }

        // Cancel any processing timeout
        processingTimeoutTask?.cancel()
        processingTimeoutTask = nil

        // Cancel any cloud transcription task
        cloudTranscriptionTask?.cancel()
        cloudTranscriptionTask = nil
        cloudAudioFileManager = nil

        // Stop audio capture without processing
        audioManager.stopCapture()

        // Reset state
        recordingState = .idle
        finalText = ""

        // Hide overlay
        overlayPanel?.hide()

        Logger.shared.log("Recording cancelled")
    }

    // MARK: - File Transcription Control

    /// Store a file transcription task for cancellation support
    func setFileTranscriptionTask(_ task: Task<Void, Never>?) {
        fileTranscriptionTask = task
    }

    /// Cancel an ongoing file transcription
    func cancelFileTranscription() {
        fileTranscriptionTask?.cancel()
        fileTranscriptionTask = nil

        Logger.shared.log("File transcription cancelled")
        // State cleanup is handled by the error handling in the task itself
    }

    // MARK: - Capture Mode Control
    func startCaptureMode() async {
        Logger.shared.log("=== STARTING CAPTURE MODE ===")

        // Validate Groq configuration
        let validation = groqProvider.validateConfiguration()
        if !validation.isValid {
            Logger.shared.log("Groq configuration invalid: \(validation.errorMessage ?? "unknown")", level: .error)
            errorMessage = validation.errorMessage
            recordingState = .error(validation.errorMessage ?? "Groq not configured")
            return
        }

        // Check if Notes app is available
        let notesAvailable = notesIntegrationService.isNotesAvailable()
        guard notesAvailable else {
            Logger.shared.log("Notes app not available", level: .error)
            errorMessage = "Notes app is not available"
            recordingState = .error("Notes app not found")
            return
        }

        // Create a new note for this capture session
        do {
            let title = "Mute Capture - \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short))"
            captureNoteId = try await notesIntegrationService.createNewNote(title: title)
            Logger.shared.log("Created note with ID: \(captureNoteId ?? "nil")")
            isCaptureMode = true

            // Start recording
            await startRecording()
        } catch {
            Logger.shared.log("Failed to create note: \(error)", level: .error)
            errorMessage = "Failed to create note: \(error.localizedDescription)"
            recordingState = .error("Failed to create note")
            isCaptureMode = false
            captureNoteId = nil
        }
    }

    func stopCaptureMode() async {
        guard isCaptureMode else { return }

        // Store the note ID before stopping - we need it for the final transcription
        pendingCaptureNoteId = captureNoteId

        // Reset capture state early (but keep pendingCaptureNoteId for finalization)
        isCaptureMode = false
        captureNoteId = nil

        // Stop the recording - this will trigger final transcription
        await stopRecording()

        // Note: Don't finalize the note here - do it after final transcription in handleFinalTranscription
    }

    func toggleCaptureMode() async {
        Logger.shared.log("toggleCaptureMode called, isCaptureMode: \(isCaptureMode)")
        if isCaptureMode {
            await stopCaptureMode()
        } else {
            await startCaptureMode()
        }
    }

    // MARK: - Transcription Handlers
    private func handleFinalTranscription(_ text: String) {
        // Cancel processing timeout since we received a response
        processingTimeoutTask?.cancel()
        processingTimeoutTask = nil

        // Check if we need to apply a transformation
        if let mode = modeManager.dictationMode,
           mode.hasTransformation {
            // Apply transformation before proceeding
            Task {
                await applyTransformationAndComplete(originalText: text, mode: mode)
            }
            return
        }

        // No transformation needed, proceed with the original text
        completeTranscription(text)
    }

    /// Applies text transformation using Groq Chat and then completes the transcription
    private func applyTransformationAndComplete(originalText: String, mode: TranscriptionMode) async {
        // Update overlay to show transforming
        if showOverlay {
            overlayPanel?.show(state: .processing)
        }

        do {
            Logger.shared.log("Applying transformation with mode: \(mode.name)")
            let transformedText = try await groqChatProvider.transform(
                text: originalText,
                prompt: mode.prompt,
                model: mode.modelId,
                temperature: mode.temperature,
                maxTokens: mode.maxTokens
            )
            Logger.shared.log("Transformation complete: \(transformedText.prefix(100))...")
            completeTranscription(transformedText, wasTransformed: true)
        } catch {
            Logger.shared.log("Transformation failed: \(error)", level: .error)
            // Fall back to original text on error (plain text, not transformed)
            completeTranscription(originalText)
        }
    }

    /// Completes the transcription process with the final text
    /// - Parameters:
    ///   - text: The transcription text
    ///   - wasTransformed: If true, text came from LLM and should be treated as HTML
    private func completeTranscription(_ text: String, wasTransformed: Bool = false) {
        finalText = text

        // Handle capture mode differently - append to Notes instead of clipboard
        if isCaptureMode, let noteId = captureNoteId {
            Task {
                do {
                    try await notesIntegrationService.appendToNote(noteId: noteId, text: text, isHTML: wasTransformed)
                    Logger.shared.log("Transcription appended to note")
                } catch {
                    Logger.shared.log("Failed to append to note: \(error)", level: .error)
                }
            }
            // In capture mode, keep recording state as recording (don't set to done)
            // The user will stop it manually
            recordingState = .recording
            return
        }

        // Check if this is a final transcription from a capture session that just ended
        if let noteId = pendingCaptureNoteId {
            Task {
                do {
                    // Append final transcription text if not empty
                    let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedText.isEmpty {
                        try await notesIntegrationService.appendToNote(noteId: noteId, text: trimmedText, isHTML: wasTransformed)
                        Logger.shared.log("Final transcription appended to note")
                    }
                    // Then finalize the note
                    try await notesIntegrationService.finalizeNote(noteId: noteId)
                    Logger.shared.log("Capture mode ended, note finalized")
                } catch {
                    Logger.shared.log("Failed to finalize capture note: \(error)", level: .error)
                }
            }
            pendingCaptureNoteId = nil
            recordingState = .done

            // Show done overlay briefly
            if showOverlay {
                overlayPanel?.show(state: .done, text: "Saved to Notes")
            }

            // Auto-hide overlay after delay
            doneTimer?.invalidate()
            doneTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.overlayPanel?.hide()
                }
            }
            return  // Don't copy to clipboard for capture mode
        }

        recordingState = .done

        // Show done overlay
        if showOverlay {
            overlayPanel?.show(state: .done, text: String(text.prefix(60)))
        }

        // Copy to clipboard and optionally paste
        if pasteOnStop {
            textInsertionService.insertText(text, preserveClipboard: preserveClipboard)
        } else {
            textInsertionService.copyToClipboard(text)
        }

        // Record stats for this dictation
        if !text.isEmpty {
            recordDictation()
        }

        Logger.shared.log("Final transcription received: \(text.prefix(100))...")

        // Auto-hide overlay after delay
        doneTimer?.invalidate()
        doneTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.overlayPanel?.hide()
                // Don't reset state to idle automatically - keep showing done
            }
        }
    }

    private func handleError(_ error: String) {
        // Cancel any processing timeout
        processingTimeoutTask?.cancel()
        processingTimeoutTask = nil

        errorMessage = error
        recordingState = .error(error)

        if showOverlay {
            overlayPanel?.show(state: .error)
        }

        // Stop audio if recording
        audioManager.stopCapture()

        Logger.shared.log("Error: \(error)", level: .error)
    }

    // MARK: - Utility
    func refreshLogs() {
        logs = Logger.shared.getLogs()
    }

    // MARK: - Usage Stats

    /// Get this week's dictation count (Monday to Sunday)
    var weekDictations: Int {
        refreshWeekIfNeeded()
        guard let counts = try? JSONDecoder().decode([Int].self, from: weekDictationsData) else {
            return 0
        }
        return counts.reduce(0, +)
    }

    /// Record a completed dictation
    func recordDictation(wordCount: Int = 0) {
        refreshDayIfNeeded()
        refreshWeekIfNeeded()

        let today = currentDateString()

        // Set first use date if not set
        if firstUseDate.isEmpty {
            firstUseDate = today
        }

        // Increment total
        totalDictations += 1

        // Increment today (use backing property since we already refreshed)
        _todayDictations += 1

        // Update personal best
        if _todayDictations > personalBestDay {
            personalBestDay = _todayDictations
        }

        // Update streak
        updateStreak(forDate: today)

        // Estimate words (average ~25 words per dictation if not provided)
        totalWordsEstimate += wordCount > 0 ? wordCount : 25

        // Increment this week's day
        var counts = (try? JSONDecoder().decode([Int].self, from: weekDictationsData)) ?? [0, 0, 0, 0, 0, 0, 0]
        let dayOfWeek = currentDayOfWeek()
        if dayOfWeek >= 0 && dayOfWeek < 7 {
            counts[dayOfWeek] += 1
        }
        if let data = try? JSONEncoder().encode(counts) {
            weekDictationsData = data
        }

        Logger.shared.log("Dictation recorded: today=\(todayDictations), week=\(weekDictations), total=\(totalDictations), streak=\(_currentStreak)")
    }

    /// Get weekly data as array for chart [Mon, Tue, Wed, Thu, Fri, Sat, Sun]
    var weeklyData: [Int] {
        refreshWeekIfNeeded()
        return (try? JSONDecoder().decode([Int].self, from: weekDictationsData)) ?? [0, 0, 0, 0, 0, 0, 0]
    }

    /// Get the best day of the week (0 = Monday, 6 = Sunday)
    var bestDayOfWeek: (dayIndex: Int, count: Int)? {
        let data = weeklyData
        guard let maxCount = data.max(), maxCount > 0 else { return nil }
        guard let index = data.firstIndex(of: maxCount) else { return nil }
        return (index, maxCount)
    }

    /// Average dictations per day (since first use)
    var averagePerDay: Double {
        guard !firstUseDate.isEmpty else { return 0 }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current

        guard let startDate = formatter.date(from: firstUseDate) else { return 0 }
        let daysSinceStart = max(1, Calendar.current.dateComponents([.day], from: startDate, to: Date()).day ?? 1)

        return Double(totalDictations) / Double(daysSinceStart)
    }

    /// Estimated time saved in seconds (speaking ~150 WPM vs typing ~40 WPM)
    var timeSavedSeconds: Int {
        // Time to type the words at 40 WPM (in minutes, then convert to seconds)
        let typingTimeMinutes = Double(totalWordsEstimate) / 40.0
        // Time to speak the words at 150 WPM
        let speakingTimeMinutes = Double(totalWordsEstimate) / 150.0
        // Time saved in seconds
        return max(0, Int((typingTimeMinutes - speakingTimeMinutes) * 60))
    }

    /// Day name for index (0 = Monday)
    func dayName(for index: Int) -> String {
        let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        guard index >= 0 && index < days.count else { return "" }
        return days[index]
    }

    func fullDayName(for index: Int) -> String {
        let days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        guard index >= 0 && index < days.count else { return "" }
        return days[index]
    }

    private func refreshDayIfNeeded() {
        let today = currentDateString()
        if todayDateString != today {
            todayDateString = today
            _todayDictations = 0
        }
    }

    private func refreshWeekIfNeeded() {
        let weekStart = currentWeekStartString()

        // Safety check: don't reset if we got an empty or invalid week start
        guard !weekStart.isEmpty, weekStart.count == 10 else {
            return
        }

        if weekStartDateString != weekStart {
            Logger.shared.log("Week changed from \(weekStartDateString) to \(weekStart), resetting weekly data")
            weekStartDateString = weekStart
            // Reset week counts
            let emptyCounts = [0, 0, 0, 0, 0, 0, 0]
            if let data = try? JSONEncoder().encode(emptyCounts) {
                weekDictationsData = data
            }
        }
    }

    private func currentDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current  // Explicitly use local timezone
        return formatter.string(from: Date())
    }

    private func currentWeekStartString() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current

        let today = Date()

        // Get weekday: Sunday = 1, Monday = 2, ..., Saturday = 7
        let weekday = calendar.component(.weekday, from: today)

        // Calculate days since Monday (Monday = 0, Tuesday = 1, ..., Sunday = 6)
        let daysSinceMonday = (weekday + 5) % 7

        // Get Monday by subtracting days since Monday
        guard let monday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: today) else {
            // Return existing value to prevent accidental data reset
            return weekStartDateString.isEmpty ? currentDateString() : weekStartDateString
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: monday)
    }

    private func currentDayOfWeek() -> Int {
        // Use gregorian calendar with Monday as first weekday
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2  // Monday = 2 in gregorian
        calendar.timeZone = TimeZone.current  // Use local timezone

        // Get weekday (1 = Sunday, 2 = Monday, ..., 7 = Saturday in gregorian)
        let weekday = calendar.component(.weekday, from: Date())
        // Convert to Monday = 0, Sunday = 6
        // Monday (2) -> 0, Tuesday (3) -> 1, ..., Sunday (1) -> 6
        return (weekday + 5) % 7
    }

    // MARK: - Streak Management

    private func updateStreak(forDate today: String) {
        if lastDictationDate.isEmpty {
            // First ever dictation
            _currentStreak = 1
            lastDictationDate = today
        } else if lastDictationDate == today {
            // Already dictated today, streak unchanged
            return
        } else if isYesterday(lastDictationDate, relativeTo: today) {
            // Dictated yesterday, extend streak
            _currentStreak += 1
            lastDictationDate = today
        } else {
            // Missed a day, reset streak
            _currentStreak = 1
            lastDictationDate = today
        }

        // Update longest streak if current is higher
        if _currentStreak > longestStreak {
            longestStreak = _currentStreak
        }
    }

    private func refreshStreakIfNeeded() {
        let today = currentDateString()

        // If we haven't dictated today and it's been more than a day, reset streak
        if !lastDictationDate.isEmpty && lastDictationDate != today {
            if !isYesterday(lastDictationDate, relativeTo: today) && !isToday(lastDictationDate) {
                _currentStreak = 0
            }
        }
    }

    private func isYesterday(_ dateString: String, relativeTo today: String) -> Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current

        guard let date = formatter.date(from: dateString),
              let todayDate = formatter.date(from: today) else {
            return false
        }

        let calendar = Calendar.current
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: todayDate) else {
            return false
        }

        return calendar.isDate(date, inSameDayAs: yesterday)
    }

    private func isToday(_ dateString: String) -> Bool {
        return dateString == currentDateString()
    }

}
