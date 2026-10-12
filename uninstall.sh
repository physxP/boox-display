#!/bin/zsh
# Remove the login items, commands and control app. Leaves BetterDisplay, scrcpy, AVNC,
# the virtual screen and ~/.local/state/boox-display alone.
ROOT=${0:A:h}
"$ROOT/bin/boox-laptop" >/dev/null 2>&1
for p in $ROOT/launchd/*.plist; do
  launchctl bootout gui/$UID/${p:t:r} 2>/dev/null
  rm -f $HOME/Library/LaunchAgents/${p:t}
done
for c in boox-screen boox-laptop boox-control boox-auto; do rm -f /opt/homebrew/bin/$c; done
rm -rf "$HOME/Applications/Boox Control.app" "$ROOT/build"
echo "Uninstalled."
