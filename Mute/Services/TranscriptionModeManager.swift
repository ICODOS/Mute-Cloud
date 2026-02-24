// TranscriptionModeManager.swift
// Mute

import Foundation
import Combine

/// Manages transcription modes (presets) for text transformation
@MainActor
final class TranscriptionModeManager: ObservableObject {
    static let shared = TranscriptionModeManager()

    // MARK: - Published Properties

    /// All available modes (built-in + user-defined)
    @Published private(set) var modes: [TranscriptionMode] = []

    /// The active mode ID for Quick Dictation
    @Published var dictationModeId: UUID? {
        didSet {
            saveModeId(dictationModeId, forKey: dictationModeIdKey)
        }
    }

    /// The active mode ID for Audio File Transcription
    @Published var fileTranscriptionModeId: UUID? {
        didSet {
            saveModeId(fileTranscriptionModeId, forKey: fileTranscriptionModeIdKey)
        }
    }

    /// The active mode for Quick Dictation
    var dictationMode: TranscriptionMode? {
        guard let id = dictationModeId else { return nil }
        return modes.first { $0.id == id }
    }

    /// The active mode for Audio File Transcription
    var fileTranscriptionMode: TranscriptionMode? {
        guard let id = fileTranscriptionModeId else { return nil }
        return modes.first { $0.id == id }
    }

    // Legacy compatibility
    var activeModeId: UUID? {
        get { fileTranscriptionModeId }
        set { fileTranscriptionModeId = newValue }
    }

    var activeMode: TranscriptionMode? {
        fileTranscriptionMode
    }

    // MARK: - Cycling Properties

    /// Mode IDs included in the hotkey cycling rotation
    @Published var cyclingModeIds: Set<UUID> = [] {
        didSet { saveCyclingModeIds() }
    }

    // MARK: - Private Properties

    private let userDefaultsKey = "transcriptionModes"
    private let dictationModeIdKey = "dictationModeId"
    private let fileTranscriptionModeIdKey = "fileTranscriptionModeId"
    private let cyclingModeIdsKey = "cyclingModeIds"

    // MARK: - Initialization

    private init() {
        loadModes()
        loadModeIds()
        loadCyclingState()
    }

    // MARK: - CRUD Operations

    /// Creates a new user-defined mode
    /// - Parameters:
    ///   - name: The mode name
    ///   - prompt: The system prompt for transformation
    ///   - modelId: The model ID to use for transformation
    ///   - temperature: Temperature for output consistency (0.0-1.0)
    ///   - maxTokens: Maximum response length in tokens
    /// - Returns: The created mode
    @discardableResult
    func createMode(
        name: String,
        prompt: String,
        modelId: String,
        temperature: Double = TemperaturePreset.creative.rawValue,
        maxTokens: Int = MaxTokensPreset.long.rawValue
    ) -> TranscriptionMode {
        let mode = TranscriptionMode(
            name: name,
            prompt: prompt,
            modelId: modelId,
            isBuiltIn: false,
            temperature: temperature,
            maxTokens: maxTokens
        )
        modes.append(mode)
        saveModes()
        Logger.shared.log("Created transcription mode: \(name)")
        return mode
    }

    /// Updates an existing mode
    /// - Parameters:
    ///   - id: The mode ID to update
    ///   - name: New name (optional)
    ///   - prompt: New prompt (optional)
    ///   - modelId: New model ID (optional)
    ///   - temperature: New temperature (optional)
    ///   - maxTokens: New max tokens (optional)
    func updateMode(
        id: UUID,
        name: String? = nil,
        prompt: String? = nil,
        modelId: String? = nil,
        temperature: Double? = nil,
        maxTokens: Int? = nil
    ) {
        guard let index = modes.firstIndex(where: { $0.id == id }) else {
            Logger.shared.log("Mode not found for update: \(id)", level: .warning)
            return
        }

        // Don't allow editing built-in modes
        guard !modes[index].isBuiltIn else {
            Logger.shared.log("Cannot edit built-in mode", level: .warning)
            return
        }

        if let name = name {
            modes[index].name = name
        }
        if let prompt = prompt {
            modes[index].prompt = prompt
        }
        if let modelId = modelId {
            modes[index].modelId = modelId
        }
        if let temperature = temperature {
            modes[index].temperature = temperature
        }
        if let maxTokens = maxTokens {
            modes[index].maxTokens = maxTokens
        }

        saveModes()
        Logger.shared.log("Updated transcription mode: \(modes[index].name)")
    }

    /// Deletes a mode
    /// - Parameter id: The mode ID to delete
    func deleteMode(id: UUID) {
        guard let index = modes.firstIndex(where: { $0.id == id }) else {
            return
        }

        // Don't allow deleting built-in modes
        guard !modes[index].isBuiltIn else {
            Logger.shared.log("Cannot delete built-in mode", level: .warning)
            return
        }

        let modeName = modes[index].name
        modes.remove(at: index)

        // If the deleted mode was active, reset to None
        if dictationModeId == id {
            dictationModeId = nil
        }
        if fileTranscriptionModeId == id {
            fileTranscriptionModeId = nil
        }

        saveModes()
        Logger.shared.log("Deleted transcription mode: \(modeName)")
    }

