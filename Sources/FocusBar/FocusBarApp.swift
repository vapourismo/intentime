import AppKit
import Carbon

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
    private var promptPanel: NSPanel?
    private var messagePanel: NSPanel?
    private var globalHotKey: GlobalHotKey?

    func applicationWillTerminate(_ notification: Notification) {
        // Ensure timer state is flushed to disk before exit.
        UserDefaults.standard.synchronize()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        timer.onAutoPhaseChange = { [weak self] phase in
            self?.showPhaseBanner(for: phase)
        }
        timer.onBreakEnded = { [weak self] in
            self?.showBreakEndedPrompt()
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

        // System-wide hotkey: Cmd+Shift+Space to set/edit the focus message.
        globalHotKey = GlobalHotKey(
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(cmdKey | shiftKey)
        ) { [weak self] in
            self?.showMessageInput()
        }
    }

    private func updateButton() {
        guard let button = statusItem.button else { return }

        let hasTimer = timer.formattedTime != nil
        let hasMessage = timer.message != nil

        if timer.isWaitingToStart {
            button.image = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: "Break Over")
            if let message = timer.message {
                let regularFont = NSFont.menuBarFont(ofSize: 0)
                let attributed = NSMutableAttributedString(string: " ")
                attributed.append(NSAttributedString(
                    string: message,
                    attributes: [.font: regularFont]))
                button.attributedTitle = attributed
                button.imagePosition = .imageLeading
            } else {
                button.title = ""
                button.imagePosition = .imageOnly
            }
        } else if hasTimer || hasMessage {
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
        if timer.isWaitingToStart {
            let headerItem = NSMenuItem(title: "Break's Over", action: nil, keyEquivalent: "")
            headerItem.isEnabled = false
            menu.addItem(headerItem)
            menu.addItem(.separator())

            let continueItem = NSMenuItem(title: "Continue Working", action: #selector(continueFromPrompt), keyEquivalent: "")
            continueItem.target = self
            menu.addItem(continueItem)

            let extendItem = NSMenuItem(title: "Extend Break (+\(Settings.shared.extendBreakMinutes) min)", action: #selector(extendBreakFromPrompt), keyEquivalent: "")
            extendItem.target = self
            menu.addItem(extendItem)

            let stopItem = NSMenuItem(title: "Stop", action: #selector(stopFromPrompt), keyEquivalent: "")
            stopItem.target = self
            menu.addItem(stopItem)
        } else if timer.isRunning {
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
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

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
        showMessageInput()
    }

    private func showMessageInput() {
        if let existing = messagePanel, existing.isVisible {
            dismissMessagePanel()
            return
        }

        let panelWidth: CGFloat = 400
        let panelHeight: CGFloat = 48

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.titled, .fullSizeContentView, .hudWindow, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true

        let textField = MessageTextField(frame: .zero)
        textField.placeholderString = "What are you focusing on?"
        textField.font = .systemFont(ofSize: 18)
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.stringValue = timer.message ?? ""
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.target = self
        textField.action = #selector(messageFieldSubmitted(_:))
        textField.onEscape = { [weak self] in self?.dismissMessagePanel() }

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))
        contentView.addSubview(textField)
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            textField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            textField.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
        panel.contentView = contentView

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let origin = NSPoint(
            x: screenFrame.midX - panelWidth / 2,
            y: screenFrame.midY + screenFrame.height * 0.15)
        panel.setFrameOrigin(origin)

        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeFirstResponder(textField)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 1
        }

        messagePanel = panel
    }

    @objc private func messageFieldSubmitted(_ sender: NSTextField) {
        let text = sender.stringValue.trimmingCharacters(in: .whitespaces)
        timer.message = text.isEmpty ? nil : text
        updateButton()
        dismissMessagePanel()
    }

    private func dismissMessagePanel() {
        guard let panel = messagePanel else { return }
        messagePanel = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.close()
        })
    }

    @objc private func clearMessage() {
        timer.message = nil
        updateButton()
    }

    private func flashScreenBorder() {
        let glowWidth: CGFloat = 40
        let color = NSColor.systemOrange

        for screen in NSScreen.screens {
            let frame = screen.frame
            let window = NSWindow(
                contentRect: frame,
                styleMask: [.borderless],
                backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .screenSaver
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .stationary]

            let borderView = BorderFlashView(frame: NSRect(origin: .zero, size: frame.size))
            borderView.glowWidth = glowWidth
            borderView.glowColor = color
            window.contentView = borderView
            window.setFrame(frame, display: true)
            window.alphaValue = 1
            window.orderFrontRegardless()
            self.flashWindows.append(window)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 2.0
                    window.animator().alphaValue = 0
                }, completionHandler: { [weak self] in
                    window.close()
                    self?.flashWindows.removeAll { $0 === window }
                })
            }
        }
    }

    private func showPhaseBanner(for phase: TimerModel.Phase) {
        guard phase == .shortBreak || phase == .longBreak else { return }
        flashScreenBorder()
        let settings = Settings.shared
        let title = phase == .longBreak ? "Long Break" : "Short Break"
        let minutes = phase == .longBreak ? settings.longBreakMinutes : settings.shortBreakMinutes
        let body = phase == .longBreak
            ? "Great work! Take a \(minutes)-minute break."
            : "Take a \(minutes)-minute break."

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

    private func showBreakEndedPrompt() {
        dismissPromptPanel()

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 88),
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
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)

        let titleField = NSTextField(labelWithString: "Break's Over")
        titleField.font = .boldSystemFont(ofSize: 14)
        let bodyField = NSTextField(labelWithString: "Ready to start the next work session?")
        bodyField.font = .systemFont(ofSize: 12)
        bodyField.textColor = .secondaryLabelColor

        let continueButton = NSButton(title: "Continue", target: self, action: #selector(continueFromPrompt))
        continueButton.bezelStyle = .rounded
        continueButton.keyEquivalent = "\r"
        let extendButton = NSButton(title: "+\(Settings.shared.extendBreakMinutes) min", target: self, action: #selector(extendBreakFromPrompt))
        extendButton.bezelStyle = .rounded
        let stopButton = NSButton(title: "Stop", target: self, action: #selector(stopFromPrompt))
        stopButton.bezelStyle = .rounded

        let buttonStack = NSStackView(views: [continueButton, extendButton, stopButton])
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 8

        stack.addArrangedSubview(titleField)
        stack.addArrangedSubview(bodyField)
        stack.addArrangedSubview(buttonStack)
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

        promptPanel = panel
        NSSound.beep()
    }

    private func dismissPromptPanel() {
        promptPanel?.close()
        promptPanel = nil
    }

    @objc private func continueFromPrompt() {
        dismissPromptPanel()
        timer.startNextWork()
        updateButton()
    }

    @objc private func extendBreakFromPrompt() {
        dismissPromptPanel()
        timer.extendBreak()
        updateButton()
    }

    @objc private func stopFromPrompt() {
        dismissPromptPanel()
        timer.stop()
        updateButton()
    }

    private var flashWindows: [NSWindow] = []
    private var settingsPanel: NSPanel?

    @objc private func openSettings() {
        if let existing = settingsPanel, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settings = Settings.shared

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled, .closable, .hudWindow, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.title = "Settings"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false

        let grid = NSGridView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 10
        grid.columnSpacing = 10

        func makeStepperRow(value: Int, min: Int, max: Int) -> (view: NSView, stepper: NSStepper) {
            let field = NSTextField(frame: .zero)
            field.integerValue = value
            field.alignment = .right
            field.widthAnchor.constraint(equalToConstant: 50).isActive = true
            let formatter = NumberFormatter()
            formatter.minimum = NSNumber(value: min)
            formatter.maximum = NSNumber(value: max)
            formatter.allowsFloats = false
            field.formatter = formatter

            let stepper = NSStepper()
            stepper.minValue = Double(min)
            stepper.maxValue = Double(max)
            stepper.increment = 1
            stepper.valueWraps = false
            stepper.integerValue = value

            field.bind(.value, to: stepper, withKeyPath: "integerValue", options: nil)
            stepper.bind(.value, to: field, withKeyPath: "integerValue", options: nil)

            let stack = NSStackView(views: [field, stepper])
            stack.orientation = .horizontal
            stack.spacing = 4
            return (stack, stepper)
        }

        let workRow = makeStepperRow(value: settings.workMinutes, min: 1, max: 120)
        let shortBreakRow = makeStepperRow(value: settings.shortBreakMinutes, min: 1, max: 60)
        let longBreakRow = makeStepperRow(value: settings.longBreakMinutes, min: 1, max: 120)
        let sessionsRow = makeStepperRow(value: settings.sessionsBeforeLongBreak, min: 1, max: 20)
        let extendBreakRow = makeStepperRow(value: settings.extendBreakMinutes, min: 1, max: 60)

        func label(_ text: String) -> NSTextField {
            let l = NSTextField(labelWithString: text)
            l.alignment = .right
            return l
        }

        grid.addRow(with: [label("Work duration (min):"), workRow.view])
        grid.addRow(with: [label("Short break (min):"), shortBreakRow.view])
        grid.addRow(with: [label("Long break (min):"), longBreakRow.view])
        grid.addRow(with: [label("Sessions before long break:"), sessionsRow.view])
        grid.addRow(with: [label("Extend break (min):"), extendBreakRow.view])

        let saveButton = NSButton(title: "Save", target: nil, action: nil)
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"

        let contentView = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
        contentView.translatesAutoresizingMaskIntoConstraints = false
        grid.translatesAutoresizingMaskIntoConstraints = false
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(grid)
        contentView.addSubview(saveButton)

        panel.contentView = contentView

        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            grid.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            saveButton.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 16),
            saveButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            saveButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])

        saveButton.target = self
        saveButton.action = #selector(saveSettings(_:))

        // Store steppers so we can read them on save.
        panel.contentView?.setAssociatedFields(
            work: workRow.stepper, shortBreak: shortBreakRow.stepper,
            longBreak: longBreakRow.stepper, sessions: sessionsRow.stepper,
            extendBreak: extendBreakRow.stepper)

        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsPanel = panel
    }

    @objc private func saveSettings(_ sender: Any?) {
        guard let contentView = settingsPanel?.contentView,
              let fields = contentView.associatedFields() else { return }
        let settings = Settings.shared
        settings.workMinutes = fields.work.integerValue
        settings.shortBreakMinutes = fields.shortBreak.integerValue
        settings.longBreakMinutes = fields.longBreak.integerValue
        settings.sessionsBeforeLongBreak = fields.sessions.integerValue
        settings.extendBreakMinutes = fields.extendBreak.integerValue
        settingsPanel?.close()
        settingsPanel = nil
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

// MARK: - Message text field (Escape handling)

private final class MessageTextField: NSTextField {
    var onEscape: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

// MARK: - Associated fields helper

private struct SettingsFields {
    let work: NSStepper
    let shortBreak: NSStepper
    let longBreak: NSStepper
    let sessions: NSStepper
    let extendBreak: NSStepper
}

// MARK: - Border flash view

private final class BorderFlashView: NSView {
    var glowWidth: CGFloat = 40
    var glowColor: NSColor = .systemGreen

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let w = glowWidth
        // Draw gradient strips along each edge.
        drawEdge(context: context, rect: NSRect(x: 0, y: 0, width: bounds.width, height: w),
                 startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: w)) // bottom
        drawEdge(context: context, rect: NSRect(x: 0, y: bounds.height - w, width: bounds.width, height: w),
                 startPoint: CGPoint(x: 0, y: bounds.height), endPoint: CGPoint(x: 0, y: bounds.height - w)) // top
        drawEdge(context: context, rect: NSRect(x: 0, y: 0, width: w, height: bounds.height),
                 startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: w, y: 0)) // left
        drawEdge(context: context, rect: NSRect(x: bounds.width - w, y: 0, width: w, height: bounds.height),
                 startPoint: CGPoint(x: bounds.width, y: 0), endPoint: CGPoint(x: bounds.width - w, y: 0)) // right
    }

    private func drawEdge(context: CGContext, rect: NSRect, startPoint: CGPoint, endPoint: CGPoint) {
        let edgeColor = glowColor.withAlphaComponent(0.6)
        let clearColor = glowColor.withAlphaComponent(0.0)
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [edgeColor.cgColor, clearColor.cgColor] as CFArray,
            locations: [0, 1]) else { return }
        context.saveGState()
        context.clip(to: rect)
        context.drawLinearGradient(gradient, start: startPoint, end: endPoint, options: [])
        context.restoreGState()
    }
}

private var settingsFieldsKey: UInt8 = 0

private extension NSView {
    func setAssociatedFields(work: NSStepper, shortBreak: NSStepper,
                             longBreak: NSStepper, sessions: NSStepper,
                             extendBreak: NSStepper) {
        let fields = SettingsFields(work: work, shortBreak: shortBreak,
                                    longBreak: longBreak, sessions: sessions,
                                    extendBreak: extendBreak)
        objc_setAssociatedObject(self, &settingsFieldsKey, fields, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    func associatedFields() -> SettingsFields? {
        objc_getAssociatedObject(self, &settingsFieldsKey) as? SettingsFields
    }
}
