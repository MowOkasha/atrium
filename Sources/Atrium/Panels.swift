import AppKit
import SwiftUI

/// Borderless, transparent panel that can take keyboard focus without activating the app.
final class GlassPanel: NSPanel {
    /// When set, the panel grows and shrinks downward from this screen y-coordinate.
    var anchorTop: CGFloat?
    var onCancel: (() -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(anchored(frameRect), display: flag)
    }

    override func setFrame(_ frameRect: NSRect, display displayFlag: Bool, animate animateFlag: Bool) {
        super.setFrame(anchored(frameRect), display: displayFlag, animate: animateFlag)
    }

    override func cancelOperation(_ sender: Any?) { onCancel?() }

    private func anchored(_ rect: NSRect) -> NSRect {
        guard let top = anchorTop else { return rect }
        var r = rect
        r.origin.y = top - r.height
        return r
    }
}

// MARK: - Menu panel

@MainActor
final class MenuPanelController {
    private let panel = GlassPanel()
    private let model: AppModel
    private var clickMonitor: Any?
    private weak var button: NSStatusBarButton?

    init(model: AppModel) {
        self.model = model
        let host = NSHostingController(rootView: MenuView().environmentObject(model))
        host.sizingOptions = [.preferredContentSize]
        host.view.wantsLayer = true
        panel.contentViewController = host
        panel.onCancel = { [weak self] in self?.close() }
    }

    private(set) var isOpen = false
    private var generation = 0

    func toggle(from button: NSStatusBarButton) {
        isOpen ? close() : show(from: button)
    }

    func show(from button: NSStatusBarButton) {
        guard let buttonWindow = button.window, let content = panel.contentViewController?.view else { return }
        self.button = button
        isOpen = true
        generation += 1
        model.menuWillOpen()

        content.layoutSubtreeIfNeeded()
        let size = content.fittingSize
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main ?? NSScreen.screens[0]
        var x = anchor.midX - size.width / 2
        x = min(max(x, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - size.width - 8)

        panel.anchorTop = anchor.minY - 6
        panel.setFrame(NSRect(x: x, y: 0, width: size.width, height: size.height), display: true)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            panel.animator().alphaValue = 1
        }
        button.highlight(true)

        if clickMonitor == nil {
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            }
        }
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        generation += 1
        let closing = generation
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        button?.highlight(false)
        model.editingID = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // Only hide if nothing re-opened the panel while it was fading out.
                guard let self, self.generation == closing else { return }
                self.panel.orderOut(nil)
                self.model.page = .desktops
            }
        })
    }
}

// MARK: - Banner

@MainActor
final class BannerController {
    private let panel = GlassPanel()
    private let host = NSHostingView(rootView: BannerView(title: "", count: 0, index: 0))
    private var hideWork: DispatchWorkItem?
    private var generation = 0

    init() {
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = host
    }

    func show(title: String, count: Int, index: Int) {
        host.rootView = BannerView(title: title, count: count, index: index)
        let size = host.fittingSize
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.frame else { return }
        panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
                              width: size.width, height: size.height), display: true)

        hideWork?.cancel()
        generation += 1
        let shown = generation
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 1
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.45
                self.panel.animator().alphaValue = 0
            }, completionHandler: {
                MainActor.assumeIsolated {
                    if self.generation == shown { self.panel.orderOut(nil) }
                }
            })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: work)
    }
}
