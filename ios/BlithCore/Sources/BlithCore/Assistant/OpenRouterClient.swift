import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// OpenAI-compatible chat message.
public struct LLMMessage: Codable, Sendable, Hashable {
    public struct ToolCall: Codable, Sendable, Hashable {
        public struct Function: Codable, Sendable, Hashable {
            public var name: String
            public var arguments: String
        }
        public var id: String
        public var type: String
        public var function: Function
    }

    public var role: String
    public var content: String?
    public var tool_calls: [ToolCall]?
    public var tool_call_id: String?

    public init(role: String, content: String?, tool_calls: [ToolCall]? = nil, tool_call_id: String? = nil) {
        self.role = role
        self.content = content
        self.tool_calls = tool_calls
        self.tool_call_id = tool_call_id
    }

    public static func system(_ s: String) -> LLMMessage { LLMMessage(role: "system", content: s) }
    public static func user(_ s: String) -> LLMMessage { LLMMessage(role: "user", content: s) }
    public static func assistant(_ s: String) -> LLMMessage { LLMMessage(role: "assistant", content: s) }
}

public protocol ChatCompletionClient: Sendable {
    func complete(messages: [LLMMessage], tools: [ToolDefinition]) async throws -> LLMMessage
}

public enum AssistantError: Error, LocalizedError, Sendable {
    case missingAPIKey
    case http(Int, String)
    case emptyResponse
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: "The AI service isn't configured."
        case .http(let code, let message): "The AI service returned an error (\(code)). \(message)"
        case .emptyResponse: "The AI service returned an empty answer."
        case .network(let m): "Couldn't reach the AI service. \(m)"
        }
    }
}

/// OpenRouter chat-completions client (OpenAI-compatible, tool calling).
public struct OpenRouterClient: ChatCompletionClient {
    /// Fast, low-cost default. Change here or via configuration.
    public static let defaultModel = "openai/gpt-6-luna"

    public let apiKey: String
    public let model: String
    public let endpoint: URL
    public let timeout: TimeInterval

    public init(apiKey: String, model: String = OpenRouterClient.defaultModel,
                endpoint: URL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!, timeout: TimeInterval = 45) {
        self.apiKey = apiKey
        self.model = model
        self.endpoint = endpoint
        self.timeout = timeout
    }

    struct RequestBody: Encodable {
        var model: String
        var messages: [LLMMessage]
        var tools: [JSONValue]?
        var tool_choice: String?
        var temperature: Double
        var max_tokens: Int
    }

    struct ResponseBody: Decodable {
        struct Choice: Decodable { var message: LLMMessage }
        struct APIError: Decodable { var message: String? }
        var choices: [Choice]?
        var error: APIError?
    }

    public func complete(messages: [LLMMessage], tools: [ToolDefinition]) async throws -> LLMMessage {
        guard !apiKey.isEmpty else { throw AssistantError.missingAPIKey }
        var request = URLRequest(url: endpoint, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://github.com/pixelbuyte/blith-health", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Blith", forHTTPHeaderField: "X-Title")
        let body = RequestBody(model: model, messages: messages, tools: tools.isEmpty ? nil : tools.map(\.json),
                               tool_choice: tools.isEmpty ? nil : "auto", temperature: 0.3, max_tokens: 1500)
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AssistantError.network(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let decoded = try? JSONDecoder().decode(ResponseBody.self, from: data)
        guard (200..<300).contains(status) else {
            throw AssistantError.http(status, decoded?.error?.message ?? String(decoding: data.prefix(300), as: UTF8.self))
        }
        if let message = decoded?.error?.message { throw AssistantError.http(status, message) }
        guard let message = decoded?.choices?.first?.message else { throw AssistantError.emptyResponse }
        return message
    }
}
