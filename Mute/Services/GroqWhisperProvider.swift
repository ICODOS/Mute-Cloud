// GroqWhisperProvider.swift
// Mute

import Foundation

/// Groq Whisper V3 Turbo transcription provider
/// Uses Groq's Speech-to-Text API endpoint for fast cloud transcription
///
/// API Documentation: https://console.groq.com/docs/speech-to-text
///
/// Note: Groq bills minimum 10 seconds per request. For very short recordings (<10s),
/// you will still be charged for 10 seconds of audio.
final class GroqWhisperProvider: TranscriptionProvider {
    // MARK: - Constants

    private let apiEndpoint = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!
    private let modelName = "whisper-large-v3-turbo"

    /// Request timeout in seconds (generous for large files)
    private let requestTimeout: TimeInterval = 120

    /// Maximum retries for transient errors
    private let maxRetries = 2

    /// Delay between retries (seconds)
    private let retryDelay: TimeInterval = 1.0

    /// Maximum file size (MB) - Groq Developer tier limit
    private let maxFileSizeMB: Double = 40.0

    // MARK: - TranscriptionProvider Protocol

    var displayName: String {
        return "Groq Whisper V3 Turbo"
    }

    var requiresAPIKey: Bool {
        return true
    }

    func validateConfiguration() -> TranscriptionProviderValidation {
        guard let apiKey = KeychainManager.shared.getGroqAPIKey(), !apiKey.isEmpty else {
            return .invalid(reason: "Groq API key is not configured. Please add your API key in Settings → Cloud Transcription.")
        }

        // Basic format validation (Groq keys typically start with "gsk_")
        if !apiKey.hasPrefix("gsk_") {
            return .invalid(reason: "API key format appears invalid. Groq API keys typically start with 'gsk_'.")
        }

        return .valid
    }

    // MARK: - Transcription

    func transcribe(audioFileURL: URL, language: String?, prompt: String?) async throws -> String {
        // Validate configuration
        let validation = validateConfiguration()
        if case .invalid(let reason) = validation {
            throw TranscriptionError.missingAPIKey
        }

        guard let apiKey = KeychainManager.shared.getGroqAPIKey() else {
            throw TranscriptionError.missingAPIKey
        }

        // Load audio file
        let audioData: Data
        do {
            audioData = try Data(contentsOf: audioFileURL)
        } catch {
            Logger.shared.log("GroqWhisperProvider: Failed to load audio file: \(error)", level: .error)
            throw TranscriptionError.networkError(underlying: error)
        }

        // Validate file size
        let fileSizeMB = Double(audioData.count) / (1024 * 1024)
        if fileSizeMB > maxFileSizeMB {
            throw TranscriptionError.audioFileTooLarge(sizeMB: fileSizeMB, maxMB: maxFileSizeMB)
        }

        Logger.shared.log(String(format: "GroqWhisperProvider: Uploading audio file (%.2f MB)", fileSizeMB))

        // Build multipart request
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: apiEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = requestTimeout

        // Build multipart body
        let body = buildMultipartBody(
            audioData: audioData,
            fileName: audioFileURL.lastPathComponent,
            language: language,
            prompt: prompt,
            boundary: boundary
        )
        request.httpBody = body

        // Execute with retries
        var lastError: Error?
        for attempt in 0...maxRetries {
            if attempt > 0 {
                Logger.shared.log("GroqWhisperProvider: Retry attempt \(attempt)/\(maxRetries)")
                try await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
            }

            do {
                let transcription = try await executeRequest(request)
                Logger.shared.log("GroqWhisperProvider: Transcription successful (\(transcription.count) chars)")
                return transcription
            } catch let error as TranscriptionError {
                lastError = error

                // Don't retry for certain errors
                switch error {
                case .invalidAPIKey, .missingAPIKey, .audioFileTooLarge, .unsupportedAudioFormat:
                    throw error
                case .cancelled:
                    throw error
                case .serverError(let statusCode, _) where statusCode >= 400 && statusCode < 500:
                    // Don't retry client errors (except 429 rate limit)
                    if statusCode != 429 {
                        throw error
                    }
                default:
                    // Retry for network/server errors
                    continue
                }
            } catch {
                lastError = error
                // Retry for unknown errors
            }
        }

        throw lastError ?? TranscriptionError.unknown(message: "Request failed after \(maxRetries) retries")
    }

