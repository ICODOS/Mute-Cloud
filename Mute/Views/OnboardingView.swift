// OnboardingView.swift
// Mute

import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentStep = 0
    @Environment(\.dismiss) private var dismiss
    
    private let totalSteps = 4
    
    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            HStack(spacing: 8) {
                ForEach(0..<totalSteps, id: \.self) { step in
                    Circle()
                        .fill(step <= currentStep ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 20)
            
            // Content
            TabView(selection: $currentStep) {
                WelcomeStep()
                    .tag(0)
                
                MicrophonePermissionStep()
                    .tag(1)
                
                AccessibilityPermissionStep()
                    .tag(2)
                
                APIKeySetupStep()
                    .tag(3)
            }
            .tabViewStyle(.automatic)
            .frame(maxHeight: .infinity)
            
            // Navigation buttons
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation {
                            currentStep -= 1
                        }
                    }
                    .buttonStyle(.bordered)
                }
                
                Spacer()
                
                if currentStep < totalSteps - 1 {
                    Button("Next") {
                        withAnimation {
                            currentStep += 1
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Get Started") {
                        completeOnboarding()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
        .frame(width: 500, height: 450)
    }
    
    private func completeOnboarding() {
        appState.hasCompletedOnboarding = true
        dismiss()
    }
}

// MARK: - Welcome Step
struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "mic.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)
            
            Text("Welcome to Mute")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Cloud speech-to-text powered by Groq")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "bolt.fill", title: "Fast & Accurate", description: "State-of-the-art Whisper V3 Turbo")
                FeatureRow(icon: "keyboard", title: "Global Hotkey", description: "Start dictating from any app")
                FeatureRow(icon: "doc.on.clipboard", title: "Auto-Paste", description: "Text is automatically inserted")
                FeatureRow(icon: "wand.and.stars", title: "Smart Modes", description: "Transform text with AI")
            }
            .padding(.top, 10)
        }
        .padding(40)
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Microphone Permission Step
struct MicrophonePermissionStep: View {
    @EnvironmentObject var appState: AppState
    @State private var permissionStatus: String = "Not Requested"
    @State private var hasPermission = false
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "mic.badge.plus")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)
            
            Text("Microphone Access")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Mute needs access to your microphone to transcribe your speech.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            HStack {
                Circle()
                    .fill(hasPermission ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)
                Text(permissionStatus)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 10)
            
            if !hasPermission {
                Button("Request Microphone Access") {
                    requestPermission()
                }
                .buttonStyle(.borderedProminent)
            } else {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Microphone access granted!")
                }
            }
            
            Text("Audio is sent to Groq for transcription.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(40)
        .onAppear {
            checkPermission()
        }
    }
    
    private func checkPermission() {
        Task {
            hasPermission = await appState.permissionManager.hasMicrophonePermission()
            permissionStatus = hasPermission ? "Granted" : "Not Granted"
        }
    }
    
    private func requestPermission() {
        Task {
            hasPermission = await appState.permissionManager.requestMicrophonePermission()
            permissionStatus = hasPermission ? "Granted" : "Denied"
        }
    }
}

// MARK: - Accessibility Permission Step
struct AccessibilityPermissionStep: View {
    @EnvironmentObject var appState: AppState
    @State private var hasPermission = false
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)
            
            Text("Accessibility Access")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Mute needs Accessibility access to paste text into other apps.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            HStack {
                Circle()
                    .fill(hasPermission ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)
                Text(hasPermission ? "Granted" : "Not Granted")
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 10)
            
            VStack(spacing: 12) {
                if !hasPermission {
                    Text("To enable:")
                        .fontWeight(.medium)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. Click 'Open System Settings' below")
                        Text("2. Find Mute in the list")
                        Text("3. Toggle the switch to enable")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    
                    Button("Open System Settings") {
                        openAccessibilitySettings()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Accessibility access granted!")
                    }
                }
            }
            
            Text("Without this permission, text will only be copied to clipboard.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 10)
        }
        .padding(40)
        .onAppear {
            checkPermission()
        }
    }
    
    private func checkPermission() {
        hasPermission = appState.permissionManager.hasAccessibilityPermission()
    }
    
    private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        
        // Poll for permission changes
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if appState.permissionManager.hasAccessibilityPermission() {
                hasPermission = true
                timer.invalidate()
            }
        }
    }
}

// MARK: - API Key Setup Step
struct APIKeySetupStep: View {
    @EnvironmentObject var appState: AppState
    @State private var apiKeyInput: String = ""
    @State private var hasStoredKey: Bool = false
    @State private var validationStatus: String = ""

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("Groq API Key")
                .font(.title2)
                .fontWeight(.bold)

            Text("Mute uses Groq's cloud API for fast, accurate transcription. You'll need a free API key to get started.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                HStack {
                    SecureField("gsk_...", text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)

                    if !apiKeyInput.isEmpty {
                        Button("Save") {
                            saveAPIKey()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .frame(width: 300)

                // Status indicator
                HStack {
                    Circle()
                        .fill(hasStoredKey ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(hasStoredKey ? "API key saved" : (validationStatus.isEmpty ? "No API key configured" : validationStatus))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Get API Key link
                Button(action: {
                    NSWorkspace.shared.open(URL(string: "https://console.groq.com/keys")!)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                        Text("Get a free API key from Groq Console")
                            .font(.caption)
                    }
                }
                .buttonStyle(.link)
            }

            Text("You can set this up later in Settings.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(40)
        .onAppear {
            refreshKeyStatus()
        }
    }

    private func saveAPIKey() {
        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if KeychainManager.shared.setGroqAPIKey(trimmed) {
            hasStoredKey = true
            validationStatus = ""
            apiKeyInput = ""
        } else {
            validationStatus = "Failed to save key"
        }
    }

    private func refreshKeyStatus() {
        hasStoredKey = KeychainManager.shared.getGroqAPIKey() != nil
    }
}
