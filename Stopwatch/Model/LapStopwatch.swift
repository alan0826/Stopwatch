//
//  LapStopwatch.swift
//  Stopwatch
//

import Foundation
import Observation

/// 內建時鐘那種單純的碼錶：起點／停止 + 圈數／重置。
@Observable
final class LapStopwatch {

    struct Lap: Identifiable, Hashable {
        let id = UUID()
        let index: Int
        let duration: TimeInterval
    }

    private(set) var isRunning = false
    private(set) var laps: [Lap] = []
    private(set) var displayNow = Date()

    private var startedAt: Date?
    private var accumulated: TimeInterval = 0
    private var completedLapsTotal: TimeInterval = 0
    private var ticker: Timer?

    /// 總經過時間。
    var elapsed: TimeInterval {
        accumulated + (startedAt.map { displayNow.timeIntervalSince($0) } ?? 0)
    }

    private var preciseElapsed: TimeInterval {
        accumulated + (startedAt.map { Date().timeIntervalSince($0) } ?? 0)
    }

    /// 進行中的這一圈。
    var currentLapDuration: TimeInterval {
        max(elapsed - completedLapsTotal, 0)
    }

    var currentLapIndex: Int { laps.count + 1 }

    var hasStarted: Bool { isRunning || elapsed > 0 }

    /// 三圈以上才標示最快／最慢，與系統碼錶一致。
    private var comparableLaps: [Lap] { laps.count >= 3 ? laps : [] }
    var fastestLapID: UUID? { comparableLaps.min { $0.duration < $1.duration }?.id }
    var slowestLapID: UUID? { comparableLaps.max { $0.duration < $1.duration }?.id }

    // MARK: - 控制

    func toggle() {
        isRunning ? stop() : start()
    }

    /// 執行中是「圈數」，停止時是「重置」。
    func lapOrReset() {
        isRunning ? recordLap() : reset()
    }

    private func start() {
        guard !isRunning else { return }
        startedAt = Date()
        isRunning = true
        displayNow = Date()
        startTicker()
    }

    private func stop() {
        guard isRunning else { return }
        accumulated = preciseElapsed
        startedAt = nil
        isRunning = false
        displayNow = Date()
        stopTicker()
    }

    private func recordLap() {
        let total = preciseElapsed
        laps.insert(Lap(index: currentLapIndex, duration: total - completedLapsTotal), at: 0)
        completedLapsTotal = total
    }

    func reset() {
        stopTicker()
        isRunning = false
        startedAt = nil
        accumulated = 0
        completedLapsTotal = 0
        laps.removeAll()
        displayNow = Date()
    }

    // MARK: - 計時器

    private func startTicker() {
        stopTicker()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async { self.displayNow = Date() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    func refresh() {
        displayNow = Date()
    }
}
