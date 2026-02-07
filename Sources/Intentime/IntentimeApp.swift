import AppKit
import Carbon

/// Entry point. Configures the app as a menu-bar-only agent (no Dock icon) and starts the run loop.
@main
enum IntentimeApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

/// Main application controller owning the `NSStatusItem`, timer model, and all UI panels.
///
/// Uses `NSMenuDelegate` to rebuild the menu on demand (via ``menuNeedsUpdate(_:)``)
/// and a 0.5 s polling timer in `.common` run-loop mode to keep the menu bar title
/// updated even while the dropdown is open.
private final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let timer = TimerModel()
    /// Polls `TimerModel` every 0.5 s to refresh the status item button. Runs in `.common` mode
    /// so it fires during `NSMenu` event tracking.
    private var displayTimer: Timer?
    /// The floating HUD shown when a break ends, prompting the user to continue/extend/stop.
    private var promptPanel: NSPanel?
    /// The Spotlight-like HUD for entering/editing the focus message.
    private var messagePanel: NSPanel?
    /// System-wide shortcut registration (Cmd+Shift+Space).
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

    /// Refresh the status item's icon and title to reflect the current timer/message state.
    ///
    /// Title format: `MM:SS — message` (both), `MM:SS` (timer only), `message` (message only).
    /// Icon: progress pie during work, cup during break, pause symbol when paused, clock when idle.
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
            } else if timer.isRunning, timer.phase == .work, let seconds = timer.secondsLeft {
                let progress = 1.0 - Double(seconds) / timer.phaseDuration
                button.image = progressCircleImage(progress: progress)
            } else if timer.isRunning, (timer.phase == .shortBreak || timer.phase == .longBreak) {
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

    /// Draw a template image of a pie-chart circle filling clockwise from 12 o'clock.
    ///
    /// - Parameter progress: 0.0 (empty) to 1.0 (full).
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

    /// Rebuild the entire menu each time it opens, reflecting the current timer state.
    ///
    /// Called by AppKit because `self` is the menu's `delegate`. Items and layout
    /// depend on the current phase: idle, running (work/break), paused, or waiting to start.
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

                let skipItem = NSMenuItem(title: "Go to Break", action: #selector(skipPhase), keyEquivalent: "")
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

    // MARK: - Menu actions

    /// Start a fresh Pomodoro cycle.
    @objc private func startTimer() {
        dismissBlurOverlay()
        timer.start()
        updateButton()
    }

    /// Resume a previously persisted session.
    @objc private func resumeTimer() {
        timer.resume()
        updateButton()
    }

    /// Pause the running work timer.
    @objc private func pauseTimer() {
        timer.pause()
        updateButton()
    }

    /// Resume a paused timer.
    @objc private func unpauseTimer() {
        timer.unpause()
        updateButton()
    }

    /// Stop the timer and reset to idle.
    @objc private func stopTimer() {
        dismissBlurOverlay()
        timer.stop()
        updateButton()
    }

    /// Skip the current phase (work → break or break → work).
    @objc private func skipPhase() {
        let wasBreak = timer.phase == .shortBreak || timer.phase == .longBreak
        if wasBreak {
            dismissBlurOverlay()
        }
        timer.skip()
        let isBreak = timer.phase == .shortBreak || timer.phase == .longBreak
        if isBreak {
            showBlurOverlay()
        }
        updateButton()
    }

    /// Open the message input HUD (same panel used by the global hotkey).
    @objc private func editMessage() {
        showMessageInput()
    }

    // MARK: - Message input panel

    /// Show (or toggle off) the Spotlight-like floating HUD for entering the focus message.
    ///
    /// Enter confirms, Escape cancels. If the panel is already visible, it is dismissed instead.
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

    /// Called when the user presses Enter in the message text field.
    @objc private func messageFieldSubmitted(_ sender: NSTextField) {
        let text = sender.stringValue.trimmingCharacters(in: .whitespaces)
        timer.message = text.isEmpty ? nil : text
        updateButton()
        dismissMessagePanel()
    }

    /// Fade out and close the message input panel.
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

    /// Clear the focus message and update the menu bar.
    @objc private func clearMessage() {
        timer.message = nil
        updateButton()
    }

    // MARK: - Notifications

    /// Flash an orange glow along the borders of all screens to signal a break starting.
    ///
    /// The glow fades out over 2 seconds after a 0.3 s hold. Uses `BorderFlashView` for the gradient.
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

    /// Show a full-screen blur overlay on all displays during breaks.
    ///
    /// Uses `NSVisualEffectView` with `.behindWindow` blending for a live, hardware-accelerated
    /// blur that requires no special permissions. The overlay passes through all mouse events.
    private func showBlurOverlay() {
        guard Settings.shared.blurScreenDuringBreaks else { return }
        dismissBlurOverlay(animated: false)

        for screen in NSScreen.screens {
            let frame = screen.frame
            let window = NSWindow(
                contentRect: frame,
                styleMask: [.borderless],
                backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .floating
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .stationary]

            let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
            effectView.material = .fullScreenUI
            effectView.blendingMode = .behindWindow
            effectView.state = .active

            // Add a very light dark tint while keeping the blur subtle.
            let tintView = NSView(frame: effectView.bounds)
            tintView.autoresizingMask = [.width, .height]
            tintView.wantsLayer = true
            tintView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.02).cgColor
            effectView.addSubview(tintView)

            window.contentView = effectView
            window.setFrame(frame, display: true)
            window.alphaValue = 0
            window.orderFrontRegardless()
            blurWindows.append(window)

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.5
                // Reduce overall effect strength so more of the screen remains visible.
                window.animator().alphaValue = 0.7
            }
        }
    }

    /// Dismiss all blur overlay windows.
    ///
    /// - Parameter animated: Whether to fade out (0.3 s) or close immediately.
    private func dismissBlurOverlay(animated: Bool = true) {
        let windows = blurWindows
        blurWindows.removeAll()
        guard !windows.isEmpty else { return }

        if animated {
            for window in windows {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.3
                    window.animator().alphaValue = 0
                }, completionHandler: {
                    window.close()
                })
            }
        } else {
            for window in windows {
                window.close()
            }
        }
    }

    /// Show a temporary HUD banner in the top-right corner announcing a break phase.
    ///
    /// Auto-dismisses after 4 seconds. Only shown for break phases (not work).
    private func showPhaseBanner(for phase: TimerModel.Phase) {
        guard phase == .shortBreak || phase == .longBreak else { return }
        flashScreenBorder()
        showBlurOverlay()
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
        panel.level = !blurWindows.isEmpty
            ? NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
            : .floating
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

    /// Show a persistent HUD prompt when a break ends, offering "Continue", "Extend Break", and "Stop".
    ///
    /// The prompt stays visible until the user interacts with one of the buttons.
    private func showBreakEndedPrompt() {
        dismissPromptPanel()

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 88),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .hudWindow],
            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = !blurWindows.isEmpty
            ? NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
            : .floating
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

    /// Close the break-ended prompt panel.
    private func dismissPromptPanel() {
        promptPanel?.close()
        promptPanel = nil
    }

    /// User chose "Continue" — start the next work session.
    @objc private func continueFromPrompt() {
        dismissPromptPanel()
        dismissBlurOverlay()
        timer.startNextWork()
        updateButton()
    }

    /// User chose "Extend Break" — add more break time.
    @objc private func extendBreakFromPrompt() {
        dismissPromptPanel()
        timer.extendBreak()
        updateButton()
    }

    /// User chose "Stop" — end the Pomodoro session entirely.
    @objc private func stopFromPrompt() {
        dismissPromptPanel()
        dismissBlurOverlay()
        timer.stop()
        updateButton()
    }

    /// Windows used for the screen-border flash animation (one per display).
    private var flashWindows: [NSWindow] = []
    /// Full-screen blur overlay windows shown during breaks (one per display).
    private var blurWindows: [NSWindow] = []
    /// The currently open settings panel, if any.
    private var settingsPanel: NSPanel?

    // MARK: - Settings

    /// Open (or bring to front) the settings panel with stepper controls for all durations.
    @objc private func openSettings() {
        if let existing = settingsPanel, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settings = Settings.shared

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 470, height: 410),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.title = "Settings"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.titleVisibility = .visible
        panel.titlebarAppearsTransparent = false

        func makeStepperRow(value: Int, min: Int, max: Int) -> (view: NSView, stepper: NSStepper) {
            let field = NSTextField(frame: .zero)
            field.integerValue = value
            field.alignment = .center
            field.font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
            field.isEditable = true
            field.isSelectable = true
            field.isBezeled = false
            field.isBordered = false
            field.drawsBackground = false
            field.focusRingType = .none
            field.translatesAutoresizingMaskIntoConstraints = false
            let formatter = NumberFormatter()
            formatter.minimum = NSNumber(value: min)
            formatter.maximum = NSNumber(value: max)
            formatter.allowsFloats = false
            field.formatter = formatter

            let fieldContainer = NSView(frame: .zero)
            fieldContainer.wantsLayer = true
            fieldContainer.layer?.cornerRadius = 8
            fieldContainer.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.45).cgColor
            fieldContainer.translatesAutoresizingMaskIntoConstraints = false
            fieldContainer.widthAnchor.constraint(equalToConstant: 64).isActive = true
            fieldContainer.heightAnchor.constraint(equalToConstant: 30).isActive = true
            fieldContainer.addSubview(field)

            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: fieldContainer.leadingAnchor, constant: 8),
                field.trailingAnchor.constraint(equalTo: fieldContainer.trailingAnchor, constant: -8),
                field.centerYAnchor.constraint(equalTo: fieldContainer.centerYAnchor),
            ])

            let stepper = NSStepper()
            stepper.minValue = Double(min)
            stepper.maxValue = Double(max)
            stepper.increment = 1
            stepper.valueWraps = false
            stepper.integerValue = value
            stepper.controlSize = .small

            field.bind(.value, to: stepper, withKeyPath: "integerValue", options: nil)
            stepper.bind(.value, to: field, withKeyPath: "integerValue", options: nil)

            let stack = NSStackView(views: [fieldContainer, stepper])
            stack.orientation = .horizontal
            stack.spacing = 8
            stack.alignment = .centerY
            return (stack, stepper)
        }

        let workRow = makeStepperRow(value: settings.workMinutes, min: 1, max: 120)
        let shortBreakRow = makeStepperRow(value: settings.shortBreakMinutes, min: 1, max: 60)
        let longBreakRow = makeStepperRow(value: settings.longBreakMinutes, min: 1, max: 120)
        let sessionsRow = makeStepperRow(value: settings.sessionsBeforeLongBreak, min: 1, max: 20)
        let extendBreakRow = makeStepperRow(value: settings.extendBreakMinutes, min: 1, max: 60)

        func label(_ text: String) -> NSTextField {
            let l = NSTextField(labelWithString: text)
            l.alignment = .left
            l.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            l.textColor = NSColor.labelColor.withAlphaComponent(0.9)
            return l
        }

        let titleLabel = NSTextField(labelWithString: "Timer Settings")
        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .semibold)

        let subtitleLabel = NSTextField(labelWithString: "Changes apply on the next phase transition.")
        subtitleLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.textColor = NSColor.secondaryLabelColor

        let grid = NSGridView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 12
        grid.columnSpacing = 18
        grid.addRow(with: [label("Work duration (min):"), workRow.view])
        grid.addRow(with: [label("Short break (min):"), shortBreakRow.view])
        grid.addRow(with: [label("Long break (min):"), longBreakRow.view])
        grid.addRow(with: [label("Sessions before long break:"), sessionsRow.view])
        grid.addRow(with: [label("Extend break (min):"), extendBreakRow.view])
        grid.column(at: 0).xPlacement = .leading
        grid.column(at: 1).xPlacement = .trailing
        for index in 0..<grid.numberOfRows {
            grid.row(at: index).yPlacement = .center
        }

        let blurCheckbox = NSButton(checkboxWithTitle: "Blur screen during breaks", target: nil, action: nil)
        blurCheckbox.state = settings.blurScreenDuringBreaks ? .on : .off
        blurCheckbox.font = NSFont.systemFont(ofSize: 13, weight: .medium)

        let saveButton = NSButton(title: "Save", target: nil, action: nil)
        saveButton.bezelStyle = .rounded
        saveButton.controlSize = .large
        saveButton.keyEquivalent = "\r"

        let cancelButton = NSButton(title: "Cancel", target: panel, action: #selector(NSWindow.performClose(_:)))
        cancelButton.bezelStyle = .recessed
        cancelButton.controlSize = .large
        cancelButton.keyEquivalent = "\u{1b}"

        let formCard = NSView(frame: .zero)
        formCard.wantsLayer = true
        formCard.layer?.cornerRadius = 14
        formCard.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5).cgColor
        formCard.translatesAutoresizingMaskIntoConstraints = false
        formCard.addSubview(grid)

        let buttonRow = NSStackView(views: [cancelButton, saveButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10
        buttonRow.alignment = .centerY
        buttonRow.distribution = .fillProportionally
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSVisualEffectView(frame: panel.contentRect(forFrameRect: panel.frame))
        contentView.material = .hudWindow
        contentView.blendingMode = .behindWindow
        contentView.state = .active
        contentView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        blurCheckbox.translatesAutoresizingMaskIntoConstraints = false
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)
        contentView.addSubview(subtitleLabel)
        contentView.addSubview(formCard)
        contentView.addSubview(blurCheckbox)
        contentView.addSubview(buttonRow)

        panel.contentView = contentView

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 26),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 26),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -26),

            formCard.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 16),
            formCard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 22),
            formCard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -22),

            grid.topAnchor.constraint(equalTo: formCard.topAnchor, constant: 16),
            grid.leadingAnchor.constraint(equalTo: formCard.leadingAnchor, constant: 16),
            grid.trailingAnchor.constraint(equalTo: formCard.trailingAnchor, constant: -16),
            grid.bottomAnchor.constraint(equalTo: formCard.bottomAnchor, constant: -16),

            blurCheckbox.topAnchor.constraint(equalTo: formCard.bottomAnchor, constant: 14),
            blurCheckbox.leadingAnchor.constraint(equalTo: formCard.leadingAnchor, constant: 4),

            buttonRow.topAnchor.constraint(equalTo: blurCheckbox.bottomAnchor, constant: 20),
            buttonRow.trailingAnchor.constraint(equalTo: formCard.trailingAnchor),
            buttonRow.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -22),
        ])

        saveButton.target = self
        saveButton.action = #selector(saveSettings(_:))

        // Store steppers/controls so we can read them on save.
        panel.contentView?.setAssociatedFields(
            work: workRow.stepper, shortBreak: shortBreakRow.stepper,
            longBreak: longBreakRow.stepper, sessions: sessionsRow.stepper,
            extendBreak: extendBreakRow.stepper,
            blurDuringBreaks: blurCheckbox)

        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsPanel = panel
    }

    /// Read current stepper values from the settings panel and persist them.
    @objc private func saveSettings(_ sender: Any?) {
        guard let contentView = settingsPanel?.contentView,
              let fields = contentView.associatedFields() else { return }
        let settings = Settings.shared
        settings.workMinutes = fields.work.integerValue
        settings.shortBreakMinutes = fields.shortBreak.integerValue
        settings.longBreakMinutes = fields.longBreak.integerValue
        settings.sessionsBeforeLongBreak = fields.sessions.integerValue
        settings.extendBreakMinutes = fields.extendBreak.integerValue
        settings.blurScreenDuringBreaks = fields.blurDuringBreaks.state == .on
        settingsPanel?.close()
        settingsPanel = nil
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

// MARK: - Message text field (Escape handling)

/// `NSTextField` subclass that forwards Escape key presses to an ``onEscape`` closure,
/// used by the message input panel to dismiss on Escape.
private final class MessageTextField: NSTextField {
    var onEscape: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

// MARK: - Associated fields helper

/// Bundles the `NSStepper` references from the settings panel so they can be read back on save.
private struct SettingsFields {
    let work: NSStepper
    let shortBreak: NSStepper
    let longBreak: NSStepper
    let sessions: NSStepper
    let extendBreak: NSStepper
    let blurDuringBreaks: NSButton
}

// MARK: - Border flash view

/// Custom view that draws a soft gradient glow along all four edges of its bounds,
/// used by ``AppDelegate/flashScreenBorder()`` to overlay full-screen flash windows.
private final class BorderFlashView: NSView {
    var glowWidth: CGFloat = 40
    var glowColor: NSColor = .systemGreen

    /// Draw gradient strips along each edge (bottom, top, left, right).
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

    /// Draw a single edge gradient from `startPoint` (opaque) to `endPoint` (transparent), clipped to `rect`.
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

/// Associated-object key for attaching ``SettingsFields`` to the settings panel's content view.
private var settingsFieldsKey: UInt8 = 0

/// Convenience for stashing/retrieving ``SettingsFields`` on the settings panel content view
/// via Objective-C associated objects so the save action can read stepper values.
private extension NSView {
    func setAssociatedFields(work: NSStepper, shortBreak: NSStepper,
                             longBreak: NSStepper, sessions: NSStepper,
                             extendBreak: NSStepper,
                             blurDuringBreaks: NSButton) {
        let fields = SettingsFields(work: work, shortBreak: shortBreak,
                                    longBreak: longBreak, sessions: sessions,
                                    extendBreak: extendBreak,
                                    blurDuringBreaks: blurDuringBreaks)
        objc_setAssociatedObject(self, &settingsFieldsKey, fields, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    func associatedFields() -> SettingsFields? {
        objc_getAssociatedObject(self, &settingsFieldsKey) as? SettingsFields
    }
}
