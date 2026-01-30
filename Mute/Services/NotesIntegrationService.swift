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

        let htmlBody = """
        <h2>Capture Started</h2>\
        <p style="color:gray;font-size:small;">\(timestamp)</p>\
        <hr>
        """
        let escapedBody = escapeForAppleScript(htmlBody)

        let script = """
        tell application "Notes"
            set newNote to make new note at folder "Notes" with properties {name:"\(escapedTitle)", body:"\(escapedBody)"}
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
    ///   - isHTML: If true, text is treated as HTML and passed through as-is. If false, text is escaped and wrapped in paragraph tags.
    func appendToNote(noteId: String, text: String, isHTML: Bool = false) async throws {
        let htmlContent: String
        if isHTML {
            // LLM output - pass through as-is (already HTML formatted)
            htmlContent = text
        } else {
            // Plain text - escape and wrap in paragraph
            let htmlSafeText = escapeHTML(text)
            htmlContent = "<p>\(htmlSafeText)</p>"
        }
        let escapedContent = escapeForAppleScript(htmlContent)
        let escapedId = escapeForAppleScript(noteId)

        let script = """
        tell application "Notes"
            set theNote to note id "\(escapedId)"
            set currentBody to body of theNote
            set body of theNote to currentBody & "\(escapedContent)"
        end tell
        """

        _ = try await runAppleScript(script)
        Logger.shared.log("Appended text to note: \(text.prefix(50))...")
    }

    /// Creates a new note for audio file transcription
    /// - Parameters:
    ///   - title: The title for the note
    ///   - fileName: The original audio file name
    /// - Returns: The note identifier
    func createTranscriptionNote(title: String, fileName: String) async throws -> String {
        let escapedTitle = escapeForAppleScript(title)
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)
        let safeFileName = escapeHTML(fileName)

        let htmlBody = """
        <h2>Transcription</h2>\
        <p style="color:gray;font-size:small;">File: \(safeFileName)<br>Transcribed: \(timestamp)</p>\
        <hr>
        """
        let escapedBody = escapeForAppleScript(htmlBody)

        let script = """
        tell application "Notes"
            set newNote to make new note at folder "Notes" with properties {name:"\(escapedTitle)", body:"\(escapedBody)"}
            return id of newNote
        end tell
        """

        let noteId = try await runAppleScript(script)
        let trimmedId = noteId.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedId.isEmpty else {
            throw NotesError.noteCreationFailed
        }

        Logger.shared.log("Created transcription note with ID: \(trimmedId)")
        return trimmedId
    }

    /// Finalizes a transcription note
    /// - Parameter noteId: The note identifier
    func finalizeTranscriptionNote(noteId: String) async throws {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)
        let escapedId = escapeForAppleScript(noteId)

        let htmlFooter = """
        <hr>\
        <p style="color:gray;font-size:small;font-style:italic;">Transcription completed: \(timestamp)</p>
        """
        let escapedFooter = escapeForAppleScript(htmlFooter)

        let script = """
        tell application "Notes"
            set theNote to note id "\(escapedId)"
            set currentBody to body of theNote
            set body of theNote to currentBody & "\(escapedFooter)"
        end tell
        """

        _ = try await runAppleScript(script)
        Logger.shared.log("Finalized transcription note: \(noteId)")
    }

    /// Finalizes a capture session by adding a completion timestamp
    /// - Parameter noteId: The note identifier
    func finalizeNote(noteId: String) async throws {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)
        let escapedId = escapeForAppleScript(noteId)

        let htmlFooter = """
        <hr>\
        <p style="color:gray;font-size:small;font-style:italic;">Capture ended: \(timestamp)</p>
        """
        let escapedFooter = escapeForAppleScript(htmlFooter)

        let script = """
        tell application "Notes"
            set theNote to note id "\(escapedId)"
            set currentBody to body of theNote
            set body of theNote to currentBody & "\(escapedFooter)"
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

    private func escapeHTML(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
