# TinyDictate - Detailed Architecture & Implementation Plan

## Executive Summary

TinyDictate is a macOS menu bar application that provides instant local dictation-to-text using NVIDIA's Parakeet TDT v3 model. The app captures audio via a global hotkey, streams it to a local Python-based ASR backend, and pastes the transcribed text into the focused application.

---

## 1. Architecture Overview

### 1.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    TinyDictate macOS App                        │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────────────┐  │
│  │   Menu Bar   │  │   Overlay    │  │    Settings Window    │  │
│  │   (SwiftUI)  │  │  (NSPanel)   │  │      (SwiftUI)        │  │
│  └──────────────┘  └──────────────┘  └───────────────────────┘  │
│           │               │                    │                 │
│  ┌────────┴───────────────┴────────────────────┴──────────────┐ │
│  │                    AppState (ObservableObject)              │ │
│  │  - Recording state machine                                  │ │
│  │  - Settings persistence (UserDefaults)                      │ │
│  │  - Backend connection management                            │ │
│  └─────────────────────────────────────────────────────────────┘ │
│           │               │                    │                 │
│  ┌────────┴───────┐ ┌─────┴──────┐   ┌────────┴───────────────┐ │
│  │  AudioCapture  │ │  Hotkey    │   │   TextInsertion        │ │
│  │  (AVAudioEng)  │ │  Manager   │   │   (Clipboard/Paste)    │ │
│  └────────────────┘ └────────────┘   └────────────────────────┘ │
│           │                                                      │
│           │ WebSocket (localhost:9877)                          │
│           ▼                                                      │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │              Python ASR Backend (Subprocess)                │ │
│  │  ┌─────────────────┐  ┌─────────────────────────────────┐  │ │
│  │  │  Model Manager  │  │   Streaming ASR Inference       │  │ │
│  │  │  (HF Download)  │  │   (NeMo/Parakeet TDT v3)        │  │ │
│  │  └─────────────────┘  └─────────────────────────────────┘  │ │
│  └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 Chosen Approach: Option 1 - Swift App + Python Backend Process

**Rationale:**
- Parakeet TDT v3 is a NeMo-based model requiring PyTorch and NVIDIA NeMo toolkit
- Python ecosystem has mature support for NeMo models
- WebSocket communication provides clean separation and robust streaming
- Swift handles all macOS-specific UI/UX concerns optimally
- Backend can be restarted independently if it crashes

---

## 2. Component Details

### 2.1 macOS App (Swift/SwiftUI)

#### 2.1.1 Menu Bar Component
- **Framework:** SwiftUI `MenuBarExtra`
- **Items:**
  - Recording status indicator (red dot when recording)
  - Start/Stop Recording (reflects current state)
  - Settings... (opens settings window)
  - Separator
  - About TinyDictate
  - Quit

#### 2.1.2 Settings Window
- **Framework:** SwiftUI Window
- **Tabs:**
  1. **General**
     - Global hotkey recorder (using KeyboardShortcuts package)
     - Audio input device selector
     - "Paste on stop" toggle (default: ON)
     - "Show overlay" toggle (default: ON)
  
  2. **Transcription**
     - Quality preset dropdown (Ultra Low Latency / Balanced / High Accuracy)
     - Language mode (Auto / English forced)
     - Chunk size slider (200-1000ms)
  
  3. **Model**
     - Model status (Downloaded / Not Downloaded / Downloading X%)
     - Download/Re-download button
     - Model storage location
     - Clear cache button
  
  4. **Advanced**
     - Developer mode toggle (shows logs)
     - Backend status indicator
     - Restart backend button
     - Log viewer
  
  5. **About**
     - Version info
     - Licenses (CC-BY-4.0 for model, MIT for packages)
     - Privacy statement

