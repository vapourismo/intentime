import Carbon

/// Registers a system-wide keyboard shortcut using the Carbon `RegisterEventHotKey` API.
///
/// Carbon hot keys work without Accessibility permissions and without a bundle identifier,
/// making them suitable for SwiftPM executables. Retain the instance to keep the hot key
/// active; the registration is cleaned up on `deinit`.
final class GlobalHotKey {
    /// The registered hot key reference, needed to unregister on teardown.
    private var hotKeyRef: EventHotKeyRef?
    /// The Carbon event handler reference, needed to remove on teardown.
    private var eventHandlerRef: EventHandlerRef?
    /// Closure invoked on the main thread when the hot key is pressed.
    private let handler: () -> Void

    /// Register a global hot key.
    ///
    /// - Parameters:
    ///   - keyCode: A Carbon virtual key code (e.g. `UInt32(kVK_Space)`).
    ///   - modifiers: Carbon modifier flags (e.g. `UInt32(cmdKey | shiftKey)`).
    ///   - handler: Called each time the hot key is pressed.
    init(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        self.handler = handler

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed))

        // Pass `self` as unretained user-data so the C callback can reach back into Swift.
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                Unmanaged<GlobalHotKey>.fromOpaque(userData)
                    .takeUnretainedValue().handler()
                return noErr
            },
            1, &eventType, selfPtr, &eventHandlerRef)

        let hotKeyID = EventHotKeyID(
            signature: fourCharCode("FBAR"), id: 1)
        RegisterEventHotKey(
            keyCode, modifiers, hotKeyID,
            GetEventDispatcherTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        if let ref = eventHandlerRef { RemoveEventHandler(ref) }
    }
}

/// Convert a 4-character ASCII string (e.g. `"FBAR"`) into a Carbon `OSType` (aka `FourCharCode`).
private func fourCharCode(_ s: String) -> OSType {
    var result: OSType = 0
    for byte in s.utf8.prefix(4) {
        result = (result << 8) | OSType(byte)
    }
    return result
}
