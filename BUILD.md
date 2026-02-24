# TinyDictate Build Instructions

Complete guide to building, testing, and packaging TinyDictate for macOS.

## Prerequisites

### Required Software
- **macOS 13.0 (Ventura) or later** - Required for deployment target
- **Xcode 15.0 or later** - Download from the Mac App Store
- **Python 3.11 or later** - For the ASR backend
- **Homebrew** (recommended) - For installing dependencies

### Installing Prerequisites

```bash
# Install Homebrew (if not already installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install Python 3.11+
brew install python@3.11

# Install XcodeGen (for generating Xcode project)
brew install xcodegen

# Verify installations
python3 --version  # Should show 3.11.x or later
xcodegen --version
```

## Project Setup

### Step 1: Set Up the Python Backend

The backend handles ASR (Automatic Speech Recognition) using NVIDIA's Parakeet model.

```bash
cd /path/to/TinyDictate

# Make the setup script executable
chmod +x setup_backend.sh

# Run the setup script
./setup_backend.sh
```

This script will:
1. Verify Python 3.11+ is installed
2. Create directories in `~/Library/Application Support/TinyDictate/`
3. Create a Python virtual environment with all dependencies
4. Install PyTorch, NeMo Toolkit, and other required packages
5. Create a launcher script for the backend

**Note:** The initial setup downloads ~2-3GB of dependencies (PyTorch, NeMo). This may take 10-30 minutes depending on your internet connection.

### Step 2: Generate the Xcode Project

```bash
cd /path/to/TinyDictate

# Generate Xcode project using XcodeGen
xcodegen generate
```

This creates `TinyDictate.xcodeproj` from the `project.yml` configuration.

### Step 3: Open in Xcode

```bash
open TinyDictate.xcodeproj
```

Or open Xcode and navigate to `File > Open` and select the project.

## Building the App

### Development Build

1. Open `TinyDictate.xcodeproj` in Xcode
2. Select the `TinyDictate` scheme in the toolbar
3. Select your target: `My Mac` (Apple Silicon)
4. Click **Build** (⌘B) or **Run** (⌘R)

### Release Build

1. Select **Product > Scheme > Edit Scheme...**
2. Change Build Configuration to **Release**
3. **Product > Build** (⌘B)

Or from command line:

```bash
xcodebuild -project TinyDictate.xcodeproj \
           -scheme TinyDictate \
           -configuration Release \
           -derivedDataPath build \
           build
```

The built app will be in `build/Build/Products/Release/TinyDictate.app`

## Code Signing

### For Development

1. Open the project in Xcode
2. Select the `TinyDictate` target
3. Go to **Signing & Capabilities**
4. Check "Automatically manage signing"
5. Select your Personal Team or Development Team

### For Distribution

For distributing outside the Mac App Store, you need:

1. **Apple Developer Program membership** ($99/year)
2. **Developer ID Application certificate**

Configure signing:

```bash
# In project.yml or Xcode:
CODE_SIGN_IDENTITY: "Developer ID Application: Your Name (TEAM_ID)"
DEVELOPMENT_TEAM: "YOUR_TEAM_ID"
```

## Notarization (Required for Distribution)

Apple requires notarization for apps distributed outside the App Store.

### Step 1: Create an Archive

```bash
xcodebuild -project TinyDictate.xcodeproj \
           -scheme TinyDictate \
           -configuration Release \
           -archivePath build/TinyDictate.xcarchive \
           archive
```

### Step 2: Export the App

```bash
xcodebuild -exportArchive \
           -archivePath build/TinyDictate.xcarchive \
           -exportOptionsPlist ExportOptions.plist \
           -exportPath build/export
```

Create `ExportOptions.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>YOUR_TEAM_ID</string>
</dict>
</plist>
```

### Step 3: Notarize

```bash
# Store credentials (one-time setup)
xcrun notarytool store-credentials "TinyDictate-Profile" \
    --apple-id "your@email.com" \
    --team-id "YOUR_TEAM_ID" \
    --password "app-specific-password"

# Submit for notarization
xcrun notarytool submit build/export/TinyDictate.app \
    --keychain-profile "TinyDictate-Profile" \
    --wait

# Staple the notarization ticket
xcrun stapler staple build/export/TinyDictate.app
```

## Creating a DMG Installer

```bash
# Create a DMG for distribution
hdiutil create -volname "TinyDictate" \
               -srcfolder build/export/TinyDictate.app \
               -ov \
               -format UDZO \
               build/TinyDictate-1.0.0.dmg

# For a nicer DMG with Applications symlink:
# 1. Create a temporary folder
mkdir -p build/dmg-contents
cp -R build/export/TinyDictate.app build/dmg-contents/
ln -s /Applications build/dmg-contents/Applications

# 2. Create DMG
hdiutil create -volname "TinyDictate" \
               -srcfolder build/dmg-contents \
               -ov \
               -format UDZO \
               build/TinyDictate-1.0.0.dmg

# 3. Clean up
rm -rf build/dmg-contents
```

## First Run Setup

When running TinyDictate for the first time:

1. **Grant Microphone Permission**
   - System will prompt for microphone access
   - Also accessible via: System Settings > Privacy & Security > Microphone

