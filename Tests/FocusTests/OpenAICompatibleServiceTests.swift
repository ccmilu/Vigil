import XCTest
@testable import Focus

/// 单元测试：用自定义 URLProtocol 拦截 URLSession 请求，
/// 不依赖网络也不依赖 LM Studio 是否在线。
final class OpenAICompatibleServiceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StubURLProtocol.requests.removeAll()
        StubURLProtocol.responder = nil
    }

    // MARK: - JSON 解析

    func testExtractFirstJSONObject_pureJSON() {
        let raw = #"{"taskType":"writing","suggestion":null}"#
        XCTAssertEqual(OpenAICompatibleService.extractFirstJSONObject(from: raw), raw)
    }

    func testExtractFirstJSONObject_wrappedInMarkdown() {
        let raw = """
        Sure, here's the result:
        ```json
        {"taskType":"design","suggestion":"再具体些"}
        ```
        """
        let json = OpenAICompatibleService.extractFirstJSONObject(from: raw)
        XCTAssertEqual(json, #"{"taskType":"design","suggestion":"再具体些"}"#)
    }

    func testDecodeTaskAnalysis_clearPromise() throws {
        let raw = #"{"taskType":"development","suggestion":null}"#
        let analysis = try OpenAICompatibleService.decodeTaskAnalysis(raw)
        XCTAssertEqual(analysis.taskType, .development)
        XCTAssertNil(analysis.suggestion)
    }

    func testDecodeTaskAnalysis_withSuggestion() throws {
        let raw = #"{"taskType":"other","suggestion":"你打算具体做什么呢？"}"#
        let analysis = try OpenAICompatibleService.decodeTaskAnalysis(raw)
        XCTAssertEqual(analysis.taskType, .other)
        XCTAssertEqual(analysis.suggestion, "你打算具体做什么呢？")
    }

    // MARK: - 请求格式

    func testAnalyzeTask_requestShape() async throws {
        StubURLProtocol.responder = { request in
            // 检查请求形态
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(
                request.url?.absoluteString,
                "http://127.0.0.1:1234/v1/chat/completions"
            )
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Authorization"),
                "Bearer test-key"
            )
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Content-Type"),
                "application/json"
            )

            let body = request.httpBodyData ?? Data()
            let json = try! JSONSerialization.jsonObject(with: body) as! [String: Any]
            XCTAssertEqual(json["model"] as? String, "test-model")
            let messages = json["messages"] as! [[String: String]]
            XCTAssertEqual(messages.count, 2)
            XCTAssertEqual(messages[0]["role"], "system")
            XCTAssertEqual(messages[1]["role"], "user")
            XCTAssertTrue(messages[1]["content"]!.contains("写一份周报"))

            // 回一个成功响应
            let respBody = #"""
            {
              "choices": [
                { "message": { "content": "{\"taskType\":\"writing\",\"suggestion\":null}" } }
              ]
            }
            """#.data(using: .utf8)!
            let resp = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (resp, respBody)
        }

        let service = OpenAICompatibleService(
            baseURL: URL(string: "http://127.0.0.1:1234/v1")!,
            model: "test-model",
            apiKey: "test-key",
            session: stubSession()
        )
        let result = try await service.analyzeTask("写一份周报")
        XCTAssertEqual(result.taskType, .writing)
        XCTAssertNil(result.suggestion)
    }

    func testAnalyzeTask_serverError() async {
        StubURLProtocol.responder = { request in
            let resp = HTTPURLResponse(
                url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil
            )!
            return (resp, Data("internal error".utf8))
        }
        let service = OpenAICompatibleService(session: stubSession())
        do {
            _ = try await service.analyzeTask("foo")
            XCTFail("should throw")
        } catch let AIServiceError.invalidResponse(status, body) {
            XCTAssertEqual(status, 500)
            XCTAssertTrue(body.contains("internal error"))
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    // MARK: - Helpers

    private func stubSession() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: cfg)
    }
}

// MARK: - URLProtocol stub

private final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responder: (@Sendable (URLRequest) -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        guard let responder = Self.responder else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (resp, data) = responder(request)
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension URLRequest {
    /// URLProtocol 模式下 httpBody 不会直接附着，而是通过 bodyStream 暴露
    var httpBodyData: Data? {
        if let body = httpBody { return body }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buf, maxLength: buf.count)
            if read <= 0 { break }
            data.append(buf, count: read)
        }
        return data
    }
}
