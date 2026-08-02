//
//  SoundPlayer.swift
//  Stopwatch
//

import AVFoundation
import AudioToolbox
import Foundation

/// 負責播放鈴聲，以及「背景持續運作」用的無聲循環音軌。
final class SoundPlayer {

    static let shared = SoundPlayer()

    private var players: [String: AVAudioPlayer] = [:]
    private var keepAlivePlayer: AVAudioPlayer?

    private init() {}

    var isKeepingAlive: Bool { keepAlivePlayer != nil }

    // MARK: - 音訊工作階段

    /// `.playback` 類別可以在響鈴模式關閉（靜音鍵）時照樣出聲，這對提醒 App 是必要的。
    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        // 背景保活時不能一直壓低別的 App 音量，所以只在單純響鈴時使用 duckOthers。
        let options: AVAudioSession.CategoryOptions = isKeepingAlive ? [.mixWithOthers] : [.duckOthers]
        try? session.setCategory(.playback, mode: .default, options: options)
        try? session.setActive(true)
    }

    private func deactivateSessionIfIdle() {
        guard !isKeepingAlive else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - 播放

    func play(_ option: SoundOption, times: Int = 1) {
        let repeatCount = max(times, 1)
        activateSession()

        switch option.source {
        case .file(let url):
            guard let player = player(for: option.id, url: url) else { return }
            player.numberOfLoops = repeatCount - 1
            player.currentTime = 0
            player.play()

        case .systemID(let soundID):
            playSystemSound(soundID, remaining: repeatCount)
        }
    }

    /// 試聽（永遠只響一聲）。
    func preview(_ option: SoundOption) {
        play(option, times: 1)
    }

    func stopAll() {
        for player in players.values where player.isPlaying {
            player.stop()
        }
        deactivateSessionIfIdle()
    }

    private func player(for id: String, url: URL) -> AVAudioPlayer? {
        if let cached = players[id] { return cached }
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.prepareToPlay()
        players[id] = player
        return player
    }

    private func playSystemSound(_ soundID: SystemSoundID, remaining: Int) {
        guard remaining > 0 else { return }
        AudioServicesPlaySystemSoundWithCompletion(soundID) {
            DispatchQueue.main.async {
                SoundPlayer.shared.playSystemSound(soundID, remaining: remaining - 1)
            }
        }
    }

    // MARK: - 背景保活

    /// 播放無聲音軌，讓 App 在鎖定／背景時維持執行，計時器才能準時響鈴。
    /// 需要 Info.plist 的 `UIBackgroundModes = audio`。
    func startKeepAlive() {
        guard keepAlivePlayer == nil, let url = Self.silentTrackURL() else { return }
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }

        player.numberOfLoops = -1
        player.volume = 0
        keepAlivePlayer = player
        activateSession()
        player.play()
    }

    func stopKeepAlive() {
        keepAlivePlayer?.stop()
        keepAlivePlayer = nil
        deactivateSessionIfIdle()
    }

    /// 產生一段 1 秒的無聲 WAV，避免在 App 內夾帶音檔。
    private static func silentTrackURL() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("keep-alive.wav")
        if FileManager.default.fileExists(atPath: url.path) { return url }

        let sampleRate = 44_100
        let channels = 1
        let bitsPerSample = 16
        let byteCount = sampleRate * channels * bitsPerSample / 8  // 1 秒

        var data = Data()
        func appendASCII(_ text: String) { data.append(contentsOf: Array(text.utf8)) }
        func appendUInt32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func appendUInt16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }

        appendASCII("RIFF")
        appendUInt32(UInt32(36 + byteCount))
        appendASCII("WAVE")
        appendASCII("fmt ")
        appendUInt32(16)
        appendUInt16(1)                                                  // PCM
        appendUInt16(UInt16(channels))
        appendUInt32(UInt32(sampleRate))
        appendUInt32(UInt32(sampleRate * channels * bitsPerSample / 8))  // byte rate
        appendUInt16(UInt16(channels * bitsPerSample / 8))               // block align
        appendUInt16(UInt16(bitsPerSample))
        appendASCII("data")
        appendUInt32(UInt32(byteCount))
        data.append(Data(count: byteCount))

        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