#### 2.1.3 Overlay Panel
- **Framework:** AppKit `NSPanel` with SwiftUI content
- **Configuration:**
  - `styleMask: [.borderless, .nonactivatingPanel]`
  - `level: .floating` (or `.screenSaver` for above fullscreen)
  - `collectionBehavior: [.canJoinAllSpaces, .stationary, .ignoresCycle]`
  - `isMovableByWindowBackground: false`
  - `ignoresMouseEvents: true` (click-through)
- **Position:** Top-left corner, 8pt margin, follows active screen
- **Size:** ~80x24pt pill shape
- **States:**
  - Hidden (idle)
  - Recording: Red dot + "Rec" text
  - Processing: Spinner + "..." 
  - Done: Green checkmark (auto-hides after 1.5s)
  - Error: Yellow warning icon

#### 2.1.4 Audio Capture
- **Framework:** AVFoundation (`AVAudioEngine`)
- **Pipeline:**
  1. Install tap on input node
  2. Capture at device native rate (typically 48kHz)
  3. Convert to 16kHz mono Float32 using `AVAudioConverter`
  4. Buffer into chunks (configurable 200-500ms)
  5. Send via WebSocket to backend
- **Format:** 16kHz, mono, Float32 PCM (Parakeet requirement)

#### 2.1.5 Hotkey Manager
- **Library:** `KeyboardShortcuts` (https://github.com/sindresorhus/KeyboardShortcuts)
- **Default:** Cmd+Shift+Space (configurable)
- **Behavior:**
  - Toggle recording on press
  - Debounce rapid presses (100ms)

#### 2.1.6 Text Insertion
- **Strategy (in order):**
  1. Copy final transcript to `NSPasteboard.general`
  2. If "paste on stop" enabled:
     a. Save current clipboard content
     b. Set transcript to clipboard
     c. Simulate Cmd+V via CGEvent
     d. Restore previous clipboard (optional, configurable)
  3. If paste fails or no text field focused: show toast with transcript
- **Accessibility:** Requires Accessibility permission for CGEvent posting

### 2.2 Python ASR Backend

#### 2.2.1 Overview
- **Runtime:** Bundled Python 3.11+ via pyenv or system Python
- **Communication:** WebSocket server on localhost:9877
- **Dependencies:** 
  - `torch` (CPU version for simplicity, or MPS-capable)
  - `nemo_toolkit[asr]`
  - `websockets`
  - `huggingface_hub`

#### 2.2.2 Model Manager
- **Model ID:** `nvidia/parakeet-tdt-0.6b-v3`
- **Storage:** `~/Library/Application Support/TinyDictate/Models/`
- **Features:**
  - Check if model exists and is valid
  - Download via `huggingface_hub.snapshot_download`
  - Resume interrupted downloads
  - Report progress via WebSocket messages

#### 2.2.3 Streaming Inference
- **Approach:** Chunked buffered inference
  - Accumulate audio chunks into a rolling buffer
  - Run inference on accumulated audio periodically
  - Emit partial results as they change
  - On "stop" signal, run final inference and emit final result
- **Optimization:**
  - Use `torch.inference_mode()` for speed
  - Batch size 1 (single stream)
  - Consider torch.compile() for additional speedup

#### 2.2.4 WebSocket Protocol
```
Client -> Server:
  {"type": "start", "settings": {"preset": "balanced", "language": "auto"}}
  {"type": "audio", "data": "<base64 PCM>", "timestamp": 12345}
  {"type": "stop"}
  {"type": "ping"}

Server -> Client:
  {"type": "ready", "model_loaded": true}
  {"type": "partial", "text": "Hello wor", "timestamp": 12400}
  {"type": "final", "text": "Hello world.", "timestamp": 12500}
  {"type": "error", "message": "..."}
  {"type": "model_progress", "percent": 45.5}
  {"type": "pong"}
```

---

## 3. Permissions & Entitlements

### 3.1 Required Permissions

| Permission | Purpose | Request Trigger |
|------------|---------|-----------------|
| Microphone | Audio capture | First recording attempt |
| Accessibility | Simulating Cmd+V paste | First paste attempt |

### 3.2 Info.plist Keys
```xml
<key>NSMicrophoneUsageDescription</key>
<string>TinyDictate needs microphone access to transcribe your speech.</string>
```

### 3.3 Entitlements
```xml
<key>com.apple.security.app-sandbox</key>
<false/>  <!-- Required for subprocess spawning and global hotkeys -->
<key>com.apple.security.device.audio-input</key>
<true/>
<key>com.apple.security.automation.apple-events</key>
<true/>
```

### 3.4 Onboarding Flow
1. First launch: Welcome screen explaining features
2. Microphone permission prompt (system dialog)
3. Accessibility permission guidance (direct to System Settings)
4. Model download prompt
5. Ready to use

---

## 4. Performance Strategy

### 4.1 Latency Targets
| Metric | Target | Strategy |
|--------|--------|----------|
| Audio capture latency | <50ms | Small buffer size (1024 frames) |
| Chunk transmission | <10ms | WebSocket on localhost |
| Partial result latency | 500-1500ms | Chunked inference, 300ms chunks |
| Final result latency | <500ms | Single final inference pass |

### 4.2 Quality Presets
| Preset | Chunk Size | Inference Interval | Notes |
|--------|------------|-------------------|-------|
| Ultra Low Latency | 200ms | 200ms | More CPU, faster partials |
| Balanced | 400ms | 400ms | Default |
| High Accuracy | 800ms | 800ms | Less CPU, better accuracy |

### 4.3 Resource Management
- Backend process: Monitor memory usage, restart if >2GB
- Audio buffers: Cap at 60 seconds (prevent memory growth)
- Idle timeout: Unload model after 5 minutes of inactivity (optional)

---

## 5. Risk Assessment & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| NeMo not working on Apple Silicon | Medium | High | Test thoroughly; fallback to Whisper.cpp if needed |
| PyTorch MPS issues | Medium | Low | Default to CPU; MPS is optional optimization |
| Large model download (~600MB) | Low | Medium | Progress UI, resume support, user guidance |
| Accessibility permission denied | Medium | Low | Graceful fallback to clipboard-only mode |
| Backend crashes | Low | Medium | Auto-restart with exponential backoff |
| Hotkey conflicts | Low | Low | Conflict detection, user notification |
| Memory leaks in audio pipeline | Low | High | Careful buffer management, monitoring |

---

## 6. Packaging Strategy

### 6.1 App Bundle Structure
```
TinyDictate.app/
├── Contents/
│   ├── Info.plist
│   ├── MacOS/
│   │   └── TinyDictate (main executable)
│   ├── Resources/
│   │   ├── Assets.xcassets
│   │   ├── backend/
│   │   │   ├── main.py
│   │   │   ├── asr_engine.py
│   │   │   ├── model_manager.py
│   │   │   └── requirements.txt
│   │   └── Licenses/
│   │       ├── PARAKEET_LICENSE.txt
│   │       └── THIRD_PARTY_LICENSES.txt
│   └── Entitlements.plist
```

### 6.2 Python Environment Strategy
**Option A (Recommended for v1):** Require user to have Python 3.11+ installed
- On first run, check for Python
- Create venv in `~/Library/Application Support/TinyDictate/venv/`
- Install requirements automatically
- Show progress during setup

**Option B (Future):** Bundle Python with py2app or similar
- More complex but better UX
- Consider for v2

### 6.3 Code Signing & Notarization
1. Sign with Developer ID Application certificate
2. Enable Hardened Runtime (except for Python subprocess)
3. Notarize via `xcrun notarytool`
4. Staple ticket to app

---

## 7. Implementation Milestones

### Phase 1: Foundation (Days 1-2)
- [x] Project setup (Xcode, SwiftPM)
- [ ] Menu bar app skeleton
- [ ] Settings window UI
- [ ] Hotkey registration
- [ ] Basic state machine

### Phase 2: Audio Pipeline (Days 3-4)
- [ ] AVAudioEngine setup
- [ ] Audio format conversion (48kHz → 16kHz)
- [ ] Chunk buffering
- [ ] WebSocket client

### Phase 3: Python Backend (Days 5-7)
- [ ] WebSocket server
- [ ] Model download manager
- [ ] NeMo model loading
- [ ] Streaming inference implementation
- [ ] Protocol implementation

### Phase 4: Integration (Days 8-9)
- [ ] Connect Swift ↔ Python
- [ ] Overlay panel implementation
- [ ] Clipboard & paste functionality
- [ ] Error handling

### Phase 5: Polish (Days 10-12)
- [ ] Permission flow UI
- [ ] Progress indicators
- [ ] Presets & settings persistence
- [ ] Logging & developer mode
- [ ] Testing & bug fixes

### Phase 6: Packaging (Days 13-14)
- [ ] App bundling
- [ ] Python environment setup script
- [ ] Code signing
- [ ] Documentation

---

## 8. Testing Strategy

### 8.1 Unit Tests
- State machine transitions
- Audio chunk buffering logic
- WebSocket protocol parsing
- Settings persistence

### 8.2 Integration Tests
- Audio capture → WebSocket → Backend
- Backend → Transcription → Response
- End-to-end recording flow

### 8.3 Manual QA Checklist
- [ ] First launch experience
- [ ] Microphone permission flow
- [ ] Accessibility permission flow
- [ ] Model download (fresh, resume, re-download)
- [ ] Recording in various apps (Safari, Notes, VS Code, Terminal)
- [ ] Hotkey in fullscreen apps
- [ ] Multiple monitors
- [ ] Secure input fields (password fields)
- [ ] Long recordings (>60s)
- [ ] Rapid start/stop
- [ ] Backend crash recovery
- [ ] Memory usage over time
- [ ] CPU usage during recording

---

## 9. File Structure

```
TinyDictate/
├── TinyDictate.xcodeproj
├── TinyDictate/
│   ├── App/
│   │   ├── TinyDictateApp.swift
│   │   ├── AppState.swift
│   │   └── AppDelegate.swift
│   ├── Views/
│   │   ├── MenuBarView.swift
│   │   ├── SettingsView.swift
│   │   ├── OverlayPanel.swift
│   │   └── OnboardingView.swift
│   ├── Audio/
│   │   ├── AudioCaptureManager.swift
│   │   └── AudioChunker.swift
│   ├── Backend/
│   │   ├── BackendManager.swift
│   │   └── WebSocketClient.swift
│   ├── Services/
│   │   ├── HotkeyManager.swift
│   │   ├── TextInsertionService.swift
│   │   └── PermissionManager.swift
│   ├── Models/
│   │   ├── TranscriptionState.swift
│   │   └── Settings.swift
│   ├── Utilities/
│   │   ├── Logger.swift
│   │   └── Constants.swift
│   ├── Resources/
│   │   ├── Assets.xcassets
│   │   ├── Info.plist
│   │   └── TinyDictate.entitlements
│   └── Backend/
│       ├── main.py
│       ├── asr_engine.py
│       ├── model_manager.py
│       ├── websocket_server.py
│       └── requirements.txt
├── Tests/
│   └── TinyDictateTests/
├── README.md
├── BUILD.md
└── setup_backend.sh
```

---

## 10. Dependencies

### Swift Packages
| Package | Version | Purpose |
|---------|---------|---------|
| KeyboardShortcuts | 2.0.0+ | Global hotkey registration |
| Starscream | 4.0.0+ | WebSocket client |

### Python Packages
| Package | Version | Purpose |
|---------|---------|---------|
| torch | 2.1.0+ | ML framework |
| nemo_toolkit[asr] | 1.22.0+ | Parakeet model support |
| websockets | 12.0+ | WebSocket server |
| huggingface_hub | 0.20.0+ | Model downloading |
| numpy | 1.24.0+ | Array operations |

---

This plan provides a comprehensive roadmap for implementing TinyDictate. The next step is to implement each component following this architecture.
