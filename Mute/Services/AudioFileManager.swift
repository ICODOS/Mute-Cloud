// AudioFileManager.swift
// Mute

import Foundation
import AVFoundation

/// Manages audio file creation and storage for cloud transcription
final class AudioFileManager {
    private var audioBuffer: [Float] = []
    private let sampleRate: Double = 16000  // 16kHz mono, matching AudioCaptureManager
    private let lock = NSLock()

    /// Appends audio data (Float32 PCM) to the internal buffer
    /// - Parameter data: Raw Float32 PCM audio data
    func appendAudioData(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }

        // Convert Data to [Float]
        let floatCount = data.count / MemoryLayout<Float>.size
        var floats = [Float](repeating: 0, count: floatCount)
        _ = floats.withUnsafeMutableBytes { data.copyBytes(to: $0) }

        audioBuffer.append(contentsOf: floats)
    }

    /// Resets the audio buffer
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        audioBuffer.removeAll()
    }

    /// Returns the current duration of recorded audio in seconds
    var duration: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return Double(audioBuffer.count) / sampleRate
    }

    /// Returns the approximate file size in bytes
    var estimatedFileSize: Int {
        lock.lock()
        defer { lock.unlock() }
        // WAV header (44 bytes) + audio data (16-bit = 2 bytes per sample)
        return 44 + (audioBuffer.count * 2)
    }

    /// Writes the buffered audio to a WAV file
    /// - Returns: URL to the created WAV file, or nil if buffer is empty
    func writeToWAVFile() throws -> URL? {
        lock.lock()
        let samples = audioBuffer
        lock.unlock()

        guard !samples.isEmpty else {
            Logger.shared.log("AudioFileManager: No audio data to write", level: .warning)
            return nil
        }

        // Create temp file
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "mute_recording_\(UUID().uuidString).wav"
        let fileURL = tempDir.appendingPathComponent(fileName)

        // Convert Float32 to Int16 PCM
        let int16Samples = samples.map { sample -> Int16 in
            let clamped = max(-1.0, min(1.0, sample))
            return Int16(clamped * Float(Int16.max))
        }

        // Build WAV file
        var wavData = Data()

        // RIFF header
        wavData.append("RIFF".data(using: .ascii)!)

        // File size (will be filled later)
        let dataSize = UInt32(int16Samples.count * 2)
        let fileSize = UInt32(36 + dataSize)
        wavData.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })

        // WAVE format
        wavData.append("WAVE".data(using: .ascii)!)

        // fmt subchunk
        wavData.append("fmt ".data(using: .ascii)!)
        let fmtChunkSize: UInt32 = 16
        wavData.append(contentsOf: withUnsafeBytes(of: fmtChunkSize.littleEndian) { Array($0) })

        let audioFormat: UInt16 = 1  // PCM
        wavData.append(contentsOf: withUnsafeBytes(of: audioFormat.littleEndian) { Array($0) })

        let numChannels: UInt16 = 1  // Mono
        wavData.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Array($0) })

        let sampleRateUInt: UInt32 = UInt32(sampleRate)
        wavData.append(contentsOf: withUnsafeBytes(of: sampleRateUInt.littleEndian) { Array($0) })

        let byteRate: UInt32 = sampleRateUInt * UInt32(numChannels) * 2  // 2 bytes per sample
        wavData.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })

        let blockAlign: UInt16 = numChannels * 2
        wavData.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })

        let bitsPerSample: UInt16 = 16
        wavData.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })

        // data subchunk
        wavData.append("data".data(using: .ascii)!)
        wavData.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })

        // Audio data
        for sample in int16Samples {
            wavData.append(contentsOf: withUnsafeBytes(of: sample.littleEndian) { Array($0) })
        }

        // Write to file
        try wavData.write(to: fileURL)

        let fileSizeMB = Double(wavData.count) / (1024 * 1024)
        Logger.shared.log("AudioFileManager: Created WAV file at \(fileURL.lastPathComponent) (%.2f MB, %.1f seconds)", level: .info)
        Logger.shared.log(String(format: "AudioFileManager: WAV file size: %.2f MB, duration: %.1f seconds", fileSizeMB, duration))

        return fileURL
    }

    /// Deletes a temporary audio file
    /// - Parameter url: URL of the file to delete
    static func deleteTemporaryFile(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
            Logger.shared.log("AudioFileManager: Deleted temp file \(url.lastPathComponent)")
        } catch {
            Logger.shared.log("AudioFileManager: Failed to delete temp file: \(error)", level: .warning)
        }
    }
}

// MARK: - File Size Utilities

extension AudioFileManager {
    /// Maximum file size for Groq free tier (25 MB)
    static let groqFreeTierMaxSizeMB: Double = 25.0

    /// Maximum file size for Groq developer tier (100 MB)
    static let groqDevTierMaxSizeMB: Double = 100.0

    /// Checks if the current buffer would exceed the given file size limit
    /// - Parameter maxSizeMB: Maximum size in megabytes
    /// - Returns: True if within limit, false if exceeds
    func isWithinSizeLimit(maxSizeMB: Double) -> Bool {
        let currentSizeMB = Double(estimatedFileSize) / (1024 * 1024)
        return currentSizeMB <= maxSizeMB
    }
}
