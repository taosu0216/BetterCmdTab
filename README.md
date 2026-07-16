<div align="center">

<img src="https://github.com/user-attachments/assets/3e4bbb67-ef7d-4619-8068-1458d8460331" width="160" height="160" alt="BetterCmdTab" />

# BetterCmdTab

**The ⌘+Tab macOS deserves.**

Fast · Native · Liquid Glass · Zero telemetry · Free forever

[![image](https://img.shields.io/badge/Download_Latest_Release-F5F5F4?style=for-the-badge&logo=apple&logoColor=black)](https://github.com/rokartur/BetterCmdTab/releases/latest)

<p>
  <a href="https://github.com/rokartur/BetterCmdTab/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/rokartur/BetterCmdTab?include_prereleases&style=for-the-badge&label=release&color=white"></a>
  <img alt="macOS" src="https://img.shields.io/badge/macOS-13.0+-000?style=for-the-badge&color=white">
  <a href="https://github.com/rokartur/BetterCmdTab/releases"><img alt="Downloads" src="https://img.shields.io/github/downloads/rokartur/BetterCmdTab/total?style=for-the-badge&color=white"></a>
</p>

<sub>
  <a href="#install">Install</a> ·
  <a href="#features">Features</a> ·
  <a href="#this-fork">This fork</a> ·
  <a href="#build--run-locally-this-fork">Build & run locally</a> ·
  <a href="#contributing">Contribute</a>
</sub>

<br />
<br />

<img src="web/public/screenshots/preview.jpg" width="49%" alt="BetterCmdTab grid of app icons layout" />
<img src="web/public/screenshots/grid.jpg" width="49%" alt="BetterCmdTab grid of app icons layout" />
<img src="web/public/screenshots/list.jpg" width="49%" alt="BetterCmdTab classic vertical list layout" />

</div>

## Features

### Switching & Navigation

- **Three layouts** — classic list, grid of icons, or live window previews.
- **Letter-prefix jump** — type a name to jump to it.
- **Search & launch** — press `/` to fuzzy-find, or launch any installed app.
- **Window switching** — `` ⌘+ ` `` cycles windows of the front app.
- **Tap or hold** — tap to switch instantly, hold to open the switcher.
- **Scroll to switch** — spin the mouse wheel to move through apps.
- **Multi-monitor** — opens on the display you're actively working on.
- **Stay open** — optionally keep the switcher open after you release ⌘: browse at your pace, confirm with Return or a click, dismiss with Esc.
- **Reverse step** — hold Shift to keep stepping backwards through the list (or turn the tap-Shift reverse off).
- **Keyboard-only** — optionally turn off selecting with mouse hover and mouse click.

### Window & Tab Management

- **Window titles** — show each window's title under its icon in Grid and Previews.
- **Tab drill-in** — press `\` on a row whose window has tabs to pick a specific tab (Safari, Chrome, Arc, Brave, Edge, Vivaldi, Opera, Dia, Finder, Terminal, iTerm).
- **Tabs as rows** — optionally surface each native or browser tab as its own row, not just behind the `\` peek — with an experimental most-recently-used tab order and a clear hint when Safari/Chrome need automation permission.
- **Quick actions** — quit, close, minimize, maximize, hide inline.
- **Hover actions** — quick-action buttons appear on hover: close, minimize, zoom, hide, quit, force-quit.
- **Window management** — tile windows to halves or corners, maximize, or center with `⌃⌘` arrows; press the tile key again to cycle ½ → ⅔ → ⅓ widths.
- **Move windows** — send the highlighted window to the next display.

### Filtering & Organization

- **Sort order** — order apps by recents (MRU), alphabetically, or launch order — or by most-recent windows, mixing every app's windows by when you last used them.
- **Scoped shortcuts** — add as many global hotkeys as you like, each opening the switcher pre-filtered (all windows, the current Space, Visible Spaces, the current app's windows, or minimized only), and each with its own layout, sorting, filters, and colors independent of the global settings.
- **Show windows from** — All Spaces, the current Space only, or **Visible Spaces** — made for multiple monitors: lists what's on screen across all your displays and hides windows parked on background desktops.
- **Minimized & hidden** — include minimized windows, hidden and windowless apps.
- **Pin & filter** — keep favorites up top, hide the rest.
- **Per-app rules** — hide an app, or have it ignore ⌘Tab always or only when fullscreen.

### Productivity & Workflow

- **App hotkeys** — assign a global shortcut to focus or launch a chosen app (9 slots).
- **Recently closed** — reopen an app you just quit.
- **Unread badges** — Dock badge counts, in the switcher.
- **Audio indicator** — flags apps playing sound.
- **Instant Spaces** — switch Spaces with no animation.

### Reliability & Power Features

- **Force quit** — `⌘+⌥+Q` SIGKILLs the highlighted app for when graceful Quit hangs.
- **Secure-input survivor** — ⌘Tab and window management keep working even while a password field holds Secure Event Input.

### Appearance & Customization

- **Liquid Glass** — system material on macOS 26.
- **Theming** — panel opacity, corner radius, background material, and a custom accent color.
- **Preview titles** — choose how window titles align in previews and whether the selected name is bold.
- **Configurable** — custom hotkey, size, scale, layout, grid columns, and reveal delay.

### Gestures & Feedback

- **Trackpad & haptics** — three-finger swipe to open the switcher or switch Spaces, with optional haptic and click feedback.

### Privacy & Backup

- **Hide from screen sharing** — keep the switcher out of screen recordings and shared screens. Needs macOS 14.6+.
- **Export & import** — back up and move your whole setup as a versioned `.cmdtab` file.

## This fork

This is [@taosu0216](https://github.com/taosu0216)'s personal fork of the upstream
[rokartur/BetterCmdTab](https://github.com/rokartur/BetterCmdTab). It exists to build
and run locally with two small personal changes on top of upstream, not to publish
releases or track upstream going forward:

- **Defaults to Chinese** — `AppleLanguages` is set to `zh-Hans` so the switcher and
  settings UI come up in Chinese out of the box, instead of following system locale.
- **Windowless rows keep "Quit App"** — hover actions used to be all-or-nothing per
  row: if a row had no real window (or its screenshot hadn't loaded yet), the whole
  hover bar — including "Quit App", which doesn't need a window at all — disappeared.
  Now "Quit App" only requires the process to be running; "Close/Minimize/Maximize"
  still require a real window.

This fork is **not kept in sync with upstream** on purpose — it's force-pushed from a
local branch each time, so upstream history may be overwritten. If you want upstream's
latest features/fixes, use [rokartur/BetterCmdTab](https://github.com/rokartur/BetterCmdTab)
directly instead of this fork.

## Build & run locally (this fork)

You don't need a signed release or Homebrew for personal use — build with Xcode and
run the `.app` it produces. This section also covers the permission pitfalls we hit
getting it running, so you don't have to rediscover them.

### 1. Build

```bash
xcodebuild -scheme "BetterCmdTab Debug" -configuration Debug build
```

The built app lands under Xcode's DerivedData, typically:

```bash
open ~/Library/Developer/Xcode/DerivedData/BetterCmdTab-*/Build/Products/Debug/"BetterCmdTab Debug.app"
```

(Or just open the project in Xcode and hit Run — same result.)

### 2. Grant permissions (first launch)

The app requests two *separate* macOS permissions, and it silently degrades if either
is missing rather than erroring — so it's easy to think it's broken when it's just
unauthorized:

- **Accessibility** (`System Settings → Privacy & Security → Accessibility`) — required
  for the global ⌘+Tab event tap and for reading the window list via the Accessibility
  API. Without it, the switcher controller never boots at all: ⌘+Tab silently falls
  through to macOS's native switcher, with no error dialog telling you why.
- **Screen Recording** (`System Settings → Privacy & Security → Screen Recording`) —
  required only for the **window-previews layout** to show real window thumbnails.
  Without it, previews silently fall back to big app icons — which looks like a bug
  ("why don't I see my windows?") but is actually just this permission missing.

After granting either permission, **fully quit and relaunch the app** — a running
process does not pick up a freshly granted permission.

### 3. The pitfall: permissions are tied to code signature, not just the app

The one mistake worth calling out explicitly: **macOS's TCC permission database keys
Accessibility (and Screen Recording) grants to the app's code signature/identity, not
just its bundle path or name.** In practice this means:

- Re-signing the app (including Xcode's automatic ad-hoc re-sign on every rebuild)
  can invalidate a previously granted permission if the signing identity or bundle
  identifier changes between builds.
- Renaming the bundle identifier, display name, or **internal executable name**
  (`CFBundleExecutable`) counts as a new "app" to TCC, even if it's the exact same
  binary otherwise — an already-granted permission won't carry over.
- Symptom when this happens: ⌘+Tab was working, then after a rebuild/rename it
  silently reverts to the native macOS switcher, with the toggle in Accessibility
  settings showing unchecked (or a duplicate stale entry) for what looks like the
  same app.

**Fix**: if this happens, just re-grant Accessibility (and Screen Recording if you use
previews) for the current build, quit, relaunch. If you're renaming the app for any
reason (e.g. running it side-by-side with another BetterCmdTab install so permissions
don't collide), change *only* the external bundle id / display name and leave the
internal product/executable name alone — that's enough to avoid TCC treating rebuilds
as a brand-new, unauthorized app each time.

### Requirements

- macOS 13.0 (Ventura) or newer, same OS build as whoever built the reference version
  is recommended if you're sharing a build rather than building from source yourself
- Xcode 16+ and the macOS 26 SDK (see [CLAUDE.md](CLAUDE.md) for exact build/test commands)

## Install (upstream)

### Requirements

- macOS 13.0 (Ventura) or newer
- Accessibility permission

### Homebrew
```bash
brew install --cask bettercmdtab
```

### Download

Grab the latest signed `.dmg` from the [Releases page](https://github.com/rokartur/BetterCmdTab/releases), open it, drag `BetterCmdTab.app` to `/Applications`, and launch.

On first launch macOS will ask for **Accessibility** permission — this is required for the global ⌘+Tab event tap and for reading window lists via the Accessibility API. Grant it under `System Settings → Privacy & Security → Accessibility`.

### Build from source

If you prefer building it yourself from source, see [this section in CONTRIBUTING.md](CONTRIBUTING.md#Building) for instructions.

## Privacy

BetterCmdTab does not collect, transmit, or store any data. There is no telemetry, no crash reporting service, no analytics SDK, and no account. The only network requests it makes are to `api.github.com` and `github.com` when checking for updates, and only when you ask it to.

## Contributing

Issues and pull requests welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for project layout, build / test instructions, and PR guidelines.

## License

GPL v3. See [LICENSE](LICENSE).

BetterCmdTab is licensed under the GNU General Public License v3.0. You are free to use, study, modify, and redistribute it — including for commercial purposes — but any distributed derivative work must also be released under GPL v3 with full source code. This keeps the project and any fork of it open, forever.

## Credits

Built by [@rokartur](https://github.com/rokartur). Inspired by [AltTab](https://alt-tab.app/), [Witch](https://manytricks.com/witch/), and [Contexts](https://contexts.co/).
