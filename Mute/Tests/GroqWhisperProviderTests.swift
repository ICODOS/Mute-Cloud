// GroqWhisperProviderTests.swift
// Mute Tests
//
// Unit tests for GroqWhisperProvider multipart form building and response parsing

import Foundation
@testable import Mute

// MARK: - Multipart Form Builder Tests

/// Tests for the multipart form data builder
struct MultipartFormBuilderTests {

    /// Test that multipart body includes all required fields
    static func testMultipartBodyContainsRequiredFields() -> Bool {
        let provider = GroqWhisperProvider()
        let testAudioData = Data([0x00, 0x01, 0x02, 0x03])
        let boundary = "TestBoundary123"

        let body = provider.buildMultipartBody(
            audioData: testAudioData,
            fileName: "test.wav",
            language: nil,
            prompt: nil,
            boundary: boundary
        )

        let bodyString = String(data: body, encoding: .utf8) ?? ""

        // Verify required fields
        let hasFile = bodyString.contains("name=\"file\"")
        let hasModel = bodyString.contains("name=\"model\"")
        let hasResponseFormat = bodyString.contains("name=\"response_format\"")
        let hasTemperature = bodyString.contains("name=\"temperature\"")
        let hasModelValue = bodyString.contains("whisper-large-v3-turbo")
        let hasFormatValue = bodyString.contains("text")
        let hasTempValue = bodyString.contains("\r\n0\r\n")
        let hasBoundaryStart = bodyString.contains("--TestBoundary123\r\n")
        let hasBoundaryEnd = bodyString.contains("--TestBoundary123--")

        let allPassed = hasFile && hasModel && hasResponseFormat && hasTemperature &&
                        hasModelValue && hasFormatValue && hasTempValue &&
                        hasBoundaryStart && hasBoundaryEnd

        print("testMultipartBodyContainsRequiredFields: \(allPassed ? "PASSED" : "FAILED")")
        if !allPassed {
            print("  hasFile: \(hasFile)")
            print("  hasModel: \(hasModel)")
            print("  hasResponseFormat: \(hasResponseFormat)")
            print("  hasTemperature: \(hasTemperature)")
            print("  hasModelValue: \(hasModelValue)")
            print("  hasFormatValue: \(hasFormatValue)")
            print("  hasTempValue: \(hasTempValue)")
            print("  hasBoundaryStart: \(hasBoundaryStart)")
            print("  hasBoundaryEnd: \(hasBoundaryEnd)")
        }

        return allPassed
    }

    /// Test that optional language field is included when provided
    static func testMultipartBodyIncludesLanguage() -> Bool {
        let provider = GroqWhisperProvider()
        let testAudioData = Data([0x00])
        let boundary = "TestBoundary"

        let body = provider.buildMultipartBody(
            audioData: testAudioData,
            fileName: "test.wav",
            language: "en",
            prompt: nil,
            boundary: boundary
        )

        let bodyString = String(data: body, encoding: .utf8) ?? ""
        let hasLanguage = bodyString.contains("name=\"language\"")
        let hasLanguageValue = bodyString.contains("\r\nen\r\n")

        let passed = hasLanguage && hasLanguageValue
        print("testMultipartBodyIncludesLanguage: \(passed ? "PASSED" : "FAILED")")
        return passed
    }

    /// Test that optional prompt field is included when provided
    static func testMultipartBodyIncludesPrompt() -> Bool {
        let provider = GroqWhisperProvider()
        let testAudioData = Data([0x00])
        let boundary = "TestBoundary"

        let body = provider.buildMultipartBody(
            audioData: testAudioData,
            fileName: "test.wav",
            language: nil,
            prompt: "SwiftUI, Xcode",
            boundary: boundary
        )

        let bodyString = String(data: body, encoding: .utf8) ?? ""
        let hasPrompt = bodyString.contains("name=\"prompt\"")
        let hasPromptValue = bodyString.contains("SwiftUI, Xcode")

        let passed = hasPrompt && hasPromptValue
        print("testMultipartBodyIncludesPrompt: \(passed ? "PASSED" : "FAILED")")
        return passed
    }

