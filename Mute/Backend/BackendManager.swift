// BackendManager.swift
// Mute

import Foundation
import Combine
import AppKit

@MainActor
class BackendManager: ObservableObject {
    @Published var status: BackendStatus = .disconnected
    @Published var modelStatus: ModelStatus = .unknown
    @Published var downloadProgress: Double = 0.0
    @Published var whisperAvailable: Bool = false
    @Published var loadedModels: [String] = []
    @Published var availableModels: [ModelInfo] = []

    var onPartialTranscription: ((String) -> Void)?
    var onFinalTranscription: ((String) -> Void)?
    var onIntervalTranscription: ((String) -> Void)?  // Just the new text to append
    var onError: ((String) -> Void)?
    var onRecordingReady: ((String) -> Void)?  // Called when backend is ready to receive audio

    private var process: Process?
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var reconnectTimer: Timer?
    private var pingTimer: Timer?

    private let backendPort = 9877
    private let maxReconnectAttempts = 5
    private var reconnectAttempts = 0

    private var messageQueue: [Data] = []
    private var isConnected = false

    // Connection health tracking
    private var lastPongTime: Date = Date()
    private let connectionStaleThreshold: TimeInterval = 120  // 2 minutes without pong = stale

    // MARK: - Initialization
    init() {
        setupSleepWakeObservers()
    }

