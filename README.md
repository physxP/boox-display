# boox-display

Use an Onyx Boox Note Max (13.3", 3200×2400 e-ink) as the Mac's screen over USB or Wi-Fi, or
drive the Boox itself with the Mac's keyboard and trackpad.

Built for one setup and shared as-is: a **Boox Note Max** and an **Apple Silicon MacBook**
(see [Assumptions](#assumptions) for what to change otherwise). Read
[Security and side effects](#security-and-side-effects) before installing.

## Modes

| Mode | Command | What happens |
|---|---|---|
| Boox screen | `boox-screen [--wifi] [color\|boox\|mirror]` | A 1600×1200 HiDPI desktop (exactly 3200×2400 pixels, 1:1 with the panel) is shown on the Boox via VNC over USB (or Wi-Fi), in one of three [layouts](#layouts). |
| Laptop | `boox-laptop` | Laptop screen only, at its own resolution and brightness. VNC session ended. |
| Control | `boox-control [--wifi]` | Mac keyboard and trackpad appear on the Boox as a real keyboard and mouse (scrcpy, no streaming). Laptop dark. **Right ⌘** ends it and returns to the previous mode. |

Plugging the Boox in switches to Boox screen mode in the default layout (`color`, set by
`DEFAULT_LAYOUT` in `bin/lib.sh`); unplugging switches to laptop mode. `boox-auto off` turns that off (plugging in then just charges / exposes files);
`boox-auto on` turns it back on. All of this is also in the menu bar item, which shows whether
the Boox is connected over USB, Wi-Fi or both, with separate USB and Wi-Fi items for each mode.

### Layouts

| Layout | Menu item | What happens |
|---|---|---|
| `color` (default) | Color screen main, Boox extended | The color screen that was main before (an external one if connected, else the laptop) stays main; the Boox extends it. |
| `boox` | Boox main, color screens extended | The Boox is the main screen (menu bar, Dock); the laptop and any external screen extend it, lit. |
| `mirror` | Mirror: same desktop on both | The laptop mirrors the Boox desktop with its backlight off; brightness keys bring it back. |

The extended layouts are for moving windows between e-ink and color. *Use Boox as screen*
starts the default layout; picking a layout while the Boox isn't a screen yet starts Boox
screen mode over USB (else Wi-Fi). Control mode returns to the layout it left. Laptop mode
makes the previous main screen main again.

## Wi-Fi

Both modes also work over Android wireless debugging, with no cable:

- Every USB plug-in turns wireless debugging on (`settings global adb_wifi_enabled 1`), finds
  its port, connects over Wi-Fi as well, and remembers the Boox's serial and address. So after
  one plug-in, `boox-screen --wifi` keeps working after you unplug.
- `findboox` looks the Boox up by mDNS (`_adb-tls-connect`, advertised as `adb-<serial>-…`)
  and falls back to the last known address, because the Boox's mDNS responder is unreliable.
- The watcher re-discovers the Boox every 15 s and ends a Wi-Fi session after ~15 s without the
  link or a VNC client, returning to laptop mode.
- The Mac and the Boox must be on the same network.

## How it works

- **Display:** a BetterDisplay virtual screen is the Boox. In the mirror layout it is the main
  display and the built-in display mirrors it, so unplugging never leaves you without a screen
  (brightness keys bring the laptop back). The other layouts turn mirroring off and pick the
  main display.
- **Transport, one desktop** (mirror, no external screen): macOS Screen Sharing (VNC) →
  `adb reverse tcp:5900` → [AVNC] on the Boox. Lossless and pixel-exact, so text stays sharp.
- **Transport, several desktops** (extended layouts, or an external screen attached): Screen
  Sharing would send every display as one wide image, so `booxvnc` serves the Boox display
  alone: ScreenCaptureKit at the panel's pixel size → libvncserver on `127.0.0.1:5901` →
  `adb reverse tcp:5901` → AVNC, opened with a `vnc://` link. View-only (use the Mac's keyboard
  and trackpad), lossless (JPEG is switched off), and only changed rows are sent. launchd starts
  it (`local.boox-display.vnc`) so its Screen Recording permission belongs to `booxvnc`.
- **Cursor:** macOS VNC sends the cursor's shape but not its position, so `vnccursor` draws one
  into the screen image while the Boox is connected (`booxvnc` captures that cursor too).
- **Control mode:** `scrcpy --no-video --keyboard=uhid --mouse=uhid`, wrapped in
  `Boox Control.app` so macOS gives it focus. While scrcpy holds the mouse the Mac pointer is
  frozen; `mousewatch` treats the pointer moving again (right ⌘) as "stop".
- **Watcher:** `boox-watch` (login item) reacts to plug/unplug, honours auto-off and control
  mode, and waits for the Mac to be unlocked before switching (BetterDisplay can't change
  displays on the lock screen).
- **Links:** USB and Wi-Fi can both be connected; every adb/scrcpy call targets one through
  `ANDROID_SERIAL`.

State lives in `~/.local/state/boox-display`: current `mode` and `layout`, the `auto-off`
flag, the Boox's `boox-serial` and last `boox-wifi` address, `control-serial` and
`control-active` for control mode, `laptop-brightness`, `color-main` (the main screen before
the Boox took over), `editor-zoom.json`, `booxvnc`'s random `vnc-password` and `booxvnc.log`,
and the watcher's `watch.log`. It is machine-local and never committed.

## Setup

1. `brew install --cask betterdisplay` and `brew install scrcpy libvncserver`; Android platform-tools at
   `~/Library/Android/sdk/platform-tools/adb` (Android Studio's default). The login items, the
   menu and `Boox Control.app` only look there; `ADB=/path/to/adb` works only for commands you
   run from a shell. Xcode Command Line Tools for `swiftc` (`xcode-select --install`).
2. System Settings → General → Sharing → **Screen Sharing** on, limited to your own account
   (see the security notes below).
3. Boox: enable USB debugging, install [AVNC], add a server `localhost:5900` with
   *Auto-connect when app starts* and image quality at max, and log in once with *Remember*
   (this stores your Mac login password in AVNC on the tablet).
4. `./install.sh` (builds the Swift helpers into `build/`, installs `~/Applications/Boox Control.app`,
   links the commands into `/opt/homebrew/bin`, and loads the LaunchAgents rendered from
   `launchd/`). `./uninstall.sh` reverses it; BetterDisplay, the virtual screen and the state
   directory are left alone.
5. The first plug-in (or any extended layout) asks for **Screen Recording** permission for
   `booxvnc`: allow it in System Settings → Privacy & Security → Screen & System Audio
   Recording, then pick a layout from the menu. `booxvnc` is ad-hoc signed, so after a change to `src/booxvnc.swift` the rebuilt
   binary has to be allowed again.

Keep the clone where it is: the login items run from it (and restart if they exit), so run
`./uninstall.sh` before moving or deleting it.

## Assumptions

- **Boox Note Max:** the tablet is recognised by its adb model name `NoteMax`, and the screen
  size (1600×1200 HiDPI) and virtual screen name are set for it (`BOOX_MODEL`, `BOOX_RES`,
  `VIRTUAL_NAME` in `bin/lib.sh`, plus `src/booxmenu.swift` and `src/vnccursor.swift`). On
  another Boox nothing happens until you edit those.
- **MacBook:** brightness handling expects a display called "Built-in Display".
- **Apple Silicon Homebrew** (`/opt/homebrew`); on an Intel Mac `install.sh` stops partway.
- BetterDisplay must be installed; every mode switch starts it if it isn't running.

## Security and side effects

- **Screen Sharing (VNC, port 5900) listens on every network the Mac joins**, not only the
  tablet's adb tunnel. Allow only your own account, don't enable "VNC viewers may control
  screen with password", keep the macOS firewall on, and turn Screen Sharing off when you stop
  using this (`uninstall.sh` leaves it on).
- **booxvnc has Screen Recording permission** and, while an extended layout is on, serves the
  Boox display on `127.0.0.1:5901` only (no other interface, no IPv6). It is view-only and asks
  for a random 8-character password (`vnc-password`, readable only by you). Classic VNC
  passwords are weak, so this protects against other local programs and Boox apps, not a
  determined attacker on the Mac. The password is handed to AVNC on an `am start` command line.
- **Wireless debugging on the Boox is switched on at every USB plug-in and never switched off**,
  and `stay_on_while_plugged_in` is set. While it is on, the tablet advertises itself (with its
  serial number) on the local network and accepts adb from computers it has trusted. To stop:
  `adb shell settings put global adb_wifi_enabled 0`, and uninstall, since the next plug-in turns
  it back on.
- **Background work:** the watcher checks every 3 s and keeps an adb server running; every 15 s
  it disconnects offline adb devices, which can include your other phones or emulators.
- **Other scrcpy windows:** any process named `scrcpy` counts as control mode and is killed
  (`kill -9`) on mode switches, including scrcpy sessions for other devices.
- **Editor settings:** Boox screen mode (mirror and `boox` layouts) sets `window.zoomLevel` in VS Code's and Antigravity's
  `settings.json` and restores it in laptop mode. The file is rewritten (reformatted), files with
  comments are skipped, and Settings Sync may carry the zoom to your other machines.
- `install.sh` puts the four commands into `/opt/homebrew/bin`, replacing anything with the same
  names; `uninstall.sh` removes those names.

## Boox and Mac tips

- Boox E-ink Center: **X-mode/Speed** refresh and higher contrast for AVNC.
- Boox App management: turn off *freeze* for AVNC (the scripts work around it anyway).
- Mac Accessibility → Display: *Increase contrast*, *Reduce transparency*, larger *Text size*.
  Browsers at 125% page zoom. VS Code / Antigravity are zoomed automatically in Boox screen mode.

## Gotchas found along the way

- Login items run without Homebrew on `PATH`; `lib.sh` sets it.
- scrcpy ignores SIGTERM/SIGINT on macOS; it's stopped with `kill -9` (the Boox cleans up).
- Boox disables sideloaded apps it "freezes"; `pm enable` before launching AVNC.
- The Boox sleeps after 5 minutes even while VNC is in use; `stay_on_while_plugged_in` fixes it.
- Scaled resolutions (e.g. 1280×960) look soft; enlarge content per app instead.
- A freshly connected BetterDisplay virtual screen ignores settings for a moment; poll its mode
  list before setting the resolution.
- Laptop brightness fades in, so wait for it to settle before saving it.
- macOS Screen Sharing sends all displays as one wide image to non-Apple viewers, so an
  extended desktop needs its own single-display server (`booxvnc`).
- ScreenCaptureKit's `SCDisplay.width` is in points; capturing at that size halves the Boox's
  resolution. `booxvnc` uses the display mode's pixel size.
- libvncserver also listens on IPv6 on every interface unless `ipv6port` is 0, and its Tight
  encoder JPEG-compresses anti-aliased text whenever the viewer asks for a quality level.
- Homebrew upgrades of BetterDisplay quit it and don't restart it, so plugging in did nothing
  until it was started by hand; mode switches now start it themselves. `betterdisplaycli` runs
  the BetterDisplay binary too, so a plain `pgrep BetterDisplay` can't tell whether the app is up.
- Wireless debugging listens on a random port; it is found among the Boox's listening ports.
- The `adb reverse` VNC forward is device-wide and tied to the link that created it, so it is
  recreated on the chosen link at every mode switch.
- With both USB and Wi-Fi connected, adb needs `ANDROID_SERIAL` or it refuses to pick one.
- Deskreen and similar browser-based mirrors were tried and dropped as flaky; VNC is pixel-exact.

## License

MIT, see [LICENSE](LICENSE).

[AVNC]: https://github.com/gujjwal00/avnc
