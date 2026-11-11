# Shared settings and helpers for the boox-display scripts. Sourced, not run.
export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
export ADB=${ADB:-$HOME/Library/Android/sdk/platform-tools/adb}  # scrcpy reads $ADB too

BIN=${${(%):-%x}:A:h}
STATE=$HOME/.local/state/boox-display
mkdir -p $STATE

VIRTUAL_NAME="Boox Note Max"   # BetterDisplay virtual screen
LAPTOP_NAME="Built-in Display"
BOOX_RES="1600x1200"           # HiDPI -> 3200x2400, 1:1 with the Note Max panel
BOOX_MODEL="NoteMax"           # adb model name
AVNC=com.gaurav.avnc
VNC_PORT=5900                  # macOS Screen Sharing: the whole desktop
BOOXVNC_PORT=5901              # booxvnc: the Boox display alone
DEFAULT_LAYOUT=color           # on plug-in and for boox-screen without a layout (see boox-screen)

# --- Connections -------------------------------------------------------------------
# The Boox can be reachable over USB and over Wi-Fi (Android wireless debugging) at the
# same time, so every adb/scrcpy call targets one of them via ANDROID_SERIAL.
usb_serial()  { $ADB devices -l 2>/dev/null | awk -v m="model:$BOOX_MODEL" '$2 == "device" && / usb:/ && index($0, m) { print $1; exit }' }
wifi_serial() { $ADB devices -l 2>/dev/null | awk -v m="model:$BOOX_MODEL" '$2 == "device" && $1 ~ /^[0-9.]+:[0-9]+$/ && index($0, m) { print $1; exit }' }
usb_connected()  { [[ -n $(usb_serial) ]] }
wifi_connected() { [[ -n $(wifi_serial) ]] }

# use_link usb|wifi: point adb and scrcpy at that connection. Fails if it isn't there.
use_link() {
  local s; [[ $1 == wifi ]] && s=$(wifi_serial) || s=$(usb_serial)
  [[ -n $s ]] || return 1
  export ANDROID_SERIAL=$s LINK=$1
}

# Connect adb to the Boox over Wi-Fi. First by network discovery (it advertises
# _adb-tls-connect as "adb-<serial>-..." while wireless debugging is on), then by the
# address recorded at the last USB plug-in; the Boox's mDNS responder is unreliable.
wifi_discover() {
  wifi_connected && return 0
  local serial=$(cat $STATE/boox-serial 2>/dev/null) target
  [[ -n $serial ]] || return 1
  if target=$($BIN/../build/findboox $serial 3); then
    echo $target > $STATE/boox-wifi
  else
    target=$(cat $STATE/boox-wifi 2>/dev/null)
  fi
  [[ -n $target ]] || return 1
  $ADB connect $target >/dev/null 2>&1
  wifi_connected || { $ADB disconnect $target >/dev/null 2>&1; return 1 }
}

# On every USB plug-in: remember which Boox this is, make sure wireless debugging is on
# (so Wi-Fi works again after a restart or a network change), and connect over Wi-Fi too.
usb_housekeeping() {
  local ANDROID_SERIAL=$(usb_serial) ip port
  [[ -n $ANDROID_SERIAL ]] || return
  export ANDROID_SERIAL
  echo $ANDROID_SERIAL > $STATE/boox-serial
  if [[ $($ADB shell settings get global adb_wifi_enabled 2>/dev/null) != 1* ]]; then
    $ADB shell settings put global adb_wifi_enabled 1 >/dev/null 2>&1; sleep 2
  fi
  wifi_connected && return
  # Wireless debugging listens on a random port; find it among the Boox's listening ports.
  ip=$($ADB shell ip -4 addr show wlan0 2>/dev/null | awk '/inet / { split($2, a, "/"); print a[1]; exit }')
  [[ -n $ip ]] || return
  for port in $($ADB shell netstat -ltn 2>/dev/null | awk '$6 == "LISTEN" && $4 ~ /^\[::\]:/ { n = split($4, a, ":"); print a[n] }'); do
    [[ $port == ($VNC_PORT|$BOOXVNC_PORT) ]] && continue
    $ADB connect $ip:$port >/dev/null 2>&1
    if wifi_connected; then echo $ip:$port > $STATE/boox-wifi; return; fi
    $ADB disconnect $ip:$port >/dev/null 2>&1
  done
}

# --- Mode state ----------------------------------------------------------------------
# $STATE/mode: laptop | screen-usb | screen-wifi | control-usb | control-wifi
mode() { cat $STATE/mode 2>/dev/null || echo laptop }
set_mode() { echo $1 > $STATE/mode }
# $STATE/layout, while the Boox is a screen: mirror | boox (Boox main) | color (color screen main)
layout() { cat $STATE/layout 2>/dev/null || echo $DEFAULT_LAYOUT }
# BetterDisplay can't change displays while the Mac is locked, so mode switches wait for unlock.
mac_locked() { ioreg -n Root -d1 | grep -q '"CGSSessionScreenIsLocked"=Yes' }
wait_unlocked() { while mac_locked; do sleep 2; done }
boox_mode_active() { system_profiler SPDisplaysDataType 2>/dev/null | grep -q "$VIRTUAL_NAME:" }
controlling() { pgrep -xq scrcpy }
# The VNC server in use: booxvnc when the Boox is one of several desktops, else Screen Sharing.
booxvnc_running() { pgrep -xq booxvnc }
vnc_port() { booxvnc_running && echo $BOOXVNC_PORT || echo $VNC_PORT }
# The VNC forward is device-wide; its label says which link carries it (UsbFfs = USB).
vnc_forward_on() {
  local l=$($ADB -s ${$(usb_serial):-$(wifi_serial)} reverse --list 2>/dev/null | awk -v p="tcp:$(vnc_port)" '$2 == p { print $1 }')
  [[ $1 == usb && $l == UsbFfs* ]] || [[ $1 == wifi && -n $l && $l != UsbFfs* ]]
}
vnc_client_connected() { netstat -an -p tcp 2>/dev/null | grep -q "127.0.0.1.$(vnc_port) .*ESTABLISHED" }

