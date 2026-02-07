import SwiftUI

@main
struct FocusBarApp: App {
    @StateObject private var timer = TimerModel()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            if timer.isRunning {
                Button("Stop") { timer.stop() }
            } else {
                Button("Start Focus Session") { timer.start() }
            }
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        } label: {
            if let time = timer.formattedTime {
                Label(time, systemImage: "clock")
            } else {
                Image(systemName: "clock")
            }
        }
    }
}
