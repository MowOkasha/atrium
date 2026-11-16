import AppKit
import Combine

@main
enum AtriumApp {
    @MainActor static let delegate = AppDelegate()

    @MainActor static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        #if DEBUG
        if DebugSnapshot.runIfRequested() { return }
        #endif
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel.shared
    private var statusItem: NSStatusItem!
    private var menu: MenuPanelController!
    private let banner = BannerController()
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "Atrium"
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
        }

        menu = MenuPanelController(model: model)
        model.closeMenu = { [weak self] in self?.menu.close() }
        model.onSpaceChange = { [weak self] desktop in self?.showBanner(for: desktop) }

        model.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &subscriptions)

        model.start()
        updateStatusItem()

        if !UserDefaults.standard.bool(forKey: "hasLaunchedBefore") {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self, let button = self.statusItem.button else { return }
                self.menu.show(from: button)
            }
        }
    }

    /// atrium://switch/3 · atrium://next · atrium://previous · atrium://save-layout · atrium://restore-layout
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "atrium" {
            model.handle(command: url.host() ?? "", argument: url.pathComponents.dropFirst().first)
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            menu.close()
            let quick = NSMenu()
            quick.addItem(withTitle: "Quit Atrium", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            statusItem.menu = quick
            sender.performClick(nil)
            statusItem.menu = nil
        } else {
            menu.toggle(from: sender)
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "rectangle.stack.fill", accessibilityDescription: "Atrium")?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
        image?.isTemplate = true
        button.image = image
        if model.showNameInMenuBar {
            button.title = " " + model.currentName
            button.imagePosition = .imageLeading
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
        }
        button.toolTip = model.currentName
    }

    private func showBanner(for desktop: Desktop) {
        guard model.showBanner else { return }
        let siblings = model.desktops.filter { $0.displayID == desktop.displayID }
        banner.show(title: model.name(for: desktop), count: siblings.count,
                    index: siblings.firstIndex(of: desktop) ?? 0)
    }
}
