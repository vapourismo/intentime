import AppKit
import Combine

@main
enum FocusBarApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let timer = TimerModel()
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusItem()

        timer.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateStatusItem()
                }
            }
            .store(in: &cancellables)
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }

        if let time = timer.formattedTime {
            button.image = NSImage(systemSymbolName: "clock", accessibilityDescription: "Focus Timer")
            button.title = " \(time)"
            button.imagePosition = .imageLeading
        } else {
            button.image = NSImage(systemSymbolName: "clock", accessibilityDescription: "Focus Timer")
            button.title = ""
            button.imagePosition = .imageOnly
        }

        let menu = NSMenu()
        if timer.isRunning {
            let stopItem = NSMenuItem(title: "Stop", action: #selector(stopTimer), keyEquivalent: "")
            stopItem.target = self
            menu.addItem(stopItem)
        } else {
            let startItem = NSMenuItem(title: "Start Focus Session", action: #selector(startTimer), keyEquivalent: "")
            startItem.target = self
            menu.addItem(startItem)
        }
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    @objc private func startTimer() {
        timer.start()
    }

    @objc private func stopTimer() {
        timer.stop()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
