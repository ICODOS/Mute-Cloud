// ContinuousTranscriptionSession.swift
// Mute

import Foundation
import Combine

/// Orchestrates continuous chunked transcription using Groq Whisper API.
///
/// Audio is buffered and sent to Groq every ~15 seconds with 3 seconds of overlap.
/// The overlap gives Whisper acoustic context at chunk boundaries for better accuracy.
/// The stitcher uses a simple time-based cutoff to avoid duplication.
@MainActor
final class ContinuousTranscriptionSession: ObservableObject {

    // MARK: - Published State

    @Published private(set) var runningTranscript: String = ""
    @Published private(set) var isActive: Bool = false

    // MARK: - Configuration

    let chunkIntervalSeconds: Double = 15
    let overlapSeconds: Double = 3
    var silenceThresholdRMS: Float = 0.005  // ~-46 dB
    let silenceWindowSeconds: Double = 5
    private let sampleRate: Double = 16000

    // MARK: - Internal State

    private var audioSampleBuffer: [Float] = []
    private let bufferLock = NSLock()
    /// The sample index up to which audio has been sent to Groq (non-overlap boundary)
    private var lastSentSampleIndex: Int = 0
    private var lastSpeechSampleIndex: Int = 0
    private var isSilent: Bool = false
    private var sessionStartTime: Date = Date()
    private var chunkTimer: Timer?
    private var pendingChunkTasks: [Task<Void, Never>] = []
    private var chunkIndex: Int = 0
    private var consecutiveFailures: Int = 0
    private var currentChunkInterval: Double = 15
    private var lastPromptContext: String = ""

    let stitcher = TranscriptStitcher()
    private let groqProvider = GroqWhisperProvider.shared

    // MARK: - Callbacks

    /// Called when new transcript text is available to append to Notes
    var onNewTranscript: ((String) -> Void)?

    // MARK: - Cloud Settings (captured at start)

    private var language: String?
    private var prompt: String?

    // MARK: - Lifecycle

