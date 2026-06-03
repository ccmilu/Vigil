import XCTest
@testable import Focus

@MainActor
final class ProviderStoreTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: ProviderStore.providersKey)
        UserDefaults.standard.removeObject(forKey: ProviderStore.selectedKey)
    }

    func testFirstLaunchHasFallback() {
        let s = ProviderStore()
        XCTAssertEqual(s.providers.count, 1)
        XCTAssertNotNil(s.selectedID)
        XCTAssertEqual(s.selected?.nickname, "本地 LM Studio")
    }

    func testAddUpdateRemove() {
        let s = ProviderStore()
        let p = AIProvider(
            nickname: "OpenAI",
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o-mini",
            apiKey: "sk-x"
        )
        s.add(p)
        XCTAssertEqual(s.providers.count, 2)

        var updated = p
        updated.nickname = "OpenAI Renamed"
        s.update(updated)
        XCTAssertEqual(s.providers.first(where: { $0.id == p.id })?.nickname, "OpenAI Renamed")

        s.remove(updated)
        XCTAssertEqual(s.providers.count, 1)
    }

    func testSelectPersistsAcrossInstances() {
        let s1 = ProviderStore()
        let p = AIProvider(
            nickname: "DeepSeek",
            baseURL: "https://api.deepseek.com/v1",
            model: "deepseek-vl",
            apiKey: "k"
        )
        s1.add(p)
        s1.select(p.id)

        // 新建实例模拟 App 重启
        let s2 = ProviderStore()
        XCTAssertEqual(s2.selectedID, p.id)
        XCTAssertEqual(s2.selected?.nickname, "DeepSeek")
    }

    func testMakeService_pointsToConfiguredURL() throws {
        let p = AIProvider(
            nickname: "LM Studio",
            baseURL: "http://192.168.1.99:1234/v1",
            model: "qwen",
            apiKey: "x"
        )
        let svc = p.makeService() as? OpenAICompatibleService
        XCTAssertNotNil(svc)
        XCTAssertEqual(svc?.baseURL.absoluteString, "http://192.168.1.99:1234/v1")
        XCTAssertEqual(svc?.model, "qwen")
    }
}
