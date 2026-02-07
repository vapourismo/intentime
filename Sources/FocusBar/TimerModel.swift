import Combine
import Foundation

final class TimerModel: ObservableObject {
    @Published var secondsLeft: Int?

    private let focusDuration: TimeInterval = 25 * 60
    private let endTimeKey = "endTime"
    private var timerCancellable: AnyCancellable?

    var isRunning: Bool { secondsLeft != nil && secondsLeft! > 0 }

    var formattedTime: String? {
        guard let seconds = secondsLeft, seconds > 0 else { return nil }
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    init() {
        restoreIfNeeded()
    }

    func start() {
        let endTime = Date.now.timeIntervalSince1970 + focusDuration
        UserDefaults.standard.set(endTime, forKey: endTimeKey)
        tick()
        startTimer()
    }

    func stop() {
        UserDefaults.standard.removeObject(forKey: endTimeKey)
        secondsLeft = nil
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    private func restoreIfNeeded() {
        let endTime = UserDefaults.standard.double(forKey: endTimeKey)
        guard endTime > 0 else { return }

        let remaining = Int(endTime - Date.now.timeIntervalSince1970)
        if remaining > 0 {
            secondsLeft = remaining
            startTimer()
        } else {
            UserDefaults.standard.removeObject(forKey: endTimeKey)
        }
    }

    private func startTimer() {
        timerCancellable?.cancel()
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    private func tick() {
        let endTime = UserDefaults.standard.double(forKey: endTimeKey)
        guard endTime > 0 else {
            stop()
            return
        }
        let remaining = Int(endTime - Date.now.timeIntervalSince1970)
        if remaining > 0 {
            secondsLeft = remaining
        } else {
            stop()
        }
    }
}
