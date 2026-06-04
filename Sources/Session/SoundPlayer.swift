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

    /// 持有上一次播放的 NSSound 实例，以便在下次 play 前调 stop()。
    /// NSSound(named:) 内部缓存单例，连续 play() 会被忽略，必须先 stop 再 copy 播新实例。
    /// 暴露给测试：internal(set) 方便 SoundPlayerTests 验证 ivar 是否被正确更新。
    private(set) var current: NSSound?

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
        guard let name = soundNames[cue] else {
            logger.warning("找不到 cue 对应的音名：\(cue.rawValue)")
            return
        }
        // 停掉前一个实例，避免单例缓存导致连续 play 静默
        current?.stop()
        // NSSound(named:) 返回缓存单例；copy() 拿到独立实例才能保证本次 play 不被忽略
        guard let sound = (NSSound(named: name)?.copy() as? NSSound) ?? NSSound(named: name) else {
            logger.warning("找不到系统音：\(name)")
            return
        }
        sound.volume = volume
        sound.play()
        current = sound
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

/// hover 试听专用：保证可以连续中断 + 反向重播。
/// NSSound(named:) 内部缓存了同一个实例，连续调 play 会被忽略——必须先 stop 再 play。
@MainActor
enum HoverSoundPreview {
    private static var current: NSSound?

    static func play(_ name: String) {
        // 停掉前一个
        current?.stop()
        // 用 copy 拿一个独立 sound 实例，避免 NSSound(named:) 单例打架
        let sound = (NSSound(named: name)?.copy() as? NSSound) ?? NSSound(named: name)
        sound?.volume = SoundPlayer.shared.volume
        sound?.play()
        current = sound
    }

    static func stop() {
        current?.stop()
        current = nil
    }
}
