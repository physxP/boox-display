#!/bin/zsh
# Build the helpers, install the control app and login items, and link the commands.
# Safe to re-run after changes.
set -e
ROOT=${0:A:h}
cd $ROOT
export PATH="/opt/homebrew/bin:$PATH"

for c in betterdisplaycli scrcpy swiftc; do
  command -v $c >/dev/null || { echo "Missing $c. Needs: brew install --cask betterdisplay; brew install scrcpy; Xcode command line tools."; exit 1; }
done
[[ -x $HOME/Library/Android/sdk/platform-tools/adb ]] || echo "Warning: adb not found at ~/Library/Android/sdk/platform-tools/adb (set ADB to override)."

echo "Building helpers..."
mkdir -p build
for s in vnccursor mousewatch booxmenu; do swiftc -O src/$s.swift -o build/$s; done

source bin/lib.sh
if [[ -z $(boox_tag) ]]; then
  echo "Creating the \"$VIRTUAL_NAME\" virtual screen in BetterDisplay..."
  betterdisplaycli create --type=VirtualScreen --virtualScreenName="$VIRTUAL_NAME" \
    --aspectWidth=4 --aspectHeight=3 --virtualScreenHiDPI=on
fi

echo "Installing Boox Control.app and commands..."
rm -rf "$HOME/Applications/Boox Control.app"
mkdir -p $HOME/Applications
cp -R "app/Boox Control.app" $HOME/Applications/
for c in boox-screen boox-laptop boox-control boox-auto; do ln -sf $ROOT/bin/$c /opt/homebrew/bin/$c; done

echo "Installing login items..."
for p in launchd/*.plist; do
  label=${p:t:r} dest=$HOME/Library/LaunchAgents/${p:t}
  sed "s|__ROOT__|$ROOT|g" $p > $dest
  launchctl bootout gui/$UID/$label 2>/dev/null || true
  launchctl bootstrap gui/$UID $dest
done
echo "Done."
