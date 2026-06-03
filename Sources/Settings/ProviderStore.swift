import Foundation
import SwiftUI

/// 把 providers JSON 数组存到 UserDefaults，selectedID 单独存。
/// MVP 用 @AppStorage；v0.3 迁 Keychain。
@MainActor
final class ProviderStore: ObservableObject {
    static let providersKey = "providers.json"
    static let selectedKey = "providers.selectedID"

    /// 全局共享实例，保证 SessionManager 闭包和 SwiftUI Environment 拿到同一份状态
    static let shared = ProviderStore()

    @Published var providers: [AIProvider]
    @Published var selectedID: UUID?

    init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.providersKey),
           let list = try? JSONDecoder().decode([AIProvider].self, from: data),
           !list.isEmpty {
            self.providers = list
        } else {
            self.providers = [.demoFallback]
        }
        if let idStr = defaults.string(forKey: Self.selectedKey),
           let id = UUID(uuidString: idStr),
           providers.contains(where: { $0.id == id }) {
            self.selectedID = id
        } else {
            self.selectedID = providers.first?.id
        }
    }

    var selected: AIProvider? {
        providers.first(where: { $0.id == selectedID }) ?? providers.first
    }

    func add(_ p: AIProvider) {
        providers.append(p)
        if selectedID == nil { selectedID = p.id }
        persist()
    }

    func update(_ p: AIProvider) {
        if let idx = providers.firstIndex(where: { $0.id == p.id }) {
            providers[idx] = p
            persist()
        }
    }

    func remove(_ p: AIProvider) {
        providers.removeAll(where: { $0.id == p.id })
        if selectedID == p.id { selectedID = providers.first?.id }
        persist()
    }

    func select(_ id: UUID) {
        selectedID = id
        persist()
    }

    private func persist() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(providers) {
            defaults.set(data, forKey: Self.providersKey)
        }
        defaults.set(selectedID?.uuidString, forKey: Self.selectedKey)
    }
}
