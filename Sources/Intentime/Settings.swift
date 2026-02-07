import Foundation

/// Singleton holding user-configurable Pomodoro durations and session counts,
/// persisted in `UserDefaults`. Changes take effect on the next timer phase
/// (the currently running phase keeps its original duration).
final class Settings {
    static let shared = Settings()

    /// `UserDefaults` keys for each setting.
    private enum DefaultsKey {
        static let workMinutes = "settings.workMinutes"
        static let shortBreakMinutes = "settings.shortBreakMinutes"
        static let longBreakMinutes = "settings.longBreakMinutes"
        static let sessionsBeforeLongBreak = "settings.sessionsBeforeLongBreak"
        static let extendBreakMinutes = "settings.extendBreakMinutes"
        static let blurScreenDuringBreaks = "settings.blurScreenDuringBreaks"
    }

    /// Fallback values used when no persisted value exists (or the stored value is ≤ 0).
    private enum Default {
        static let workMinutes = 25
        static let shortBreakMinutes = 5
        static let longBreakMinutes = 20
        static let sessionsBeforeLongBreak = 4
        static let extendBreakMinutes = 5
    }

    /// Duration of a work (focus) session, in minutes. Default: 25.
    var workMinutes: Int {
        get { stored(DefaultsKey.workMinutes, default: Default.workMinutes) }
        set { UserDefaults.standard.set(newValue, forKey: DefaultsKey.workMinutes) }
    }

    /// Duration of the short break between work sessions, in minutes. Default: 5.
    var shortBreakMinutes: Int {
        get { stored(DefaultsKey.shortBreakMinutes, default: Default.shortBreakMinutes) }
        set { UserDefaults.standard.set(newValue, forKey: DefaultsKey.shortBreakMinutes) }
    }

    /// Duration of the long break after every `sessionsBeforeLongBreak` work sessions, in minutes. Default: 20.
    var longBreakMinutes: Int {
        get { stored(DefaultsKey.longBreakMinutes, default: Default.longBreakMinutes) }
        set { UserDefaults.standard.set(newValue, forKey: DefaultsKey.longBreakMinutes) }
    }

    /// Number of work sessions to complete before triggering a long break. Default: 4.
    var sessionsBeforeLongBreak: Int {
        get { stored(DefaultsKey.sessionsBeforeLongBreak, default: Default.sessionsBeforeLongBreak) }
        set { UserDefaults.standard.set(newValue, forKey: DefaultsKey.sessionsBeforeLongBreak) }
    }

    /// Extra time added when the user chooses "Extend Break" at the end-of-break prompt, in minutes. Default: 5.
    var extendBreakMinutes: Int {
        get { stored(DefaultsKey.extendBreakMinutes, default: Default.extendBreakMinutes) }
        set { UserDefaults.standard.set(newValue, forKey: DefaultsKey.extendBreakMinutes) }
    }

    /// Whether to show a full-screen blur overlay on all displays during breaks. Default: false.
    var blurScreenDuringBreaks: Bool {
        get { UserDefaults.standard.bool(forKey: DefaultsKey.blurScreenDuringBreaks) }
        set { UserDefaults.standard.set(newValue, forKey: DefaultsKey.blurScreenDuringBreaks) }
    }

    /// Reads an integer from `UserDefaults`, falling back to `fallback` when the
    /// stored value is missing or ≤ 0 (guards against invalid/cleared entries).
    private func stored(_ key: String, default fallback: Int) -> Int {
        let val = UserDefaults.standard.integer(forKey: key)
        return val > 0 ? val : fallback
    }
}