2. **Grant Accessibility Permission**
   - Required for paste simulation and global hotkey
   - System Settings > Privacy & Security > Accessibility
   - Add TinyDictate to the allowed apps

3. **Download the Model**
   - Open Settings (click menu bar icon > Settings)
   - Go to the **Model** tab
   - Click "Download Model"
   - Wait for the ~600MB model to download

## Troubleshooting

### Build Issues

**"KeyboardShortcuts package not found"**
```bash
# Reset package cache
rm -rf ~/Library/Caches/org.swift.swiftpm
xcodebuild -resolvePackageDependencies
```

**"Code signing error"**
- Ensure you have a valid signing identity in Xcode
- Check Keychain Access for valid certificates
- Try: `security find-identity -v -p codesigning`

### Runtime Issues

**"Backend failed to start"**
```bash
# Verify Python installation
which python3
python3 --version

# Test backend manually
~/Library/Application\ Support/TinyDictate/run_backend.sh --port 9877
```

**"Model download failed"**
- Check internet connection
- Verify disk space (need ~1GB free)
- Check Hugging Face Hub is accessible
- Look at logs in Settings > Advanced > View Logs

**"Paste not working"**
- Ensure Accessibility permission is granted
- Some apps (secure fields, Terminal) may block paste
- Text is always copied to clipboard as fallback

**"Microphone not detected"**
- Check System Settings > Sound > Input
- Ensure microphone permission is granted
- Try selecting a different audio device in Settings

### Logs Location

- App logs: Console.app, filter by "TinyDictate"
- Backend logs: `~/Library/Application Support/TinyDictate/backend.log`
- Enable Developer Mode in Settings for additional debug info

## Testing Checklist

### Unit Tests
```bash
# Run tests from command line
xcodebuild test -project TinyDictate.xcodeproj \
                -scheme TinyDictate \
                -destination 'platform=macOS'
```

### Manual QA Checklist

- [ ] Fresh install on clean system
- [ ] Microphone permission flow
- [ ] Accessibility permission flow
- [ ] Model download and progress
- [ ] Global hotkey registration
- [ ] Recording in various apps (Notes, TextEdit, Safari, VS Code)
- [ ] Paste into secure text fields (Password field in Safari)
- [ ] Clipboard preservation option
- [ ] Multiple monitors
- [ ] Overlay visibility and positioning
- [ ] Settings persistence across restarts
- [ ] Backend crash recovery
- [ ] Long recording sessions (5+ minutes)
- [ ] Rapid start/stop cycles
- [ ] Memory usage over time
- [ ] CPU usage during recording
- [ ] Hotkey conflicts with system shortcuts

### Performance Checklist

- [ ] Latency: First partial result < 1.5s after speech
- [ ] Latency: Final result < 0.5s after stop
- [ ] Memory: < 500MB during idle
- [ ] Memory: < 2GB during recording
- [ ] CPU: < 10% during idle
- [ ] Model load time: < 10s on M1/M2/M3/M4

## Project Structure

```
TinyDictate/
├── Package.swift           # Swift Package Manager config
├── project.yml             # XcodeGen configuration
├── setup_backend.sh        # Backend setup script
├── PLAN.md                 # Architecture document
├── BUILD.md                # This file
├── TinyDictate/            # Swift source code
│   ├── App/
│   │   ├── TinyDictateApp.swift
│   │   ├── AppDelegate.swift
│   │   └── AppState.swift
│   ├── Views/
│   │   ├── MenuBarView.swift
│   │   ├── SettingsView.swift
│   │   ├── OverlayPanel.swift
│   │   └── OnboardingView.swift
│   ├── Audio/
│   │   └── AudioCaptureManager.swift
│   ├── Backend/
│   │   └── BackendManager.swift
│   ├── Services/
│   │   ├── TextInsertionService.swift
│   │   └── PermissionManager.swift
│   ├── Info.plist
│   └── TinyDictate.entitlements
└── backend/                # Python ASR backend
    ├── main.py             # WebSocket server
    ├── asr_engine.py       # NeMo ASR inference
    ├── model_manager.py    # Model download/cache
    └── requirements.txt
```

## Dependencies

### Swift Dependencies
- **KeyboardShortcuts** (2.0.0+) - Global hotkey registration

### Python Dependencies
- **torch** (2.1.0+) - PyTorch for inference
- **nemo_toolkit[asr]** (1.22.0+) - NVIDIA NeMo for ASR
- **websockets** (12.0+) - WebSocket server
- **huggingface_hub** (0.20.0+) - Model downloading
- **numpy** (1.24.0+) - Numerical operations

### System Frameworks
- AVFoundation - Audio capture
- AppKit - UI, overlay, clipboard
- ApplicationServices - Accessibility, event posting
- Security - Secure input detection

## Licenses

- **TinyDictate**: MIT License
- **NVIDIA Parakeet Model**: CC-BY-4.0
- **KeyboardShortcuts**: MIT License
- **NeMo Toolkit**: Apache 2.0
- **PyTorch**: BSD License

## Support

For issues and feature requests, please file an issue on the project repository.
