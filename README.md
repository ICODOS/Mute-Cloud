# Mute

A privacy-focused speech-to-text app for macOS with support for multiple ASR models, speaker diarization, and optional cloud transcription.

![macOS](https://img.shields.io/badge/macOS-13.0+-blue)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-M1/M2/M3/M4-green)
![Version](https://img.shields.io/badge/version-1.2.0-orange)
![License](https://img.shields.io/badge/License-MIT-yellow)

## Features

### Core Features
- **Global Hotkey Activation** - Customizable hotkey to start/stop dictation
- **Cancel Recording Hotkey** - Discard recording without transcription
- **Local Processing by Default** - All audio processed on-device, never sent to servers
- **Optional Cloud Transcription** - Fast cloud transcription via Groq Whisper V3 Turbo
- **Smart Text Insertion** - Automatically pastes transcribed text into any app
- **Recording Overlay** - Unobtrusive indicator showing recording status
- **Clipboard Preservation** - Optionally restore clipboard after paste

### ASR Models
- **NVIDIA Parakeet TDT v3** - Fast, multilingual (25 European languages), MPS-accelerated
- **OpenAI Whisper** - Multiple sizes (tiny, base, small, medium, large) with word-level timestamps
- **Groq Whisper V3 Turbo** - Cloud-based, fast inference, requires API key

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

## Cloud Transcription (Groq)

Mute supports optional cloud transcription using Groq's Whisper V3 Turbo API for fast inference.

### Setup

1. **Create a Groq Account**
   - Go to [console.groq.com](https://console.groq.com)
   - Create an account and navigate to API Keys

2. **Get an API Key**
   - Create a new API key in the Groq Console
   - For higher rate limits, add billing (Developer tier)
   - Supported payment methods: Credit card, US bank, SEPA debit

3. **Configure in Mute**
   - Open Settings > Cloud tab
   - Select "Cloud: Groq - Whisper V3 Turbo" as the transcription backend
   - Paste your API key (stored securely in macOS Keychain)

### Billing Notes

- Groq bills minimum **10 seconds per request** - short recordings (<10s) are billed as 10s
- Free tier: 25 MB max upload per request
- Developer tier: 100 MB max upload per request
- Typical dictation (<60s) fits in a single request

### Privacy

When using cloud transcription:
- Audio is sent to Groq's servers for processing
- API key is stored in macOS Keychain (not UserDefaults)
- Local transcription remains the default option

## Cloud Transcription Test Checklist

Use this checklist to verify cloud transcription is working correctly:

- [ ] **Missing API Key**
  - Select Groq backend without configuring API key
  - Expected: Error message "Groq API key is not configured"
  - Recording should not start

- [ ] **Invalid API Key**
  - Configure an invalid API key (e.g., "invalid_key")
  - Expected: Error message about invalid API key format

- [ ] **Wrong API Key (Valid Format)**
  - Configure a fake key starting with "gsk_"
  - Start recording, speak for 5s, stop
  - Expected: Error "Invalid API key" from Groq API

- [ ] **Offline / Network Error**
  - Disable network connection
  - Start recording, speak for 5s, stop
  - Expected: Network error message, recording not lost

- [ ] **Successful Transcription**
  - Configure valid Groq API key
  - Start recording, speak clearly for 10-20s, stop
  - Expected: Transcription returned and pasted to active app

- [ ] **Short Recording (<10s)**
  - Record for 3-5 seconds
  - Expected: Works correctly (note: still billed as 10s by Groq)

- [ ] **Cancel During Transcription**
  - Start recording, speak for 5s, stop
  - While "Transcribing..." is shown, cancel
  - Expected: Transcription cancelled, state reset to idle

- [ ] **Backend Switching**
  - Switch from Local to Groq, make a recording
  - Switch back to Local, make another recording
  - Expected: Both backends work independently

## Architecture

```
┌───────────────────────────────────────────────────────────────┐
│                       Mute App (Swift)                         │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────┐            │
│  │  SwiftUI    │  │ Audio Engine │  │  Services  │            │
│  │  Interface  │  │ (AVAudio)    │  │  (Notes,   │            │
│  │             │  │              │  │   Paste)   │            │
│  └─────────────┘  └──────────────┘  └────────────┘            │
│         │                │                 ▲                   │
│         ▼                ▼                 │                   │
│  ┌────────────────────────┴────────────────┴─────────────┐    │
│  │                  Transcription Router                  │    │
│  │   ┌─────────────────┐     ┌─────────────────────┐     │    │
│  │   │  Local Backend  │     │   Cloud Provider    │     │    │
│  │   │  (WebSocket)    │     │  (Groq HTTP API)    │     │    │
│  │   └─────────────────┘     └─────────────────────┘     │    │
│  └───────────────────────────────────────────────────────┘    │
└───────────────────────────────────────────────────────────────┘
           │                              │
           ▼ localhost:9877               ▼ HTTPS
┌──────────────────────────┐    ┌──────────────────────────┐
│   Python ASR Backend     │    │     Groq Cloud API       │
│ ┌────────┐ ┌───────────┐ │    │  ┌───────────────────┐   │
│ │Parakeet│ │  Whisper  │ │    │  │ Whisper V3 Turbo  │   │
│ │        │ │  (local)  │ │    │  │                   │   │
│ └────────┘ └───────────┘ │    │  └───────────────────┘   │
└──────────────────────────┘    └──────────────────────────┘
```

## Privacy

Mute is designed with privacy as a core principle:

- **Local mode (default)** - All audio processed on-device, never sent to servers
- **Cloud mode (opt-in)** - Audio sent to Groq servers only when cloud backend is selected
- **No telemetry** - No usage data is collected or sent
- **No accounts** - No sign-in required (Groq account only for cloud mode)
- **Secure key storage** - API keys stored in macOS Keychain, not plain text
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
- **Groq API**: Proprietary (requires API key and agreement to Groq Terms of Service)
- **Pyannote.audio**: MIT License

## Acknowledgments

- [NVIDIA NeMo](https://github.com/NVIDIA/NeMo) - ASR toolkit
- [OpenAI Whisper](https://github.com/openai/whisper) - Speech recognition
- [Groq](https://groq.com/) - Cloud inference API
- [Pyannote.audio](https://github.com/pyannote/pyannote-audio) - Speaker diarization
- [Hugging Face](https://huggingface.co/) - Model hosting
