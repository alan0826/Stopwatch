//
//  SoundCatalog.swift
//  Stopwatch
//

import AVFoundation
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
        ("silver-bell", "銀鈴", "Silver Bell"),
        ("crystal", "水晶", "Crystal"),
        ("breeze", "微風", "Breeze"),
        ("sunrise", "晨光", "Sunrise"),
        ("moonlight", "月光", "Moonlight"),
        ("beacon", "信標", "Beacon"),
        ("sparkle", "星光", "Sparkle"),
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

    /// 背景通知要用的鈴聲。
    ///
    /// `UNNotificationSound` 本身沒有「播放幾次」的設定。若直接交給系統原始音檔，
    /// 不論前景設定幾次，背景都只會響一次。因此 2～5 次連響會先在 Library/Sounds
    /// 準備成單一重複音檔；系統仍只送一張通知，但會完整播放指定次數。
    static func notificationSound(for soundID: String, times: Int) -> UNNotificationSound {
        guard let name = backgroundSoundName(for: soundID, times: times) else { return .default }
        return UNNotificationSound(named: UNNotificationSoundName(name))
    }

    /// AlarmKit 與本地通知共用同一份已處理好連響次數的音檔。
    static func backgroundSoundName(for soundID: String, times: Int) -> String? {
        guard let option = resolved(id: soundID) else { return nil }
        let repeatCount = min(max(times, 1), 5)
        guard repeatCount > 1 else { return option.notificationSoundName }
        return repeatedNotificationSoundName(for: option, times: repeatCount)
            ?? option.notificationSoundName
    }

    /// 連響快取的共同命名片段，`pruneRepeatCache` 靠它認出自己產生的檔案。
    private static let repeatMarker = "-repeat-"
    /// 寫到一半的暫存檔。清理時要跳過，否則可能刪掉另一條路徑正在寫的檔案。
    private static let repeatTemporarySuffix = "-repeat-writing.wav"

    private static var repeatCacheDirectory: URL? {
        FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Sounds", isDirectory: true)
    }

    /// iOS 會從 App bundle 或 Library/Sounds 尋找自訂通知音效。
    /// 檔名帶版本，日後若替換原始鈴聲，只要提高版本就不會誤用舊快取。
    private static func repeatedNotificationSoundName(for option: SoundOption,
                                                      times: Int) -> String? {
        // v2：原始鈴聲已重新去除爆音，舊快取必須作廢，否則已安裝的裝置會一直
        // 沿用帶雜音的那份連響檔。
        let fileName = "\(option.id)\(repeatMarker)\(times)-v2.wav"
        let fileManager = FileManager.default
        guard let soundsDirectory = repeatCacheDirectory,
              let sourceURL = Bundle.main.url(forResource: option.id,
                                              withExtension: option.fileExtension)
        else { return nil }

        let destinationURL = soundsDirectory.appendingPathComponent(fileName)
        do {
            try fileManager.createDirectory(at: soundsDirectory,
                                            withIntermediateDirectories: true,
                                            attributes: [.protectionKey: FileProtectionType.none])
            // 只有可重新產生的鈴聲使用此保護等級，提醒資料仍維持原本保護。
            try fileManager.setAttributes([.protectionKey: FileProtectionType.none],
                                          ofItemAtPath: soundsDirectory.path)
            if fileManager.fileExists(atPath: destinationURL.path) {
                // 一併修正已安裝版本產生的舊快取。
                try fileManager.setAttributes([.protectionKey: FileProtectionType.none],
                                              ofItemAtPath: destinationURL.path)
                return fileName
            }
            let source = try AVAudioFile(forReading: sourceURL)
            let duration = Double(source.length) / source.processingFormat.sampleRate
            // 自訂通知音效超過 30 秒時，iOS 會改播預設音效。
            guard duration * Double(times) < 30 else { return nil }

            let temporaryURL = soundsDirectory
                .appendingPathComponent("\(option.id)\(repeatTemporarySuffix)")
            try? fileManager.removeItem(at: temporaryURL)

            var destination: AVAudioFile? = try AVAudioFile(forWriting: temporaryURL,
                                              settings: source.fileFormat.settings)
            let bufferCapacity = AVAudioFrameCount(min(source.length, 65_536))
            guard bufferCapacity > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: source.processingFormat,
                                                frameCapacity: bufferCapacity)
            else { return nil }

            for _ in 0..<times {
                source.framePosition = 0
                while source.framePosition < source.length {
                    try source.read(into: buffer)
                    guard buffer.frameLength > 0 else { break }
                    try destination?.write(from: buffer)
                }
            }
            // 關閉寫入器、完成 WAV 標頭後，才把檔案交給系統通知使用。
            destination = nil
            try fileManager.setAttributes([.protectionKey: FileProtectionType.none],
                                          ofItemAtPath: temporaryURL.path)
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            return fileName
        } catch {
            // 產生失敗時仍使用原始音效，至少不會讓通知完全無聲。
            return nil
        }
    }

    // MARK: - 清理

    /// 刪掉 Library/Sounds 裡已經沒人引用的連響檔。
    ///
    /// 連響檔是依「鈴聲 × 次數 × 版本」快取出來的，而且不會自己消失：換掉原始
    /// 鈴聲而提高版本、把某顆鈴聲下架、或使用者改了連響次數之後，舊檔就只是佔著
    /// 空間。這裡不去比對版本字串，而是直接留下「現在真的被待送通知引用的那幾個
    /// 檔名」，其餘一律刪除——這樣日後再換鈴聲也不必記得同步改清理規則。
    ///
    /// 必須在待送通知重排完成之後才呼叫。提早清理會把還被舊通知指著的檔案刪掉，
    /// 那些通知就會改響系統預設音。
    static func pruneRepeatCache(keeping keep: Set<String>) {
        let fileManager = FileManager.default
        guard let soundsDirectory = repeatCacheDirectory,
              let entries = try? fileManager.contentsOfDirectory(at: soundsDirectory,
                                                                 includingPropertiesForKeys: nil)
        else { return }

        // 同版本音檔數量有界（16 × 4），保留以供剛送達或延遲交付的通知播放。
        // pending 清單不包含已送達、但系統仍可能尚未讀取音效的通知。
        let currentNames = Set(options.flatMap { option in
            (2...5).map { "\(option.id)\(repeatMarker)\($0)-v2.wav" }
        })
        for entry in entries {
            let name = entry.lastPathComponent
            guard name.contains(repeatMarker),
                  !name.hasSuffix(repeatTemporarySuffix),
                  !keep.contains(name),
                  !currentNames.contains(name)
            else { continue }
            try? fileManager.removeItem(at: entry)
        }
    }
}
