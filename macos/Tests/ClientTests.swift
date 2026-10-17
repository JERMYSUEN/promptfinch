import Foundation

/// A URLProtocol fixture never connects to a socket or a model service.
private final class ConfigFixtureProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var payload = Data()
    static func setPayload(_ value: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: value)
        lock.lock(); defer { lock.unlock() }
        payload = data
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); let data = Self.payload; Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
func runPromptClientIdentityTests(check: (Bool, String) -> Void) async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ConfigFixtureProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let client = PromptClient(baseURL: URL(string: "https://promptfinch-test.invalid")!, session: session)
    let backendID = String(repeating: "b", count: 64)
    let instanceID = "test-owned-instance"
    let base: [String: Any] = ["service": "prompt-studio", "apiVersion": 2, "backendID": backendID,
                               "mode": "mock", "ready": true, "promptLanguages": ["en"]]
    let cases: [(String, Any?)] = [("missing", nil), ("null", NSNull()), ("empty", ""),
                                    ("different", "unrelated-process"), ("correct", instanceID)]
    for (name, value) in cases {
        var payload = base
        if let value { payload["backendInstanceID"] = value }
        try ConfigFixtureProtocol.setPayload(payload)
        do {
            let result = try await client.config(expectedBackendID: backendID, expectedInstanceID: instanceID)
            check(name == "correct" && result.backendInstanceID == instanceID,
                  "only the exact expected process identity is accepted (\(name))")
        } catch {
            check(name != "correct" && error.localizedDescription == L10n.text(.backendInstanceMismatch),
                  "missing/null/empty/foreign process identities are rejected (\(name))")
        }
    }
    try ConfigFixtureProtocol.setPayload(base)
    let unowned = try await client.config(expectedBackendID: backendID)
    check(unowned.backendInstanceID == nil, "an optional process check stays optional for non-owned connections")
    var resultPayload: [String: Any] = ["prompt": "Write a synthetic notice.", "improvements": ["合成メモ"],
                                        "assumptions": [], "mode": "mock", "promptLanguage": "en", "notesLanguage": "ja"]
    try ConfigFixtureProtocol.setPayload(resultPayload)
    let localized = try await client.optimize(PromptRequest(prompt: "合成の依頼", task: "writing", targetModel: "", notesLanguage: "ja"))
    check(localized.notesLanguage == "ja" && localized.promptLanguage == "en", "result note language metadata stays separate from prompt language")
    resultPayload.removeValue(forKey: "notesLanguage")
    try ConfigFixtureProtocol.setPayload(resultPayload)
    let legacy = try await client.optimize(PromptRequest(prompt: "Synthetic request", task: "general", targetModel: ""))
    check(legacy.notesLanguage == nil && legacy.prompt == localized.prompt, "older results without optional notes metadata remain readable")
}
