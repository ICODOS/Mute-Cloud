# Mute

A local, privacy-focused speech-to-text app for macOS with support for multiple ASR models and speaker diarization.

![macOS](https://img.shields.io/badge/macOS-13.0+-blue)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-M1/M2/M3/M4-green)
![Version](https://img.shields.io/badge/version-0.9.0--beta.1-orange)
![License](https://img.shields.io/badge/License-MIT-yellow)

## Features

### Core Features
- **Global Hotkey Activation** - Customizable hotkey to start/stop dictation
- **Cancel Recording Hotkey** - Discard recording without transcription
- **100% Local Processing** - All audio processed on-device, never sent to servers
- **Smart Text Insertion** - Automatically pastes transcribed text into any app
- **Recording Overlay** - Unobtrusive indicator showing recording status
- **Clipboard Preservation** - Optionally restore clipboard after paste

### ASR Models
- **NVIDIA Parakeet TDT v3** - Fast, multilingual (25 European languages), MPS-accelerated
- **OpenAI Whisper** - Multiple sizes (tiny, base, small, medium, large) with word-level timestamps

### Advanced Features
- **Speaker Diarization** - Identify different speakers using pyannote.audio
- **Capture to Notes** - Send transcriptions directly to Apple Notes
- **Continuous Capture Mode** - 15-second interval recording for meetings/lectures
- **Multiple Audio Devices** - Separate device selection for Dictation vs Capture to Notes
- **Keep Model Warm** - Preload model for faster first transcription
- **Usage Statistics** - Track daily, weekly, and total dictations

### Developer Features
- **Developer Mode** - Detailed logging for debugging
- **File-based Logging** - Logs stored in `~/Library/Application Support/Mute/`

## Quick Start

### Prerequisites
- macOS 13.0 (Ventura) or later
- Apple Silicon Mac (M1/M2/M3/M4)
- Python 3.11+ (for the ASR backend)
- Xcode 15+ (for building)

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/ICODOS/Mute.git
   cd Mute
   ```

2. **Set up the Python backend**
   ```bash
   ./setup_backend.sh
   ```
   This installs PyTorch, ASR models, and dependencies.

3. **Open in Xcode**
   ```bash
   open Mute.xcodeproj
   ```

4. **Build and run** (Cmd+R in Xcode)

5. **Grant permissions**
   - Microphone access (for recording)
   - Accessibility access (for text paste simulation)
   - Apple Events (for Capture to Notes feature)

6. **Download a model**
   - Click the menu bar icon > Settings > Model tab
   - Select and download your preferred model

## Usage

### Dictation Mode
1. Press your configured hotkey (default: Cmd+Shift+Space) to start recording
2. Speak into your microphone
3. Press the hotkey again to stop and transcribe
4. Text is automatically pasted into the active text field

### Capture to Notes
1. Enable Capture to Notes in Settings
2. Start recording - transcriptions are sent to Apple Notes
3. Continuous mode sends text every 15 seconds

### Cancel Recording
- Press the cancel hotkey to discard the current recording without transcription

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    Mute App (Swift)                  │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────┐  │
│  │  SwiftUI    │  │ Audio Engine │  │  Services  │  │
│  │  Interface  │  │ (AVAudio)    │  │  (Notes,   │  │
│  │             │  │              │  │   Paste)   │  │
│  └─────────────┘  └──────────────┘  └────────────┘  │
│         │                │                 ▲         │
│         ▼                ▼                 │         │
│  ┌─────────────────────────────────────────┴───────┐ │
│  │              WebSocket Client                    │ │
│  └─────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────┘
                          │
                          ▼ localhost:9877
┌─────────────────────────────────────────────────────┐
│              Python ASR Backend                      │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────┐  │
│  │  Parakeet    │  │   Whisper    │  │ Pyannote  │  │
│  │  Engine      │  │   Engine     │  │ Diarize   │  │
│  └──────────────┘  └──────────────┘  └───────────┘  │
└─────────────────────────────────────────────────────┘
```

## Privacy

Mute is designed with privacy as a core principle:

- **All processing is local** - Audio never leaves your device
- **No telemetry** - No usage data is collected or sent
- **No accounts** - No sign-in required
- **Models stored locally** - Downloaded once, runs offline

## Troubleshooting

See [BUILD.md](BUILD.md) for detailed build instructions and troubleshooting.

Common issues:
- **Backend won't start**: Run `./setup_backend.sh` again
- **Model download fails**: Check internet connection, try again
- **Paste not working**: Enable Accessibility permission in System Settings
- **Bluetooth headset issues**: App auto-falls back to default microphone if device disconnects

## License

- **Mute**: MIT License
- **NVIDIA Parakeet Model**: CC-BY-4.0
- **OpenAI Whisper**: MIT License
- **Pyannote.audio**: MIT License

## Acknowledgments

- [NVIDIA NeMo](https://github.com/NVIDIA/NeMo) - ASR toolkit
- [OpenAI Whisper](https://github.com/openai/whisper) - Speech recognition
- [Pyannote.audio](https://github.com/pyannote/pyannote-audio) - Speaker diarization
- [Hugging Face](https://huggingface.co/) - Model hosting