    /// Moves a mode from one position to another
    /// - Parameters:
    ///   - fromIndex: The current index of the mode (within user modes, not including built-in)
    ///   - toIndex: The target index
    func moveMode(fromIndex: Int, toIndex: Int) {
        // Get only user modes
        var userModes = modes.filter { !$0.isBuiltIn }

        guard fromIndex >= 0, fromIndex < userModes.count,
              toIndex >= 0, toIndex <= userModes.count else {
            return
        }

        let mode = userModes.remove(at: fromIndex)
        let insertIndex = toIndex > fromIndex ? toIndex - 1 : toIndex
        userModes.insert(mode, at: min(insertIndex, userModes.count))

        // Rebuild modes array: built-in first, then user modes in new order
        modes = modes.filter { $0.isBuiltIn } + userModes
        saveModes()
        Logger.shared.log("Reordered modes")
    }

    /// Moves modes using IndexSet (for SwiftUI onMove)
    /// - Parameters:
    ///   - source: Source indices
    ///   - destination: Destination index
    func moveModes(from source: IndexSet, to destination: Int) {
        var userModes = modes.filter { !$0.isBuiltIn }
        userModes.move(fromOffsets: source, toOffset: destination)

        // Rebuild modes array: built-in first, then user modes in new order
        modes = modes.filter { $0.isBuiltIn } + userModes
        saveModes()
        Logger.shared.log("Reordered modes")
    }

    /// Sets the active mode for Quick Dictation
    /// - Parameter id: The mode ID to activate, or nil for no mode
    func setDictationMode(_ id: UUID?) {
        dictationModeId = id
        if let mode = dictationMode {
            Logger.shared.log("Dictation mode set to: \(mode.name)")
        } else {
            Logger.shared.log("Dictation mode cleared")
        }
    }

    /// Sets the active mode for Audio File Transcription
    /// - Parameter id: The mode ID to activate, or nil for no mode
    func setFileTranscriptionMode(_ id: UUID?) {
        fileTranscriptionModeId = id
        if let mode = fileTranscriptionMode {
            Logger.shared.log("File transcription mode set to: \(mode.name)")
        } else {
            Logger.shared.log("File transcription mode cleared")
        }
    }

    /// Legacy: Sets the active mode (defaults to file transcription)
    /// - Parameter id: The mode ID to activate, or nil for no mode
    func setActiveMode(_ id: UUID?) {
        setFileTranscriptionMode(id)
    }

    // MARK: - Cycling Operations

    func toggleCycling(for modeId: UUID) {
        if cyclingModeIds.contains(modeId) {
            cyclingModeIds.remove(modeId)
        } else {
            cyclingModeIds.insert(modeId)
        }
    }

    func isCyclingEnabled(for modeId: UUID) -> Bool {
        cyclingModeIds.contains(modeId)
    }

    /// Cycles to the next dictation mode in the rotation and returns its display name
    @discardableResult
    func cycleToNextDictationMode() -> String {
        // Build ordered list of mode IDs in the cycle (nil = None, always included)
        var cycleList: [UUID?] = [nil]
        // Append user modes that are in the cycling set, preserving drag-reorder
        let userModes = modes.filter { !$0.isBuiltIn }
        for mode in userModes where cyclingModeIds.contains(mode.id) {
            cycleList.append(mode.id)
        }

        // If nothing to cycle through, stay on current
        guard !cycleList.isEmpty else {
            return dictationMode?.name ?? "None"
        }

        // Find current position
        let currentIndex = cycleList.firstIndex(where: { $0 == dictationModeId }) ?? -1
        let nextIndex = (currentIndex + 1) % cycleList.count
        let nextId = cycleList[nextIndex]

        setDictationMode(nextId)

        if let nextId = nextId, let mode = modes.first(where: { $0.id == nextId }) {
            return mode.name
        }
        return "None"
    }

    // MARK: - Persistence

    private func loadModes() {
        // Always start with the built-in "None" mode
        modes = [TranscriptionMode.none]

        // Load user-defined modes from UserDefaults
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            return
        }

        do {
            let userModes = try JSONDecoder().decode([TranscriptionMode].self, from: data)
            // Filter out any built-in modes that might have been accidentally saved
            let filteredModes = userModes.filter { !$0.isBuiltIn }
            modes.append(contentsOf: filteredModes)
            Logger.shared.log("Loaded \(filteredModes.count) user transcription modes")
        } catch {
            Logger.shared.log("Failed to load transcription modes: \(error)", level: .error)
        }
    }

    private func saveModes() {
        // Only save user-defined modes
        let userModes = modes.filter { !$0.isBuiltIn }

        do {
            let data = try JSONEncoder().encode(userModes)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            Logger.shared.log("Failed to save transcription modes: \(error)", level: .error)
        }
    }

    private func loadModeIds() {
        // Load dictation mode ID
        if let idString = UserDefaults.standard.string(forKey: dictationModeIdKey),
           let id = UUID(uuidString: idString),
           modes.contains(where: { $0.id == id }) {
            dictationModeId = id
        } else {
            dictationModeId = nil
        }

        // Load file transcription mode ID
        if let idString = UserDefaults.standard.string(forKey: fileTranscriptionModeIdKey),
           let id = UUID(uuidString: idString),
           modes.contains(where: { $0.id == id }) {
            fileTranscriptionModeId = id
        } else {
            fileTranscriptionModeId = nil
        }
    }

    private func saveModeId(_ id: UUID?, forKey key: String) {
        if let id = id {
            UserDefaults.standard.set(id.uuidString, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func loadCyclingState() {
        // Load cycling mode IDs
        if let strings = UserDefaults.standard.stringArray(forKey: cyclingModeIdsKey) {
            cyclingModeIds = Set(strings.compactMap { UUID(uuidString: $0) })
        }
    }

    private func saveCyclingModeIds() {
        let strings = cyclingModeIds.map { $0.uuidString }
        UserDefaults.standard.set(strings, forKey: cyclingModeIdsKey)
    }
}
