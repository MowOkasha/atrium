import SwiftUI

// MARK: - Menu

struct MenuView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            switch model.page {
            case .desktops: DesktopsPage().transition(.move(edge: .leading).combined(with: .opacity))
            case .settings: SettingsPage().transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(width: 312)
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 26, style: .continuous))
        .animation(.smooth(duration: 0.28), value: model.page)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct DesktopsPage: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("You're on")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(model.currentName)
                        .font(.system(size: 21, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
                Spacer()
                CircleButton(symbol: "gearshape", help: "Settings") { model.page = .settings }
            }
            .padding(.horizontal, 6)
            .padding(.top, 2)

            rows

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button { model.saveLayout() } label: {
                        Label("Save Layout", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    Button { model.restoreLayout() } label: {
                        Label("Restore", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(model.layoutSavedAt == nil)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .disabled(model.isWorking)
            }

            Text(model.toast ?? model.layoutCaption)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: model.toast)
        }
    }

    @ViewBuilder private var rows: some View {
        let list = VStack(alignment: .leading, spacing: 2) {
            ForEach(model.groups) { group in
                if model.hasMultipleDisplays {
                    Text(group.name.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 10)
                        .padding(.top, group.id == model.groups.first?.id ? 0 : 8)
                        .padding(.bottom, 2)
                }
                ForEach(group.desktops) { DesktopRow(desktop: $0) }
            }
        }
        if model.desktops.count > 10 {
            ScrollView { list }.frame(height: 380).scrollIndicators(.never)
        } else {
            list
        }
    }
}

struct DesktopRow: View {
    @EnvironmentObject var model: AppModel
    let desktop: Desktop
    @FocusState private var focused: Bool

    private var isCurrent: Bool { model.currentID == desktop.id }
    private var editing: Bool { model.editingID == desktop.id }
    private var hovering: Bool { model.hoveredID == desktop.id }

    var body: some View {
        HStack(spacing: 11) {
            badge
            if editing {
                TextField(model.defaultName(for: desktop), text: $model.draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($focused)
                    .onSubmit { model.rename(desktop, to: model.draft) }
                    .onExitCommand { model.editingID = nil }
                    .onAppear {
                        model.draft = model.customName(for: desktop) ?? ""
                        DispatchQueue.main.async { focused = true }
                    }
            } else {
                Text(model.name(for: desktop))
                    .font(.system(size: 14, weight: isCurrent ? .semibold : .regular))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if editing {
                Button("Done") { model.rename(desktop, to: model.draft) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tint)
            } else if hovering && !desktop.isFullscreen {
                Button { model.editingID = desktop.id } label: {
                    Image(systemName: "pencil").font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Rename")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(isCurrent ? 0.09 : (hovering ? 0.05 : 0)))
        }
        .contentShape(.rect)
        .onHover { h in
            withAnimation(.easeOut(duration: 0.12)) {
                if h { model.hoveredID = desktop.id } else if model.hoveredID == desktop.id { model.hoveredID = nil }
            }
        }
        .onTapGesture { if !editing { model.switchTo(desktop) } }
        .contextMenu {
            if !desktop.isFullscreen {
                Button("Rename…") { model.editingID = desktop.id }
                if model.customName(for: desktop) != nil {
                    Button("Reset Name") { model.rename(desktop, to: "") }
                }
            }
        }
    }

    private var badge: some View {
        ZStack {
            Circle().fill(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.primary.opacity(0.08)))
            if desktop.isFullscreen {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 8, weight: .bold))
            } else {
                Text("\(desktop.number)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(isCurrent ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
        .frame(width: 22, height: 22)
    }
}

// MARK: - Settings

struct SettingsPage: View {
    @EnvironmentObject var model: AppModel

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                CircleButton(symbol: "chevron.left", help: "Back") { model.page = .desktops }
                Text("Settings")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Spacer()
            }
            .padding(.horizontal, 2)

            Card {
                ToggleRow(title: "Name banner", detail: "Show the desktop's name as you switch",
                          isOn: $model.showBanner)
                CardDivider()
                ToggleRow(title: "Name in menu bar", detail: "Show the name next to the icon",
                          isOn: $model.showNameInMenuBar)
                CardDivider()
                ToggleRow(title: "Keep desktops in order", detail: "Stop macOS from shuffling them",
                          isOn: Binding(get: { model.keepOrder }, set: { model.setKeepOrder($0) }))
                CardDivider()
                ToggleRow(title: "Open at login", detail: nil,
                          isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
            }

            Card {
                StatusRow(title: "Accessibility", detail: "To switch desktops and arrange windows",
                          ok: model.accessibilityGranted, action: "Allow") { model.requestAccessibility() }
                CardDivider()
                StatusRow(title: "Desktop shortcuts", detail: "⌃1 – ⌃9 jump straight to a desktop",
                          ok: model.shortcutsReady, action: "Turn On") { model.enableDesktopShortcuts() }
            }

            if let toast = model.toast {
                Text(toast)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }

            HStack {
                Text("Atrium \(version)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Link("GitHub", destination: AppModel.repoURL)
                    .font(.system(size: 11))
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - Pieces

struct CircleButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .help(help)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}

struct CardDivider: View {
    var body: some View { Divider().opacity(0.6) }
}

struct ToggleRow: View {
    let title: String
    let detail: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium))
                if let detail {
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        .padding(.vertical, 9)
    }
}

struct StatusRow: View {
    let title: String
    let detail: String
    let ok: Bool
    let action: String
    let perform: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if ok {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.green)
            } else {
                Button(action, action: perform)
                    .buttonStyle(.glassProminent)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 9)
    }
}

// MARK: - Banner

struct BannerView: View {
    let title: String
    let count: Int
    let index: Int

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .lineLimit(1)
            if count > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<count, id: \.self) { i in
                        Capsule()
                            .fill(Color.primary.opacity(i == index ? 0.85 : 0.22))
                            .frame(width: i == index ? 18 : 6, height: 6)
                    }
                }
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 24)
        .frame(minWidth: 220)
        .glassEffect(.regular, in: .rect(cornerRadius: 30, style: .continuous))
        .padding(30)
    }
}
