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
        static let pausedMillisecondsLeft = "pausedMillisecondsLeft"
        // Legacy key used before millisecond precision persistence.
        static let pausedSecondsLeftLegacy = "pausedSecondsLeft"
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
        if pausedMillisecondsLeft() != nil {
            return true
        }
        let endTime = UserDefaults.standard.double(forKey: DefaultsKey.endTime)
        guard endTime > 0 else { return false }
        return remainingSeconds(until: endTime) != nil
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

    /// Pause the running timer, persisting the remaining milliseconds so the session survives a restart.
    func pause() {
        guard !isPaused else { return }
        let remainingMilliseconds = remainingMillisecondsForPause()
        guard remainingMilliseconds > 0 else { return }

        timer?.invalidate()
        timer = nil
        UserDefaults.standard.removeObject(forKey: DefaultsKey.endTime)
        UserDefaults.standard.set(remainingMilliseconds, forKey: DefaultsKey.pausedMillisecondsLeft)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.pausedSecondsLeftLegacy)
        flushDefaults()

        secondsLeft = remainingSeconds(fromMilliseconds: remainingMilliseconds)
        isPaused = true
        updateDerived()
    }

    /// Resume from a paused state, recomputing a new end-time from the saved remaining milliseconds.
    func unpause() {
        guard isPaused, let remainingMilliseconds = pausedMillisecondsLeft() else { return }

        isPaused = false
        UserDefaults.standard.removeObject(forKey: DefaultsKey.pausedMillisecondsLeft)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.pausedSecondsLeftLegacy)

        let endTime = Date.now.timeIntervalSince1970 + (Double(remainingMilliseconds) / 1000.0)
        UserDefaults.standard.set(endTime, forKey: DefaultsKey.endTime)
        flushDefaults()

        secondsLeft = remainingSeconds(fromMilliseconds: remainingMilliseconds)
        updateDerived()
        startTimer()
    }

    /// Stop the timer entirely, clearing all persisted state and resetting to idle.
    func stop() {
        UserDefaults.standard.removeObject(forKey: DefaultsKey.endTime)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.pausedMillisecondsLeft)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.pausedSecondsLeftLegacy)
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
        UserDefaults.standard.removeObject(forKey: DefaultsKey.pausedMillisecondsLeft)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.pausedSecondsLeftLegacy)
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
        UserDefaults.standard.removeObject(forKey: DefaultsKey.pausedMillisecondsLeft)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.pausedSecondsLeftLegacy)
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
        if let pausedMilliseconds = pausedMillisecondsLeft() {
            // Migrate any legacy seconds value to millisecond persistence.
            UserDefaults.standard.set(pausedMilliseconds, forKey: DefaultsKey.pausedMillisecondsLeft)
            UserDefaults.standard.removeObject(forKey: DefaultsKey.pausedSecondsLeftLegacy)
            flushDefaults()

            secondsLeft = remainingSeconds(fromMilliseconds: pausedMilliseconds)
            isPaused = true
            updateDerived()
            return
        }

        let endTime = UserDefaults.standard.double(forKey: DefaultsKey.endTime)
        guard endTime > 0 else { return }

        if let remaining = remainingSeconds(until: endTime) {
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
        if let remaining = remainingSeconds(until: endTime) {
            secondsLeft = remaining
            updateDerived()
        } else {
            advancePhase()
        }
    }

    /// Convert an absolute end-time to whole seconds remaining.
    ///
    /// Uses ceiling to avoid skipping visible values when timer callbacks drift slightly
    /// past exact 1-second boundaries (for example right after unpausing).
    private func remainingSeconds(until endTime: TimeInterval) -> Int? {
        let delta = endTime - Date.now.timeIntervalSince1970
        let seconds = Int(ceil(delta))
        return seconds > 0 ? seconds : nil
    }

    /// Convert an absolute end-time to whole milliseconds remaining.
    private func remainingMilliseconds(until endTime: TimeInterval) -> Int? {
        let delta = endTime - Date.now.timeIntervalSince1970
        let milliseconds = Int(ceil(delta * 1000.0))
        return milliseconds > 0 ? milliseconds : nil
    }

    /// Convert whole milliseconds remaining to display seconds.
    private func remainingSeconds(fromMilliseconds milliseconds: Int) -> Int? {
        guard milliseconds > 0 else { return nil }
        return Int(ceil(Double(milliseconds) / 1000.0))
    }

    /// Read paused milliseconds from defaults (supports legacy seconds key).
    private func pausedMillisecondsLeft() -> Int? {
        let milliseconds = UserDefaults.standard.integer(forKey: DefaultsKey.pausedMillisecondsLeft)
        if milliseconds > 0 {
            return milliseconds
        }

        let legacySeconds = UserDefaults.standard.integer(forKey: DefaultsKey.pausedSecondsLeftLegacy)
        if legacySeconds > 0 {
            return legacySeconds * 1000
        }

        return nil
    }

    /// Compute remaining milliseconds to persist when pausing.
    private func remainingMillisecondsForPause() -> Int {
        let endTime = UserDefaults.standard.double(forKey: DefaultsKey.endTime)
        if let milliseconds = remainingMilliseconds(until: endTime) {
            return milliseconds
        }
        if let secondsLeft, secondsLeft > 0 {
            return secondsLeft * 1000
        }
        return 0
    }
}
