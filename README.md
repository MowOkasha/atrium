<p align="center">
  <img src="Resources/icon-256.png" width="128" alt="Atrium icon">
</p>

<h1 align="center">Atrium</h1>

<p align="center">
  Give your macOS desktops real names — and keep your windows where they belong.<br>
  A tiny menu bar app built with Liquid Glass.
</p>

<p align="center">
  <code>brew install --cask mowokasha/tap/atrium</code>
</p>

---

macOS calls your Spaces "Desktop 1, 2, 3…" and quietly reshuffles them by recent use. Atrium fixes that:

- **Named desktops.** The menu bar shows where you are — `Uni`, `Projects`, `Chill` — instead of nothing at all. Names are tied to each desktop itself, so they follow it even if macOS reorders things.
- **A glass banner as you switch.** A soft Liquid Glass card fades in with the desktop's name and a row of dots showing where you are.
- **One-click switching.** Click any desktop in the menu to jump there.
- **Saved window layouts.** *Save Layout* remembers where every window sits; *Restore* puts them back after a reboot, a monitor change, or a mess.
- **Keep desktops in order.** One switch turns off macOS's "rearrange Spaces based on most recent use".
- **Scriptable.** `open atrium://switch/3`, `atrium://switch/Projects`, `atrium://next`, `atrium://previous`, `atrium://save-layout`, `atrium://restore-layout` — handy from Shortcuts or Raycast.

No Dock icon, no windows, no network access, no analytics.

## Install

```bash
brew install --cask mowokasha/tap/atrium
```

Requires macOS 26 Tahoe or later (Apple silicon or Intel).

Or download `Atrium-x.y.z.zip` from [Releases](https://github.com/MowOkasha/atrium/releases), unzip, and drag **Atrium** to Applications. Atrium is not notarized, so the first time, right-click it and choose **Open** (Homebrew handles this for you).

## First run

Click the stack icon in the menu bar, then the gear:

1. **Accessibility → Allow.** Needed to switch desktops and move windows. macOS asks once.
2. **Desktop shortcuts → Turn On.** Enables Mission Control's ⌃1 – ⌃9 "Switch to Desktop" shortcuts, which Atrium uses to jump straight to a desktop. Without them Atrium steps with ⌃← / ⌃→.
3. Hover a desktop and click the pencil (or right-click → Rename) to name it.

## Good to know

- macOS doesn't let apps rename the labels inside Mission Control itself; Atrium shows your names in the menu bar, the banner and its menu instead.
- Since macOS 14, apps can't move windows *between* desktops without disabling System Integrity Protection, which Atrium will never ask you to do. Restore puts windows back in place on their own desktop. To pin an app to a desktop, right-click it in the Dock → Options → Assign To.
- Reading the current desktop uses the same private WindowServer calls as WhichSpace and Spaceman. A major macOS update could require an Atrium update.
- Atrium is ad-hoc signed, so macOS may ask for Accessibility again after an update.

## Build from source

Only the Xcode Command Line Tools are needed.

```bash
git clone https://github.com/MowOkasha/atrium && cd atrium
./scripts/build.sh          # → build/Atrium.app (universal)
open build/Atrium.app
```

`swift scripts/make-icon.swift Resources/icon-1024.png` regenerates the icon.

## Uninstall

```bash
brew uninstall --cask --zap atrium
```

## License

MIT
