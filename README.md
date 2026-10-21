# boox-display

Use an Onyx Boox Note Max (13.3", 3200×2400 e-ink) as the Mac's screen over USB or Wi-Fi, or
drive the Boox itself with the Mac's keyboard and trackpad.

Built for one setup and shared as-is: a **Boox Note Max** and an **Apple Silicon MacBook**
(see [Assumptions](#assumptions) for what to change otherwise). Read
[Security and side effects](#security-and-side-effects) before installing.

## Modes

| Mode | Command | What happens |
|---|---|---|
| Boox screen | `boox-screen [--wifi]` | A 1600×1200 HiDPI desktop (exactly 3200×2400 pixels, 1:1 with the panel) is mirrored to the laptop and shown on the Boox via VNC over USB (or Wi-Fi). Laptop backlight off. |
| Laptop | `boox-laptop` | Laptop screen only, at its own resolution and brightness. VNC session ended. |
| Control | `boox-control [--wifi]` | Mac keyboard and trackpad appear on the Boox as a real keyboard and mouse (scrcpy, no streaming). Laptop dark. **Right ⌘** ends it and returns to the previous mode. |

Plugging the Boox in switches to Boox screen mode; unplugging switches to laptop mode.
`boox-auto off` turns that off (plugging in then just charges / exposes files); `boox-auto on`
turns it back on. All of this is also in the menu bar item, which shows whether the Boox is
connected over USB, Wi-Fi or both, with separate USB and Wi-Fi items for each mode.

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

- **Display:** a BetterDisplay virtual screen is the main display; the built-in display mirrors
  it, so unplugging never leaves you without a screen (brightness keys bring the laptop back).
- **Transport:** macOS Screen Sharing (VNC) → `adb reverse tcp:5900` → [AVNC] on the Boox.
  Lossless and pixel-exact, so text stays sharp.
- **Cursor:** macOS VNC sends the cursor's shape but not its position, so `vnccursor` draws one
  into the screen image while Boox screen mode is on.
- **Control mode:** `scrcpy --no-video --keyboard=uhid --mouse=uhid`, wrapped in
  `Boox Control.app` so macOS gives it focus. While scrcpy holds the mouse the Mac pointer is
  frozen; `mousewatch` treats the pointer moving again (right ⌘) as "stop".
- **Watcher:** `boox-watch` (login item) reacts to plug/unplug, waits for BetterDisplay after
  login, honours auto-off and control mode, and waits for the Mac to be unlocked before
  switching (BetterDisplay can't change displays on the lock screen).
- **Links:** USB and Wi-Fi can both be connected; every adb/scrcpy call targets one through
  `ANDROID_SERIAL`.

State lives in `~/.local/state/boox-display`: current `mode`, the `auto-off` flag, the Boox's
`boox-serial` and last `boox-wifi` address, `control-serial` and `control-active` for control
mode, `laptop-brightness`, `editor-zoom.json`, and the watcher's `watch.log`. It is
machine-local and never committed.

## Setup

1. `brew install --cask betterdisplay` and `brew install scrcpy`; Android platform-tools at
   `~/Library/Android/sdk/platform-tools/adb` (Android Studio's default). The login items, the
   menu and `Boox Control.app` only look there; `ADB=/path/to/adb` works only for commands you
   run from a shell. Xcode Command Line Tools for `swiftc` (`xcode-select --install`).
2. System Settings → General → Sharing → **Screen Sharing** on, limited to your own account
   (see the security notes below).
3. Boox: enable USB debugging, install [AVNC], add a server `localhost:5900` with
   *Auto-connect when app starts* and image quality at max, and log in once with *Remember*
   (this stores your Mac login password in AVNC on the tablet).
4. `./install.sh` (builds the Swift helpers into `build/`, installs `~/Applications/Boox Control.app`,
   links the commands into `/opt/homebrew/bin`, and loads the three LaunchAgents rendered from
   `launchd/`). `./uninstall.sh` reverses it; BetterDisplay, the virtual screen and the state
   directory are left alone.

Keep the clone where it is: the login items run from it (and restart if they exit), so run
`./uninstall.sh` before moving or deleting it.

## Assumptions

- **Boox Note Max:** the tablet is recognised by its adb model name `NoteMax`, and the screen
  size (1600×1200 HiDPI) and virtual screen name are set for it (`BOOX_MODEL`, `BOOX_RES`,
  `VIRTUAL_NAME` in `bin/lib.sh`, plus `src/booxmenu.swift` and `src/vnccursor.swift`). On
  another Boox nothing happens until you edit those.
- **MacBook:** brightness handling expects a display called "Built-in Display".
- **Apple Silicon Homebrew** (`/opt/homebrew`); on an Intel Mac `install.sh` stops partway.
- BetterDisplay must be running for any mode switch.

## Security and side effects

- **Screen Sharing (VNC, port 5900) listens on every network the Mac joins**, not only the
  tablet's adb tunnel. Allow only your own account, don't enable "VNC viewers may control
  screen with password", keep the macOS firewall on, and turn Screen Sharing off when you stop
  using this (`uninstall.sh` leaves it on).
- **Wireless debugging on the Boox is switched on at every USB plug-in and never switched off**,
  and `stay_on_while_plugged_in` is set. While it is on, the tablet advertises itself (with its
  serial number) on the local network and accepts adb from computers it has trusted. To stop:
  `adb shell settings put global adb_wifi_enabled 0`, and uninstall, since the next plug-in turns
  it back on.
- **Background work:** the watcher checks every 3 s and keeps an adb server running; every 15 s
  it disconnects offline adb devices, which can include your other phones or emulators.
- **Other scrcpy windows:** any process named `scrcpy` counts as control mode and is killed
  (`kill -9`) on mode switches, including scrcpy sessions for other devices.
- **Editor settings:** Boox screen mode sets `window.zoomLevel` in VS Code's and Antigravity's
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
- Wireless debugging listens on a random port; it is found among the Boox's listening ports.
- The `adb reverse` VNC forward is device-wide and tied to the link that created it, so it is
  recreated on the chosen link at every mode switch.
- With both USB and Wi-Fi connected, adb needs `ANDROID_SERIAL` or it refuses to pick one.
- Deskreen and similar browser-based mirrors were tried and dropped as flaky; VNC is pixel-exact.

## License

MIT, see [LICENSE](LICENSE).

[AVNC]: https://github.com/gujjwal00/avnc
