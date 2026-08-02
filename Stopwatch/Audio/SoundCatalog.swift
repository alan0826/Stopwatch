//
//  SoundCatalog.swift
//  Stopwatch
//

import AudioToolbox
import Foundation

enum SoundCategory: String, CaseIterable, Identifiable, Hashable {
    case alert = "提示音"
    case classic = "經典音效"
    case ringtone = "鈴聲"

    var id: String { rawValue }
}

/// 一個可以挑選的鈴聲。
struct SoundOption: Identifiable, Hashable {
    enum Source: Hashable {
        /// 直接讀取系統音效檔：可連響、可跟著音訊工作階段在背景播放
        case file(URL)
        /// 退路：公開的 AudioServices 內建音效 ID
        case systemID(SystemSoundID)
    }

    let id: String
    let name: String
    let englishName: String
    let category: SoundCategory
    let source: Source
}

/// 蒐集 iOS 內建的 Apple 官方音效。
///
/// iOS 沒有公開 API 可以列出「設定 → 聲音與觸覺」裡的鈴聲清單，因此這裡的做法是：
/// 1. 執行期掃描系統音效目錄（`/System/Library/Audio/UISounds`、`/Library/Ringtones`）；
/// 2. 讀不到檔案時，退回同一顆音效在 AudioServices 的公開音效 ID。
/// 兩條路都是播放 Apple 自己的音效，App 本身不夾帶任何鈴聲檔案。
enum SoundCatalog {

    static let uiSoundsRoot = "/System/Library/Audio/UISounds"
    static let ringtonesRoot = "/Library/Ringtones"

    static let defaultID = "New/Bloom"

    private struct Entry {
        let file: String
        let zh: String
        let en: String
        let category: SoundCategory
        let fallback: SystemSoundID?
    }

    /// iOS 現行的提示音（設定 App 裡「提示音」那一組）
    private static let alertEntries: [Entry] = [
        Entry(file: "New/Anticipate.caf", zh: "期待", en: "Anticipate", category: .alert, fallback: 1020),
        Entry(file: "New/Bloom.caf", zh: "綻放", en: "Bloom", category: .alert, fallback: 1021),
        Entry(file: "New/Calypso.caf", zh: "卡利普索", en: "Calypso", category: .alert, fallback: 1022),
        Entry(file: "New/Choo_Choo.caf", zh: "火車", en: "Choo Choo", category: .alert, fallback: 1023),
        Entry(file: "New/Descent.caf", zh: "下降", en: "Descent", category: .alert, fallback: 1024),
        Entry(file: "New/Fanfare.caf", zh: "號角", en: "Fanfare", category: .alert, fallback: 1025),
        Entry(file: "New/Ladder.caf", zh: "階梯", en: "Ladder", category: .alert, fallback: 1026),
        Entry(file: "New/Minuet.caf", zh: "小步舞曲", en: "Minuet", category: .alert, fallback: 1027),
        Entry(file: "New/News_Flash.caf", zh: "快訊", en: "News Flash", category: .alert, fallback: 1028),
        Entry(file: "New/Noir.caf", zh: "黑色電影", en: "Noir", category: .alert, fallback: 1029),
        Entry(file: "New/Sherwood_Forest.caf", zh: "雪伍德森林", en: "Sherwood Forest", category: .alert, fallback: 1030),
        Entry(file: "New/Spell.caf", zh: "咒語", en: "Spell", category: .alert, fallback: 1031),
        Entry(file: "New/Suspense.caf", zh: "懸疑", en: "Suspense", category: .alert, fallback: 1032),
        Entry(file: "New/Telegraph.caf", zh: "電報", en: "Telegraph", category: .alert, fallback: 1033),
        Entry(file: "New/Tiptoes.caf", zh: "躡手躡腳", en: "Tiptoes", category: .alert, fallback: 1034),
        Entry(file: "New/Typewriters.caf", zh: "打字機", en: "Typewriters", category: .alert, fallback: 1035),
        Entry(file: "New/Update.caf", zh: "更新", en: "Update", category: .alert, fallback: 1036),
    ]

