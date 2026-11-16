import AppKit
import ApplicationServices

struct WindowRecord: Codable, Sendable {
    var bundleID: String
    var appName: String
    var title: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var desktop: String?
}

struct WindowLayout: Codable, Sendable {
    var savedAt: Date
    var windows: [WindowRecord]
}

struct RunningAppRef: Sendable {
    let pid: pid_t
    let bundleID: String
    let name: String

    @MainActor static func current() -> [RunningAppRef] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, let id = app.bundleIdentifier,
                  id != Bundle.main.bundleIdentifier else { return nil }
            return RunningAppRef(pid: app.processIdentifier, bundleID: id, name: app.localizedName ?? id)
        }
    }
}

/// Saves and restores window positions through the Accessibility API.
enum WindowLayouts {
    static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Atrium", isDirectory: true)
            .appendingPathComponent("layout.json")
    }

    static func load() -> WindowLayout? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WindowLayout.self, from: data)
    }

    static func save(_ layout: WindowLayout) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(layout).write(to: fileURL, options: .atomic)
    }

    static func capture(apps: [RunningAppRef], desktopIDs: [UInt64: String]) -> WindowLayout {
        let cid = CGSMainConnectionID()
        var records: [WindowRecord] = []
        for app in apps {
            for window in windows(of: app.pid) {
                guard let frame = frame(of: window) else { continue }
                var desktop: String?
                var wid: CGWindowID = 0
                if _AXUIElementGetWindow(window, &wid) == .success, wid != 0,
                   let spaces = CGSCopySpacesForWindows(cid, 0x7, [NSNumber(value: wid)] as CFArray)?
                       .takeRetainedValue() as? [NSNumber],
                   let space = spaces.first {
                    desktop = desktopIDs[space.uint64Value]
                }
                records.append(WindowRecord(
                    bundleID: app.bundleID, appName: app.name,
                    title: attribute(window, kAXTitleAttribute) ?? "",
                    x: frame.origin.x, y: frame.origin.y,
                    width: frame.width, height: frame.height,
                    desktop: desktop))
            }
        }
        return WindowLayout(savedAt: Date(), windows: records)
    }

    /// Returns how many windows were moved back into place.
    static func restore(_ layout: WindowLayout, apps: [RunningAppRef]) -> Int {
        let saved = Dictionary(grouping: layout.windows, by: \.bundleID)
        var moved = 0
        for app in apps {
            guard var remaining = saved[app.bundleID] else { continue }
            var pairs: [(AXUIElement, WindowRecord)] = []
            var unmatched: [AXUIElement] = []
            for window in windows(of: app.pid) {
                let title: String = attribute(window, kAXTitleAttribute) ?? ""
                if let i = remaining.firstIndex(where: { $0.title == title }) {
                    pairs.append((window, remaining.remove(at: i)))
                } else {
                    unmatched.append(window)
                }
            }
            pairs += zip(unmatched, remaining).map { ($0, $1) }
            for (window, record) in pairs where setFrame(window, to: CGRect(
                x: record.x, y: record.y, width: record.width, height: record.height)) {
                moved += 1
            }
        }
        return moved
    }

    // MARK: Accessibility helpers

    private static func windows(of pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.75)
        let all: [AXUIElement] = attribute(app, kAXWindowsAttribute) ?? []
        return all.filter { window in
            (attribute(window, kAXSubroleAttribute) as String?) == kAXStandardWindowSubrole
                && (attribute(window, kAXMinimizedAttribute) as Bool?) != true
        }
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    private static func axValue(_ element: AXUIElement, _ name: String) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        guard let p = axValue(window, kAXPositionAttribute), let s = axValue(window, kAXSizeAttribute) else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(p, .cgPoint, &origin)
        AXValueGetValue(s, .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }

    private static func setFrame(_ window: AXUIElement, to target: CGRect) -> Bool {
        guard let current = frame(of: window) else { return false }
        let close = abs(current.minX - target.minX) < 2 && abs(current.minY - target.minY) < 2
            && abs(current.width - target.width) < 2 && abs(current.height - target.height) < 2
        if close { return false }
        var origin = target.origin
        var size = target.size
        guard let p = AXValueCreate(.cgPoint, &origin), let s = AXValueCreate(.cgSize, &size) else { return false }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, p)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, s)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, p)
        return true
    }
}
