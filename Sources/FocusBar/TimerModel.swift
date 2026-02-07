import Combine
import Foundation

final class TimerModel: ObservableObject {
    @Published var secondsLeft: Int?
    @Published var formattedTime: String?
    @Published var isRunning: Bool = false

    private let focusDuration: TimeInterval = 25 * 60
    private let endTimeKey = "endTime"
    private var timerCancellable: AnyCancellable?

    private func updateDerived() {
        if let seconds = secondsLeft, seconds > 0 {
            let m = seconds / 60
            let s = seconds % 60
            formattedTime = String(format: "%02d:%02d", m, s)
            isRunning = true
        } else {
            formattedTime = nil
            isRunning = false
        }
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
        updateDerived()
    }

    private func restoreIfNeeded() {
        let endTime = UserDefaults.standard.double(forKey: endTimeKey)
        guard endTime > 0 else { return }

        let remaining = Int(endTime - Date.now.timeIntervalSince1970)
        if remaining > 0 {
            secondsLeft = remaining
            updateDerived()
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
            updateDerived()
        } else {
            stop()
        }
    }
}