    func start(language: String?, prompt: String?) {
        guard !isActive else { return }

        // Reset state
        audioSampleBuffer.removeAll()
        audioSampleBuffer.reserveCapacity(Int(sampleRate * 60 * 10))  // Pre-allocate ~10 min
        lastSentSampleIndex = 0
        lastSpeechSampleIndex = 0
        isSilent = false
        sessionStartTime = Date()
        chunkIndex = 0
        consecutiveFailures = 0
        currentChunkInterval = chunkIntervalSeconds
        lastPromptContext = ""
        stitcher.reset()
        runningTranscript = ""

        self.language = language
        self.prompt = prompt

        isActive = true

        // Fire first tick sooner (10s) so user sees output quickly,
        // then switch to regular interval
        chunkTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isActive else { return }
                self.tick()

                // Now start the repeating timer at the normal interval
                self.chunkTimer?.invalidate()
                self.chunkTimer = Timer.scheduledTimer(withTimeInterval: self.currentChunkInterval, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.tick()
                    }
                }
            }
        }

        Logger.shared.log("ContinuousTranscriptionSession: Started (chunk interval: \(currentChunkInterval)s, overlap: \(overlapSeconds)s)")
    }

    /// Receives raw PCM Float32 audio data from AudioCaptureManager
    func receiveAudio(_ data: Data) {
        let floatCount = data.count / MemoryLayout<Float>.size
        guard floatCount > 0 else { return }

        var floats = [Float](repeating: 0, count: floatCount)
        _ = floats.withUnsafeMutableBytes { data.copyBytes(to: $0) }

        // Calculate RMS for silence detection
        let sumOfSquares = floats.reduce(Float(0)) { $0 + $1 * $1 }
        let rms = sqrt(sumOfSquares / Float(floatCount))

        bufferLock.lock()
        audioSampleBuffer.append(contentsOf: floats)
        let currentBufferCount = audioSampleBuffer.count

        if rms > silenceThresholdRMS {
            lastSpeechSampleIndex = currentBufferCount
            if isSilent {
                isSilent = false
                Logger.shared.log("ContinuousTranscriptionSession: Speech resumed")
            }
        }
        bufferLock.unlock()
    }

    /// Stops the session and returns the final formatted transcript
    func stop() async -> String {
        guard isActive else { return runningTranscript }

        isActive = false
        chunkTimer?.invalidate()
        chunkTimer = nil

        // Send final chunk with whatever remains
        await sendFinalChunk()

        // Wait for all pending chunk tasks
        for task in pendingChunkTasks {
            _ = await task.result
        }
        pendingChunkTasks.removeAll()

        runningTranscript = stitcher.formattedTranscript()

        Logger.shared.log("ContinuousTranscriptionSession: Stopped. Total words: \(stitcher.confirmedWords.count)")
        return runningTranscript
    }

    /// Cancels the session without waiting for pending chunks
    func cancel() {
        isActive = false
        chunkTimer?.invalidate()
        chunkTimer = nil

        for task in pendingChunkTasks {
            task.cancel()
        }
        pendingChunkTasks.removeAll()

        Logger.shared.log("ContinuousTranscriptionSession: Cancelled")
    }

    // MARK: - Chunk Timer

    private func tick() {
        guard isActive else { return }

        bufferLock.lock()
        let bufferCount = audioSampleBuffer.count
        let speechIndex = lastSpeechSampleIndex
        bufferLock.unlock()

        let availableSamples = bufferCount - lastSentSampleIndex

        // Need at least 2 seconds of new audio to bother sending
        let minSamples = Int(sampleRate * 2)
        guard availableSamples >= minSamples else { return }

        // Check for sustained silence
        let silenceDurationSamples = bufferCount - speechIndex
        let silenceDurationSeconds = Double(silenceDurationSamples) / sampleRate

        if silenceDurationSeconds >= silenceWindowSeconds {
            if !isSilent {
                isSilent = true
                let sessionTime = Double(speechIndex) / sampleRate
                stitcher.markPause(atSessionTime: sessionTime)
                Logger.shared.log("ContinuousTranscriptionSession: Silence detected (\(String(format: "%.1f", silenceDurationSeconds))s), skipping chunk")
            }
            // DON'T advance lastSentSampleIndex here — when speech resumes,
            // we want the next chunk's overlap to reach back for context.
            // But do advance to speechIndex so we don't send pure silence.
            lastSentSampleIndex = max(lastSentSampleIndex, speechIndex)
            return
        }

        // Determine chunk range: overlap + all new audio
        let overlapSamples = Int(sampleRate * overlapSeconds)
        let chunkStart: Int
        if chunkIndex == 0 {
            chunkStart = 0  // No overlap for first chunk
        } else {
            chunkStart = max(0, lastSentSampleIndex - overlapSamples)
        }
        // Send ALL available audio, not just one chunk's worth
        let chunkEnd = bufferCount
        let chunkOffsetInSession = Double(chunkStart) / sampleRate

        // Advance the sent marker to the end of this chunk
        lastSentSampleIndex = chunkEnd

        let currentChunkIndex = chunkIndex
        chunkIndex += 1

        // Extract samples
        bufferLock.lock()
        let safeEnd = min(chunkEnd, audioSampleBuffer.count)
        let samples = Array(audioSampleBuffer[chunkStart..<safeEnd])
        bufferLock.unlock()

        // Dispatch async transcription
        let task = Task { [weak self] in
            guard let self = self else { return }
            await self.processChunk(
                samples: samples,
                chunkIndex: currentChunkIndex,
                chunkOffsetInSession: chunkOffsetInSession
            )
        }
        pendingChunkTasks.append(task)

        // Clean up completed tasks
        pendingChunkTasks.removeAll { $0.isCancelled }
    }

    private func sendFinalChunk() async {
        bufferLock.lock()
        let bufferCount = audioSampleBuffer.count
        bufferLock.unlock()

        let remainingSamples = bufferCount - lastSentSampleIndex

        // Only send if we have meaningful audio (at least 0.5 seconds)
        guard remainingSamples > Int(sampleRate * 0.5) else { return }

        let overlapSamples = Int(sampleRate * overlapSeconds)
        let chunkStart: Int
        if chunkIndex == 0 {
            chunkStart = 0
        } else {
            chunkStart = max(0, lastSentSampleIndex - overlapSamples)
        }
        let chunkEnd = bufferCount
        let chunkOffsetInSession = Double(chunkStart) / sampleRate

        bufferLock.lock()
        let samples = Array(audioSampleBuffer[chunkStart..<chunkEnd])
        bufferLock.unlock()

        let currentChunkIndex = chunkIndex
        chunkIndex += 1

        await processChunk(
            samples: samples,
            chunkIndex: currentChunkIndex,
            chunkOffsetInSession: chunkOffsetInSession
        )
    }

    // MARK: - Chunk Processing

    private func processChunk(samples: [Float], chunkIndex: Int, chunkOffsetInSession: TimeInterval) async {
        guard !samples.isEmpty else { return }

        let durationSeconds = Double(samples.count) / sampleRate
        Logger.shared.log("ContinuousTranscriptionSession: Processing chunk \(chunkIndex) (\(String(format: "%.1f", durationSeconds))s, offset \(String(format: "%.1f", chunkOffsetInSession))s)")

        // Write samples to WAV file
        guard let fileURL = writeWAVFile(samples: samples) else {
            Logger.shared.log("ContinuousTranscriptionSession: Failed to write WAV for chunk \(chunkIndex)", level: .error)
            let sessionTime = chunkOffsetInSession + durationSeconds
            stitcher.markGap(atSessionTime: sessionTime)
            return
        }

        defer { AudioFileManager.deleteTemporaryFile(fileURL) }

        do {
            // Use last prompt context for better continuity across chunks
            let chunkPrompt = lastPromptContext.isEmpty ? prompt : lastPromptContext

            let result = try await groqProvider.transcribeVerbose(
                audioFileURL: fileURL,
                language: language,
                prompt: chunkPrompt
            )

            guard !Task.isCancelled else { return }

            // Integrate words into stitcher
            if let words = result.words, !words.isEmpty {
                stitcher.integrate(chunkWords: words, chunkOffsetInSession: chunkOffsetInSession)

                // Update prompt context with last ~50 words for next chunk
                let recentWords = stitcher.confirmedWords.suffix(50)
                lastPromptContext = recentWords.map { $0.word }.joined(separator: " ")

                Logger.shared.log("ContinuousTranscriptionSession: Chunk \(chunkIndex) → \(words.count) words from Whisper, \(stitcher.confirmedWords.count) total confirmed")
            } else if !result.text.isEmpty {
                // Fallback: no word timestamps — create a single synthetic word
                let syntheticWord = GroqWord(
                    word: result.text,
                    start: 0,
                    end: result.duration ?? durationSeconds
                )
                stitcher.integrate(chunkWords: [syntheticWord], chunkOffsetInSession: chunkOffsetInSession)
                Logger.shared.log("ContinuousTranscriptionSession: Chunk \(chunkIndex) → no word timestamps, used text fallback")
            }

            // Update running transcript and notify
            runningTranscript = stitcher.formattedTranscript()

            if let newText = stitcher.newTranscriptSinceLastAppend() {
                onNewTranscript?(newText)
            }

            consecutiveFailures = 0

            // Restore chunk interval if it was increased due to rate limiting
            if currentChunkInterval > chunkIntervalSeconds {
                currentChunkInterval = chunkIntervalSeconds
                restartTimer()
            }

        } catch let error as TranscriptionError {
            Logger.shared.log("ContinuousTranscriptionSession: Chunk \(chunkIndex) failed: \(error.localizedDescription)", level: .error)

            consecutiveFailures += 1

            let sessionTime = chunkOffsetInSession + durationSeconds
            stitcher.markGap(atSessionTime: sessionTime)

            // Handle rate limiting — back off
            if case .serverError(let statusCode, _) = error, statusCode == 429 {
                currentChunkInterval = min(currentChunkInterval * 2, 60)
                restartTimer()
                Logger.shared.log("ContinuousTranscriptionSession: Rate limited, increasing interval to \(currentChunkInterval)s", level: .warning)
            }

            if consecutiveFailures >= 3 {
                Logger.shared.log("ContinuousTranscriptionSession: 3 consecutive failures — transcription may be degraded", level: .warning)
            }

        } catch {
            Logger.shared.log("ContinuousTranscriptionSession: Chunk \(chunkIndex) error: \(error)", level: .error)
            consecutiveFailures += 1

            let sessionTime = chunkOffsetInSession + durationSeconds
            stitcher.markGap(atSessionTime: sessionTime)
        }
    }

    // MARK: - Helpers

    private func restartTimer() {
        chunkTimer?.invalidate()
        guard isActive else { return }

        chunkTimer = Timer.scheduledTimer(withTimeInterval: currentChunkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    /// Writes Float32 samples to a temporary WAV file
    private nonisolated func writeWAVFile(samples: [Float]) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "mute_chunk_\(UUID().uuidString).wav"
        let fileURL = tempDir.appendingPathComponent(fileName)

        // Convert Float32 to Int16 PCM
        let int16Samples = samples.map { sample -> Int16 in
            let clamped = max(-1.0, min(1.0, sample))
            return Int16(clamped * Float(Int16.max))
        }

        var wavData = Data()
        let sampleRate = UInt32(self.sampleRate)

        // RIFF header
        wavData.append("RIFF".data(using: .ascii)!)
        let dataSize = UInt32(int16Samples.count * 2)
        let fileSize = UInt32(36 + dataSize)
        wavData.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        wavData.append("WAVE".data(using: .ascii)!)

        // fmt subchunk
        wavData.append("fmt ".data(using: .ascii)!)
        let fmtChunkSize: UInt32 = 16
        wavData.append(contentsOf: withUnsafeBytes(of: fmtChunkSize.littleEndian) { Array($0) })
        let audioFormat: UInt16 = 1  // PCM
        wavData.append(contentsOf: withUnsafeBytes(of: audioFormat.littleEndian) { Array($0) })
        let numChannels: UInt16 = 1
        wavData.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Array($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Array($0) })
        let byteRate: UInt32 = sampleRate * 2
        wavData.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        let blockAlign: UInt16 = 2
        wavData.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        let bitsPerSample: UInt16 = 16
        wavData.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })

        // data subchunk
        wavData.append("data".data(using: .ascii)!)
        wavData.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })

        for sample in int16Samples {
            wavData.append(contentsOf: withUnsafeBytes(of: sample.littleEndian) { Array($0) })
        }

        do {
            try wavData.write(to: fileURL)
            return fileURL
        } catch {
            return nil
        }
    }
}