    /// 經典音效（含鬧鈴、三音等）
    private static let classicEntries: [Entry] = [
        Entry(file: "alarm.caf", zh: "鬧鈴", en: "Alarm", category: .classic, fallback: 1005),
        Entry(file: "sms-received1.caf", zh: "三音", en: "Tri-tone", category: .classic, fallback: 1007),
        Entry(file: "sms-received2.caf", zh: "鐘聲", en: "Chime", category: .classic, fallback: 1008),
        Entry(file: "sms-received3.caf", zh: "玻璃", en: "Glass", category: .classic, fallback: 1009),
        Entry(file: "sms-received4.caf", zh: "號角聲", en: "Horn", category: .classic, fallback: 1010),
        Entry(file: "sms-received5.caf", zh: "鈴鐺", en: "Bell", category: .classic, fallback: 1013),
        Entry(file: "sms-received6.caf", zh: "電子音", en: "Electronic", category: .classic, fallback: 1014),
        Entry(file: "Doorbell.caf", zh: "門鈴", en: "Doorbell", category: .classic, fallback: nil),
        Entry(file: "new-mail.caf", zh: "新郵件", en: "New Mail", category: .classic, fallback: 1000),
        Entry(file: "Tink.caf", zh: "叮", en: "Tink", category: .classic, fallback: 1103),
        Entry(file: "Tock.caf", zh: "嗒", en: "Tock", category: .classic, fallback: 1104),
        Entry(file: "Swish.caf", zh: "咻", en: "Swish", category: .classic, fallback: nil),
        Entry(file: "health_notification.caf", zh: "健康提醒", en: "Health", category: .classic, fallback: nil),
        Entry(file: "payment_success.caf", zh: "付款成功", en: "Payment Success", category: .classic, fallback: nil),
        Entry(file: "multiway_invitation.caf", zh: "邀請", en: "Invitation", category: .classic, fallback: nil),
        Entry(file: "low_power.caf", zh: "低電量", en: "Low Power", category: .classic, fallback: nil),
    ]

    /// 全部可用鈴聲，第一次存取時掃描一次。
    static let options: [SoundOption] = build()

    private static let index: [String: SoundOption] = {
        Dictionary(uniqueKeysWithValues: options.map { ($0.id, $0) })
    }()

    static func option(id: String) -> SoundOption? {
        index[id]
    }

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

    // MARK: - 建立清單

    private static func build() -> [SoundOption] {
        let fileManager = FileManager.default
        var result: [SoundOption] = []

        for entry in alertEntries + classicEntries {
            let url = URL(fileURLWithPath: uiSoundsRoot).appendingPathComponent(entry.file)
            let id = (entry.file as NSString).deletingPathExtension

            if fileManager.isReadableFile(atPath: url.path) {
                result.append(SoundOption(id: id, name: entry.zh, englishName: entry.en,
                                          category: entry.category, source: .file(url)))
            } else if let fallback = entry.fallback {
                result.append(SoundOption(id: id, name: entry.zh, englishName: entry.en,
                                          category: entry.category, source: .systemID(fallback)))
            }
        }

        result.append(contentsOf: ringtoneOptions())
        return result
    }

    /// 真機上的官方鈴聲（模擬器沒有這個目錄，會自動略過）。
    private static func ringtoneOptions() -> [SoundOption] {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: ringtonesRoot) else { return [] }

        return names
            .filter { ["m4r", "caf", "m4a"].contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted()
            .compactMap { name in
                let url = URL(fileURLWithPath: ringtonesRoot).appendingPathComponent(name)
                guard fileManager.isReadableFile(atPath: url.path) else { return nil }
                let base = (name as NSString).deletingPathExtension
                let pretty = base.replacingOccurrences(of: "_", with: " ")
                return SoundOption(id: "Ringtone/\(base)", name: pretty, englishName: pretty,
                                   category: .ringtone, source: .file(url))
            }
    }

    // MARK: - 通知音效

    /// 本地通知的音效檔必須位於 App 容器內，這裡把選中的系統音效複製到
    /// `Library/Sounds/`，讓背景通知也能用同一顆鈴聲。複製不成功就回傳 nil（改用預設音）。
    static func notificationSoundName(for option: SoundOption) -> String? {
        guard case .file(let url) = option.source,
              url.pathExtension.lowercased() == "caf" else { return nil }

        let fileManager = FileManager.default
        guard let library = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first else { return nil }

        let directory = library.appendingPathComponent("Sounds", isDirectory: true)
        let fileName = option.id.replacingOccurrences(of: "/", with: "_") + ".caf"
        let destination = directory.appendingPathComponent(fileName)

        if !fileManager.fileExists(atPath: destination.path) {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                try fileManager.copyItem(at: url, to: destination)
            } catch {
                return nil
            }
        }
        return fileName
    }
}
