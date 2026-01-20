// AudioCaptureManager.swift
// Mute

import AVFoundation
import Accelerate
import AudioToolbox
import Combine

// MARK: - Audio Device
struct AudioDevice: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let uid: String

    static func == (lhs: AudioDevice, rhs: AudioDevice) -> Bool {
        return lhs.uid == rhs.uid
    }
}

// MARK: - Audio Device Monitor
/// Monitors for audio device changes and publishes updates
class AudioDeviceMonitor: ObservableObject {
    static let shared = AudioDeviceMonitor()

    @Published private(set) var inputDevices: [AudioDevice] = []

    private var propertyListenerBlock: AudioObjectPropertyListenerBlock?
    private var pollingTimer: Timer?
    private var lastDeviceUIDs: Set<String> = []

    private init() {
        Logger.shared.log("AudioDeviceMonitor: Initializing...")
        refreshDevicesSync()
        setupDeviceChangeListener()
        startPolling()
        Logger.shared.log("AudioDeviceMonitor: Initialized with \(inputDevices.count) devices")
    }

    deinit {
        stopPolling()
        removeDeviceChangeListener()
    }

    /// Refresh the list of available input devices (async)
    func refreshDevices() {
        let devices = AudioCaptureManager.getAvailableInputDevices()
        let newUIDs = Set(devices.map { $0.uid })

        // Only log and update if devices actually changed
        if newUIDs != lastDeviceUIDs {
            Logger.shared.log("AudioDeviceMonitor: Device list changed, found \(devices.count) input devices")
            lastDeviceUIDs = newUIDs
            DispatchQueue.main.async {
                self.inputDevices = devices
            }
        }
    }

    /// Refresh devices synchronously (for init)
    private func refreshDevicesSync() {
        let devices = AudioCaptureManager.getAvailableInputDevices()
        lastDeviceUIDs = Set(devices.map { $0.uid })
        inputDevices = devices
        Logger.shared.log("AudioDeviceMonitor: Initial device scan found \(devices.count) input devices")
    }

    /// Check if a device with the given UID is currently available
    func isDeviceAvailable(uid: String) -> Bool {
        return inputDevices.contains { $0.uid == uid }
    }

    // MARK: - Polling (Fallback for unreliable CoreAudio notifications)

    private func startPolling() {
        // Poll every 2 seconds as a fallback
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshDevices()
        }
        Logger.shared.log("AudioDeviceMonitor: Started polling timer (2s interval)")
    }

    private func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    // MARK: - CoreAudio Listener Setup

    private func setupDeviceChangeListener() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        // Create the listener block
        propertyListenerBlock = { [weak self] (numberAddresses: UInt32, addresses: UnsafePointer<AudioObjectPropertyAddress>) in
            Logger.shared.log("AudioDeviceMonitor: CoreAudio device change notification received")
            // Device list changed - refresh on main thread
            DispatchQueue.main.async {
                self?.refreshDevices()
            }
        }

        // Add the property listener
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main,
            propertyListenerBlock!
        )

        if status == noErr {
            Logger.shared.log("AudioDeviceMonitor: Device change listener registered successfully")
        } else {
            Logger.shared.log("AudioDeviceMonitor: Failed to add device change listener: \(status)", level: .error)
        }
    }

    private func removeDeviceChangeListener() {
        guard let listenerBlock = propertyListenerBlock else { return }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main,
            listenerBlock
        )

        propertyListenerBlock = nil
    }
}

// MARK: - Audio Capture Manager
class AudioCaptureManager {
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var audioConverter: AVAudioConverter?
    
    private var chunkBuffer: [Float] = []
    private var chunkSizeInSamples: Int = 0
    private var onAudioChunk: ((Data) -> Void)?
    
    private let targetSampleRate: Double = 16000 // Parakeet expects 16kHz
    private let lock = NSLock()
    
    // For detecting audio flow issues
    private var audioFlowStarted = false
    private var configChangeObserver: NSObjectProtocol?
    private var currentDeviceUID: String?
    private var currentChunkSizeMs: Int = 400