    private func setupSleepWakeObservers() {
        // Observe when Mac wakes from sleep to reconnect
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Logger.shared.log("Mac woke from sleep - checking backend connection")
            Task { @MainActor in
                // Give the system a moment to restore network
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await self?.checkAndReconnect()
            }
        }
    }

    private func checkAndReconnect() async {
        // Check if backend is responsive by sending a ping
        if status == .connected {
            // Record time before ping
            let pingTime = Date()

            // Send a test ping - if it fails, reconnect
            Logger.shared.log("Checking backend connection after wake...")
            send(["type": "ping"])

            // Wait a bit for pong response
            try? await Task.sleep(nanoseconds: 3_000_000_000)

            // Check if we got a pong after our ping
            let gotPong = lastPongTime > pingTime

            // If still showing connected but backend might be dead, restart
            if status == .connected && (!isBackendProcessRunning() || !gotPong) {
                Logger.shared.log("Backend not responsive after wake (process: \(isBackendProcessRunning()), pong: \(gotPong)) - restarting")
                await restart()
            } else if gotPong {
                // Connection is alive - refresh model status
                Logger.shared.log("Backend responsive, refreshing model status")
                getAvailableModels()
            }
        } else {
            Logger.shared.log("Backend not connected after wake - starting")
            await start()
        }
    }

    /// Check if connection appears stale (no recent pong)
    func isConnectionStale() -> Bool {
        let timeSinceLastPong = Date().timeIntervalSince(lastPongTime)
        return timeSinceLastPong > connectionStaleThreshold
    }

    /// Verify connection is healthy before critical operations
    func verifyConnection() async -> Bool {
        if !isConnected || status != .connected {
            Logger.shared.log("verifyConnection: not connected (isConnected=\(isConnected), status=\(status))")
            return false
        }

        let timeSinceLastPong = Date().timeIntervalSince(lastPongTime)

        // If connection seems stale, do a ping check
        if isConnectionStale() {
            Logger.shared.log("Connection appears stale (last pong: \(Int(timeSinceLastPong))s ago, threshold: \(Int(connectionStaleThreshold))s), verifying...", level: .warning)
            let pingTime = Date()
            send(["type": "ping"])

            // Wait briefly for pong
            try? await Task.sleep(nanoseconds: 2_000_000_000)

            if lastPongTime <= pingTime {
                Logger.shared.log("Connection confirmed stale - no pong received after 2s", level: .error)
                return false
            }
            Logger.shared.log("Connection recovered - pong received")
        } else {
            Logger.shared.log("Connection healthy (last pong: \(Int(timeSinceLastPong))s ago)")
        }

        return true
    }

    private func isBackendProcessRunning() -> Bool {
        return process?.isRunning ?? false
    }

    // MARK: - Lifecycle
    func start() async {
        Logger.shared.log("Starting backend manager")
        
        // Disconnect any existing connection first
        disconnect()
        
        // Start the Python backend process
        await startBackendProcess()
        
        // Wait longer for the process to start and model to load
        // The model takes ~10+ seconds to load
        Logger.shared.log("Waiting for backend process to start...")
        try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
        
        // Connect to WebSocket
        await connect()
    }
    
    func stop() {
        Logger.shared.log("Stopping backend manager")
        
        disconnect()
        stopBackendProcess()
        killExistingProcessOnPort()
    }
    
    func restart() async {
        Logger.shared.log("Restarting backend")
        stop()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        await start()
    }
    
    private func killExistingProcessOnPort() {
        // Try different paths for lsof
        let lsofPaths = ["/usr/sbin/lsof", "/usr/bin/lsof"]
        var lsofPath: String?
        
        for path in lsofPaths {
            if FileManager.default.fileExists(atPath: path) {
                lsofPath = path
                break
            }
        }
        
        guard let foundLsof = lsofPath else {
            Logger.shared.log("lsof not found, skipping port cleanup", level: .warning)
            return
        }
        
        // Kill multiple times to ensure the process is dead
        for attempt in 1...3 {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: foundLsof)
            task.arguments = ["-ti", ":\(backendPort)"]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = FileHandle.nullDevice
            
            do {
                try task.run()
                task.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !output.isEmpty {
                    let pids = output.split(separator: "\n")
                    let currentPID = ProcessInfo.processInfo.processIdentifier
                    
                    for pidStr in pids {
                        if let pid = Int32(pidStr), pid != currentPID {
                            Logger.shared.log("Killing process \(pid) on port \(backendPort) (attempt \(attempt))")
                            kill(pid, SIGKILL)
                        }
                    }
                    
                    // Wait for port to be released
                    Thread.sleep(forTimeInterval: 0.5)
                } else {
                    // No process found on port
                    break
                }
            } catch {
                Logger.shared.log("Could not check for existing processes: \(error)", level: .warning)
                break
            }
        }
        
        // Final wait to ensure port is fully released
        Thread.sleep(forTimeInterval: 0.3)
    }
    
    // MARK: - Backend Process Management
    private func startBackendProcess() async {
        // Kill any existing process on the port first
        killExistingProcessOnPort()
        
        // Find Python and backend script
        let backendPath = getBackendPath()
        let pythonPath = findPython()
        
        guard let python = pythonPath else {
            Logger.shared.log("Python not found", level: .error)
            status = .error("Python not found. Please install Python 3.11+")
            return
        }
        
        guard FileManager.default.fileExists(atPath: backendPath) else {
            Logger.shared.log("Backend script not found at \(backendPath)", level: .error)
            status = .error("Backend not found")
            return
        }
        
        Logger.shared.log("Starting backend with Python: \(python)")
        
        process = Process()
        process?.executableURL = URL(fileURLWithPath: python)
        process?.arguments = [backendPath, "--port", "\(backendPort)"]
        process?.currentDirectoryURL = URL(fileURLWithPath: backendPath).deletingLastPathComponent()
        
        // Setup environment
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"

        // Set up venv environment to ensure packages are found
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let venvDir = "\(homeDir)/Library/Application Support/Mute/venv"
        if FileManager.default.fileExists(atPath: venvDir) {
            env["VIRTUAL_ENV"] = venvDir
            env["PATH"] = "\(venvDir)/bin:" + (env["PATH"] ?? "")
            // CRITICAL: Set PYTHONPATH to include venv site-packages
            let sitePackages = "\(venvDir)/lib/python3.11/site-packages"
            env["PYTHONPATH"] = sitePackages
            Logger.shared.log("Set VIRTUAL_ENV to: \(venvDir)")
            Logger.shared.log("Set PYTHONPATH to: \(sitePackages)")
        }

        process?.environment = env
        
        // Capture output
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process?.standardOutput = outputPipe
        process?.standardError = errorPipe
        
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                Logger.shared.log("[Backend] \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }
        
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                Logger.shared.log("[Backend Error] \(output.trimmingCharacters(in: .whitespacesAndNewlines))", level: .error)
            }
        }
        
        process?.terminationHandler = { [weak self] process in
            Logger.shared.log("Backend process terminated with code: \(process.terminationStatus)")
            Task { @MainActor in
                self?.handleProcessTermination()
            }
        }
        
        do {
            try process?.run()
            Logger.shared.log("Backend process started with PID: \(process?.processIdentifier ?? 0)")
        } catch {
            Logger.shared.log("Failed to start backend: \(error)", level: .error)
            status = .error("Failed to start backend: \(error.localizedDescription)")
        }
    }
    
    private func stopBackendProcess() {
        process?.terminate()
        process = nil
    }
    
    private func handleProcessTermination() {
        status = .disconnected
        
        // Auto-restart if unexpected termination
        if reconnectAttempts < maxReconnectAttempts {
            reconnectAttempts += 1
            Logger.shared.log("Backend terminated, attempting restart (\(reconnectAttempts)/\(maxReconnectAttempts))")
            
            Task {
                try? await Task.sleep(nanoseconds: UInt64(reconnectAttempts) * 1_000_000_000)
                await start()
            }
        } else {
            Logger.shared.log("Max reconnect attempts reached", level: .error)
            status = .error("Backend crashed. Please restart the app.")
        }
    }
    
    private func getBackendPath() -> String {
        // Check for backend in app bundle
        if let bundlePath = Bundle.main.resourcePath {
            let bundledBackend = "\(bundlePath)/backend/main.py"
            if FileManager.default.fileExists(atPath: bundledBackend) {
                return bundledBackend
            }
        }
        
        // Development fallback - look in project directory
        let developmentPath = FileManager.default.currentDirectoryPath + "/backend/main.py"
        if FileManager.default.fileExists(atPath: developmentPath) {
            return developmentPath
        }
        
        // Try Application Support
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Mute/backend/main.py").path ?? ""
        
        return appSupport
    }
    
    private func findPython() -> String? {
        // Check for venv in Application Support first - use direct path construction
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let venvPath = "\(homeDir)/Library/Application Support/Mute/venv/bin/python3"

        Logger.shared.log("Checking venv Python at: \(venvPath)")

        if FileManager.default.fileExists(atPath: venvPath) {
            Logger.shared.log("Found venv Python, using it")
            return venvPath
        } else {
            Logger.shared.log("Venv Python not found at \(venvPath)")
        }

        // Check common Python locations
        let pythonPaths = [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
            "/opt/homebrew/bin/python3.11",
            "/opt/homebrew/bin/python3.12"
        ]

        for path in pythonPaths {
            if FileManager.default.fileExists(atPath: path) {
                Logger.shared.log("Using system Python: \(path)")
                return path
            }
        }
        
        // Try using `which python3`
        let whichProcess = Process()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = ["python3"]
        
        let pipe = Pipe()
        whichProcess.standardOutput = pipe
        
        do {
            try whichProcess.run()
            whichProcess.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                return path
            }
        } catch {
            Logger.shared.log("Failed to find Python: \(error)", level: .warning)
        }
        
        return nil
    }
    
    // MARK: - WebSocket Connection
    private func connect() async {
        status = .connecting

        let url = URL(string: "ws://localhost:\(backendPort)/ws")!

        urlSession = URLSession(configuration: .default)
        webSocketTask = urlSession?.webSocketTask(with: url)

        webSocketTask?.resume()

        // Start receiving messages
        receiveMessage()

        // Start ping timer
        startPingTimer()

        // Reset connection health tracking
        lastPongTime = Date()

        isConnected = true
        status = .connected
        reconnectAttempts = 0

        Logger.shared.log("WebSocket connected")
        
        // Flush message queue
        for message in messageQueue {
            sendRaw(message)
        }
        messageQueue.removeAll()
    }
    
    private func disconnect() {
        pingTimer?.invalidate()
        pingTimer = nil
        
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession = nil
        
        isConnected = false
        status = .disconnected
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                Task { @MainActor in
                    self?.handleMessage(message)
                    self?.receiveMessage() // Continue receiving
                }

            case .failure(let error):
                Logger.shared.log("WebSocket receive error: \(error)", level: .error)
                Task { @MainActor in
                    self?.handleConnectionError(error)
                }
            }
        }
    }
    
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            parseMessage(text)
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                parseMessage(text)
            }
        @unknown default:
            break
        }
    }
    
    private func parseMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            Logger.shared.log("Failed to parse message: \(text)", level: .warning)
            return
        }

        switch type {
        case "ready":
            let modelLoaded = json["model_loaded"] as? Bool ?? false
            let whisperAvail = json["whisper_available"] as? Bool ?? false
            let loaded = json["loaded_models"] as? [String] ?? []

            whisperAvailable = whisperAvail
            loadedModels = loaded
            modelStatus = modelLoaded ? .ready : .notDownloaded
            Logger.shared.log("Backend ready, model loaded: \(modelLoaded), whisper available: \(whisperAvail)")

            // Request available models list
            getAvailableModels()

        case "partial":
            if let partialText = json["text"] as? String {
                onPartialTranscription?(partialText)
            }

        case "final":
            if let finalText = json["text"] as? String {
                onFinalTranscription?(finalText)
            }

        case "interval_transcription":
            if let text = json["text"] as? String, !text.isEmpty {
                onIntervalTranscription?(text)
            }

        case "error":
            if let errorMessage = json["message"] as? String {
                onError?(errorMessage)
            }

        case "model_progress":
            if let percent = json["percent"] as? Double {
                downloadProgress = percent / 100.0
                modelStatus = .downloading
            }

        case "model_downloaded":
            modelStatus = .downloaded
            downloadProgress = 1.0

        case "model_loaded":
            modelStatus = .ready
            if let modelId = json["model"] as? String {
                if !loadedModels.contains(modelId) {
                    loadedModels.append(modelId)
                }
                Logger.shared.log("Model loaded: \(modelId)")
            }
            // Refresh models list
            getAvailableModels()

        case "model_error":
            if let errorMessage = json["message"] as? String {
                modelStatus = .error(errorMessage)
            }

        case "models_list":
            if let modelsArray = json["models"] as? [[String: Any]] {
                availableModels = modelsArray.map { ModelInfo(from: $0) }
                Logger.shared.log("Received \(availableModels.count) available models")
            }

        case "pong":
            // Keep-alive response - update last pong time
            lastPongTime = Date()
            break

        case "keep_warm_updated":
            let models = json["models"] as? [String] ?? []
            let duration = json["duration"] as? String ?? "4h"
            Logger.shared.log("Keep-warm settings updated: models=\(models), duration=\(duration)")

        case "model_unloaded":
            if let modelId = json["model"] as? String {
                loadedModels.removeAll { $0 == modelId }
                Logger.shared.log("Model unloaded due to idle timeout: \(modelId)")
                // Refresh models list
                getAvailableModels()
            }

        case "recording_ready":
            let modelId = json["model"] as? String ?? ""
            Logger.shared.log("Recording ready with model: \(modelId)")
            onRecordingReady?(modelId)

        default:
            Logger.shared.log("Unknown message type: \(type)", level: .warning)
        }
    }
    
    private func handleConnectionError(_ error: Error) {
        isConnected = false

        // During reconnection attempts, show connecting state instead of error
        if reconnectAttempts < maxReconnectAttempts {
            status = .connecting
            Logger.shared.log("Connection failed, retrying... (attempt \(reconnectAttempts + 1)/\(maxReconnectAttempts))")

            // Schedule reconnect
            reconnectTimer?.invalidate()
            reconnectTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.reconnectAttempts += 1
                    await self?.connect()
                }
            }
        } else {
            // Max attempts reached, show error
            status = .error("Connection failed")
            Logger.shared.log("Max reconnection attempts reached", level: .error)
        }
    }
    
    private func startPingTimer() {
        pingTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sendPing()
            }
        }
    }
    
    private func sendPing() {
        send(["type": "ping"])
    }
    
    // MARK: - Sending Messages
    private func send(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        sendRaw(data)
    }
    
    private func sendRaw(_ data: Data) {
        guard isConnected else {
            messageQueue.append(data)
            return
        }
        
        guard let text = String(data: data, encoding: .utf8) else { return }
        
        webSocketTask?.send(.string(text)) { error in
            if let error = error {
                Logger.shared.log("WebSocket send error: \(error)", level: .error)
            }
        }
    }
    
    // MARK: - Transcription Control
    func startTranscription(model: String = "parakeet", enableDiarization: Bool = false) async {
        let settings: [String: Any] = [
            "type": "start",
            "settings": [
                "model": model,
                "enable_diarization": enableDiarization
            ]
        ]
        send(settings)
    }
    
    func stopTranscription() async {
        send(["type": "stop"])
    }

    func requestIntervalTranscription() async {
        send(["type": "transcribe_interval"])
    }

    func sendAudioChunk(_ data: Data) async {
        let base64Audio = data.base64EncodedString()
        let message: [String: Any] = [
            "type": "audio",
            "data": base64Audio,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000)
        ]
        send(message)
    }
    
    // MARK: - Model Management
    func downloadModel() async {
        modelStatus = .downloading
        downloadProgress = 0.0
        send(["type": "download_model"])
    }

    func clearModelCache() {
        send(["type": "clear_cache"])
        modelStatus = .notDownloaded
    }

    func getAvailableModels() {
        send(["type": "get_models"])
    }

    func loadModel(_ modelId: String) {
        send(["type": "load_model", "model": modelId])
    }

    func sendKeepWarmSettings(models: [String], duration: String) {
        send([
            "type": "set_keep_warm",
            "models": models,
            "duration": duration
        ])
    }
}

// MARK: - Model Info
struct ModelInfo: Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let size: String
    let downloaded: Bool
    let loaded: Bool
    let available: Bool

    init(from dict: [String: Any]) {
        self.id = dict["id"] as? String ?? ""
        self.name = dict["name"] as? String ?? ""
        self.description = dict["description"] as? String ?? ""
        self.size = dict["size"] as? String ?? ""
        self.downloaded = dict["downloaded"] as? Bool ?? false
        self.loaded = dict["loaded"] as? Bool ?? false
        self.available = dict["available"] as? Bool ?? false
    }
}
