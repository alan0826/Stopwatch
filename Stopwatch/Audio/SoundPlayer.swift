//
//  SoundPlayer.swift
//  Stopwatch
//

import AVFoundation
import AudioToolbox
import Foundation

/// 負責播放鈴聲。
final class SoundPlayer {

    static let shared = SoundPlayer()

    private var players: [String: AVAudioPlayer] = [:]

    private init() {}

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

    // MARK: - 播放

    func play(_ option: SoundOption, times: Int = 1) {
        let repeatCount = max(times, 1)

        switch option.source {
        case .bundled(let name, let ext):
            activateSession()
            guard let player = player(for: option.id, name: name, ext: ext) else { return }
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
        deactivateSession()
    }

    private func player(for id: String, name: String, ext: String) -> AVAudioPlayer? {
        if let cached = players[id] { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: ext),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
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
}
