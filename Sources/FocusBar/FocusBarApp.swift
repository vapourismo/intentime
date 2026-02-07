import AppKit

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

private final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let timer = TimerModel()
    private var displayTimer: Timer?

    func applicationWillTerminate(_ notification: Notification) {
        // Ensure timer state is flushed to disk before exit.
        UserDefaults.standard.synchronize()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        timer.onAutoPhaseChange = { [weak self] phase in
            self?.showBreakBanner(for: phase)
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        updateButton()

        // Use a plain Timer in .common mode so it fires even during menu tracking.
        // Combine's receive(on:)/DispatchQueue.main.async don't deliver while
        // NSMenu's event-tracking run loop is active.
        displayTimer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateButton()
        }
        RunLoop.main.add(displayTimer!, forMode: .common)
    }

    private func updateButton() {
        guard let button = statusItem.button else { return }

        let hasTimer = timer.formattedTime != nil
        let hasMessage = timer.message != nil

        if hasTimer || hasMessage {
            if timer.isPaused {
                button.image = NSImage(systemSymbolName: "pause.fill", accessibilityDescription: "Pomodoro Timer")
            } else if timer.phase == .work, let seconds = timer.secondsLeft {
                let progress = 1.0 - Double(seconds) / timer.phaseDuration
                button.image = progressCircleImage(progress: progress)
            } else if timer.phase == .shortBreak || timer.phase == .longBreak {
                button.image = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: "Break")
            } else {
                button.image = NSImage(systemSymbolName: "clock", accessibilityDescription: "Pomodoro Timer")
            }
            var parts: [(text: String, font: NSFont)] = []
            let monoDigitFont = NSFont.monospacedDigitSystemFont(
                ofSize: NSFont.systemFontSize, weight: .regular)
            let regularFont = NSFont.menuBarFont(ofSize: 0)
            if let time = timer.formattedTime {
                parts.append((time, monoDigitFont))
            }
            if let message = timer.message {
                parts.append((message, regularFont))
            }
            let attributed = NSMutableAttributedString(string: " ")
            for (index, part) in parts.enumerated() {
                if index > 0 {
                    attributed.append(NSAttributedString(string: " — "))
                }
                attributed.append(NSAttributedString(
                    string: part.text,
                    attributes: [.font: part.font]))
            }
            button.attributedTitle = attributed
            button.imagePosition = .imageLeading
        } else {
            button.image = NSImage(systemSymbolName: "clock", accessibilityDescription: "Pomodoro Timer")
            button.title = ""
            button.imagePosition = .imageOnly
        }
    }

    private func progressCircleImage(progress: Double) -> NSImage {
        let size: CGFloat = 18
        let lineWidth: CGFloat = 1.5
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }

            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = (min(rect.width, rect.height) - lineWidth) / 2.0

            // Draw background circle (track)
            context.setStrokeColor(NSColor.secondaryLabelColor.cgColor)
            context.setLineWidth(lineWidth)
            context.addArc(center: center, radius: radius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
            context.strokePath()

            // Draw filled progress arc (clockwise from 12 o'clock)
            if progress > 0 {
                let startAngle = CGFloat.pi / 2 // 12 o'clock
                let endAngle = startAngle - CGFloat(progress) * 2 * .pi

                context.setFillColor(NSColor.labelColor.cgColor)
                context.move(to: center)
                context.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
                context.closePath()
                context.fillPath()
            }

            return true
        }
        image.isTemplate = true
        return image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if timer.isRunning || timer.isPaused {
            // Phase info header
            let phaseLabel: String
            switch timer.phase {
            case .work:
                phaseLabel = "Work"
            case .shortBreak:
                phaseLabel = "Short Break"
            case .longBreak:
                phaseLabel = "Long Break"
            }
            let phaseItem = NSMenuItem(title: phaseLabel, action: nil, keyEquivalent: "")
            phaseItem.isEnabled = false
            menu.addItem(phaseItem)
            menu.addItem(.separator())
        }

        // Timer section
        if timer.isRunning {
            if timer.phase == .work {
                let pauseItem = NSMenuItem(title: "Pause", action: #selector(pauseTimer), keyEquivalent: "")
                pauseItem.target = self
                menu.addItem(pauseItem)

                let skipItem = NSMenuItem(title: "Skip to Break", action: #selector(skipPhase), keyEquivalent: "")
                skipItem.target = self
                menu.addItem(skipItem)
            } else {
                let skipItem = NSMenuItem(title: "Skip Break", action: #selector(skipPhase), keyEquivalent: "")
                skipItem.target = self
                menu.addItem(skipItem)
            }

            let stopItem = NSMenuItem(title: "Stop", action: #selector(stopTimer), keyEquivalent: "")
            stopItem.target = self
            menu.addItem(stopItem)
        } else if timer.isPaused {
            let resumeItem = NSMenuItem(title: "Resume", action: #selector(unpauseTimer), keyEquivalent: "")
            resumeItem.target = self
            menu.addItem(resumeItem)

            let stopItem = NSMenuItem(title: "Stop", action: #selector(stopTimer), keyEquivalent: "")
            stopItem.target = self
            menu.addItem(stopItem)
        } else {
            let startItem = NSMenuItem(title: "Start Pomodoro", action: #selector(startTimer), keyEquivalent: "")
            startItem.target = self
            menu.addItem(startItem)

            if timer.hasPreviousSession {
                let continueItem = NSMenuItem(title: "Continue Previous Session", action: #selector(resumeTimer), keyEquivalent: "")
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
    }

    @objc private func startTimer() {
        timer.start()
        updateButton()
    }

    @objc private func resumeTimer() {
        timer.resume()
        updateButton()
    }

    @objc private func pauseTimer() {
        timer.pause()
        updateButton()
    }

    @objc private func unpauseTimer() {
        timer.unpause()
        updateButton()
    }

    @objc private func stopTimer() {
        timer.stop()
        updateButton()
    }

    @objc private func skipPhase() {
        timer.skip()
        updateButton()
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

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let text = input.stringValue
            timer.message = text.isEmpty ? nil : text
            updateButton()
        }
    }

    @objc private func clearMessage() {
        timer.message = nil
        updateButton()
    }

    private func showBreakBanner(for phase: TimerModel.Phase) {
        guard phase == .shortBreak || phase == .longBreak else { return }
        let title = phase == .longBreak ? "Long Break" : "Short Break"
        let body = phase == .longBreak
            ? "Great work! Take a 20-minute break."
            : "Take a 5-minute break."

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 64),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .hudWindow],
            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.titleVisibility = .hidden

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)

        let titleField = NSTextField(labelWithString: title)
        titleField.font = .boldSystemFont(ofSize: 14)
        let bodyField = NSTextField(labelWithString: body)
        bodyField.font = .systemFont(ofSize: 12)
        bodyField.textColor = .secondaryLabelColor

        stack.addArrangedSubview(titleField)
        stack.addArrangedSubview(bodyField)
        panel.contentView = stack

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelSize = panel.frame.size
        let origin = NSPoint(
            x: screenFrame.maxX - panelSize.width - 16,
            y: screenFrame.maxY - panelSize.height - 16)
        panel.setFrameOrigin(origin)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            panel.animator().alphaValue = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.5
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.close()
            })
        }

        NSSound.beep()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
