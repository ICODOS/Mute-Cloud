# TinyDictate

A local, privacy-focused dictation app for macOS that uses NVIDIA's Parakeet TDT v3 model for fast, accurate speech-to-text.

![macOS](https://img.shields.io/badge/macOS-13.0+-blue)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-M1/M2/M3/M4-green)
![License](https://img.shields.io/badge/License-MIT-yellow)

## Features

- **🎤 Global Hotkey Activation** - Press Cmd+Shift+Space (customizable) to start/stop dictation
- **⚡ Low Latency Streaming** - See partial transcriptions as you speak
- **🔒 100% Local Processing** - No internet required after initial model download
- **📋 Smart Text Insertion** - Automatically pastes transcribed text into any app
- **🎯 Tiny Overlay Indicator** - Unobtrusive recording status at screen corner
- **⚙️ Configurable Quality Presets** - Balance between speed and accuracy

## Quick Start

### Prerequisites
- macOS 13.0 (Ventura) or later
- Apple Silicon Mac (M1/M2/M3/M4)
- Python 3.11+ (for the ASR backend)
- Xcode 15+ (for building)

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/TinyDictate.git
   cd TinyDictate
   ```

2. **Set up the Python backend**
   ```bash
   ./setup_backend.sh
   ```
   This installs PyTorch, NeMo Toolkit, and other dependencies (~2-3GB download).

3. **Generate Xcode project**
   ```bash
   brew install xcodegen  # if not installed
   xcodegen generate
   ```

4. **Build and run**
   ```bash
   open TinyDictate.xcodeproj
   # Press Cmd+R in Xcode
   ```

5. **Grant permissions**
   - Microphone access (system prompt)
   - Accessibility access (for paste simulation)

6. **Download the model**
   - Click the menu bar icon > Settings > Model tab
   - Click "Download Model" (~600MB)

## Usage

1. Press **Cmd+Shift+Space** to start recording
2. Speak clearly into your microphone
3. Press **Cmd+Shift+Space** again to stop
4. Transcribed text is automatically pasted into the active text field

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                  TinyDictate App                     │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────┐  │
│  │  SwiftUI    │  │ Audio Engine │  │  Text      │  │
│  │  Menu Bar   │  │ (AVAudio)    │  │  Insertion │  │
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
│  ┌─────────────┐  ┌──────────────┐  ┌────────────┐  │
│  │  WebSocket  │  │ NeMo ASR     │  │  Model     │  │
│  │  Server     │──│ Engine       │──│  Manager   │  │
│  └─────────────┘  └──────────────┘  └────────────┘  │
└─────────────────────────────────────────────────────┘
```

## Configuration

### Settings

| Setting | Description | Default |
|---------|-------------|---------|
| Hotkey | Global shortcut to toggle recording | Cmd+Shift+Space |
| Quality Preset | Ultra Low Latency / Balanced / High Accuracy | Balanced |
| Audio Device | Input microphone | System Default |
| Auto-paste | Paste text after transcription | On |
| Preserve Clipboard | Restore previous clipboard after paste | Off |
| Show Overlay | Display recording indicator | On |

### Quality Presets

| Preset | Chunk Size | Latency | Accuracy |
|--------|------------|---------|----------|
| Ultra Low Latency | 200ms | ~500ms | Good |
| Balanced | 400ms | ~800ms | Better |
| High Accuracy | 800ms | ~1.2s | Best |

## Privacy

TinyDictate is designed with privacy as a core principle:

- **All processing is local** - Audio never leaves your device
- **No telemetry** - No usage data is collected or sent
- **No accounts** - No sign-in required
- **Model stored locally** - Downloaded once, runs offline forever

## Troubleshooting

See [BUILD.md](BUILD.md) for detailed troubleshooting steps.

Common issues:
- **Backend won't start**: Run `./setup_backend.sh` again
- **Model download fails**: Check internet connection, try again
- **Paste not working**: Enable Accessibility permission in System Settings
- **Low accuracy**: Try "High Accuracy" preset, check microphone levels

## License

- **TinyDictate**: MIT License
- **NVIDIA Parakeet Model**: CC-BY-4.0
- **NeMo Toolkit**: Apache 2.0

## Acknowledgments

- [NVIDIA NeMo](https://github.com/NVIDIA/NeMo) - ASR toolkit
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) - Global hotkey handling
- [Hugging Face](https://huggingface.co/) - Model hosting

## Contributing

Contributions are welcome! Please read our contributing guidelines before submitting a PR.

## Support

For issues and feature requests, please open an issue on GitHub.
