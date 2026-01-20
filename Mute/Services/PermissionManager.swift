// PermissionManager.swift
// Mute

import AVFoundation
import AppKit

class PermissionManager {
    
    // MARK: - Microphone Permission
    func hasMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return false
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
    
    func requestMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        
        switch status {
        case .authorized:
            return true
            
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    Logger.shared.log("Microphone permission: \(granted ? "granted" : "denied")")
                    continuation.resume(returning: granted)
                }
            }
            
        case .denied, .restricted:
            Logger.shared.log("Microphone permission denied/restricted", level: .warning)
            return false
            
        @unknown default:
            return false
        }
    }
    
    // MARK: - Accessibility Permission
    func hasAccessibilityPermission() -> Bool {
        return AXIsProcessTrusted()
    }
    
    func requestAccessibilityPermission() {
        // We can only prompt by showing the system dialog
        // This will show the accessibility prompt
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        Logger.shared.log("Accessibility permission requested, currently: \(trusted ? "granted" : "not granted")")
    }
    
    func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    
    // MARK: - Combined Check
    func checkAllPermissions() async -> PermissionStatus {
        let microphoneGranted = await hasMicrophonePermission()
        let accessibilityGranted = hasAccessibilityPermission()
        
        return PermissionStatus(
            microphone: microphoneGranted,
            accessibility: accessibilityGranted
        )
    }
}

// MARK: - Permission Status
struct PermissionStatus {
    let microphone: Bool
    let accessibility: Bool
    
    var allGranted: Bool {
        return microphone && accessibility
    }
    
    var canRecord: Bool {
        return microphone
    }
    
    var canPaste: Bool {
        return accessibility
    }
}
