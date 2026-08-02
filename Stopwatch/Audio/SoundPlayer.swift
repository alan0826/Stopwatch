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

    // MARK: - 播放

    func play(_ option: SoundOption, times: Int = 1) {
        activateSession()
        guard let player = player(for: option) else { return }
        player.numberOfLoops = max(times, 1) - 1
        player.currentTime = 0
        player.play()
    }

    /// 試聽（永遠只響一聲）。
    func preview(_ option: SoundOption) {
        play(option, times: 1)
    }

    func stopAll() {
        for player in players.values where player.isPlaying {
            player.stop()
        }
        deactivateSession()
    }

    private func player(for option: SoundOption) -> AVAudioPlayer? {
        if let cached = players[option.id] { return cached }
        guard let url = Bundle.main.url(forResource: option.id, withExtension: option.fileExtension),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.delegate = self
        player.prepareToPlay()
        players[option.id] = player
        return player
    }
}
