import Foundation

/// AI 调用时的"返回语言"默认值。
/// 任何 input struct / service init 未显式传 `responseLanguage` 时回落到这里——
/// 主要给单元测试用，生产路径都会被 SessionManager / AIProvider 显式覆盖。
let kDefaultAIResponseLanguage = "Simplified Chinese (简体中文)"

/// 单帧分析的输入。
struct FrameAnalysisInput: Sendable {
    let promise: String
    let appName: String
    let windowTitles: String
    /// JPEG 二进制；如为 nil 表示不带图（仅文本判断）
    let screenshotJPEG: Data?
    /// AI 回复 reasoning / reminder 使用的语言，自然语言名（如 "English" / "Simplified Chinese (简体中文)"）。
    /// 由 SessionManager 在构造 input 时按用户当前语言注入；测试代码可省略走默认值。
    let responseLanguage: String

    init(
        promise: String,
        appName: String,
        windowTitles: String,
        screenshotJPEG: Data?,
        responseLanguage: String = kDefaultAIResponseLanguage
    ) {
        self.promise = promise
        self.appName = appName
        self.windowTitles = windowTitles
        self.screenshotJPEG = screenshotJPEG
        self.responseLanguage = responseLanguage
    }
}

/// 整体复盘的输入。
struct SummaryInput: Sendable {
    let promise: String
    let sessionSeconds: Int
    let fullySec: Int
    let wanderingSec: Int
    let distractedSec: Int
    let idleSec: Int
    let distractedNotes: [String]
    /// AI 回复整段复盘文本使用的语言。同 FrameAnalysisInput.responseLanguage。
    let responseLanguage: String

    init(
        promise: String,
        sessionSeconds: Int,
        fullySec: Int,
        wanderingSec: Int,
        distractedSec: Int,
        idleSec: Int,
        distractedNotes: [String],
        responseLanguage: String = kDefaultAIResponseLanguage
    ) {
        self.promise = promise
        self.sessionSeconds = sessionSeconds
        self.fullySec = fullySec
        self.wanderingSec = wanderingSec
        self.distractedSec = distractedSec
        self.idleSec = idleSec
        self.distractedNotes = distractedNotes
        self.responseLanguage = responseLanguage
    }
}

/// 给所有 AI 厂商实现的统一协议。
///
/// `analyzeTask` 用 String 入参（promise 太轻量，不值得包成 struct）；
/// service 实现侧自己持有 `responseLanguage`（OpenAICompatibleService 在 init 接收），
/// 不通过参数传——这样不破任何已实现 protocol 的测试 mock。
/// `analyzeFrame` / `summarize` 走 input struct，responseLanguage 从字段里读。
protocol AIService: Sendable {
    func analyzeTask(_ promise: String) async throws -> TaskAnalysis
    func analyzeFrame(_ input: FrameAnalysisInput) async throws -> FrameAnalysis
    func summarize(_ input: SummaryInput) async throws -> String
}
