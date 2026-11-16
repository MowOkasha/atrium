#if DEBUG
import AppKit
import SwiftUI
import ApplicationServices

/// `Atrium --snapshot <dir>`: renders the menu pages and banner to PNGs for layout checks.
@MainActor enum DebugSnapshot {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        if args.contains("--selftest") { selfTest(); return true }
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return false }
        let dir = URL(fileURLWithPath: args[i + 1])
        let model = AppModel.shared
        model.start()
        for (name, page) in [("menu-desktops", Page.desktops), ("menu-settings", Page.settings)] {
            model.page = page
            if page == .desktops {
                model.hoveredID = model.desktops.dropFirst().first?.id
                if args.contains("--no-permission") { model.debugPretendNoPermission() }
            }
            render(MenuView().environmentObject(model), to: dir.appendingPathComponent(name + ".png"))
        }
        render(BannerView(title: "Projects", count: 5, index: 2), to: dir.appendingPathComponent("banner.png"))
        return true
    }

    private static func wait(_ s: Double) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

    private static func selfTest() {
        let model = AppModel.shared
        model.start()
        print("accessibility:", AXIsProcessTrusted())
        print("desktops:", model.desktops.map { "\($0.number)" }.joined(separator: ","), "current:", model.currentName)
        guard let start = model.current else { print("FAIL no current desktop"); return }
        let peers = model.desktops.filter { $0.displayID == start.displayID }
        let target = peers.first { $0.positionOnDisplay == start.positionOnDisplay + 1 }
            ?? peers.first { $0.positionOnDisplay == start.positionOnDisplay - 1 }
        if let target {
            DesktopSwitcher.go(to: target, from: start)
            wait(1.6); model.refresh()
            print(model.currentID == target.id ? "PASS switch to \(model.name(for: target))" : "FAIL switch (now \(model.currentName))")
            DesktopSwitcher.go(to: start, from: model.current)
            wait(1.6); model.refresh()
            print(model.currentID == start.id ? "PASS switch back to \(model.name(for: start))" : "FAIL switch back (now \(model.currentName))")
        }
        let apps = RunningAppRef.current()
        let ids = Dictionary(model.desktops.map { ($0.managedID, $0.id) }, uniquingKeysWith: { a, _ in a })
        let layout = WindowLayouts.capture(apps: apps, desktopIDs: ids)
        let tagged = layout.windows.filter { $0.desktop != nil }.count
        print("captured \(layout.windows.count) windows (\(tagged) tagged with a desktop) from \(Set(layout.windows.map(\.appName)).sorted().joined(separator: ", "))")
        let moved = WindowLayouts.restore(layout, apps: apps)
        print(moved == 0 ? "PASS restore of unchanged layout moved nothing" : "WARN restore moved \(moved)")
    }

    private static func render<V: View>(_ view: V, to url: URL) {
        let host = NSHostingView(rootView: view.padding(40).background(
            LinearGradient(colors: [Color(red: 0.1, green: 0.3, blue: 0.7), Color(red: 0.05, green: 0.08, blue: 0.25)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)))
        host.frame.size = host.fittingSize
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.orderOut(nil)
        print("wrote \(url.path)")
    }
}
#endif
