// NotesIntegrationService.swift
// Mute

import Foundation
import AppKit

enum NotesError: LocalizedError {
    case scriptExecutionFailed(String)
    case noteCreationFailed
    case noteNotFound
    case notesAppNotAvailable

    var errorDescription: String? {
        switch self {
        case .scriptExecutionFailed(let message):
            return "AppleScript failed: \(message)"
        case .noteCreationFailed:
            return "Failed to create note in Notes app"
        case .noteNotFound:
            return "Note not found"
        case .notesAppNotAvailable:
            return "Notes app is not available"
        }
    }
}

class NotesIntegrationService {

    // MARK: - Public API

    /// Creates a new note in Apple Notes and returns its identifier
    /// - Parameter title: The title for the new note
    /// - Returns: The note identifier that can be used for subsequent appends
    func createNewNote(title: String) async throws -> String {
        let escapedTitle = escapeForAppleScript(title)
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)

        let script = """
        tell application "Notes"
            set newNote to make new note at folder "Notes" with properties {name:"\(escapedTitle)", body:"Capture started: \(timestamp)\\n\\n"}
            return id of newNote
        end tell
        """

        let noteId = try await runAppleScript(script)
        let trimmedId = noteId.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedId.isEmpty else {
            throw NotesError.noteCreationFailed
        }

        Logger.shared.log("Created new note with ID: \(trimmedId)")
        return trimmedId
    }

    /// Appends text to an existing note
    /// - Parameters:
    ///   - noteId: The note identifier returned from createNewNote
    ///   - text: The text to append
    func appendToNote(noteId: String, text: String) async throws {
        let escapedText = escapeForAppleScript(text)
        let escapedId = escapeForAppleScript(noteId)

        let script = """
        tell application "Notes"
            set theNote to note id "\(escapedId)"
            set currentBody to body of theNote
            set body of theNote to currentBody & "\(escapedText)" & "\\n\\n"
        end tell
        """

        _ = try await runAppleScript(script)
        Logger.shared.log("Appended text to note: \(text.prefix(50))...")
    }

    /// Finalizes a capture session by adding a completion timestamp
    /// - Parameter noteId: The note identifier
    func finalizeNote(noteId: String) async throws {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)
        let escapedId = escapeForAppleScript(noteId)

        let script = """
        tell application "Notes"
            set theNote to note id "\(escapedId)"
            set currentBody to body of theNote
            set body of theNote to currentBody & "---\\nCapture ended: \(timestamp)"
        end tell
        """

        _ = try await runAppleScript(script)
        Logger.shared.log("Finalized note: \(noteId)")
    }

    /// Checks if Notes app is available
    func isNotesAvailable() -> Bool {
        let workspace = NSWorkspace.shared
        return workspace.urlForApplication(withBundleIdentifier: "com.apple.Notes") != nil
    }

    // MARK: - Private Helpers

    private func runAppleScript(_ script: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                let appleScript = NSAppleScript(source: script)

                guard let result = appleScript?.executeAndReturnError(&error) else {
                    let errorMessage = error?[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                    continuation.resume(throwing: NotesError.scriptExecutionFailed(errorMessage))
                    return
                }

                let output = result.stringValue ?? ""
                continuation.resume(returning: output)
            }
        }
    }

    private func escapeForAppleScript(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}
