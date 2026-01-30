# Changelog

All notable changes to Mute will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.4.1] - 2026-01-30

### Added
- Rich text formatting for Apple Notes using HTML (headers, styled timestamps, horizontal rules)
- Separate note formatting for Capture2Notes vs Audio File Transcription
- LLM transformation output now renders as formatted HTML in Notes (for prompts that output HTML)

### Fixed
- Capture2Notes final transcription not being saved to note (race condition in stopCaptureMode)
- Notes created but empty when continuous capture mode was disabled

### Changed
- Note structure now uses semantic HTML: `<h2>` headers, `<p>` paragraphs, `<hr>` separators
- Timestamps displayed in gray, smaller text with italic styling for end markers
- Transcription text properly escaped to prevent HTML injection

## [1.3.1] - 2026-01-26

### Added
- Adaptive processing timeout based on recording duration (minimum 30s or 1.5x audio length)
- Backend sends `transcription_started` message for better progress tracking
- Graceful recording stop at 4:55 (before 5-minute limit) with automatic transcription
- New `recording_stopping` message type for clean max-duration handling

### Fixed
- FFmpeg library conflict with Homebrew causing random crashes (removed unused `faster_whisper` and `av` packages)
- 15-second processing timeout too aggressive for longer recordings
- Recording hitting 5-minute limit showed error instead of transcribing gracefully

### Changed
- Recording overlay animation: faster rotation (1.2s vs 2.5s), shorter arc (35% vs 65%) for snappier feel
- Processing overlay animation: consistent style with recording, slightly faster (0.8s)
- Both indicators now use 2.5pt line width for better visibility

## [1.3.0] - 2026-01-23

### Added
- Redesigned overlay indicator with frosted glass backdrop, animated gradient ring, and soft glow effects
- GPU warm-up inference to prevent MPS stale state after long idle periods
- Background model loading (server starts immediately, models load asynchronously)
- Audio device change monitoring with real-time updates in Settings
- Automatic fallback to default microphone when selected device disconnects
- Backend audio watchdog (auto-stops recording if no audio received within 5s)
- Proper cleanup when recording fails (cancels backend task, stops transcription)

### Fixed
- App crash from concurrent backend restarts racing on port (added `isRestarting` guard)
- Backend reconnect counter never resetting, preventing recovery after legitimate restarts
- Backend server blocked by model loading, causing WebSocket connection timeout
- Fallback whisper model list showing unavailable models (small, medium removed)
- App crash/freeze when Bluetooth headset disconnects during recording
- Settings not updating when audio devices connect/disconnect
- Selected device not resetting to "System Default" when device is removed

### Changed
- Overlay indicator uses multi-layered glow, radial gradient base, and directional highlight bezel
- Recording indicator shows rounded-square stop icon with rotating gradient comet ring
- Processing indicator shows waveform icon with fast-spinning gradient ring
- Done/error indicators animate in with spring physics and sequenced reveals

## [0.9.0-beta.1] - 2026-01-20

### Added
- Speech-to-text transcription using NVIDIA Parakeet TDT v3 (multilingual, 25 European languages)
- OpenAI Whisper model support (tiny, base, small, medium, large variants)
- Word-level timestamps with Whisper models
- Capture to Notes feature with Apple Notes integration
- Speaker diarization using pyannote.audio
- Continuous capture mode with 15-second intervals
- Global hotkey for start/stop recording (customizable)
- Cancel recording hotkey (discard without transcription)
- Recording overlay indicator
- Automatic paste after transcription
- Clipboard preservation option
- Multiple audio input device support
- Separate audio device selection for Dictation vs Capture to Notes
- Model download with progress indicator
- Keep model warm feature (preload for faster first transcription)
- Usage statistics tracking (daily, weekly, total dictations)
- Developer mode with detailed logging
- File-based logging for debugging (`~/Library/Application Support/Mute/`)
- Onboarding flow for first-time setup

### Technical
- WebSocket-based communication between Swift frontend and Python backend
- Parallel audio + backend initialization for faster recording start
- MPS (Apple Silicon GPU) acceleration for Parakeet model
- Efficient audio buffering with memory limits (5 min max recording)
- Audio resampling to 16kHz for model compatibility
- Smart Bluetooth headset mode switching with retry logic
- Graceful shutdown handling with signal trapping

### Security
- All audio processing happens locally on device
- No data sent to external servers
- Microphone permission with clear usage description

---

## Version History

### Release Versions
- `1.4.1` - Rich text formatting for Apple Notes, Capture2Notes fix
- `1.4.0` - Configurable modes hotkey and enhanced mode editor
- `1.3.1` - Stability fixes (FFmpeg conflict, adaptive timeout), improved animations
- `1.3.0` - Overlay redesign, stability fixes (GPU warm-up, concurrent restart guard)
- `1.2.0` - Cloud transcription with Groq Whisper V3 Turbo
- `0.9.x` - Beta releases, feature complete, testing phase

### Versioning Scheme
- **MAJOR.MINOR.PATCH** following [Semantic Versioning](https://semver.org/)
- Build numbers use date format: `YYYYMMDD`
