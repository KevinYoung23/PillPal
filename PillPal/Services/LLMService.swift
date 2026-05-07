import Foundation
import UIKit

final class LLMService {
    struct Configuration {
        var endpointURL: URL?
        var apiKey: String?
        var model: String

        static func load(bundle: Bundle = .main) -> Configuration {
            let configURL = bundle.url(forResource: "Config", withExtension: "plist")
                ?? bundle.url(forResource: "Config.example", withExtension: "plist")

            guard let url = configURL,
                  let data = try? Data(contentsOf: url),
                  let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
                  let dict = object as? [String: Any]
            else {
                return Configuration(
                    endpointURL: Self.defaultDeepSeekEndpoint,
                    apiKey: Self.resolveAPIKeyFromEnvironment(),
                    model: Self.fallbackModel
                )
            }

            let endpointString = (dict["LLMEndpointURL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let plistKey = (dict["LLMApiKey"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let model = (dict["LLMModel"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

            let resolvedEndpoint = Self.resolveEndpoint(from: endpointString)
            let resolvedKey = (plistKey?.isEmpty == false) ? plistKey : Self.resolveAPIKeyFromEnvironment()
            let resolvedModel = (model?.isEmpty == false) ? model! : Self.fallbackModel

            return Configuration(endpointURL: resolvedEndpoint, apiKey: resolvedKey, model: resolvedModel)
        }

        private static let defaultDeepSeekEndpoint = URL(string: "https://api.deepseek.com/chat/completions")!
        private static let fallbackModel = "deepseek-chat"

        private static func resolveAPIKeyFromEnvironment() -> String? {
            let env = ProcessInfo.processInfo.environment
            return env["DEEPSEEK_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? env["LLM_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? env["OPENAI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private static func resolveEndpoint(from endpointString: String?) -> URL {
            guard let endpointString,
                  let url = URL(string: endpointString)
            else {
                return defaultDeepSeekEndpoint
            }

            let normalizedPath = url.path.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalizedPath.isEmpty || normalizedPath == "/" || normalizedPath == "/v1" || normalizedPath == "/v1/" {
                var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                if normalizedPath == "/v1" || normalizedPath == "/v1/" {
                    components?.path = "/v1/chat/completions"
                } else {
                    components?.path = "/chat/completions"
                }
                return components?.url ?? defaultDeepSeekEndpoint
            }

            return url
        }
    }

    enum ExtractionError: LocalizedError {
        case apiKeyMissing
        case requestFailed(statusCode: Int, message: String?)
        case transportFailed(String)
        case responseNotJSON
        case decodeFailed

        var errorDescription: String? {
            switch self {
            case .apiKeyMissing:
                return "LLM API key not configured."
            case .requestFailed(let statusCode, let message):
                if let message, !message.isEmpty {
                    return "LLM request failed (\(statusCode)): \(message)"
                }
                return "LLM request failed (\(statusCode))."
            case .transportFailed(let message):
                return "Network error: \(message)"
            case .responseNotJSON:
                return "LLM response is not valid UTF-8 JSON."
            case .decodeFailed:
                return "Unable to decode structured LLM response."
            }
        }
    }

    private struct ChatCompletionsRequest: Codable {
        var model: String
        var messages: [ChatMessage]
        var responseFormat: ResponseFormat
        var temperature: Double
        var stream: Bool

        enum CodingKeys: String, CodingKey {
            case model
            case messages
            case responseFormat = "response_format"
            case temperature
            case stream
        }
    }

    private struct ResponseFormat: Codable {
        var type: String
    }

    private struct ChatMessage: Codable {
        var role: String
        var content: String
    }

    private struct ChatCompletionsResponse: Codable {
        var choices: [ChatCompletionChoice]?
    }

    private struct ChatCompletionChoice: Codable {
        var message: AssistantMessage
    }

    private struct AssistantMessage: Codable {
        var content: String
    }

    private struct ContentWrapper: Codable {
        var output: String?
        var content: String?
        var choices: [Choice]?
    }

    private struct Choice: Codable {
        var message: Message
    }

    private struct Message: Codable {
        var content: String
    }

    private struct APIErrorEnvelope: Codable {
        var error: APIErrorBody
    }

    private struct APIErrorBody: Codable {
        var message: String
    }

    private let configuration: Configuration
    private let session: URLSession

    private static let defaultDeepSeekEndpoint = URL(string: "https://api.deepseek.com/chat/completions")!
    private static let fallbackModel = "deepseek-chat"

    init(configuration: Configuration = .load(), session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    var isConfigured: Bool {
        normalizedAPIKey != nil
    }

    var endpointHost: String {
        let endpoint = configuration.endpointURL ?? Self.defaultDeepSeekEndpoint
        return endpoint.host ?? endpoint.absoluteString
    }

    func extract(ocrText: String, redactedImages: [UIImage]) async throws -> LLMExtractionResult {
        guard let apiKey = normalizedAPIKey else {
            throw ExtractionError.apiKeyMissing
        }

        let selectedModel = normalizedModel

        do {
            return try await performExtraction(
                ocrText: ocrText,
                redactedPageCount: redactedImages.count,
                apiKey: apiKey,
                model: selectedModel
            )
        } catch let error as ExtractionError where shouldRetryWithFallback(error: error, selectedModel: selectedModel) {
            Logger.warning("Retrying LLM extraction with fallback model \(Self.fallbackModel).")
            return try await performExtraction(
                ocrText: ocrText,
                redactedPageCount: redactedImages.count,
                apiKey: apiKey,
                model: Self.fallbackModel
            )
        }
    }

    private func performExtraction(
        ocrText: String,
        redactedPageCount: Int,
        apiKey: String,
        model: String
    ) async throws -> LLMExtractionResult {
        let endpointURL = configuration.endpointURL ?? Self.defaultDeepSeekEndpoint

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let payload = ChatCompletionsRequest(
            model: model,
            messages: buildMessages(ocrText: ocrText, redactedPageCount: redactedPageCount),
            responseFormat: ResponseFormat(type: "json_object"),
            temperature: 0,
            stream: false
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw ExtractionError.transportFailed(urlError.localizedDescription)
        } catch {
            throw ExtractionError.transportFailed(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let errorMessage = parseAPIErrorMessage(from: data)
            throw ExtractionError.requestFailed(statusCode: statusCode, message: errorMessage)
        }

        return try decodeExtractionResponse(from: data)
    }

    private func buildMessages(ocrText: String, redactedPageCount: Int) -> [ChatMessage] {
        [
            ChatMessage(role: "system", content: Self.extractionPrompt),
            ChatMessage(
                role: "user",
                content: """
                Extract medication plan from OCR text.
                OCR is generated locally from privacy-redacted pages only.
                REDACTED_PAGE_COUNT: \(redactedPageCount)
                OCR_TEXT_START
                \(ocrText)
                OCR_TEXT_END
                """
            )
        ]
    }

    private func decodeExtractionResponse(from data: Data) throws -> LLMExtractionResult {
        let decoder = JSONDecoder()

        if let direct = try? decoder.decode(LLMExtractionResult.self, from: data) {
            return direct
        }

        if let chatResponse = try? decoder.decode(ChatCompletionsResponse.self, from: data),
           let content = chatResponse.choices?.first?.message.content,
           !content.isEmpty
        {
            let jsonString = stripCodeFence(content)
            guard let jsonData = jsonString.data(using: .utf8) else {
                throw ExtractionError.responseNotJSON
            }
            return try decoder.decode(LLMExtractionResult.self, from: jsonData)
        }

        if let wrapper = try? decoder.decode(ContentWrapper.self, from: data),
           let content = wrapper.output ?? wrapper.content ?? wrapper.choices?.first?.message.content
        {
            let jsonString = stripCodeFence(content)
            guard let jsonData = jsonString.data(using: .utf8) else {
                throw ExtractionError.responseNotJSON
            }
            return try decoder.decode(LLMExtractionResult.self, from: jsonData)
        }

        throw ExtractionError.decodeFailed
    }

    private func stripCodeFence(_ content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }

        var lines = trimmed.components(separatedBy: .newlines)
        if !lines.isEmpty {
            lines.removeFirst()
        }
        if let last = lines.last, last.trimmingCharacters(in: .whitespacesAndNewlines) == "```" {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    private var normalizedAPIKey: String? {
        guard let raw = configuration.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else {
            return nil
        }

        if raw.contains("REPLACE_WITH") || raw.contains("YOUR_API_KEY") {
            return nil
        }

        return raw
    }

    private var normalizedModel: String {
        let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.isEmpty ? Self.fallbackModel : model
    }

    private func shouldRetryWithFallback(error: ExtractionError, selectedModel: String) -> Bool {
        guard selectedModel != Self.fallbackModel else {
            return false
        }

        guard case .requestFailed(_, let message) = error,
              let message
        else {
            return false
        }

        let normalized = message.lowercased()
        return normalized.contains("model")
            || normalized.contains("does not exist")
            || normalized.contains("not found")
            || normalized.contains("not available")
            || normalized.contains("unsupported")
    }

    private func parseAPIErrorMessage(from data: Data) -> String? {
        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(APIErrorEnvelope.self, from: data) {
            return envelope.error.message
        }
        return nil
    }

    static let extractionPrompt = """
    You are a strict JSON extraction engine.
    Output a SINGLE JSON object only, matching the schema below.
    Do NOT include markdown, code fences, comments, or any extra text.
    Do NOT wrap the JSON in backticks.
    Do NOT add keys not present in the schema.
    Every field must be present. Use \"unknown\" for unknown strings and [] for empty arrays.
    The response must be valid JSON (UTF-8), no trailing commas.

    Schema (exact keys and value types):
    {
      \"medications\": [
        {
          \"name\": \"string\",
          \"dose\": \"string\",
          \"route\": \"oral|topical|eye|injection|other|unknown\",
          \"frequency\": { \"type\": \"times_per_day|interval_hours|specific_times|unknown\", \"value\": 3 },
          \"times\": [\"08:00\",\"13:00\",\"20:00\"],
          \"start_date\": \"YYYY-MM-DD|unknown\",
          \"end_date\": \"YYYY-MM-DD|unknown\",
          \"with_food\": \"before_meal|after_meal|with_meal|no_requirement|unknown\",
          \"notes\": [\"string\"],
          \"storage\": [\"refrigerate\",\"avoid_light\",\"room_temp\",\"shake_well\",\"unknown\"]
        }
      ],
      \"follow_up\": [
        { \"date\": \"YYYY-MM-DD\", \"notes\": \"string\" }
      ],
      \"uncertainties\": [
        { \"path\": \"medications[0].dose\", \"reason\": \"string\", \"candidates\": [\"string\"] }
      ]
    }

    Requirements:
    - Output JSON only and no prose.
    - Normalize bid/tid/qid/q8h terms into frequency + times.
    - Map morning/noon/evening to 08:00/13:00/20:00 and bedtime to 22:30.
    - Merge duplicate medications across pages and keep the most complete details.
    - OCR text is derived from redacted pages only. Do not infer from unavailable image data.
    - Start/end date extraction:
      1) If explicit calendar dates are present, populate start_date/end_date using YYYY-MM-DD.
      2) If relative start exists (e.g. \"术后一周开始使用\", \"术后7天开始\", \"start after 1 week\"), convert it to an absolute start_date relative to the document context when possible.
      3) If duration phrases exist (e.g. \"使用7天停止\", \"连续两周\", \"for 10 days\"), infer end_date from start_date + duration.
      4) If anchor date is missing and absolute date cannot be resolved, keep unknown and add an uncertainty for start_date/end_date.
    - Dose extraction rule:
      1) If dose is explicitly stated in OCR text, copy it directly and do NOT add an uncertainty for dose.
      2) If dose is not explicitly stated but there is a strong textual cue, infer a practical dose string.
         Example cues: \"一次眼药\" / \"eye drops once each time\" -> infer dose as \"1 drop\".
      3) Any inferred dose MUST add an uncertainty entry with path \"medications[i].dose\" and reason \"inferred from context\" (include candidates if useful).
      4) If no strong cue exists, set dose to \"unknown\" and add uncertainty for \"medications[i].dose\".
    - Never hallucinate unsupported details; use \"unknown\" plus uncertainties when evidence is insufficient.
    - If you are unsure about any required field, still output the full JSON with \"unknown\" and add an uncertainty entry.
    """
}
