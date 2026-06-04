import Foundation
import SwiftData

// MARK: - 枚举

enum SessionStatus: String, Codable, Sendable {
    case running
    case autoCompleted
    case manualCompleted
    case abandoned

    var displayName: String {
        switch self {
        case .running:         return "进行中"
        case .autoCompleted:   return "已完成"
        case .manualCompleted: return "手动结束"
        case .abandoned:       return "已放弃"
        }
    }
}

enum FocusLevel: String, Codable, Sendable {
    case fully
    case wandering
    case distracted
    case idle

    var displayName: String {
        switch self {
        case .fully:      return "专注"
        case .wandering:  return "走神"
        case .distracted: return "分心"
        case .idle:       return "空闲"
        }
    }
}

// MARK: - 实体

@Model
final class FocusSession {
    @Attribute(.unique) var id: UUID
    var promise: String
    var plannedDuration: Int          // 秒
    var actualDuration: Int           // 秒
    var statusRaw: String
    var stopReason: String?
    var startedAt: Date
    var endedAt: Date?
    var timezone: String

    var fullyRatio: Double
    var wanderingRatio: Double
    var distractedRatio: Double
    var idleRatio: Double

    var summary: String?
    var guardianAssetName: String?

    @Relationship(deleteRule: .cascade, inverse: \AnalysisRecord.session)
    var records: [AnalysisRecord] = []

    var status: SessionStatus {
        get { SessionStatus(rawValue: statusRaw) ?? .running }
        set { statusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        promise: String,
        plannedDuration: Int,
        startedAt: Date = .now,
        timezone: String = TimeZone.current.identifier
    ) {
        self.id = id
        self.promise = promise
        self.plannedDuration = plannedDuration
        self.actualDuration = 0
        self.statusRaw = SessionStatus.running.rawValue
        self.startedAt = startedAt
        self.timezone = timezone
        self.fullyRatio = 0
        self.wanderingRatio = 0
        self.distractedRatio = 0
        self.idleRatio = 0
    }
}

@Model
final class AnalysisRecord {
    @Attribute(.unique) var id: UUID
    var session: FocusSession?
    var screenshotLocalPath: String?
    var frontAppName: String
    var frontWindowTitles: String
    var levelRaw: String
    var reasoning: String
    var reminder: String
    var fromAI: Bool
    var hasChanged: Bool
    var dhashHex: String?
    var dhashDistance: Int?
    var createdAt: Date
    var analysisLatencyMs: Int

    var level: FocusLevel {
        get {
            // fallback 用 .wandering 而非 .idle：
            // .idle 会触发 maybeAlertIdle / stopSoftReminder 等有语义副作用的分支，
            // 遇到无效 levelRaw（未来新 case / 迁移拼写错误）时应回落到中性状态。
            guard let parsed = FocusLevel(rawValue: levelRaw) else {
                return .wandering
            }
            return parsed
        }
        set { levelRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        session: FocusSession? = nil,
        screenshotLocalPath: String? = nil,
        frontAppName: String,
        frontWindowTitles: String,
        level: FocusLevel,
        reasoning: String = "",
        reminder: String = "",
        fromAI: Bool,
        hasChanged: Bool,
        dhashHex: String? = nil,
        dhashDistance: Int? = nil,
        createdAt: Date = .now,
        analysisLatencyMs: Int = 0
    ) {
        self.id = id
        self.session = session
        self.screenshotLocalPath = screenshotLocalPath
        self.frontAppName = frontAppName
        self.frontWindowTitles = frontWindowTitles
        self.levelRaw = level.rawValue
        self.reasoning = reasoning
        self.reminder = reminder
        self.fromAI = fromAI
        self.hasChanged = hasChanged
        self.dhashHex = dhashHex
        self.dhashDistance = dhashDistance
        self.createdAt = createdAt
        self.analysisLatencyMs = analysisLatencyMs
    }
}

@Model
final class StreakInfo {
    var currentStreak: Int
    var longestStreak: Int
    var currentStreakStartDate: Date?
    var lastActiveDate: Date?
    var longestStreakStartDate: Date?
    var longestStreakEndDate: Date?

    init() {
        self.currentStreak = 0
        self.longestStreak = 0
    }
}

@Model
final class PlayTimer {
    var seconds: Int
    var slot: Int
    var createdAt: Date

    init(seconds: Int, slot: Int, createdAt: Date = .now) {
        self.seconds = seconds
        self.slot = slot
        self.createdAt = createdAt
    }
}
