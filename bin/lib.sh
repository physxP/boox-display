# Shared settings and helpers for the boox-display scripts. Sourced, not run.
export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
export ADB=${ADB:-$HOME/Library/Android/sdk/platform-tools/adb}  # scrcpy reads $ADB too

BIN=${${(%):-%x}:A:h}
STATE=$HOME/.local/state/boox-display
mkdir -p $STATE

VIRTUAL_NAME="Boox Note Max"   # BetterDisplay virtual screen
LAPTOP_NAME="Built-in Display"
BOOX_RES="1600x1200"           # HiDPI -> 3200x2400, 1:1 with the Note Max panel
AVNC=com.gaurav.avnc
VNC_PORT=5900

boox_connected() { $ADB get-state >/dev/null 2>&1 }
boox_mode_active() { system_profiler SPDisplaysDataType 2>/dev/null | grep -q "$VIRTUAL_NAME:" }
controlling() { pgrep -xq scrcpy }

# BetterDisplay tagIDs, looked up by name so they survive re-creating the virtual screen.
tag_of() {
  betterdisplaycli get --identifiers 2>/dev/null | python3 -c '
import json, sys
name, kind = sys.argv[1], sys.argv[2]
for d in json.loads("[" + sys.stdin.read() + "]"):
    if d.get("name") == name and d.get("deviceType") == kind:
        print(d["tagID"]); break' "$1" "$2"
}
boox_tag()   { tag_of "$VIRTUAL_NAME" VirtualScreen }
laptop_tag() { tag_of "$LAPTOP_NAME" Display }

laptop_brightness() { betterdisplaycli get --tagID=$(laptop_tag) --hardwareBrightness }
save_laptop_brightness() {
  # Brightness changes fade in; wait for it to settle so we don't save a mid-fade value.
  local b=$(laptop_brightness) prev
  for i in {1..10}; do
    sleep 0.3; prev=$b; b=$(laptop_brightness)
    [[ $b == $prev ]] && break
  done
  (( b > 0.05 )) && echo $b > $STATE/laptop-brightness  # skip if already dimmed
}
restore_laptop_brightness() {
  local t=$(laptop_tag) b
  betterdisplaycli set --tagID=$t --softwareBrightness=1
  (( $(laptop_brightness) > 0.05 )) && return  # already lit; don't override the user
  b=$(cat $STATE/laptop-brightness 2>/dev/null); [[ -z $b ]] && b=0.6
  betterdisplaycli set --tagID=$t --hardwareBrightness=$b
}

# Leave control mode (scrcpy) if it's running, and let boox-control finish its cleanup
# without "returning to the previous mode" over whatever the caller is switching to.
stop_control() {
  controlling || return 0
  touch $STATE/switching
  pkill -9 -x scrcpy  # scrcpy ignores TERM/INT on macOS; the Boox drops its devices cleanly anyway
  for i in {1..20}; do pgrep -f "bin/boox-control" >/dev/null || break; sleep 0.25; done
  rm -f $STATE/switching
}

# Start AVNC fresh so its saved profile auto-connects. Boox "app freeze" disables apps
# after they're closed, so re-enable it first.
start_avnc() {
  $ADB shell pm enable $AVNC >/dev/null 2>&1
  $ADB shell am force-stop $AVNC >/dev/null 2>&1
  $ADB shell am start -n $AVNC/.StartupActivity >/dev/null 2>&1
}
stop_avnc() { $ADB shell am force-stop $AVNC >/dev/null 2>&1 }

wake_boox() {
  $ADB shell settings put global stay_on_while_plugged_in 7 >/dev/null 2>&1  # stay awake on USB
  $ADB shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
}
