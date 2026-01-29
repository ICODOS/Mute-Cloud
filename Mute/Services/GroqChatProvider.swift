// GroqChatProvider.swift
// Mute

import Foundation

/// Groq Chat Completion API provider for text transformation
/// Uses GPT OSS models to transform transcribed text based on user prompts
final class GroqChatProvider {
    // MARK: - Constants

    private let apiEndpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions")!

    /// Request timeout in seconds
    private let requestTimeout: TimeInterval = 60

    /// Maximum retries for transient errors
    private let maxRetries = 2

    /// Delay between retries (seconds)
    private let retryDelay: TimeInterval = 1.0

    /// Default temperature for chat completions
    private let defaultTemperature: Double = 0.7

    /// Default maximum tokens for response
    private let defaultMaxTokens: Int = 4096

    // MARK: - Singleton

    static let shared = GroqChatProvider()

    private init() {}

    // MARK: - Public API

    /// Transforms text using a Groq chat model
    /// - Parameters:
    ///   - text: The text to transform (typically transcribed audio)
    ///   - prompt: The system prompt describing how to transform the text
    ///   - model: The model ID to use (e.g., "openai/gpt-oss-20b")
    ///   - temperature: Controls output randomness (0.0-1.0). Lower = more consistent.
    ///   - maxTokens: Maximum response length in tokens.
    /// - Returns: The transformed text
    func transform(
        text: String,
        prompt: String,
        model: String,
        temperature: Double? = nil,
        maxTokens: Int? = nil
    ) async throws -> String {
        guard let apiKey = KeychainManager.shared.getGroqAPIKey(), !apiKey.isEmpty else {
            throw TranscriptionError.missingAPIKey
        }

        let effectiveTemperature = temperature ?? defaultTemperature
        let effectiveMaxTokens = maxTokens ?? defaultMaxTokens

        // Build request
        var request = URLRequest(url: apiEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = requestTimeout

        // Build request body
        let requestBody = ChatCompletionRequest(
            model: model,
            messages: [
                ChatMessage(role: "system", content: prompt),
                ChatMessage(role: "user", content: text)
            ],
            temperature: effectiveTemperature,
            maxTokens: effectiveMaxTokens
        )

        request.httpBody = try JSONEncoder().encode(requestBody)

        Logger.shared.log("GroqChatProvider: Sending transformation request with model \(model), temp=\(effectiveTemperature), maxTokens=\(effectiveMaxTokens)")

        // Execute with retries
        var lastError: Error?
        for attempt in 0...maxRetries {
            if attempt > 0 {
                Logger.shared.log("GroqChatProvider: Retry attempt \(attempt)/\(maxRetries)")
                try await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
            }

            do {
                let result = try await executeRequest(request)
                Logger.shared.log("GroqChatProvider: Transformation successful (\(result.count) chars)")
                return result
            } catch let error as TranscriptionError {
                lastError = error

                // Don't retry for certain errors
                switch error {
                case .invalidAPIKey, .missingAPIKey:
                    throw error
                case .cancelled:
                    throw error
                case .serverError(let statusCode, _) where statusCode >= 400 && statusCode < 500:
                    // Don't retry client errors (except 429 rate limit)
                    if statusCode != 429 {
                        throw error
                    }
                default:
                    continue
                }
            } catch {
                lastError = error
            }
        }

        throw lastError ?? TranscriptionError.unknown(message: "Request failed after \(maxRetries) retries")
    }

    // MARK: - Request Execution

    private func executeRequest(_ request: URLRequest) async throws -> String {
        let (data, response): (Data, URLResponse)

        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .cancelled:
                throw TranscriptionError.cancelled
            case .timedOut:
                throw TranscriptionError.timeout
            case .notConnectedToInternet, .networkConnectionLost:
                throw TranscriptionError.networkError(underlying: error)
            default:
                throw TranscriptionError.networkError(underlying: error)
            }
        } catch {
            throw TranscriptionError.networkError(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            // Parse response
            do {
                let chatResponse = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
                guard let content = chatResponse.choices.first?.message.content else {
                    throw TranscriptionError.invalidResponse
                }
                return content.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                Logger.shared.log("GroqChatProvider: Failed to parse response: \(error)", level: .error)
                throw TranscriptionError.invalidResponse
            }

        case 401:
            throw TranscriptionError.invalidAPIKey

        case 429:
            let message = extractErrorMessage(from: data) ?? "Rate limit exceeded. Please try again later."
            throw TranscriptionError.serverError(statusCode: 429, message: message)

        default:
            let message = extractErrorMessage(from: data) ?? "Unknown error"
            Logger.shared.log("GroqChatProvider: Server error \(httpResponse.statusCode): \(message)", level: .error)
            throw TranscriptionError.serverError(statusCode: httpResponse.statusCode, message: message)
        }
    }

    /// Extracts error message from JSON response
    private func extractErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return String(data: data, encoding: .utf8)?.prefix(200).description
        }
        return message
    }
}

// MARK: - Request/Response Models

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
    }
}

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: ChatMessage
    }
}