    // Solution B: Smart configuration change handling
    private var lastConfigChangeRestartTime: Date?
    private var configChangeRestartCount: Int = 0
    private let maxConfigChangeRestarts: Int = 2
    private let configChangeDebounceMs: Double = 500
    
    var isCapturing: Bool {
        return audioEngine?.isRunning ?? false
    }
    
    var isAudioFlowing: Bool {
        return audioFlowStarted && (audioEngine?.isRunning ?? false)
    }
    
    init() {
        setupNotifications()
    }
    
    deinit {
        if let observer = configChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    private func setupNotifications() {
        // Listen for audio configuration changes (e.g., headset mode switches)
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleAudioConfigurationChange()
        }
    }
    
    private func handleAudioConfigurationChange() {
        Logger.shared.log("Audio configuration changed - headset mode switch detected", level: .warning)

        // If we were not capturing, ignore
        guard let engine = audioEngine, engine.isRunning, let onChunk = onAudioChunk else {
            Logger.shared.log("Config change ignored - not currently capturing")
            return
        }

        // Solution B: Smart configuration change handling

        // Check 1: Debounce - ignore if we recently restarted
        if let lastRestart = lastConfigChangeRestartTime {
            let timeSinceLastRestart = Date().timeIntervalSince(lastRestart) * 1000 // ms
            if timeSinceLastRestart < configChangeDebounceMs {
                Logger.shared.log("Config change ignored - debounce (\(Int(timeSinceLastRestart))ms since last restart)")
                return
            }
        }

        // Check 2: Max restarts per session
        if configChangeRestartCount >= maxConfigChangeRestarts {
            Logger.shared.log("Config change ignored - max restarts reached (\(configChangeRestartCount))")
            return
        }

        // Check 3: If audio is already flowing AND format is correct (16000Hz), skip restart
        if audioFlowStarted {
            let currentFormat = engine.inputNode.outputFormat(forBus: 0)
            let currentSampleRate = currentFormat.sampleRate

            // If we're already at the target sample rate (16000Hz) or close to it, skip restart
            if abs(currentSampleRate - targetSampleRate) < 100 {
                Logger.shared.log("Config change ignored - audio flowing at correct format (\(currentSampleRate)Hz)")
                return
            }

            Logger.shared.log("Config change: audio flowing but format changed to \(currentSampleRate)Hz, restarting...")
        }

        Logger.shared.log("Restarting audio capture after configuration change (restart #\(configChangeRestartCount + 1))...")

        // Store callback and restart
        let callback = onChunk
        let deviceUID = currentDeviceUID
        let chunkSize = currentChunkSizeMs

        // Update tracking
        configChangeRestartCount += 1
        lastConfigChangeRestartTime = Date()

        // Restart on a slight delay to let the audio system settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            do {
                try self?.startCaptureInternal(deviceUID: deviceUID, chunkSizeMs: chunkSize, onChunk: callback, isRestart: true)
                Logger.shared.log("Audio capture restarted successfully after configuration change")
            } catch {
                Logger.shared.log("Failed to restart audio capture: \(error)", level: .error)
            }
        }
    }
    
    // MARK: - Audio Device Discovery
    static func getAvailableInputDevices() -> [AudioDevice] {
        var devices: [AudioDevice] = []
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        
        guard status == noErr else { return devices }
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        
        guard status == noErr else { return devices }
        
        for deviceID in deviceIDs {
            // Check if device has input channels
            var inputChannels: UInt32 = 0
            var inputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            
            var inputSize: UInt32 = 0
            status = AudioObjectGetPropertyDataSize(deviceID, &inputAddress, 0, nil, &inputSize)
            
            if status == noErr && inputSize > 0 {
                let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(inputSize))
                defer { bufferList.deallocate() }
                
                status = AudioObjectGetPropertyData(deviceID, &inputAddress, 0, nil, &inputSize, bufferList)
                
                if status == noErr {
                    let audioBufferList = UnsafeMutableAudioBufferListPointer(bufferList)
                    for buffer in audioBufferList {
                        inputChannels += buffer.mNumberChannels
                    }
                }
            }
            
            guard inputChannels > 0 else { continue }
            
            // Get device name
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            
            var name: CFString = "" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            status = AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, &name)
            
            guard status == noErr else { continue }
            
            // Get device UID
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            
            var uid: CFString = "" as CFString
            var uidSize = UInt32(MemoryLayout<CFString>.size)
            status = AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidSize, &uid)
            
            guard status == noErr else { continue }
            
            devices.append(AudioDevice(name: name as String, uid: uid as String))
        }
        
        return devices
    }
    
    func startCapture(deviceUID: String?, chunkSizeMs: Int, onChunk: @escaping (Data) -> Void) throws {
        // Reset configuration change tracking for new recording session
        configChangeRestartCount = 0
        lastConfigChangeRestartTime = nil

        try startCaptureInternal(deviceUID: deviceUID, chunkSizeMs: chunkSizeMs, onChunk: onChunk, isRestart: false)
    }

    private func startCaptureInternal(deviceUID: String?, chunkSizeMs: Int, onChunk: @escaping (Data) -> Void, isRestart: Bool) throws {
        // Stop any existing capture and wait for cleanup
        stopCapture()

        // Store for potential restart
        self.currentDeviceUID = deviceUID
        self.currentChunkSizeMs = chunkSizeMs

        // Small delay to let audio system reset (helps with device switching)
        // Shorter delay for restarts since system is already warmed up
        Thread.sleep(forTimeInterval: isRestart ? 0.05 : 0.1)

        self.onAudioChunk = onChunk
        self.chunkSizeInSamples = Int(targetSampleRate * Double(chunkSizeMs) / 1000.0)
        self.chunkBuffer.removeAll()
        self.chunkBuffer.reserveCapacity(chunkSizeInSamples * 2)
        self.audioFlowStarted = false

        // For restarts, use fewer attempts since we're already in a mode switch
        let maxAttempts = isRestart ? 2 : 3

        // Try multiple times to start audio capture AND verify audio flows
        var lastError: Error?
        for attempt in 1...maxAttempts {
            do {
                try startAudioEngine(deviceUID: deviceUID)

                // Wait up to 500ms for audio to start flowing
                // This gives the headset time to switch modes
                var waitedMs = 0
                while !audioFlowStarted && waitedMs < 500 {
                    Thread.sleep(forTimeInterval: 0.05)
                    waitedMs += 50
                }

                if audioFlowStarted {
                    Logger.shared.log("Audio capture started (attempt \(attempt)\(isRestart ? ", restart" : "")) with chunk size: \(chunkSizeMs)ms - audio flowing after \(waitedMs)ms")
                    return
                } else {
                    Logger.shared.log("Audio capture attempt \(attempt): engine started but no audio flow after 500ms", level: .warning)
                    // Stop and retry
                    audioEngine?.inputNode.removeTap(onBus: 0)
                    audioEngine?.stop()
                    audioEngine?.reset()
                    audioEngine = nil
                    Thread.sleep(forTimeInterval: 0.3)  // Extra wait for headset to settle
                }
            } catch {
                lastError = error
                Logger.shared.log("Audio capture attempt \(attempt) failed: \(error)", level: .warning)

                // Reset and wait before retry
                audioEngine?.stop()
                audioEngine?.reset()
                audioEngine = nil
                Thread.sleep(forTimeInterval: 0.3)
            }
        }

        // If we get here, all attempts failed
        // If a specific device was requested and it failed (deviceNotFound), fall back to default mic
        if let error = lastError as? AudioCaptureError,
           error == .deviceNotFound,
           deviceUID != nil {
            Logger.shared.log("Specified audio device not found, falling back to default microphone", level: .warning)

            // Try with default device (nil = system default)
            do {
                try startAudioEngine(deviceUID: nil)

                // Wait for audio flow
                var waitedMs = 0
                while !audioFlowStarted && waitedMs < 500 {
                    Thread.sleep(forTimeInterval: 0.05)
                    waitedMs += 50
                }

                if audioFlowStarted {
                    Logger.shared.log("Audio capture started with default microphone (fallback) - audio flowing after \(waitedMs)ms")
                    // Update stored deviceUID to reflect we're using default
                    self.currentDeviceUID = nil
                    return
                } else {
                    Logger.shared.log("Audio capture started (fallback to default) with chunk size: \(chunkSizeMs)ms")
                    self.currentDeviceUID = nil
                    return
                }
            } catch {
                Logger.shared.log("Fallback to default microphone also failed: \(error)", level: .error)
                throw error
            }
        }

        // Last resort: try one more time with original device
        Logger.shared.log("All audio capture attempts had issues, trying final fallback", level: .warning)
        do {
            try startAudioEngine(deviceUID: deviceUID)
            Logger.shared.log("Audio capture started (final fallback) with chunk size: \(chunkSizeMs)ms")
        } catch {
            throw lastError ?? error
        }
    }
    
    private func startAudioEngine(deviceUID: String?) throws {
        // Setup audio engine
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else {
            throw AudioCaptureError.engineCreationFailed
        }
        
        inputNode = engine.inputNode
        
        // Set input device if specified
        if let uid = deviceUID, !uid.isEmpty {
            try setInputDevice(uid: uid)
        }
        
        guard let inputNode = inputNode else {
            throw AudioCaptureError.noInputDevice
        }
        
        // Get format AFTER setting input device
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // Validate format
        guard inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 else {
            Logger.shared.log("Invalid input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) channels", level: .error)
            throw AudioCaptureError.formatCreationFailed
        }
        
        Logger.shared.log("Input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) channels")
        
        // Create target format (16kHz, mono, float)
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: targetSampleRate, channels: 1, interleaved: false) else {
            throw AudioCaptureError.formatCreationFailed
        }
        
        // Create converter if sample rates differ
        if inputFormat.sampleRate != targetSampleRate || inputFormat.channelCount != 1 {
            // Create intermediate format for conversion
            guard let intermediateFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: inputFormat.sampleRate, channels: 1, interleaved: false) else {
                throw AudioCaptureError.formatCreationFailed
            }
            
            audioConverter = AVAudioConverter(from: intermediateFormat, to: targetFormat)
            
            if audioConverter == nil {
                Logger.shared.log("Failed to create audio converter, will use manual resampling", level: .warning)
            }
        }
        
        // Install tap on input node - use nil format to let system choose best format
        let bufferSize: AVAudioFrameCount = 4096  // Larger buffer for better stability
        
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: nil) { [weak self] buffer, time in
            self?.audioFlowStarted = true
            self?.processAudioBuffer(buffer)
        }
        
        // Start engine
        try engine.start()
    }
    
    var hasAudioFlowStarted: Bool {
        return audioFlowStarted
    }
    
    func stopCapture() {
        // Log whether audio was actually captured
        if !audioFlowStarted {
            Logger.shared.log("WARNING: Audio capture stopped but no audio data was received!", level: .warning)
        }
        
        // Remove tap first
        if let inputNode = audioEngine?.inputNode {
            inputNode.removeTap(onBus: 0)
        }
        
        // Stop and reset engine
        audioEngine?.stop()
        audioEngine?.reset()
        audioEngine = nil
        inputNode = nil
        audioConverter = nil
        audioFlowStarted = false
        
        // Flush remaining buffer
        lock.lock()
        if !chunkBuffer.isEmpty {
            sendChunk(chunkBuffer)
            chunkBuffer.removeAll()
        }
        lock.unlock()
        
        Logger.shared.log("Audio capture stopped")
    }
    
    // MARK: - Private Methods
    private func setInputDevice(uid: String) throws {
        var deviceID: AudioDeviceID = 0

        // Find device by UID
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == noErr else {
            throw AudioCaptureError.deviceNotFound
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )

        guard status == noErr else {
            throw AudioCaptureError.deviceNotFound
        }

        for id in deviceIDs {
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            var deviceUID: CFString = "" as CFString
            var uidSize = UInt32(MemoryLayout<CFString>.size)
            status = AudioObjectGetPropertyData(id, &uidAddress, 0, nil, &uidSize, &deviceUID)

            if status == noErr && (deviceUID as String) == uid {
                deviceID = id
                break
            }
        }

        guard deviceID != 0 else {
            throw AudioCaptureError.deviceNotFound
        }

        // Set as system default input device (this is the reliable way)
        var defaultDeviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultDeviceAddress,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &deviceID
        )

        if status != noErr {
            Logger.shared.log("Failed to set default input device, error: \(status). Will use current default.", level: .warning)
            // Don't throw - just use the current default
        } else {
            Logger.shared.log("Successfully set default input device to: \(uid)")
        }
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let floatData = buffer.floatChannelData else { return }
        
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        
        // Skip empty buffers
        guard frameCount > 0 && channelCount > 0 else { return }
        
        // Convert to mono if needed
        var monoSamples = [Float](repeating: 0, count: frameCount)
        
        if channelCount > 1 {
            // Average channels
            for i in 0..<frameCount {
                var sum: Float = 0
                for ch in 0..<channelCount {
                    sum += floatData[ch][i]
                }
                monoSamples[i] = sum / Float(channelCount)
            }
        } else {
            memcpy(&monoSamples, floatData[0], frameCount * MemoryLayout<Float>.size)
        }
        
        // Resample if needed
        let inputSampleRate = buffer.format.sampleRate
        var resampledSamples: [Float]
        
        // Validate sample rate
        guard inputSampleRate > 0 else {
            Logger.shared.log("Invalid sample rate: \(inputSampleRate)", level: .warning)
            return
        }
        
        if inputSampleRate != targetSampleRate {
            resampledSamples = resample(monoSamples, fromRate: inputSampleRate, toRate: targetSampleRate)
        } else {
            resampledSamples = monoSamples
        }
        
        // Add to chunk buffer
        lock.lock()
        chunkBuffer.append(contentsOf: resampledSamples)
        
        // Send chunks when we have enough samples
        while chunkBuffer.count >= chunkSizeInSamples {
            let chunk = Array(chunkBuffer.prefix(chunkSizeInSamples))
            chunkBuffer.removeFirst(chunkSizeInSamples)
            
            lock.unlock()
            sendChunk(chunk)
            lock.lock()
        }
        lock.unlock()
    }
    
    private func resample(_ samples: [Float], fromRate: Double, toRate: Double) -> [Float] {
        let ratio = toRate / fromRate
        let outputLength = Int(Double(samples.count) * ratio)
        var output = [Float](repeating: 0, count: outputLength)
        
        // Linear interpolation resampling
        for i in 0..<outputLength {
            let srcIndex = Double(i) / ratio
            let srcIndexInt = Int(srcIndex)
            let frac = Float(srcIndex - Double(srcIndexInt))
            
            if srcIndexInt + 1 < samples.count {
                output[i] = samples[srcIndexInt] * (1 - frac) + samples[srcIndexInt + 1] * frac
            } else if srcIndexInt < samples.count {
                output[i] = samples[srcIndexInt]
            }
        }
        
        return output
    }
    
    private func sendChunk(_ samples: [Float]) {
        // Convert Float array to Data (little-endian float32)
        let data = samples.withUnsafeBytes { Data($0) }
        
        onAudioChunk?(data)
    }
}

// MARK: - Errors
enum AudioCaptureError: Error, LocalizedError {
    case engineCreationFailed
    case noInputDevice
    case formatCreationFailed
    case deviceNotFound
    case permissionDenied
    
    var errorDescription: String? {
        switch self {
        case .engineCreationFailed:
            return "Failed to create audio engine"
        case .noInputDevice:
            return "No audio input device available"
        case .formatCreationFailed:
            return "Failed to create audio format"
        case .deviceNotFound:
            return "Audio device not found"
        case .permissionDenied:
            return "Microphone permission denied"
        }
    }
}
