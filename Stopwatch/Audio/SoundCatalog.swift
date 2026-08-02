//
//  SoundCatalog.swift
//  Stopwatch
//

import Foundation
import UserNotifications

/// 一個可以挑選的鈴聲。
///
/// 全部都是隨 App 夾帶的音效檔（本專案用正弦波合成的原創音效，放在 `Stopwatch/Sounds/`），
/// 因此前景與背景一定是同一顆聲音：可連響、可直接當作本地通知的音效，
/// 也不會去碰沙盒外的任何系統音檔。
struct SoundOption: Identifiable, Hashable {
    /// 音效檔名（不含副檔名），同時作為儲存用的識別碼。
    let id: String
    let name: String
    let englishName: String

    var fileExtension: String { "wav" }

    /// 本地通知引用時用的檔名。音效檔位於 App bundle 根目錄。
    var notificationSoundName: String { "\(id).\(fileExtension)" }
}

/// App 可用的鈴聲清單。
enum SoundCatalog {

    static let defaultID = "chime"

    static let options: [SoundOption] = [
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
        SoundOption(id: file, name: zh, englishName: en)
    }

    private static let index: [String: SoundOption] = {
        Dictionary(uniqueKeysWithValues: options.map { ($0.id, $0) })
    }()

    static func option(id: String) -> SoundOption? { index[id] }

    /// 找不到指定鈴聲時的安全退路。
    static func resolved(id: String) -> SoundOption? {
        index[id] ?? index[defaultID] ?? options.first
    }

    // MARK: - 通知音效

    /// 背景通知要用的鈴聲，與前景播放的是同一個音效檔。
    static func notificationSound(for soundID: String) -> UNNotificationSound {
        guard let option = resolved(id: soundID) else { return .default }
        return UNNotificationSound(named: UNNotificationSoundName(option.notificationSoundName))
    }
}
