// AudioFileTranscriber.swift
// Mute

import Foundation
import AVFoundation

/// Service for transcribing imported audio files using Groq Whisper
/// Supports various audio formats and optionally applies transformation modes
final class AudioFileTranscriber {
    // MARK: - Supported Formats

    /// Supported audio file extensions
    static let supportedExtensions: Set<String> = [
        "wav", "mp3", "m4a", "aac", "flac", "aiff", "ogg", "webm"
    ]

    /// Human-readable format string for UI
    static let supportedFormatsDescription = "WAV, MP3, M4A, AAC, FLAC, AIFF, OGG, WebM"

    /// Formats that Groq Whisper API accepts directly (no conversion needed)
    /// Source: https://console.groq.com/docs/speech-to-text
    static let groqSupportedExtensions: Set<String> = [
        "flac", "mp3", "mp4", "mpeg", "mpga", "m4a", "ogg", "wav", "webm"
    ]

    // MARK: - Properties

    private let groqWhisperProvider = GroqWhisperProvider.shared
    private let groqChatProvider = GroqChatProvider.shared

    /// Maximum file size in MB - Groq Developer tier limit
    private let maxFileSizeMB: Double = 40.0

    // MARK: - Singleton

    static let shared = AudioFileTranscriber()

    private init() {}

    // MARK: - Public API

    /// Transcribes an audio file and optionally transforms the result
    /// - Parameters:
    ///   - fileURL: URL to the audio file
    ///   - mode: Optional transcription mode for text transformation
    ///   - language: Optional language hint for transcription
    ///   - prompt: Optional context prompt for transcription
    ///   - progressHandler: Callback for progress updates
    /// - Returns: The transcribed (and optionally transformed) text
    func transcribe(
        fileURL: URL,
        mode: TranscriptionMode? = nil,
        language: String? = nil,
        prompt: String? = nil,
        progressHandler: ((String) -> Void)? = nil
    ) async throws -> String {
        // Validate file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw AudioFileTranscriberError.fileNotFound
        }

        // Validate file extension
        let ext = fileURL.pathExtension.lowercased()
        guard Self.supportedExtensions.contains(ext) else {
            throw AudioFileTranscriberError.unsupportedFormat(ext)
        }

        // Validate file size
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fileSize = fileAttributes[.size] as? Int64 ?? 0
        let fileSizeMB = Double(fileSize) / (1024 * 1024)

        if fileSizeMB > maxFileSizeMB {
            throw TranscriptionError.audioFileTooLarge(sizeMB: fileSizeMB, maxMB: maxFileSizeMB)
        }

        Logger.shared.log(String(format: "AudioFileTranscriber: Processing file %.2f MB", fileSizeMB))

        // Convert to WAV if needed
        progressHandler?("Preparing audio...")
        let wavURL = try await prepareAudioFile(fileURL)
        let shouldDeleteWav = wavURL != fileURL  // Only delete if we created a temp file

        defer {
            if shouldDeleteWav {
                AudioFileManager.deleteTemporaryFile(wavURL)
            }
        }

        // Transcribe with Groq Whisper
        progressHandler?("Transcribing...")
        let transcription = try await groqWhisperProvider.transcribe(
            audioFileURL: wavURL,
            language: language,
            prompt: prompt
        )

        Logger.shared.log("AudioFileTranscriber: Transcription complete (\(transcription.count) chars)")

        // Apply transformation if mode is set and has a transformation
        if let mode = mode, mode.hasTransformation {
            progressHandler?("Transforming...")
            let transformed = try await groqChatProvider.transform(
                text: transcription,
                prompt: mode.prompt,
                model: mode.modelId,
                temperature: mode.temperature,
                maxTokens: mode.maxTokens
            )
            Logger.shared.log("AudioFileTranscriber: Transformation complete (\(transformed.count) chars)")
            return transformed
        }

