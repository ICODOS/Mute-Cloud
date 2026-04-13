// TranscriptionHistoryManager.swift
// Mute

import Foundation

final class TranscriptionHistoryManager: ObservableObject {
    static let shared = TranscriptionHistoryManager()

    private let maxItems = 10
    private let storageKey = "transcriptionHistory"

    @Published var items: [TranscriptionHistoryItem] = []

    private init() {
        loadItems()
    }

    func addEntry(rawText: String, transformedText: String? = nil, modeName: String? = nil) {
        let item = TranscriptionHistoryItem(
            rawText: rawText,
            transformedText: transformedText,
            modeName: modeName
        )
        items.insert(item, at: 0)
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
        saveItems()
    }

    func clearHistory() {
        items.removeAll()
        saveItems()
    }

    private func loadItems() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        if let decoded = try? JSONDecoder().decode([TranscriptionHistoryItem].self, from: data) {
            items = decoded
        }
    }

    private func saveItems() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
