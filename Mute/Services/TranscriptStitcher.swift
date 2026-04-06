// TranscriptStitcher.swift
// Mute

import Foundation

/// A word with session-relative timestamps
struct TimestampedWord {
    let word: String
    let sessionStart: TimeInterval
    let sessionEnd: TimeInterval
}

/// Stitches overlapping transcription chunks into a seamless transcript with timestamps.
///
/// Uses a simple time-based cutoff: overlap audio gives Whisper context for accuracy,
/// but only words after the last confirmed time are kept. No fragile word alignment needed.
final class TranscriptStitcher {

    // MARK: - State

    private(set) var confirmedWords: [TimestampedWord] = []
    private(set) var lastConfirmedSessionTime: TimeInterval = 0
    private var pauseMarkers: [TimeInterval] = []
    private var gapMarkers: [TimeInterval] = []

    /// Number of confirmed words at last Notes append
    var lastAppendedWordCount: Int = 0

    // MARK: - Configuration

    /// Minimum time gap between words to start a new paragraph
    var paragraphGapSeconds: TimeInterval = 15

    // MARK: - Public API

    func reset() {
        confirmedWords.removeAll()
        lastConfirmedSessionTime = 0
        pauseMarkers.removeAll()
        gapMarkers.removeAll()
        lastAppendedWordCount = 0
    }

    /// Marks a pause (silence) at a given session time
    func markPause(atSessionTime time: TimeInterval) {
        pauseMarkers.append(time)
    }

    /// Marks a transcription gap (failed chunk) at a given session time
    func markGap(atSessionTime time: TimeInterval) {
        gapMarkers.append(time)
    }

    /// Integrates words from a new chunk into the confirmed transcript.
    ///
    /// The overlap portion of each chunk gives Whisper acoustic context for better accuracy
    /// at boundaries. We simply discard words that fall within the already-confirmed time range
    /// and keep only genuinely new words.
    ///
    /// - Parameters:
    ///   - chunkWords: Words from Groq verbose_json response (timestamps relative to chunk start)
    ///   - chunkOffsetInSession: Time offset (seconds) of the chunk's first sample relative to session start
    func integrate(chunkWords: [GroqWord], chunkOffsetInSession: TimeInterval) {
        guard !chunkWords.isEmpty else { return }

        // Convert Whisper's chunk-relative timestamps to session-relative
        let sessionWords = chunkWords.map { word in
            TimestampedWord(
                word: word.word,
                sessionStart: word.start + chunkOffsetInSession,
                sessionEnd: word.end + chunkOffsetInSession
            )
        }

        // First chunk — accept all words
        if confirmedWords.isEmpty {
            confirmedWords = sessionWords
            lastConfirmedSessionTime = sessionWords.last?.sessionEnd ?? 0
            return
        }

        // Time-based cutoff: keep only words that start after the last confirmed time.
        // Small tolerance (0.15s) catches words that straddle the chunk boundary —
        // a word starting 0.1s before the cutoff was likely clipped in the previous chunk.
        let cutoff = lastConfirmedSessionTime - 0.15
        let newWords = sessionWords.filter { $0.sessionStart >= cutoff }

        if !newWords.isEmpty {
            confirmedWords.append(contentsOf: newWords)
            lastConfirmedSessionTime = confirmedWords.last!.sessionEnd
        }
    }

    /// Returns the full formatted transcript with timestamps
    func formattedTranscript() -> String {
        return formatWords(confirmedWords, fromIndex: 0)
    }

    /// Returns only the new (un-appended) portion of the transcript
    func newTranscriptSinceLastAppend() -> String? {
        guard confirmedWords.count > lastAppendedWordCount else { return nil }

        let newWords = Array(confirmedWords[lastAppendedWordCount...])
        guard !newWords.isEmpty else { return nil }

        let text = formatWords(newWords, fromIndex: lastAppendedWordCount)
        lastAppendedWordCount = confirmedWords.count
        return text
    }

    // MARK: - Formatting

    private func formatWords(_ words: [TimestampedWord], fromIndex: Int) -> String {
        guard !words.isEmpty else { return "" }

        var result = ""
        var currentParagraphWords: [String] = []
        var paragraphStartTime: TimeInterval = words.first!.sessionStart
        var lastWordEnd: TimeInterval = words.first!.sessionStart

        for (i, word) in words.enumerated() {
            let gap = word.sessionStart - lastWordEnd

            // Check for pause/gap markers between the last word and this one
            let hasPause = pauseMarkers.contains { $0 > lastWordEnd && $0 <= word.sessionStart }
            let hasGap = gapMarkers.contains { $0 > lastWordEnd && $0 <= word.sessionStart }

            let shouldBreak = gap > paragraphGapSeconds || hasPause || hasGap

            if shouldBreak && !currentParagraphWords.isEmpty {
                // Flush current paragraph
                let timestamp = formatTimestamp(paragraphStartTime)
                let text = currentParagraphWords.joined(separator: " ").trimmingCharacters(in: .whitespaces)
                result += "\(timestamp) \(text)\n"

                if hasPause {
                    result += "\n[pause]\n\n"
                } else if hasGap {
                    result += "\n[transcription gap]\n\n"
                } else {
                    result += "\n"
                }

                currentParagraphWords = []
                paragraphStartTime = word.sessionStart
            }

            if currentParagraphWords.isEmpty && i == 0 && fromIndex > 0 {
                paragraphStartTime = word.sessionStart
            }

            currentParagraphWords.append(word.word)
            lastWordEnd = word.sessionEnd
        }

        // Flush remaining paragraph
        if !currentParagraphWords.isEmpty {
            let timestamp = formatTimestamp(paragraphStartTime)
            let text = currentParagraphWords.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            result += "\(timestamp) \(text)\n"
        }

        return result
    }

    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "[%d:%02d:%02d]", hours, minutes, secs)
        } else {
            return String(format: "[%02d:%02d]", minutes, secs)
        }
    }
}
