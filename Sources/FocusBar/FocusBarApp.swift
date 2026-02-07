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

        let hasTimer = timer.formattedTime != nil
        let hasMessage = timer.message != nil

        if hasTimer || hasMessage {
            button.image = NSImage(systemSymbolName: "clock", accessibilityDescription: "Focus Timer")
            var parts: [String] = []
            if let time = timer.formattedTime {
                parts.append(time)
            }
            if let message = timer.message {
                parts.append(message)
            }
            button.title = " " + parts.joined(separator: " — ")
            button.imagePosition = .imageLeading
        } else {
            button.image = NSImage(systemSymbolName: "clock", accessibilityDescription: "Focus Timer")
            button.title = ""
            button.imagePosition = .imageOnly
        }

        let menu = NSMenu()

        // Timer section
        if timer.isRunning {
            let stopItem = NSMenuItem(title: "Stop Timer", action: #selector(stopTimer), keyEquivalent: "")
            stopItem.target = self
            menu.addItem(stopItem)
        } else {
            let startItem = NSMenuItem(title: "Start Timer", action: #selector(startTimer), keyEquivalent: "")
            startItem.target = self
            menu.addItem(startItem)

            if timer.hasPreviousSession {
                let continueItem = NSMenuItem(title: "Continue Previous Timer", action: #selector(resumeTimer), keyEquivalent: "")
                continueItem.target = self
                menu.addItem(continueItem)
            }
        }

        menu.addItem(.separator())

        // Message section
        if timer.message != nil {
            let editItem = NSMenuItem(title: "Edit Message…", action: #selector(editMessage), keyEquivalent: "")
            editItem.target = self
            menu.addItem(editItem)

            let clearItem = NSMenuItem(title: "Clear Message", action: #selector(clearMessage), keyEquivalent: "")
            clearItem.target = self
            menu.addItem(clearItem)
        } else {
            let setItem = NSMenuItem(title: "Set Message…", action: #selector(editMessage), keyEquivalent: "")
            setItem.target = self
            menu.addItem(setItem)
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

    @objc private func resumeTimer() {
        timer.resume()
    }

    @objc private func stopTimer() {
        timer.stop()
    }

    @objc private func editMessage() {
        let alert = NSAlert()
        alert.messageText = "Focus Message"
        alert.informativeText = "What are you focusing on?"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.placeholderString = "e.g. Write blog post"
        input.stringValue = timer.message ?? ""
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let text = input.stringValue
            timer.setMessage(text.isEmpty ? nil : text)
        }
    }

    @objc private func clearMessage() {
        timer.setMessage(nil)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
