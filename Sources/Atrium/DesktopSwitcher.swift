import AppKit
import CoreGraphics

/// Switches desktops by sending the same keyboard shortcuts Mission Control listens for
/// (System Settings › Keyboard › Shortcuts › Mission Control).
enum DesktopSwitcher {
    struct Hotkey {
        let keyCode: CGKeyCode
        let flags: CGEventFlags
    }

    private static let domain = "com.apple.symbolichotkeys" as CFString
    private static let key = "AppleSymbolicHotKeys" as CFString

    // Symbolic hotkey IDs used by Mission Control.
    static let moveLeftID = 79
    static let moveRightID = 81
    static func desktopID(_ number: Int) -> Int { 117 + number } // 118 = Desktop 1 … 126 = Desktop 9

    private static let fnControl = CGEventFlags(rawValue: 0x40000 | 0x800000)
    private static let defaultLeft = Hotkey(keyCode: 123, flags: fnControl)
    private static let defaultRight = Hotkey(keyCode: 124, flags: fnControl)

    static func hotkey(id: Int) -> Hotkey? {
        guard let entry = allHotkeys()[String(id)] as? [String: Any],
              (entry["enabled"] as? Bool) == true,
              let value = entry["value"] as? [String: Any],
              let params = value["parameters"] as? [Int], params.count >= 3,
              params[1] != 65535
        else { return nil }
        return Hotkey(keyCode: CGKeyCode(params[1]), flags: CGEventFlags(rawValue: UInt64(params[2])))
    }

    /// True when "Switch to Desktop N" is on for every desktop that has a number (up to 9).
    static func shortcutsReady(desktopCount: Int) -> Bool {
        let count = max(1, min(9, desktopCount))
        return (1...count).allSatisfy { hotkey(id: desktopID($0)) != nil }
    }

    /// Turns on ⌃1 … ⌃9 for "Switch to Desktop 1 … 9", leaving any shortcut the user already enabled alone.
    static func enableDesktopShortcuts() {
        var all = allHotkeys()
        let keyCodes = [18, 19, 20, 21, 23, 22, 26, 28, 25] // ANSI 1…9
        for i in 0..<9 where hotkey(id: desktopID(i + 1)) == nil {
            all[String(desktopID(i + 1))] = [
                "enabled": true,
                "value": ["parameters": [49 + i, keyCodes[i], 0x40000], "type": "standard"],
            ] as [String: Any]
        }
        CFPreferencesSetAppValue(key, all as CFDictionary, domain)
        CFPreferencesAppSynchronize(domain)
        let tool = "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings"
        if FileManager.default.isExecutableFile(atPath: tool) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: tool)
            p.arguments = ["-u"]
            try? p.run()
        }
    }

    static func go(to target: Desktop, from current: Desktop?) {
        if !target.isFullscreen, (1...9).contains(target.number),
           let hk = hotkey(id: desktopID(target.number)) {
            post(hk)
            return
        }
        // Fall back to stepping left/right on the same display.
        guard let current, current.displayID == target.displayID else { return }
        let delta = target.positionOnDisplay - current.positionOnDisplay
        guard delta != 0 else { return }
        let hk = delta > 0 ? (hotkey(id: moveRightID) ?? defaultRight) : (hotkey(id: moveLeftID) ?? defaultLeft)
        for i in 0..<abs(delta) {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.06) { post(hk) }
        }
    }

    private static func post(_ hk: Hotkey) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: hk.keyCode, keyDown: down)
            event?.flags = hk.flags
            event?.post(tap: .cghidEventTap)
        }
    }

    private static func allHotkeys() -> [String: Any] {
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue(key, domain) as? [String: Any] ?? [:]
    }
}
