// GroqVerboseResponse.swift
// Mute

import Foundation

/// Response from Groq Whisper API with `response_format=verbose_json`
struct GroqVerboseTranscription: Codable {
    let text: String
    let language: String?
    let duration: Double?
    let words: [GroqWord]?
}

/// A single word with timestamps from Groq Whisper verbose output
struct GroqWord: Codable {
    let word: String
    let start: Double
    let end: Double
}