# --- Displays ------------------------------------------------------------------------
# BetterDisplay must be running for any display change, and Homebrew upgrades quit it without
# restarting it, so start it if needed and wait until it answers. `betterdisplaycli` runs the
# same binary with arguments, so only the bare app process counts as running.
start_betterdisplay() {
  pgrep -fxq '.*/BetterDisplay\.app/Contents/MacOS/BetterDisplay' || open -ga BetterDisplay
  local end=$(( SECONDS + 30 ))
  until [[ $(betterdisplaycli get --identifiers 2>/dev/null) == *tagID* ]]; do
    (( SECONDS < end )) || { echo "BetterDisplay isn't responding."; return 1 }
    sleep 0.5
  done
}

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
# Real (color) screens: external ones first, then the built-in one.
color_tags() {
  betterdisplaycli get --identifiers 2>/dev/null | python3 -c '
import json, sys
ds = [d for d in json.loads("[" + sys.stdin.read() + "]") if d.get("deviceType") == "Display"]
for d in sorted(ds, key=lambda d: d.get("name") == sys.argv[1]): print(d["tagID"])' "$LAPTOP_NAME"
}
external_connected() { [[ -n $(color_tags | grep -vx "$(laptop_tag)") ]] }
# The color screen that was main before the Boox took over; it is main again in the color
# layout and in laptop mode. Falls back to an external screen, then the laptop.
save_color_main() {
  local t=$(betterdisplaycli get --displayWithMainStatus --identifier=tagID 2>/dev/null)
  echo ${t%%,*} > $STATE/color-main
}
color_main() {
  local saved=$(cat $STATE/color-main 2>/dev/null) tags=($(color_tags))
  (( ${tags[(Ie)$saved]} )) && echo $saved || echo $tags[1]
}

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

# booxvnc serves the Boox display alone. launchd starts it, so Screen Recording permission
# belongs to booxvnc rather than to whatever ran this script.
start_booxvnc() {
  [[ -s $STATE/vnc-password ]] || (umask 077; LC_ALL=C tr -dc A-Za-z0-9 </dev/urandom | head -c 8 >$STATE/vnc-password)
  stop_booxvnc  # a fresh one for the current display layout
  launchctl kickstart gui/$UID/local.boox-display.vnc
  for i in {1..40}; do nc -z 127.0.0.1 $BOOXVNC_PORT 2>/dev/null && return; sleep 0.25; done
  echo "booxvnc didn't start:"; tail -2 $STATE/booxvnc.log; return 1
}
stop_booxvnc() {
  booxvnc_running || return 0
  launchctl kill TERM gui/$UID/local.boox-display.vnc 2>/dev/null
  for i in {1..20}; do booxvnc_running || break; sleep 0.1; done
}

# --- Boox side (needs use_link first) ------------------------------------------------
# Leave control mode (scrcpy) if it's running, and let boox-control finish its cleanup
# without "returning to the previous mode" over whatever the caller is switching to.
stop_control() {
  controlling || return 0
  touch $STATE/switching
  pkill -9 -x scrcpy  # scrcpy ignores TERM/INT on macOS; the Boox drops its devices cleanly anyway
  for i in {1..20}; do pgrep -f "bin/boox-control" >/dev/null || break; sleep 0.25; done
  rm -f $STATE/switching
}

# Start AVNC fresh: for Screen Sharing its saved profile auto-connects; for booxvnc it opens
# a vnc:// link (view-only, with booxvnc's password). Boox "app freeze" disables apps after
# they're closed, so re-enable it first.
start_avnc() {
  $ADB shell pm enable $AVNC >/dev/null 2>&1
  $ADB shell am force-stop $AVNC >/dev/null 2>&1
  if [[ $1 == booxvnc ]]; then
    $ADB shell "am start -a android.intent.action.VIEW -d 'vnc://localhost:$BOOXVNC_PORT?VncPassword=$(<$STATE/vnc-password)&ViewOnly=true&ConnectionName=Mac'" >/dev/null 2>&1
  else
    $ADB shell am start -n $AVNC/.StartupActivity >/dev/null 2>&1
  fi
}
stop_avnc() { $ADB shell am force-stop $AVNC >/dev/null 2>&1 }

# Keep the Boox awake while on USB power (Wi-Fi sessions rely on AVNC's "keep screen on";
# in control mode the keyboard/mouse count as activity).
wake_boox() {
  $ADB shell settings put global stay_on_while_plugged_in 7 >/dev/null 2>&1
  $ADB shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
}
