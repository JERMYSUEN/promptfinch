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
            throw ToolError.message("請先選取文字或貼上原始需求。")
        }
        // Match JavaScript's UTF-16 length rather than Swift's grapheme count.
        if prompt.utf16.count > 12000 { throw ToolError.message("需求最多 12,000 字，請縮短後再試。") }
        if targetModel.utf16.count > 80 || targetModel.unicodeScalars.contains(where: { $0.value < 32 }) {
            throw ToolError.message("目標模型請使用 80 字以內的單行文字。")
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
            throw ToolError.message("3210 連接埠上的服務不相容，請先關閉佔用此埠的程式。")
        }
        if let expectedBackendID, config.backendID != expectedBackendID {
            throw ToolError.message("本機後端版本與 App 不一致。請關閉 App，重新執行後端更新指令。")
        }
        if let expectedInstanceID, let reportedInstanceID = config.backendInstanceID, reportedInstanceID != expectedInstanceID {
            throw ToolError.message("3210 的服務不是此 App 本次啟動的後端。為避免連到舊程序，請先結束佔用該埠的服務再重試。")
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
            let message = (try? JSONDecoder().decode(Failure.self, from: data))?.error ?? "本機服務回應異常，請重試。"
            throw ToolError.message(message)
        }
        guard let result = try? JSONDecoder().decode(PromptResult.self, from: data),
              result.promptLanguage == "en", !result.prompt.isEmpty else {
            throw ToolError.message("結果不是有效的英文 Prompt 回應，請重新生成。")
        }
        return result
    }
}