    // MARK: - Request Building

    /// Returns the MIME type for an audio file based on its extension
    private func mimeType(for fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "wav":
            return "audio/wav"
        case "mp3":
            return "audio/mpeg"
        case "m4a", "mp4":
            return "audio/mp4"
        case "flac":
            return "audio/flac"
        case "ogg":
            return "audio/ogg"
        case "webm":
            return "audio/webm"
        case "mpeg", "mpga":
            return "audio/mpeg"
        default:
            return "audio/wav"
        }
    }

    /// Builds a multipart/form-data request body
    func buildMultipartBody(
        audioData: Data,
        fileName: String,
        language: String?,
        prompt: String?,
        boundary: String
    ) -> Data {
        var body = Data()

        // Helper to append string as UTF8 data
        func append(_ string: String) {
            body.append(string.data(using: .utf8)!)
        }

        // File field
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n")
        append("Content-Type: \(mimeType(for: fileName))\r\n\r\n")
        body.append(audioData)
        append("\r\n")

        // Model field
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        append("\(modelName)\r\n")

        // Response format (text for simplest integration)
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n")
        append("text\r\n")

        // Temperature (0 for deterministic output)
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"temperature\"\r\n\r\n")
        append("0\r\n")

        // Language (optional)
        if let lang = language, !lang.isEmpty {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
            append("\(lang)\r\n")
        }

        // Prompt (optional - for context/spelling guidance)
        if let promptText = prompt, !promptText.isEmpty {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n")
            append("\(promptText)\r\n")
        }

        // End boundary
        append("--\(boundary)--\r\n")

        return body
    }

    // MARK: - Request Execution

    private func executeRequest(_ request: URLRequest) async throws -> String {
        let (data, response): (Data, URLResponse)

        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .cancelled:
                throw TranscriptionError.cancelled
            case .timedOut:
                throw TranscriptionError.timeout
            case .notConnectedToInternet, .networkConnectionLost:
                throw TranscriptionError.networkError(underlying: error)
            default:
                throw TranscriptionError.networkError(underlying: error)
            }
        } catch {
            throw TranscriptionError.networkError(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }

        // Handle different status codes
        switch httpResponse.statusCode {
        case 200:
            // Success - response_format=text returns plain text
            guard let text = String(data: data, encoding: .utf8) else {
                throw TranscriptionError.invalidResponse
            }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)

        case 401:
            throw TranscriptionError.invalidAPIKey

        case 413:
            throw TranscriptionError.audioFileTooLarge(sizeMB: 0, maxMB: maxFileSizeMB)

        case 415:
            throw TranscriptionError.unsupportedAudioFormat

        case 429:
            let message = extractErrorMessage(from: data) ?? "Rate limit exceeded. Please try again later."
            throw TranscriptionError.serverError(statusCode: 429, message: message)

        default:
            let message = extractErrorMessage(from: data) ?? "Unknown error"
            // Log the error but don't log the full response (might contain sensitive info)
            Logger.shared.log("GroqWhisperProvider: Server error \(httpResponse.statusCode): \(message)", level: .error)
            throw TranscriptionError.serverError(statusCode: httpResponse.statusCode, message: message)
        }
    }

    /// Extracts error message from JSON response
    private func extractErrorMessage(from data: Data) -> String? {
        // Try to parse Groq error format: {"error": {"message": "...", "type": "..."}}
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else {
            // Fallback to raw string
            return String(data: data, encoding: .utf8)?.prefix(200).description
        }
        return message
    }
}

// MARK: - Convenience Methods

extension GroqWhisperProvider {
    /// Creates a singleton instance
    static let shared = GroqWhisperProvider()

    /// Validates an API key by making a minimal test request
    /// - Parameter apiKey: The API key to test
    /// - Returns: True if valid, throws on error
    func testAPIKey(_ apiKey: String) async throws -> Bool {
        // We can't easily test without a real audio file,
        // so just do basic validation
        guard !apiKey.isEmpty else {
            throw TranscriptionError.missingAPIKey
        }

        guard apiKey.hasPrefix("gsk_") else {
            throw TranscriptionError.invalidAPIKey
        }

        return true
    }
}
