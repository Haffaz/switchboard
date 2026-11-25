import AppKit
import Carbon.HIToolbox
import SwitchboardCore

/// System-wide shortcuts: Control-Option-1 to 9 jump to the account in that
/// position of the menu, from any app. Off until switched on in the menu.
///
/// Uses the system's hot key service, which needs no Accessibility
/// permission and sees only these nine key combinations, nothing else typed.
@MainActor
final class HotKeys {
    static let shared = HotKeys()
    private static let preferenceKey = "globalShortcuts"
    private static let signature: OSType = 0x5357_4244  // "SWBD"
    private static let keyCodes = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                                   kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]

    /// Called with the position pressed, counting from 0.
    var onPress: ((Int) -> Void)?
    private var registered: [EventHotKeyRef] = []
    private var handlerInstalled = false

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.preferenceKey) }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.preferenceKey)
        apply()
    }

    /// Bring the registered shortcuts in line with the saved setting.
    func apply() {
        unregister()
        guard isEnabled else { Log.write("shortcuts: off"); return }
        installHandler()
        for (index, code) in Self.keyCodes.enumerated() {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(index))
            let status = RegisterEventHotKey(UInt32(code), UInt32(controlKey | optionKey), id,
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { registered.append(ref) }
        }
        Log.write("shortcuts: on (\(registered.count) of \(Self.keyCodes.count) registered)")
    }

    private func unregister() {
        registered.forEach { UnregisterEventHotKey($0) }
        registered = []
    }

    private func installHandler() {
        guard !handlerInstalled else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return status }
            let index = Int(id.id)
            DispatchQueue.main.async { MainActor.assumeIsolated { HotKeys.shared.onPress?(index) } }
            return noErr
        }, 1, &spec, nil, nil)
        handlerInstalled = true
    }
}
