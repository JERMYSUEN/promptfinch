import Foundation

struct ServiceConfig: Decodable {
    let service: String
    let apiVersion: Int
    let backendID: String?
    let backendInstanceID: String?
    let mode: String
    let ready: Bool
    let generationModel: String?
    let promptLanguages: [String]
}

struct PromptResult: Decodable {
    let prompt: String
    let improvements: [String]
    let assumptions: [String]
    let mode: String
    let generationModel: String?
    let promptLanguage: String
}

struct PromptRequest: Encodable {
    let prompt: String
    let task: String
    let targetModel: String
    let promptLanguage = "en"

    func validate() throws {
        if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ToolError.message(L10n.text(.emptyInput))
        }
        // Match JavaScript's UTF-16 length rather than Swift's grapheme count.
        if prompt.utf16.count > 12000 { throw ToolError.message(L10n.text(.inputTooLong)) }
        if targetModel.utf16.count > 80 || targetModel.unicodeScalars.contains(where: { $0.value < 32 }) {
            throw ToolError.message(L10n.text(.invalidTarget))
        }
    }
}

enum ToolError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

final class PromptClient {
    let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = URL(string: "http://127.0.0.1:3210")!) {
        self.baseURL = baseURL
        let settings = URLSessionConfiguration.ephemeral
        settings.timeoutIntervalForRequest = 190
        settings.timeoutIntervalForResource = 195
        settings.urlCache = nil
        settings.httpCookieStorage = nil
        session = URLSession(configuration: settings)
    }

    func config(expectedBackendID: String? = nil, expectedInstanceID: String? = nil) async throws -> ServiceConfig {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/config"))
        request.timeoutInterval = 2
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let config = try? JSONDecoder().decode(ServiceConfig.self, from: data),
              config.service == "prompt-studio", config.apiVersion >= 2,
              config.promptLanguages.contains("en") else {
            throw ToolError.message(L10n.text(.incompatibleService))
        }
        if let expectedBackendID, config.backendID != expectedBackendID {
            throw ToolError.message(L10n.text(.backendVersionMismatch))
        }
        if let expectedInstanceID, let reportedInstanceID = config.backendInstanceID, reportedInstanceID != expectedInstanceID {
            throw ToolError.message(L10n.text(.backendInstanceMismatch))
        }
        return config
    }

    func optimize(_ input: PromptRequest) async throws -> PromptResult {
        try input.validate()
        var request = URLRequest(url: baseURL.appendingPathComponent("api/optimize"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(input)
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            struct Failure: Decodable { let error: String }
            let message = (try? JSONDecoder().decode(Failure.self, from: data))?.error ?? L10n.text(.badServiceResponse)
            throw ToolError.message(L10n.relocalize(message, from: .traditionalChinese))
        }
        guard let result = try? JSONDecoder().decode(PromptResult.self, from: data),
              result.promptLanguage == "en", !result.prompt.isEmpty else {
            throw ToolError.message(L10n.text(.invalidResult))
        }
        return result
    }
}
