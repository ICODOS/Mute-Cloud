# TinyDictate QA Checklist

## Installation & Setup

### Fresh Install
- [ ] App opens without crash on first launch
- [ ] Onboarding flow displays correctly
- [ ] Menu bar icon appears
- [ ] Backend process starts automatically

### Permissions
- [ ] Microphone permission prompt appears
- [ ] Granting microphone permission works
- [ ] Denying microphone shows appropriate error
- [ ] Accessibility permission guidance is clear
- [ ] App functions in limited mode without accessibility
- [ ] Re-prompting after initial denial works

### Model Management
- [ ] Model download starts from Settings
- [ ] Progress bar updates during download
- [ ] Download can be cancelled
- [ ] Interrupted download can be resumed
- [ ] Model verification after download
- [ ] "Delete Model" removes cached files
- [ ] App works offline after model is downloaded

## Core Functionality

### Recording
- [ ] Hotkey starts recording
- [ ] Overlay appears when recording starts
- [ ] Audio level indicator shows input
- [ ] Recording works with default microphone
- [ ] Recording works with alternate microphone
- [ ] Hotkey stops recording
- [ ] Overlay updates to "processing" state

### Transcription
- [ ] Partial results appear during recording (if enabled)
- [ ] Final transcription is accurate
- [ ] Punctuation and capitalization are correct
- [ ] Long recordings (5+ minutes) complete successfully
- [ ] Very short recordings (<1 second) handle gracefully
- [ ] Silence is handled appropriately
- [ ] Multiple languages are recognized (if auto mode)

### Text Insertion
- [ ] Text is copied to clipboard after transcription
- [ ] Text is pasted into active text field
- [ ] Paste works in Notes app
- [ ] Paste works in TextEdit
- [ ] Paste works in Safari text fields
- [ ] Paste works in VS Code / other editors
- [ ] Clipboard preservation option works
- [ ] Toast notification appears when paste fails
- [ ] Secure text fields show appropriate warning

## User Interface

### Menu Bar
- [ ] Icon is visible and clear
- [ ] Menu opens on click
- [ ] Start/Stop action works
- [ ] Settings opens settings window
- [ ] Quit terminates app cleanly

### Overlay
- [ ] Positioned at top-left (default)
- [ ] Does not steal focus
- [ ] Shows "Recording" state with red dot
- [ ] Shows "Processing" state with spinner
- [ ] Shows "Done" state briefly
- [ ] Shows "Error" state when applicable
- [ ] Click-through behavior works
- [ ] Visible on active monitor (multi-monitor)
- [ ] Visible over fullscreen apps

### Settings Window
- [ ] Opens and closes correctly
- [ ] All tabs are accessible
- [ ] Hotkey recorder captures key combinations
- [ ] Quality presets change audio chunking
- [ ] Audio device selection shows available devices
- [ ] Toggle settings persist after restart
- [ ] Reset to defaults works
- [ ] Licenses section displays

## Edge Cases

### Error Handling
- [ ] No microphone connected shows error
- [ ] Backend crash during recording recovers
- [ ] Backend restart works
- [ ] Network error during model download shows error
- [ ] Disk full during model download shows error
- [ ] Invalid model cache is detected and re-downloaded

### Multi-Environment
- [ ] Works with multiple monitors
- [ ] Works in fullscreen apps
- [ ] Works across Spaces
- [ ] Frontmost app change mid-recording
- [ ] Hotkey conflict with system shortcut

### Resource Management
- [ ] Memory usage is stable over time
- [ ] No memory leaks during long sessions
- [ ] CPU usage is reasonable during idle
- [ ] CPU usage is acceptable during recording
- [ ] Backend process terminates on app quit

## Performance

### Latency Targets
- [ ] First partial: < 1.5s after speech begins
- [ ] Final result: < 0.5s after recording stops
- [ ] Model load time: < 10s on Apple Silicon

### Resource Limits
- [ ] Memory during idle: < 500MB
- [ ] Memory during recording: < 2GB
- [ ] CPU during idle: < 10%
- [ ] Disk usage for model: < 1GB

## Compatibility

### macOS Versions
- [ ] macOS 13 (Ventura)
- [ ] macOS 14 (Sonoma)
- [ ] macOS 15 (Sequoia)

### Hardware
- [ ] Apple M1
- [ ] Apple M2
- [ ] Apple M3
- [ ] Apple M4
- [ ] Various microphone types (built-in, USB, Bluetooth)

## Security & Privacy

- [ ] No network traffic except model download
- [ ] Audio is processed locally only
- [ ] No data sent to external servers
- [ ] Temporary audio files are cleaned up
- [ ] Model cache is in appropriate location

## Packaging & Distribution

### Build
- [ ] Release build compiles without warnings
- [ ] Backend files are bundled correctly
- [ ] Code signing succeeds
- [ ] Hardened runtime enabled

### Distribution
- [ ] Notarization succeeds
- [ ] Stapling succeeds
- [ ] DMG opens correctly
- [ ] App runs after drag-to-Applications
- [ ] Gatekeeper allows app to run

---

## Test Results Log

| Date | Tester | OS Version | Hardware | Notes |
|------|--------|------------|----------|-------|
|      |        |            |          |       |

## Known Issues

<!-- Document any known issues discovered during testing -->

## Sign-off

- [ ] All critical tests passed
- [ ] All major tests passed
- [ ] Known issues documented
- [ ] Ready for release

Tested by: _________________ Date: _________
