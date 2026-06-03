import XCTest
@testable import Focus

/// 验证 analyzeFrame / summarize 的请求格式与响应解析。
final class AnalyzeFrameTests: XCTestCase {

    override func setUp() {
        super.setUp()
        FrameStub.requests.removeAll()
        FrameStub.responder = nil
    }

    func testAnalyzeFrame_visionRequestShape() async throws {
        FrameStub.responder = { request in
            XCTAssertEqual(request.url?.path, "/v1/chat/completions")
            let body = request.httpBodyData ?? Data()
            let json = try! JSONSerialization.jsonObject(with: body) as! [String: Any]
            let messages = json["messages"] as! [[String: Any]]
            XCTAssertEqual(messages.count, 2)
            // user content 是数组（text + image_url）
            let userContent = messages[1]["content"] as! [[String: Any]]
            XCTAssertEqual(userContent.count, 2)
            XCTAssertEqual(userContent[0]["type"] as? String, "text")
            XCTAssertEqual(userContent[1]["type"] as? String, "image_url")
            let imgURL = (userContent[1]["image_url"] as! [String: Any])["url"] as! String
            XCTAssertTrue(imgURL.hasPrefix("data:image/jpeg;base64,"))

            let respBody = #"""
            {
              "choices":[{"message":{"content":"{\"level\":\"fully\",\"reasoning\":\"正在编写周报草稿\",\"reminder\":\"\"}"}}]
            }
            """#.data(using: .utf8)!
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, respBody)
        }

        let service = OpenAICompatibleService(
            baseURL: URL(string: "https://api.openai.com/v1")!,  // 注意非 local，应带 detail
            model: "gpt-4o-mini",
            apiKey: "k",
            session: Self.stubSession()
        )
        let input = FrameAnalysisInput(
            promise: "写周报",
            appName: "Pages",
            windowTitles: "周报草稿.pages",
            screenshotJPEG: Data("fake".utf8)
        )
        let result = try await service.analyzeFrame(input)
        XCTAssertEqual(result.level, .fully)
        XCTAssertEqual(result.reasoning, "正在编写周报草稿")
        XCTAssertEqual(result.reminder, "")
    }

    func testAnalyzeFrame_localHostStripsDetail() async throws {
        FrameStub.responder = { request in
            let body = request.httpBodyData ?? Data()
            let json = try! JSONSerialization.jsonObject(with: body) as! [String: Any]
            let messages = json["messages"] as! [[String: Any]]
            let userContent = messages[1]["content"] as! [[String: Any]]
            let imgDict = userContent[1]["image_url"] as! [String: Any]
            XCTAssertNil(imgDict["detail"], "本地 host 不应带 detail 字段")

            let respBody = #"""
            {"choices":[{"message":{"content":"{\"level\":\"distracted\",\"reasoning\":\"刷视频\",\"reminder\":\"回到周报来吧\"}"}}]}
            """#.data(using: .utf8)!
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, respBody)
        }
        let service = OpenAICompatibleService(
            baseURL: URL(string: "http://192.168.1.23:1234/v1")!,
            model: "qwen", apiKey: "k", session: Self.stubSession()
        )
        let result = try await service.analyzeFrame(
            FrameAnalysisInput(
                promise: "写周报", appName: "YouTube",
                windowTitles: "热门视频", screenshotJPEG: Data([0xff, 0xd8])
            )
        )
        XCTAssertEqual(result.level, .distracted)
        XCTAssertFalse(result.reminder.isEmpty)
    }

    func testSummarize_returnsRawText() async throws {
        FrameStub.responder = { request in
            let respBody = #"""
            {"choices":[{"message":{"content":"今天的会话围绕周报展开，整体专注度不错。建议下次先列大纲。"}}]}
            """#.data(using: .utf8)!
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, respBody)
        }
        let service = OpenAICompatibleService(
            baseURL: URL(string: "http://127.0.0.1:1234/v1")!,
            model: "qwen", apiKey: "k", session: Self.stubSession()
        )
        let text = try await service.summarize(
            SummaryInput(
                promise: "写周报", sessionSeconds: 1500,
                fullySec: 1200, wanderingSec: 200, distractedSec: 50, idleSec: 50,
                distractedNotes: ["刷小红书"]
            )
        )
        XCTAssertTrue(text.contains("周报"))
    }

    private static func stubSession() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [FrameStub.self]
        return URLSession(configuration: cfg)
    }
}

private final class FrameStub: URLProtocol {
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
    var httpBodyData: Data? {
        if let body = httpBody { return body }
        guard let stream = httpBodyStream else { return nil }
        stream.open(); defer { stream.close() }
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