        return transcription
    }

    /// Transcribes an audio file and saves the result to Notes
    /// - Parameters:
    ///   - fileURL: URL to the audio file
    ///   - mode: Optional transcription mode for text transformation
    ///   - language: Optional language hint
    ///   - prompt: Optional context prompt
    ///   - progressHandler: Callback for progress updates
    func transcribeToNotes(
        fileURL: URL,
        mode: TranscriptionMode? = nil,
        language: String? = nil,
        prompt: String? = nil,
        progressHandler: ((String) -> Void)? = nil
    ) async throws {
        let notesService = NotesIntegrationService()

        // Verify Notes is available
        guard notesService.isNotesAvailable() else {
            throw NotesError.notesAppNotAvailable
        }

        // Transcribe the file
        let text = try await transcribe(
            fileURL: fileURL,
            mode: mode,
            language: language,
            prompt: prompt,
            progressHandler: progressHandler
        )

        // Create a new note with transcription-specific formatting
        progressHandler?("Saving to Notes...")
        let fileName = fileURL.lastPathComponent
        let title = "Transcription - \(fileURL.deletingPathExtension().lastPathComponent)"
        let noteId = try await notesService.createTranscriptionNote(title: title, fileName: fileName)

        // Append the transcription (if transformed by LLM, treat as HTML)
        let isHTML = mode?.hasTransformation ?? false
        try await notesService.appendToNote(noteId: noteId, text: text, isHTML: isHTML)
        try await notesService.finalizeTranscriptionNote(noteId: noteId)

        Logger.shared.log("AudioFileTranscriber: Saved transcription to Notes")
    }

    // MARK: - Audio Preparation

    /// Prepares an audio file for transcription, converting to WAV only if necessary
    /// - Parameter fileURL: The source audio file URL
    /// - Returns: URL to an audio file suitable for Groq Whisper
    private func prepareAudioFile(_ fileURL: URL) async throws -> URL {
        let ext = fileURL.pathExtension.lowercased()

        // If format is directly supported by Groq, use as-is (no conversion)
        if Self.groqSupportedExtensions.contains(ext) {
            Logger.shared.log("AudioFileTranscriber: Using original \(ext.uppercased()) file (no conversion needed)")
            return fileURL
        }

        // Convert unsupported formats to WAV
        Logger.shared.log("AudioFileTranscriber: Converting \(ext.uppercased()) to WAV")
        return try await convertToWAV(fileURL)
    }

    /// Converts an audio file to 16kHz mono WAV
    private func convertToWAV(_ sourceURL: URL) async throws -> URL {
        let asset = AVAsset(url: sourceURL)

        // Create output URL
        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent("mute_converted_\(UUID().uuidString).wav")

        // Create export session
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw AudioFileTranscriberError.conversionFailed("Could not create export session")
        }

        // Check if we need to use AVAssetReader/Writer for format conversion
        // For proper conversion, we'll use AVAssetReader and AVAssetWriter

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw AudioFileTranscriberError.conversionFailed("Could not read audio file: \(error.localizedDescription)")
        }

        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw AudioFileTranscriberError.conversionFailed("No audio track found")
        }

        // Configure reader output
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        reader.add(readerOutput)

        // Create writer
        let writer: AVAssetWriter
        do {
            // Remove existing file if present
            try? FileManager.default.removeItem(at: outputURL)
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .wav)
        } catch {
            throw AudioFileTranscriberError.conversionFailed("Could not create output file: \(error.localizedDescription)")
        }

        // Configure writer input
        let writerInputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: writerInputSettings)
        writer.add(writerInput)

        // Start reading and writing
        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        // Process in background
        return try await withCheckedThrowingContinuation { continuation in
            let queue = DispatchQueue(label: "com.mute.audioconversion")
            writerInput.requestMediaDataWhenReady(on: queue) {
                while writerInput.isReadyForMoreMediaData {
                    if let buffer = readerOutput.copyNextSampleBuffer() {
                        writerInput.append(buffer)
                    } else {
                        writerInput.markAsFinished()
                        writer.finishWriting {
                            if writer.status == .completed {
                                Logger.shared.log("AudioFileTranscriber: Converted audio to WAV")
                                continuation.resume(returning: outputURL)
                            } else if let error = writer.error {
                                continuation.resume(throwing: AudioFileTranscriberError.conversionFailed(error.localizedDescription))
                            } else {
                                continuation.resume(throwing: AudioFileTranscriberError.conversionFailed("Unknown error"))
                            }
                        }
                        return
                    }
                }
            }
        }
    }
}

// MARK: - Errors

enum AudioFileTranscriberError: LocalizedError {
    case fileNotFound
    case unsupportedFormat(String)
    case conversionFailed(String)
    case transformationFailed(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Audio file not found"
        case .unsupportedFormat(let ext):
            return "Unsupported audio format: .\(ext). Supported: \(AudioFileTranscriber.supportedFormatsDescription)"
        case .conversionFailed(let message):
            return "Failed to convert audio: \(message)"
        case .transformationFailed(let message):
            return "Failed to transform text: \(message)"
        }
    }
}
