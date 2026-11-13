import Foundation

final class MockProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Data))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (code, data) = Self.handler(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
struct Tests {
    static func bodyData(_ request: URLRequest) -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { fatalError("Request has no body") }
        stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { fatalError("Could not read request body") }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
    static func fixture(_ text: String, reason: String = "stop") -> [String: Any] {
        ["choices": [["message": ["content": text], "finish_reason": reason]]]
    }
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
        print("PASS: \(message)")
    }
    static func main() async throws {
        let missingRules = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("missing.txt")
        for (resource, heading) in [("academic-writing-editor", "# Academic Writing Editor"), ("paper-reading-rules", "# Summarize Research Paper")] {
            let bundled = try academicWritingRules(skillURL: missingRules, bundledURL: Bundle.main.url(forResource: resource, withExtension: "txt"))
            check(bundled.contains(heading) && !bundled.hasPrefix("---"), "Bundled \(resource) works without a personal skill installation")
        }
        let original = #"The results shows $x^2$ in \eqref{eq:a} and \citep{Smith2024}."#
        let revised = #"The results show $x^2$ in \eqref{eq:a} and \citep{Smith2024}."#
        let good = try decodeCompletion(fixture(revised), original: original, mode: .polish)
        check(good.warning == nil, "Preserved math and citations remain copyable")
        let changed = try decodeCompletion(fixture(revised.replacingOccurrences(of: "x^2", with: "x^3")), original: original, mode: .polish)
        check(changed.warning != nil, "Changed formula blocks copy")
        let refChanged = try decodeCompletion(fixture(revised.replacingOccurrences(of: "Smith2024", with: "Smith2025")), original: original, mode: .polish)
        check(refChanged.warning != nil, "Changed citation blocks copy")
        let translated = #"结果在 \eqref{eq:a} 和 \citep{Smith2024} 中显示为 $x^2$。"#
        let translation = try decodeCompletion(fixture(translated), original: original, mode: .translate)
        check(translation.warning != nil, "Reordered protected LaTeX in translation requires review")
        let faithfulTranslation = #"结果显示 $x^2$，见 \eqref{eq:a} 和 \citep{Smith2024}。"#
        let safeTranslation = try decodeCompletion(fixture(faithfulTranslation), original: original, mode: .translate)
        check(safeTranslation.warning == nil, "Faithful translation remains copyable")
        let changedTranslation = try decodeCompletion(fixture(faithfulTranslation.replacingOccurrences(of: "x^2", with: "x^3")), original: original, mode: .translate)
        check(changedTranslation.warning != nil, "Changed formula in translation blocks copy")
        do { _ = try decodeCompletion(fixture("partial", reason: "length"), original: original, mode: .polish); fatalError("Accepted truncated response") }
        catch { print("PASS: Truncated response rejected") }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockProtocol.self]
        let client = DeepSeekClient(session: URLSession(configuration: config))
        MockProtocol.handler = { r in
            check(r.url?.absoluteString == "https://api.deepseek.com/models", "Validation uses official DeepSeek endpoint")
            check(r.value(forHTTPHeaderField: "Authorization") == "Bearer test-key", "Key stays in authorization header")
            return (200, Data(#"{"data":[{"id":"deepseek-flash"}]}"#.utf8))
        }
        let models = try await client.validate(key: "test-key")
        check(models == ["deepseek-flash"], "Model list decoded")
        let writingRules = try academicWritingRules()
        for mode in [ActionMode.polish, .translate] {
            MockProtocol.handler = { r in
                let payload = try! JSONSerialization.jsonObject(with: bodyData(r)) as! [String: Any]
                let messages = payload["messages"] as! [[String: String]]
                check(r.url?.absoluteString == "https://api.deepseek.com/chat/completions", "Processing uses official DeepSeek endpoint")
                check(messages[0]["content"]!.contains(writingRules), "Full academic-writing-editor rules reach the API in \(mode)")
                check(messages[1]["role"] == "user" && messages[1]["content"] == original, "Source text stays separate from editing instructions")
                return (200, try! JSONSerialization.data(withJSONObject: fixture(revised)))
            }
            let response = try await client.complete(text: original, mode: mode, key: "test-key", model: "deepseek-flash")
            check(response.text == revised, "\(mode) request and response complete")
        }
        let request = try client.request(path: "chat/completions", key: "test-key", method: "POST", body: ["messages": [["role": "user", "content": "quotes \" and LaTeX \\alpha"]]])
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        let messages = body["messages"] as! [[String: String]]
        check(messages[0]["content"] == "quotes \" and LaTeX \\alpha", "Text and LaTeX are JSON-escaped without alteration")
        MockProtocol.handler = { r in (401, Data(#"{"error":{"message":"private detail"}}"#.utf8)) }
        do { _ = try await client.validate(key: "test-key"); fatalError("Accepted bad key") }
        catch { check(!error.localizedDescription.contains("private detail"), "API errors produce clear messages without echoing private content") }
    }
}
