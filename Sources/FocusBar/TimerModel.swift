import Foundation

/// Pomodoro state machine that drives the timer lifecycle.
///
/// Manages the countdown, phase transitions (work → short break → … → long break),
/// pause/resume, and persistence of timer state via `UserDefaults`. The timer is
/// **not** auto-restored on launch — call ``resume()`` to pick up a previous session.
///
/// Timer and focus message are independent: the timer can run without a message,
/// and a message can be set without a running timer.
final class TimerModel {
    /// A phase in the Pomodoro cycle.
    enum Phase: String {
        case work
        case shortBreak
        case longBreak
    }

    /// Seconds remaining in the current phase, or `nil` when idle.
    private(set) var secondsLeft: Int?
    /// `secondsLeft` formatted as `"MM:SS"`, or `nil` when idle.
    private(set) var formattedTime: String?
    /// `true` while the countdown is actively ticking (not paused, not idle).
    private(set) var isRunning = false
    /// `true` when the timer has been paused mid-phase by the user.
    private(set) var isPaused = false
    /// `true` after a break ends, waiting for user confirmation to start the next work session.
    private(set) var isWaitingToStart = false
    /// The current phase of the Pomodoro cycle.
    private(set) var phase: Phase = .work
    /// Number of work sessions completed in the current cycle (resets after a long break).
    private(set) var pomodorosCompleted: Int = 0

    /// Called when the phase advances automatically (not on manual skip).
    var onAutoPhaseChange: ((Phase) -> Void)?

    /// Called when a break ends and the model is waiting for user confirmation to start work.
    var onBreakEnded: (() -> Void)?

    private let settings = Settings.shared

    /// The user's focus message displayed in the menu bar.
    ///
    /// Setting this trims whitespace and persists the value to `UserDefaults`.
    /// Setting to `nil` or an empty string clears it.
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
    /// The repeating 1-second timer driving ``tick()``.
    private var timer: Timer?

    /// `UserDefaults` keys for persisted timer state.
    private enum DefaultsKey {
        static let endTime = "endTime"
        static let pausedSecondsLeft = "pausedSecondsLeft"
        static let message = "focusMessage"
        static let phase = "pomodoroPhase"
        static let pomodorosCompleted = "pomodorosCompleted"
    }

    /// Restores persisted message, phase, and pomodoro count from `UserDefaults`.
    ///
    /// Does **not** restore the timer itself — call ``resume()`` to continue a previous session.
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

    /// Resume a previously persisted session (paused or running).
    ///
    /// If the session was paused, restores the paused state. If it was running,
    /// recomputes remaining time from the stored end-time and restarts the timer.
    func resume() {
        restoreTimer()
    }

    /// Start a fresh Pomodoro cycle from the first work session.
    func start() {
        phase = .work
        pomodorosCompleted = 0
        persistPhaseState()
        startPhase()
    }

    /// Skip the current phase and advance to the next one without firing callbacks.
    func skip() {
        advancePhase(notify: false)
    }

    /// Pause the running timer, persisting the remaining seconds so the session survives a restart.
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

    /// Resume from a paused state, recomputing a new end-time from the saved remaining seconds.
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

    /// Stop the timer entirely, clearing all persisted state and resetting to idle.
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

    /// Persist the end-time for the current phase and start the countdown.
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

    /// Extend the break by ``Settings/extendBreakMinutes``, restarting the countdown as a short break.
    ///
    /// Only valid when `isWaitingToStart` is `true` (i.e. the break-ended prompt is showing).
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

    /// Transition to the next phase in the Pomodoro cycle.
    ///
    /// Work → short/long break (auto-starts). Break → work (pauses for user confirmation
    /// via ``onBreakEnded`` unless `notify` is `false`, e.g. on manual skip).
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

    /// Write the current phase and pomodoro count to `UserDefaults`.
    private func persistPhaseState() {
        UserDefaults.standard.set(phase.rawValue, forKey: DefaultsKey.phase)
        UserDefaults.standard.set(pomodorosCompleted, forKey: DefaultsKey.pomodorosCompleted)
        flushDefaults()
    }

    /// Recompute ``formattedTime`` and ``isRunning`` from the current state.
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

    /// Force-sync `UserDefaults` to disk so state survives a crash or force-quit.
    private func flushDefaults() {
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
    }

    /// Restore timer state from `UserDefaults` — either a paused session or a running countdown.
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

    /// Schedule a repeating 1-second timer on the `.common` run loop mode so it fires even during menu tracking.
    private func startTimer() {
        timer?.invalidate()
        timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    /// Read the persisted end-time, update ``secondsLeft``, and advance the phase when time is up.
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
