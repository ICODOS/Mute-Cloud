// TranscriptionHistoryItem.swift
// Mute

import Foundation

struct TranscriptionHistoryItem: Codable, Identifiable {
    let id: UUID
    let date: Date
    let rawText: String
    let transformedText: String?
    let modeName: String?

    init(rawText: String, transformedText: String? = nil, modeName: String? = nil) {
        self.id = UUID()
        self.date = Date()
        self.rawText = rawText
        self.transformedText = transformedText
        self.modeName = modeName
    }
}
