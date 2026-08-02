//
//  SoundCatalog.swift
//  Stopwatch
//

import AudioToolbox
import Foundation
import UserNotifications

enum SoundCategory: String, CaseIterable, Identifiable, Hashable {
    case builtin = "內建音效"
    case system = "系統提示音"

    var id: String { rawValue }
}

/// 一個可以挑選的鈴聲。
struct SoundOption: Identifiable, Hashable {
    enum Source: Hashable {
        /// 隨 App 夾帶的音效檔：可連響、可當作通知音、靜音時仍會出聲
        case bundled(name: String, ext: String)
        /// 由系統播放的內建提示音（公開的 AudioServices API）
        case systemID(SystemSoundID)
    }

    let id: String
    let name: String
    let englishName: String
    let category: SoundCategory
    let source: Source

    /// 背景通知能不能用這顆鈴聲。系統提示音沒有可引用的音檔，只能退回預設通知音。
    var supportsNotificationSound: Bool {
        if case .bundled = source { return true }
        return false
    }
}

/// App 可用的鈴聲清單。
///
/// 兩個來源都不碰沙盒外的檔案：
/// 1. `內建音效` 是本專案用正弦波合成的原創音效，檔案放在 `Stopwatch/Sounds/`；
/// 2. `系統提示音` 透過公開的 `AudioServicesPlaySystemSound` 請系統播放它自己的提示音，
///    App 不會讀取或複製任何系統音檔。
enum SoundCatalog {

    static let defaultID = "chime"

    static let options: [SoundOption] = builtinOptions + systemOptions

    private static let index: [String: SoundOption] = {
        Dictionary(uniqueKeysWithValues: options.map { ($0.id, $0) })
    }()

    static func option(id: String) -> SoundOption? { index[id] }

    /// 找不到指定鈴聲時的安全退路。
    static func resolved(id: String) -> SoundOption? {
        index[id] ?? index[defaultID] ?? options.first
    }

    static func options(in category: SoundCategory) -> [SoundOption] {
        options.filter { $0.category == category }
    }

    static var availableCategories: [SoundCategory] {
        SoundCategory.allCases.filter { category in options.contains { $0.category == category } }
    }

    // MARK: - 內建音效

    private static let builtinOptions: [SoundOption] = [
        ("chime", "鐘聲", "Chime"),
        ("marimba", "木琴", "Marimba"),
        ("ping", "清脆", "Ping"),
        ("rise", "上行", "Rise"),
        ("fall", "下行", "Fall"),
        ("double", "雙響", "Double"),
        ("triple", "三響", "Triple"),
        ("alert", "警示", "Alert"),
        ("soft", "柔和", "Soft"),
    ].map { file, zh, en in
        SoundOption(id: file, name: zh, englishName: en, category: .builtin,
                    source: .bundled(name: file, ext: "wav"))
    }

    // MARK: - 系統提示音

    private static let systemOptions: [SoundOption] = [
        ("tri-tone", SystemSoundID(1007), "三音", "Tri-tone"),
        ("bell", SystemSoundID(1013), "鈴鐺", "Bell"),
        ("electronic", SystemSoundID(1014), "電子音", "Electronic"),
        ("anticipate", SystemSoundID(1020), "期待", "Anticipate"),
        ("bloom", SystemSoundID(1021), "綻放", "Bloom"),
        ("calypso", SystemSoundID(1022), "卡利普索", "Calypso"),
        ("choo-choo", SystemSoundID(1023), "火車", "Choo Choo"),
        ("descent", SystemSoundID(1024), "下降", "Descent"),
        ("fanfare", SystemSoundID(1025), "號角", "Fanfare"),
        ("ladder", SystemSoundID(1026), "階梯", "Ladder"),
        ("minuet", SystemSoundID(1027), "小步舞曲", "Minuet"),
        ("news-flash", SystemSoundID(1028), "快訊", "News Flash"),
        ("noir", SystemSoundID(1029), "黑色電影", "Noir"),
        ("sherwood", SystemSoundID(1030), "雪伍德森林", "Sherwood Forest"),
        ("spell", SystemSoundID(1031), "咒語", "Spell"),
        ("suspense", SystemSoundID(1032), "懸疑", "Suspense"),
        ("telegraph", SystemSoundID(1033), "電報", "Telegraph"),
        ("tiptoes", SystemSoundID(1034), "躡手躡腳", "Tiptoes"),
        ("typewriters", SystemSoundID(1035), "打字機", "Typewriters"),
        ("update", SystemSoundID(1036), "更新", "Update"),
    ].map { id, soundID, zh, en in
        SoundOption(id: "system-\(id)", name: zh, englishName: en, category: .system,
                    source: .systemID(soundID))
    }

    // MARK: - 通知音效

    /// 夾帶的音效檔可以直接讓本地通知引用（檔案位於 App bundle 根目錄）。
    static func notificationSoundName(for option: SoundOption) -> String? {
        guard case .bundled(let name, let ext) = option.source else { return nil }
        return "\(name).\(ext)"
    }

    /// 背景通知要用的鈴聲。系統提示音沒有可引用的音檔，只能退回預設通知音。
    static func notificationSound(for soundID: String) -> UNNotificationSound {
        guard let option = resolved(id: soundID),
              let name = notificationSoundName(for: option) else {
            return .default
        }
        return UNNotificationSound(named: UNNotificationSoundName(name))
    }
}
