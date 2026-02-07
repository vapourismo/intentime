import Combine
import Foundation

final class TimerModel: ObservableObject {
    @Published var secondsLeft: Int?
    @Published var formattedTime: String?
    @Published var isRunning: Bool = false
    @Published var isPaused: Bool = false
    @Published var message: String?

    let focusDuration: TimeInterval = 25 * 60
    private let endTimeKey = "endTime"
    private let pausedSecondsKey = "pausedSecondsLeft"
    private let messageKey = "focusMessage"
    private var timerCancellable: AnyCancellable?

    private func updateDerived() {
        if let seconds = secondsLeft, seconds > 0 {
            let m = seconds / 60
            let s = seconds % 60
            formattedTime = String(format: "%02d:%02d", m, s)
            isRunning = !isPaused
        } else {
            formattedTime = nil
            isRunning = false
        }
    }

    /// Whether a previous session is persisted and still has time remaining.
    var hasPreviousSession: Bool {
        // Check for a paused session
        if UserDefaults.standard.integer(forKey: pausedSecondsKey) > 0 {
            return true
        }
        // Check for a running session
        let endTime = UserDefaults.standard.double(forKey: endTimeKey)
        guard endTime > 0 else { return false }
        return Int(endTime - Date.now.timeIntervalSince1970) > 0
    }

    init() {
        // Restore persisted message (independent of timer)
        message = UserDefaults.standard.string(forKey: messageKey)
    }

    func resume() {
        restoreTimer()
    }

    func start() {
        let endTime = Date.now.timeIntervalSince1970 + focusDuration
        UserDefaults.standard.set(endTime, forKey: endTimeKey)
        UserDefaults.standard.removeObject(forKey: pausedSecondsKey)
        flushDefaults()
        tick()
        startTimer()
    }

    func pause() {
        guard let remaining = secondsLeft, remaining > 0, !isPaused else { return }
        timerCancellable?.cancel()
        timerCancellable = nil
        UserDefaults.standard.removeObject(forKey: endTimeKey)
        UserDefaults.standard.set(remaining, forKey: pausedSecondsKey)
        flushDefaults()
        isPaused = true
        updateDerived()
    }

    func unpause() {
        guard isPaused, let remaining = secondsLeft, remaining > 0 else { return }
        isPaused = false
        UserDefaults.standard.removeObject(forKey: pausedSecondsKey)
        let endTime = Date.now.timeIntervalSince1970 + Double(remaining)
        UserDefaults.standard.set(endTime, forKey: endTimeKey)
        flushDefaults()
        updateDerived()
        startTimer()
    }

    func stop() {
        UserDefaults.standard.removeObject(forKey: endTimeKey)
        UserDefaults.standard.removeObject(forKey: pausedSecondsKey)
        flushDefaults()
        isPaused = false
        secondsLeft = nil
        timerCancellable?.cancel()
        timerCancellable = nil
        updateDerived()
    }

    func setMessage(_ text: String?) {
        let trimmed = text?.trimmingCharacters(in: .whitespaces)
        if let trimmed, !trimmed.isEmpty {
            message = trimmed
            UserDefaults.standard.set(trimmed, forKey: messageKey)
        } else {
            message = nil
            UserDefaults.standard.removeObject(forKey: messageKey)
        }
        flushDefaults()
    }

    private func flushDefaults() {
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
    }

    private func restoreTimer() {
        // Check for a paused session first
        let pausedSeconds = UserDefaults.standard.integer(forKey: pausedSecondsKey)
        if pausedSeconds > 0 {
            secondsLeft = pausedSeconds
            isPaused = true
            updateDerived()
            return
        }

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
