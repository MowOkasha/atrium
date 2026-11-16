import AppKit
import ApplicationServices
import Combine
import ServiceManagement

struct Desktop: Identifiable, Hashable {
    let id: String              // stable UUID from WindowServer
    let managedID: UInt64       // session-only space ID
    let number: Int             // 1-based among regular desktops, 0 for full-screen spaces
    let displayID: String
    let positionOnDisplay: Int  // order on its display, including full-screen spaces
    let isFullscreen: Bool
    let appName: String?        // owning app for full-screen spaces
}

struct DisplayGroup: Identifiable {
    let id: String
    let name: String
    let desktops: [Desktop]
}

enum Page { case desktops, settings }

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    static let repoURL = URL(string: "https://github.com/MowOkasha/atrium")!

    @Published private(set) var desktops: [Desktop] = []
    @Published private(set) var currentID: String?
    @Published private(set) var names: [String: String]
    @Published private(set) var displayNames: [String: String] = [:]
    @Published var page: Page = .desktops
    @Published var editingID: String?
    @Published var hoveredID: String?
    @Published var draft = ""
    @Published private(set) var permissionPulse = false
    @Published var orderTipDismissed: Bool { didSet { defaults.set(orderTipDismissed, forKey: Keys.orderTipDismissed) } }
    @Published private(set) var toast: String?
    @Published private(set) var layoutSavedAt: Date?
    @Published private(set) var isWorking = false
    @Published private(set) var accessibilityGranted = AXIsProcessTrusted()
    @Published private(set) var shortcutsReady = false
    @Published private(set) var keepOrder = false
    @Published private(set) var launchAtLogin = false
    @Published var showBanner: Bool { didSet { defaults.set(showBanner, forKey: Keys.banner) } }
    @Published var showNameInMenuBar: Bool { didSet { defaults.set(showNameInMenuBar, forKey: Keys.nameInMenuBar) } }

    var onSpaceChange: ((Desktop) -> Void)?
    var closeMenu: (() -> Void)?

    private enum Keys {
        static let names = "desktopNames"
        static let banner = "showBanner"
        static let nameInMenuBar = "showNameInMenuBar"
        static let orderTipDismissed = "orderTipDismissed"
        static let promptedAccessibility = "promptedAccessibility"
    }

    private let defaults = UserDefaults.standard
    private let cid = CGSMainConnectionID()
    private var toastWork: DispatchWorkItem?
    private var permissionTimer: Timer?

    private init() {
        defaults.register(defaults: [Keys.banner: true, Keys.nameInMenuBar: true])
        names = defaults.dictionary(forKey: Keys.names) as? [String: String] ?? [:]
        showBanner = defaults.bool(forKey: Keys.banner)
        showNameInMenuBar = defaults.bool(forKey: Keys.nameInMenuBar)
        orderTipDismissed = defaults.bool(forKey: Keys.orderTipDismissed)
        layoutSavedAt = WindowLayouts.load()?.savedAt
    }

    func start() {
        refresh()
        refreshSystemState()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.spaceDidChange() } }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
    }

    // MARK: Spaces

    var current: Desktop? { desktops.first { $0.id == currentID } }
    var currentName: String { current.map(name(for:)) ?? "Desktop" }
    var hasMultipleDisplays: Bool { Set(desktops.map(\.displayID)).count > 1 }

    var groups: [DisplayGroup] {
        var order: [String] = []
        var byDisplay: [String: [Desktop]] = [:]
        for d in desktops {
            if byDisplay[d.displayID] == nil { order.append(d.displayID) }
            byDisplay[d.displayID, default: []].append(d)
        }
        return order.enumerated().map { i, id in
            DisplayGroup(id: id, name: displayNames[id] ?? "Display \(i + 1)", desktops: byDisplay[id] ?? [])
        }
    }

    func refresh() {
        guard let raw = CGSCopyManagedDisplaySpaces(cid)?.takeRetainedValue() as? [[String: Any]] else { return }
        let active = CGSGetActiveSpace(cid)
        var result: [Desktop] = []
        var number = 0
        var activeID: String?
        for display in raw {
            let displayID = display["Display Identifier"] as? String ?? "Main"
            let spaces = display["Spaces"] as? [[String: Any]] ?? []
            for (position, space) in spaces.enumerated() {
                let managed = (space["ManagedSpaceID"] as? NSNumber)?.uint64Value
                    ?? (space["id64"] as? NSNumber)?.uint64Value ?? 0
                let fullscreen = (space["type"] as? NSNumber)?.intValue == 4
                var uuid = space["uuid"] as? String ?? ""
                if uuid.isEmpty { uuid = "primary-\(displayID)" }
                if !fullscreen { number += 1 }
                let tiles = (space["TileLayoutManager"] as? [String: Any])?["TileSpaces"] as? [[String: Any]]
                let desktop = Desktop(
                    id: uuid, managedID: managed, number: fullscreen ? 0 : number,
                    displayID: displayID, positionOnDisplay: position, isFullscreen: fullscreen,
                    appName: tiles?.compactMap { $0["appName"] as? String }.first)
                result.append(desktop)
                if managed == active { activeID = uuid }
            }
        }
        if result != desktops { desktops = result }
        if activeID != currentID { currentID = activeID }
        displayNames = Self.screenNames()
    }

    private func spaceDidChange() {
        let previous = currentID
        refresh()
        editingID = nil
        if currentID != previous, let current { onSpaceChange?(current) }
    }

    private static func screenNames() -> [String: String] {
        var map: [String: String] = [:]
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue(),
                  let string = CFUUIDCreateString(nil, uuid) as String? else { continue }
            map[string] = screen.localizedName
        }
        return map
    }

    // MARK: Names

    func defaultName(for d: Desktop) -> String {
        d.isFullscreen ? (d.appName ?? "Full Screen") : "Desktop \(d.number)"
    }

    func customName(for d: Desktop) -> String? { names[d.id] }

    func name(for d: Desktop) -> String {
        if let custom = names[d.id], !custom.isEmpty { return custom }
        return defaultName(for: d)
    }

    func rename(_ d: Desktop, to text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == defaultName(for: d) {
            names.removeValue(forKey: d.id)
        } else {
            names[d.id] = String(trimmed.prefix(40))
        }
        defaults.set(names, forKey: Keys.names)
        editingID = nil
    }

    func switchTo(_ d: Desktop) {
        editingID = nil
        guard d.id != currentID else { closeMenu?(); return }
        guard requireAccessibility() else { return }
        let from = current
        closeMenu?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { DesktopSwitcher.go(to: d, from: from) }
    }

    /// Handles atrium:// links so Shortcuts, Raycast or scripts can drive Atrium.
    func handle(command: String, argument: String?) {
        refresh()
        let regular = desktops.filter { !$0.isFullscreen }
        switch command {
        case "switch":
            guard let arg = argument else { return }
            let target = Int(arg).flatMap { n in regular.first { $0.number == n } }
                ?? desktops.first { name(for: $0).localizedCaseInsensitiveCompare(arg) == .orderedSame }
            if let target { switchTo(target) }
        case "next", "previous":
            guard let current else { return }
            let peers = desktops.filter { $0.displayID == current.displayID }
            let step = command == "next" ? 1 : -1
            if let target = peers.first(where: { $0.positionOnDisplay == current.positionOnDisplay + step }) {
                switchTo(target)
            }
        case "save-layout": saveLayout()
        case "restore-layout": restoreLayout()
        default: break
        }
    }

    // MARK: Layouts

    func saveLayout() {
        guard requireAccessibility() else { return }
        isWorking = true
        let apps = RunningAppRef.current()
        let ids = Dictionary(desktops.map { ($0.managedID, $0.id) }, uniquingKeysWith: { a, _ in a })
        Task.detached(priority: .userInitiated) {
            let layout = WindowLayouts.capture(apps: apps, desktopIDs: ids)
            let ok = (try? WindowLayouts.save(layout)) != nil
            await MainActor.run {
                self.isWorking = false
                if ok {
                    self.layoutSavedAt = layout.savedAt
                    let n = layout.windows.count
                    self.showToast("Saved \(n) window\(n == 1 ? "" : "s")")
                } else {
                    self.showToast("Couldn't save the layout")
                }
            }
        }
    }

    func restoreLayout() {
        guard requireAccessibility(), let layout = WindowLayouts.load() else { return }
        isWorking = true
        let apps = RunningAppRef.current()
        Task.detached(priority: .userInitiated) {
            let moved = WindowLayouts.restore(layout, apps: apps)
            await MainActor.run {
                self.isWorking = false
                self.showToast(moved == 0 ? "Everything is already in place"
                               : "Moved \(moved) window\(moved == 1 ? "" : "s") back")
            }
        }
    }

    var layoutCaption: String {
        guard let date = layoutSavedAt else { return "Save where your windows are, restore them anytime" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return "Layout saved \(f.localizedString(for: date, relativeTo: Date()))"
    }

    func showToast(_ text: String) {
        toast = text
        toastWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    // MARK: System state

    func menuWillOpen() {
        page = .desktops
        editingID = nil
        refresh()
        refreshSystemState()
    }

    func refreshSystemState() {
        accessibilityGranted = AXIsProcessTrusted()
        shortcutsReady = DesktopSwitcher.shortcutsReady(desktopCount: desktops.filter { !$0.isFullscreen }.count)
        CFPreferencesAppSynchronize("com.apple.dock" as CFString)
        let mru = CFPreferencesCopyAppValue("mru-spaces" as CFString, "com.apple.dock" as CFString) as? Bool
        keepOrder = (mru == false)
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Checks Accessibility; if it's missing, points at the permission card instead of acting.
    @discardableResult
    private func requireAccessibility() -> Bool {
        accessibilityGranted = AXIsProcessTrusted()
        if accessibilityGranted { return true }
        permissionPulse = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.permissionPulse = false }
        return false
    }

    #if DEBUG
    func debugPretendNoPermission() { accessibilityGranted = false }
    #endif

    func requestAccessibility() {
        if defaults.bool(forKey: Keys.promptedAccessibility) {
            // macOS only shows its own prompt once per app, so go straight to the right pane.
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        } else {
            defaults.set(true, forKey: Keys.promptedAccessibility)
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
        permissionTimer?.invalidate()
        var ticks = 0
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                ticks += 1
                self?.accessibilityGranted = AXIsProcessTrusted()
                if self?.accessibilityGranted == true || ticks > 120 { timer.invalidate() }
            }
        }
    }

    func enableDesktopShortcuts() {
        DesktopSwitcher.enableDesktopShortcuts()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refreshSystemState()
            if self?.shortcutsReady == true { self?.showToast("⌃1 – ⌃9 now jump between desktops") }
        }
    }

    func setKeepOrder(_ on: Bool) {
        keepOrder = on
        Self.run("/usr/bin/defaults", ["write", "com.apple.dock", "mru-spaces", "-bool", on ? "false" : "true"])
        Self.run("/usr/bin/killall", ["Dock"])
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            showToast("Couldn't change login item: \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private static func run(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try? p.run()
        p.waitUntilExit()
    }
}
