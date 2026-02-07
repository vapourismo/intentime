import Foundation

final class TimerModel {
    enum Phase: String {
        case work
        case shortBreak
        case longBreak
    }

    private(set) var secondsLeft: Int?
    private(set) var formattedTime: String?
    private(set) var isRunning = false
    private(set) var isPaused = false
    private(set) var isWaitingToStart = false
    private(set) var phase: Phase = .work
    private(set) var pomodorosCompleted: Int = 0

    /// Called when the phase advances automatically (not on manual skip).
    var onAutoPhaseChange: ((Phase) -> Void)?

    /// Called when a break ends and the model is waiting for user confirmation to start work.
    var onBreakEnded: (() -> Void)?

    private let settings = Settings.shared

    var message: String? {
        get { _message }
        set {
            let trimmed = newValue?.trimmingCharacters(in: .whitespaces)
            if let trimmed, !trimmed.isEmpty {
                _message = trimmed
                UserDefaults.standard.set(trimmed, forKey: DefaultsKey.message)
            } else {
                _message = nil
                UserDefaults.standard.removeObject(forKey: DefaultsKey.message)
            }
            flushDefaults()
        }
    }

    /// Duration for the current phase (reads from Settings).
    var phaseDuration: TimeInterval {
        switch phase {
        case .work: return TimeInterval(settings.workMinutes * 60)
        case .shortBreak: return TimeInterval(settings.shortBreakMinutes * 60)
        case .longBreak: return TimeInterval(settings.longBreakMinutes * 60)
        }
    }

    private var _message: String?
    private var timer: Timer?

    private enum DefaultsKey {
        static let endTime = "endTime"
        static let pausedSecondsLeft = "pausedSecondsLeft"
        static let message = "focusMessage"
        static let phase = "pomodoroPhase"
        static let pomodorosCompleted = "pomodorosCompleted"
    }

    init() {
        _message = UserDefaults.standard.string(forKey: DefaultsKey.message)
        if let savedPhase = UserDefaults.standard.string(forKey: DefaultsKey.phase),
           let restored = Phase(rawValue: savedPhase) {
            phase = restored
        }
        pomodorosCompleted = UserDefaults.standard.integer(forKey: DefaultsKey.pomodorosCompleted)
    }

    /// Whether a previous session is persisted and still has time remaining.
    var hasPreviousSession: Bool {
        if UserDefaults.standard.integer(forKey: DefaultsKey.pausedSecondsLeft) > 0 {
            return true
        }
        let endTime = UserDefaults.standard.double(forKey: DefaultsKey.endTime)
        guard endTime > 0 else { return false }
        return Int(endTime - Date.now.timeIntervalSince1970) > 0
    }

    func resume() {
        restoreTimer()
    }

    func start() {
        phase = .work
        pomodorosCompleted = 0
        persistPhaseState()
        startPhase()
    }

    func skip() {
        advancePhase(notify: false)
    }

    func pause() {
        guard let remaining = secondsLeft, remaining > 0, !isPaused else { return }
        timer?.invalidate()
        timer = nil
        UserDefaults.standard.removeObject(forKey: DefaultsKey.endTime)
        UserDefaults.standard.set(remaining, forKey: DefaultsKey.pausedSecondsLeft)
        flushDefaults()
        isPaused = true
        updateDerived()
    }

    func unpause() {
        guard isPaused, let remaining = secondsLeft, remaining > 0 else { return }
        isPaused = false
        UserDefaults.standard.removeObject(forKey: DefaultsKey.pausedSecondsLeft)
        let endTime = Date.now.timeIntervalSince1970 + Double(remaining)
        UserDefaults.standard.set(endTime, forKey: DefaultsKey.endTime)
        flushDefaults()
        updateDerived()
        startTimer()
    }

    func stop() {
        UserDefaults.standard.removeObject(forKey: DefaultsKey.endTime)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.pausedSecondsLeft)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.phase)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.pomodorosCompleted)
        flushDefaults()
        isPaused = false
        isWaitingToStart = false
        secondsLeft = nil
        phase = .work
        pomodorosCompleted = 0
        timer?.invalidate()
        timer = nil
        updateDerived()
    }

    // MARK: - Private

    private func startPhase() {
        let endTime = Date.now.timeIntervalSince1970 + phaseDuration
        UserDefaults.standard.set(endTime, forKey: DefaultsKey.endTime)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.pausedSecondsLeft)
        flushDefaults()
        tick()
        startTimer()
    }

    /// Start the next work phase. Called by the UI after the user confirms.
    func startNextWork() {
        guard isWaitingToStart else { return }
        isWaitingToStart = false
        startPhase()
    }

    /// Extend the break by the configured extend-break duration.
    func extendBreak() {
        guard isWaitingToStart else { return }
        isWaitingToStart = false
        phase = .shortBreak
        persistPhaseState()
        let duration = TimeInterval(settings.extendBreakMinutes * 60)
        let endTime = Date.now.timeIntervalSince1970 + duration
        UserDefaults.standard.set(endTime, forKey: DefaultsKey.endTime)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.pausedSecondsLeft)
        flushDefaults()
        tick()
        startTimer()
    }

    private func advancePhase(notify: Bool = true) {
        timer?.invalidate()
        timer = nil

        let wasBreak = phase == .shortBreak || phase == .longBreak

        switch phase {
        case .work:
            pomodorosCompleted += 1
            if pomodorosCompleted >= settings.sessionsBeforeLongBreak {
                phase = .longBreak
            } else {
                phase = .shortBreak
            }
        case .shortBreak:
            phase = .work
        case .longBreak:
            phase = .work
            pomodorosCompleted = 0
        }

        persistPhaseState()

        if wasBreak && notify {
            // Break ended — wait for user confirmation before starting work.
            secondsLeft = nil
            isRunning = false
            isWaitingToStart = true
            updateDerived()
            onBreakEnded?()
            return
        }

        if notify {
            onAutoPhaseChange?(phase)
        }
        startPhase()
    }

    private func persistPhaseState() {
        UserDefaults.standard.set(phase.rawValue, forKey: DefaultsKey.phase)
        UserDefaults.standard.set(pomodorosCompleted, forKey: DefaultsKey.pomodorosCompleted)
        flushDefaults()
    }

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

    private func flushDefaults() {
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
    }

    private func restoreTimer() {
        let pausedSeconds = UserDefaults.standard.integer(forKey: DefaultsKey.pausedSecondsLeft)
        if pausedSeconds > 0 {
            secondsLeft = pausedSeconds
            isPaused = true
            updateDerived()
            return
        }

        let endTime = UserDefaults.standard.double(forKey: DefaultsKey.endTime)
        guard endTime > 0 else { return }

        let remaining = Int(endTime - Date.now.timeIntervalSince1970)
        if remaining > 0 {
            secondsLeft = remaining
            updateDerived()
            startTimer()
        } else {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.endTime)
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func tick() {
        let endTime = UserDefaults.standard.double(forKey: DefaultsKey.endTime)
        guard endTime > 0 else {
            stop()
            return
        }
        let remaining = Int(endTime - Date.now.timeIntervalSince1970)
        if remaining > 0 {
            secondsLeft = remaining
            updateDerived()
        } else {
            advancePhase()
        }
    }
}
