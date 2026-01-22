// TranscriptionProvider.swift
// Mute

import Foundation

/// Protocol defining the interface for transcription providers
protocol TranscriptionProvider {
    /// Transcribes audio from a file URL
    /// - Parameters:
    ///   - audioFileURL: URL to the audio file (WAV, M4A, MP3, etc.)
    ///   - language: Optional language code (e.g., "en", "de", "es"). If nil, auto-detect.
    ///   - prompt: Optional context/spelling guidance (up to ~224 tokens)
    /// - Returns: Transcribed text
    func transcribe(audioFileURL: URL, language: String?, prompt: String?) async throws -> String

    /// Provider display name for UI
    var displayName: String { get }

    /// Whether this provider requires an API key
    var requiresAPIKey: Bool { get }

    /// Validates the provider configuration (e.g., API key is set)
    func validateConfiguration() -> TranscriptionProviderValidation
}

/// Result of provider configuration validation
enum TranscriptionProviderValidation {
    case valid
    case invalid(reason: String)

    var isValid: Bool {
        if case .valid = self { return true }
        return false
    }

    var errorMessage: String? {
        if case .invalid(let reason) = self { return reason }
        return nil
    }
}

/// Errors that can occur during transcription
enum TranscriptionError: Error, LocalizedError {
    case missingAPIKey
    case invalidAPIKey
    case networkError(underlying: Error)
    case serverError(statusCode: Int, message: String)
    case invalidResponse
    case audioFileTooLarge(sizeMB: Double, maxMB: Double)
    case unsupportedAudioFormat
    case timeout
    case cancelled
    case unknown(message: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "API key is not configured. Please add your Groq API key in Settings."
        case .invalidAPIKey:
            return "Invalid API key. Please check your Groq API key in Settings."
        case .networkError(let underlying):
            return "Network error: \(underlying.localizedDescription)"
        case .serverError(let statusCode, let message):
            return "Server error (\(statusCode)): \(message)"
        case .invalidResponse:
            return "Invalid response from server"
        case .audioFileTooLarge(let sizeMB, let maxMB):
            return String(format: "Audio file too large (%.1f MB). Maximum allowed: %.0f MB", sizeMB, maxMB)
        case .unsupportedAudioFormat:
            return "Unsupported audio format"
        case .timeout:
            return "Request timed out. Please try again."
        case .cancelled:
            return "Transcription was cancelled"
        case .unknown(let message):
            return message
        }
    }
}

/// Available transcription backends
enum TranscriptionBackend: String, CaseIterable, Identifiable {
    case local = "local"
    case groqWhisper = "groq"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .local:
            return "Local (On-Device)"
        case .groqWhisper:
            return "Cloud: Groq - Whisper V3 Turbo"
        }
    }

    var description: String {
        switch self {
        case .local:
            return "Process audio locally using NVIDIA Parakeet or Whisper models. Private and offline."
        case .groqWhisper:
            return "Fast cloud transcription using Groq's Whisper Large V3 Turbo. Requires internet and API key."
        }
    }

    var requiresInternet: Bool {
        switch self {
        case .local:
            return false
        case .groqWhisper:
            return true
        }
    }
}
