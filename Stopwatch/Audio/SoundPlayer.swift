//
//  SoundPlayer.swift
//  Stopwatch
//

import AVFoundation
import Foundation

/// 負責在前景播放鈴聲。
final class SoundPlayer: NSObject, AVAudioPlayerDelegate {

    static let shared = SoundPlayer()

    private var players: [String: AVAudioPlayer] = [:]

    private override init() {}

    // MARK: - 音訊工作階段

    /// `.playback` 類別可以在響鈴模式關閉（靜音鍵）時照樣出聲，這對提醒 App 是必要的。
    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.duckOthers])
        try? session.setActive(true)
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// 鈴聲響完就把工作階段交還出去，否則 `.duckOthers` 會一直壓著使用者的音樂。
    private func deactivateSessionIfIdle() {
        guard !players.values.contains(where: { $0.isPlaying }) else { return }
        deactivateSession()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in SoundPlayer.shared.deactivateSessionIfIdle() }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in SoundPlayer.shared.stopAll() }
    }

    // MARK: - 播放

    func play(_ option: SoundOption, times: Int = 1) {
        guard let player = player(for: option) else { return }

        // 試聽時可能在上一顆長鈴聲尚未結束前切到下一顆。若讓多個 player 疊播，
        // 原本乾淨的音效也會混成爆音或雜音，因此任何新播放都先完整停止上一輪。
        stopPlayers()
        activateSession()
        player.numberOfLoops = max(times, 1) - 1
        player.currentTime = 0
        if !player.play() {
            deactivateSession()
        }
    }

    /// 試聽（永遠只響一聲）。
    func preview(_ option: SoundOption) {
        play(option, times: 1)
    }

    func stopAll() {
        stopPlayers()
        deactivateSession()
    }

    private func stopPlayers() {
        for player in players.values {
            player.stop()
            player.currentTime = 0
        }
    }

    private func player(for option: SoundOption) -> AVAudioPlayer? {
        if let cached = players[option.id] { return cached }
        guard let url = Bundle.main.url(forResource: option.id, withExtension: option.fileExtension),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.delegate = self
        // 不預先 prepareToPlay：它會取得音訊資源，閒置快取不應占用通知音訊。
        players[option.id] = player
        return player
    }
}
