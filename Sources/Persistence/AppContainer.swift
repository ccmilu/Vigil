import Foundation
import SwiftData

/// SwiftData 容器的集中入口，App 启动时构造一次。
@MainActor
enum AppContainer {
    static let shared: ModelContainer = {
        let schema = Schema([
            FocusSession.self,
            AnalysisRecord.self,
            StreakInfo.self,
            PlayTimer.self
        ])
        let config = ModelConfiguration(
            "Vigil",
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            cloudKitDatabase: .none // MVP 暂不开 CloudKit
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("无法创建 SwiftData 容器：\(error)")
        }
    }()

    /// 测试专用：纯内存
    static func inMemory() -> ModelContainer {
        let schema = Schema([
            FocusSession.self,
            AnalysisRecord.self,
            StreakInfo.self,
            PlayTimer.self
        ])
        let config = ModelConfiguration(
            "VigilTest",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try! ModelContainer(for: schema, configurations: [config])
    }
}
