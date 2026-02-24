// TranscriptionMode.swift
// Mute

import Foundation

/// A user-defined transcription mode that combines a prompt and model for text transformation
struct TranscriptionMode: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var prompt: String
    var modelId: String  // "none", "openai/gpt-oss-20b", "openai/gpt-oss-120b"
    var isBuiltIn: Bool
    var temperature: Double  // 0.0 - 1.0, controls output consistency
    var maxTokens: Int       // Maximum response length

    init(
        id: UUID = UUID(),
        name: String,
        prompt: String,
        modelId: String,
        isBuiltIn: Bool = false,
        temperature: Double = TemperaturePreset.creative.rawValue,
        maxTokens: Int = MaxTokensPreset.long.rawValue
    ) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.modelId = modelId
        self.isBuiltIn = isBuiltIn
        self.temperature = temperature
        self.maxTokens = maxTokens
    }

    /// The default "None" mode that passes through transcription unchanged
    static let none = TranscriptionMode(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
        name: "None",
        prompt: "",
        modelId: TransformationModel.none.rawValue,
        isBuiltIn: true,
        temperature: TemperaturePreset.creative.rawValue,
        maxTokens: MaxTokensPreset.long.rawValue
    )

    /// Whether this mode will transform the transcription
    var hasTransformation: Bool {
        modelId != TransformationModel.none.rawValue && !prompt.isEmpty
    }
}

// MARK: - Temperature Presets

/// Preset temperature values for text transformation
enum TemperaturePreset: Double, CaseIterable, Identifiable {
    case precise = 0.2       // Very consistent, deterministic
    case balanced = 0.5      // Some variation, predictable
    case creative = 0.7      // More variation (default)
    case experimental = 1.0  // Maximum variation

    var id: Double { rawValue }

    var displayName: String {
        switch self {
        case .precise:
            return "Precise"
        case .balanced:
            return "Balanced"
        case .creative:
            return "Creative"
        case .experimental:
            return "Experimental"
        }
    }

    var description: String {
        switch self {
        case .precise:
            return "Very consistent output, best for formatting and grammar"
        case .balanced:
            return "Some variation while staying predictable"
        case .creative:
            return "More natural variation in output"
        case .experimental:
            return "Maximum creativity and variation"
        }
    }

    /// Find the closest preset for a given temperature value
    static func closest(to value: Double) -> TemperaturePreset {
        allCases.min(by: { abs($0.rawValue - value) < abs($1.rawValue - value) }) ?? .creative
    }
}

// MARK: - Max Tokens Presets

/// Preset max token values for response length
enum MaxTokensPreset: Int, CaseIterable, Identifiable {
    case short = 1024       // ~750 words
    case medium = 2048      // ~1500 words
    case long = 4096        // ~3000 words (default)
    case veryLong = 50000   // Maximum output

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .short:
            return "Short"
        case .medium:
            return "Medium"
        case .long:
            return "Long"
        case .veryLong:
            return "Maximum"
        }
    }

    var description: String {
        switch self {
        case .short:
            return "~750 words, for quick summaries"
        case .medium:
            return "~1,500 words, for standard responses"
        case .long:
            return "~3,000 words, for detailed output"
        case .veryLong:
            return "Maximum output length"
        }
    }

    /// Find the closest preset for a given token value
    static func closest(to value: Int) -> MaxTokensPreset {
        allCases.min(by: { abs($0.rawValue - value) < abs($1.rawValue - value) }) ?? .long
    }
}

/// Available GPT models for text transformation via Groq
enum TransformationModel: String, CaseIterable, Identifiable {
    case none = "none"
    case gptOss20b = "openai/gpt-oss-20b"
    case gptOss120b = "openai/gpt-oss-120b"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:
            return "None (Pass-through)"
        case .gptOss20b:
            return "GPT OSS 20B (Faster)"
        case .gptOss120b:
            return "GPT OSS 120B (Higher Quality)"
        }
    }

    var description: String {
        switch self {
        case .none:
            return "Don't transform the transcription"
        case .gptOss20b:
            return "Fast model for quick transformations"
        case .gptOss120b:
            return "Larger model for complex transformations"
        }
    }
}
