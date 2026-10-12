# boox-display

Use an Onyx Boox Note Max (13.3", 3200×2400 e-ink) as the Mac's screen over USB, or drive the
Boox itself with the Mac's keyboard and trackpad.

## Modes

| Mode | Command | What happens |
|---|---|---|
| Boox screen | `boox-screen` | A 1600×1200 HiDPI desktop (exactly 3200×2400 pixels, 1:1 with the panel) is mirrored to the laptop and shown on the Boox via VNC over USB. Laptop backlight off. |
| Laptop | `boox-laptop` | Laptop screen only, at its own resolution and brightness. VNC session ended. |
| Control | `boox-control` | Mac keyboard and trackpad appear on the Boox as a real USB keyboard and mouse (scrcpy, no streaming). Laptop dark. **Right ⌘** ends it and returns to the previous mode. |

Plugging the Boox in switches to Boox screen mode; unplugging switches to laptop mode.
`boox-auto off` turns that off (plugging in then just charges / exposes files); `boox-auto on`
turns it back on. All of this is also in the menu bar item.

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
  login, and pauses while auto-switch is off or control mode runs.

State lives in `~/.local/state/boox-display` (saved brightness, editor zoom, logs).

## Setup

1. `brew install --cask betterdisplay` and `brew install scrcpy`; Android platform-tools at
   `~/Library/Android/sdk/platform-tools/adb`.
2. System Settings → General → Sharing → **Screen Sharing** on.
3. Boox: enable USB debugging, install [AVNC], add a server `localhost:5900` with
   *Auto-connect when app starts* and image quality at max, and log in once with *Remember*.
4. `./install.sh`

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

[AVNC]: https://github.com/gujjwal00/avnc
