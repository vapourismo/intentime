import Foundation

final class Settings {
    static let shared = Settings()

    private enum DefaultsKey {
        static let workMinutes = "settings.workMinutes"
        static let shortBreakMinutes = "settings.shortBreakMinutes"
        static let longBreakMinutes = "settings.longBreakMinutes"
        static let sessionsBeforeLongBreak = "settings.sessionsBeforeLongBreak"
    }

    private enum Default {
        static let workMinutes = 25
        static let shortBreakMinutes = 5
        static let longBreakMinutes = 20
        static let sessionsBeforeLongBreak = 4
    }

    var workMinutes: Int {
        get { stored(DefaultsKey.workMinutes, default: Default.workMinutes) }
        set { UserDefaults.standard.set(newValue, forKey: DefaultsKey.workMinutes) }
    }

    var shortBreakMinutes: Int {
        get { stored(DefaultsKey.shortBreakMinutes, default: Default.shortBreakMinutes) }
        set { UserDefaults.standard.set(newValue, forKey: DefaultsKey.shortBreakMinutes) }
    }

    var longBreakMinutes: Int {
        get { stored(DefaultsKey.longBreakMinutes, default: Default.longBreakMinutes) }
        set { UserDefaults.standard.set(newValue, forKey: DefaultsKey.longBreakMinutes) }
    }

    var sessionsBeforeLongBreak: Int {
        get { stored(DefaultsKey.sessionsBeforeLongBreak, default: Default.sessionsBeforeLongBreak) }
        set { UserDefaults.standard.set(newValue, forKey: DefaultsKey.sessionsBeforeLongBreak) }
    }

    private func stored(_ key: String, default fallback: Int) -> Int {
        let val = UserDefaults.standard.integer(forKey: key)
        return val > 0 ? val : fallback
    }
}