    /// Test that boundary is properly formatted
    static func testBoundaryFormatting() -> Bool {
        let provider = GroqWhisperProvider()
        let testAudioData = Data([0x00])
        let boundary = "----WebKitFormBoundary7MA4YWxkTrZu0gW"

        let body = provider.buildMultipartBody(
            audioData: testAudioData,
            fileName: "test.wav",
            language: nil,
            prompt: nil,
            boundary: boundary
        )

        let bodyString = String(data: body, encoding: .utf8) ?? ""

        // Check proper boundary formatting
        let hasCRLF = bodyString.contains("\r\n")
        let startsWithBoundary = bodyString.hasPrefix("--\(boundary)\r\n")
        let endsWithFinalBoundary = bodyString.hasSuffix("--\(boundary)--\r\n")

        let passed = hasCRLF && startsWithBoundary && endsWithFinalBoundary
        print("testBoundaryFormatting: \(passed ? "PASSED" : "FAILED")")
        if !passed {
            print("  hasCRLF: \(hasCRLF)")
            print("  startsWithBoundary: \(startsWithBoundary)")
            print("  endsWithFinalBoundary: \(endsWithFinalBoundary)")
        }
        return passed
    }

    /// Run all tests
    static func runAllTests() {
        print("\n=== GroqWhisperProvider Tests ===\n")

        var passed = 0
        var failed = 0

        if testMultipartBodyContainsRequiredFields() { passed += 1 } else { failed += 1 }
        if testMultipartBodyIncludesLanguage() { passed += 1 } else { failed += 1 }
        if testMultipartBodyIncludesPrompt() { passed += 1 } else { failed += 1 }
        if testBoundaryFormatting() { passed += 1 } else { failed += 1 }

        print("\n=== Results: \(passed) passed, \(failed) failed ===\n")
    }
}

// MARK: - Audio File Manager Tests

struct AudioFileManagerTests {

    /// Test WAV file creation
    static func testWAVFileCreation() -> Bool {
        let manager = AudioFileManager()

        // Create some test audio data (1 second of silence at 16kHz)
        let sampleCount = 16000
        var testSamples = [Float](repeating: 0.0, count: sampleCount)
        // Add a simple sine wave
        for i in 0..<sampleCount {
            testSamples[i] = sin(Float(i) * 2.0 * .pi * 440.0 / 16000.0) * 0.5
        }

        // Convert to Data
        let data = testSamples.withUnsafeBytes { Data($0) }
        manager.appendAudioData(data)

        // Verify duration
        let duration = manager.duration
        let durationCorrect = abs(duration - 1.0) < 0.01
        print("  Duration: \(duration) seconds (expected ~1.0)")

        // Write to file
        do {
            guard let fileURL = try manager.writeToWAVFile() else {
                print("testWAVFileCreation: FAILED - No file created")
                return false
            }

            // Verify file exists
            let fileExists = FileManager.default.fileExists(atPath: fileURL.path)

            // Verify file size (should be ~32KB for 1 second of 16-bit 16kHz audio)
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let fileSize = attributes[.size] as? Int ?? 0
            let expectedSize = 44 + (sampleCount * 2) // Header + 16-bit samples
            let sizeCorrect = abs(fileSize - expectedSize) < 100

            print("  File size: \(fileSize) bytes (expected ~\(expectedSize))")

            // Clean up
            AudioFileManager.deleteTemporaryFile(fileURL)

            let passed = durationCorrect && fileExists && sizeCorrect
            print("testWAVFileCreation: \(passed ? "PASSED" : "FAILED")")
            return passed

        } catch {
            print("testWAVFileCreation: FAILED - \(error)")
            return false
        }
    }

    /// Run all tests
    static func runAllTests() {
        print("\n=== AudioFileManager Tests ===\n")

        var passed = 0
        var failed = 0

        if testWAVFileCreation() { passed += 1 } else { failed += 1 }

        print("\n=== Results: \(passed) passed, \(failed) failed ===\n")
    }
}
