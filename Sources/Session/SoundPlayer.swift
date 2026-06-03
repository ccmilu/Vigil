import Foundation
import AppKit
import OSLog

/// 三种关键时机的提示音。
/// MVP 用 macOS 系统自带音频（/System/Library/Sounds/），无版权问题。
/// v0.2 可以换成 CC0 音源 + 用户可选音色。
@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()

    enum Cue: String, CaseIterable {
        case start
        case distract
        case complete
    }

    /// 默认映射到 macOS 系统音
    private var soundNames: [Cue: String] = [
        .start:    "Tink",       // 清脆短音
        .distract: "Submarine",  // 低沉警示
        .complete: "Glass"       // 完成清脆铃
    ]

    private let logger = Logger(subsystem: "com.jason12138.focus", category: "Sound")
    private let defaults = UserDefaults.standard

    var isEnabled: Bool {
        get { defaults.object(forKey: "sound.enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "sound.enabled") }
    }

    var volume: Float {
        get { (defaults.object(forKey: "sound.volume") as? Float) ?? 0.7 }
        set { defaults.set(newValue, forKey: "sound.volume") }
    }

    func play(_ cue: Cue) {
        guard isEnabled else { return }
        guard let name = soundNames[cue], let sound = NSSound(named: name) else {
            logger.warning("找不到系统音 \(self.soundNames[cue] ?? "?")")
            return
        }
        sound.volume = volume
        sound.play()
    }

    /// 列出所有可用系统音的名字（给设置页下拉用）
    static let availableSystemSounds = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
        "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"
    ]

    func setSound(_ cue: Cue, name: String) {
        soundNames[cue] = name
        defaults.set(name, forKey: "sound.\(cue.rawValue)")
    }

    func currentName(for cue: Cue) -> String {
        defaults.string(forKey: "sound.\(cue.rawValue)") ?? soundNames[cue] ?? "Glass"
    }

    private init() {
        // 从 defaults 加载用户自定义
        for cue in Cue.allCases {
            if let name = defaults.string(forKey: "sound.\(cue.rawValue)") {
                soundNames[cue] = name
            }
        }
    }
}
