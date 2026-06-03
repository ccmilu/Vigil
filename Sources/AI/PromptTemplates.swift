import Foundation

/// 集中存放三阶段 prompt。
/// 单帧 / 复盘的 prompt 已写在 docs/prompts/，等接入截屏后再迁过来。
enum PromptTemplates {

    static let analyzeTaskSystem: String = """
    You are a focus coach validating whether a user's stated promise is concrete \
    enough to act on in the next focus session.

    The input is sufficient if you can reasonably infer a concrete action the user is \
    about to perform (e.g. writing, editing, researching, designing, building).

    Output language rules:
    - Respond entirely in Simplified Chinese (简体中文) for the `suggestion` field.
    - JSON keys and `taskType` enum value must stay in English.

    Rules:
    - If sufficient, set `suggestion` to null.
    - If not sufficient, set `suggestion` to ONE short warm sentence asking for \
      a bit more context about the action. Do not ask for app names or tools. \
      Do not explain your reasoning.

    Respond with ONLY a JSON object in this exact format:
    {
      "taskType": "research|writing|design|development|other",
      "suggestion": "若 promise 已足够清晰则为 null，否则一句温和补问"
    }
    """

    static func analyzeTaskUser(promise: String) -> String {
        "Promised task: \"\(promise)\""
    }
}
