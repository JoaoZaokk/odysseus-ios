#!/bin/zsh
# Builds, installs and opens Odysseus on a connected iPhone.
#
#   ./scripts/install-iphone.sh            # Release
#   ./scripts/install-iphone.sh debug      # Debug (keeps the -screenshotRoute hooks)
#
# Signing comes from Signing.xcconfig, which includes the gitignored
# Local.xcconfig. The team id is never written here: this repo is public.
#
# The iPhone must be UNLOCKED. With the screen locked `devicectl` cannot mount
# the developer disk image, so the install step waits for it instead of failing.
set -euo pipefail

CONFIG=${1:-Release}
case "${CONFIG:l}" in
  debug)   CONFIG=Debug ;;
  release) CONFIG=Release ;;
  *) print -u2 "usage: $0 [debug|release]"; exit 2 ;;
esac

ROOT=${0:A:h:h}
DD=${ODYSSEUS_DD:-$ROOT/build/dd-device}
BUNDLE=com.zao.odysseus

cd "$ROOT"

[[ -f Local.xcconfig ]] || { print -u2 "Local.xcconfig is missing: copy Local.xcconfig.example and fill in your team id."; exit 1 }

# The first physical device Xcode can reach. No UDID pinned here, since one day
# it will be another phone. Looked up after the build: the phone often wakes up
# on the network only once someone unlocks it.
find_device() {
  xcrun devicectl list devices 2>/dev/null \
    | awk '$0 !~ /simulated/ && $0 !~ /unavailable/ && ($0 ~ /available/ || $0 ~ /connected/) {for (i=1;i<=NF;i++) if ($i ~ /^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}$/) print $i}' \
    | head -1
}

command -v xcodegen >/dev/null && xcodegen generate >/dev/null

print "building $CONFIG…"
xcodebuild -project Odysseus.xcodeproj -scheme Odysseus -configuration "$CONFIG" \
  -destination 'generic/platform=iOS' -derivedDataPath "$DD" \
  CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates \
  build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true

app="$DD/Build/Products/$CONFIG-iphoneos/Odysseus.app"
[[ -d "$app" ]] || { print -u2 "the build did not produce $app"; exit 1 }
print "bundle: $(du -shx "$app" | cut -f1)"

# Wait for the screen to unlock rather than dying: a phone in a pocket should
# not cost a rebuild. A locked wireless device fails with several different
# messages for the same cause, so retry on any error, show the reason once, and
# give up after ten minutes.
print "installing…"
warned=0
installed=0
device=""
out="no iPhone available"
for attempt in {1..60}; do
  device=$(find_device)
  if [[ -n "$device" ]] && out=$(xcrun devicectl device install app --device "$device" "$app" 2>&1); then
    installed=1
    break
  fi
  if (( warned == 0 )); then
    print ""
    # `|| true`: with pipefail, a grep that matches nothing would end the script here.
    print -r -- "$out" | grep -E "ERROR|FailureReason|locked" | head -3 | sed 's/^/    /' || true
    print ""
    if [[ -z "$device" ]]; then
      print "    no iPhone available: connect it (or put it on the same network) and trust this Mac."
    fi
    print ">>> If it is the screen: UNLOCK THE IPHONE. Retrying every 10 s."
    warned=1
  fi
  sleep 10
done

if (( installed == 0 )); then
  print -u2 ""
  print -u2 "Gave up after ten minutes. Last error:"
  print -u2 "$out" | tail -8
  exit 1
fi
print "installed on $device."

xcrun devicectl device process launch --device "$device" "$BUNDLE" >/dev/null 2>&1 \
  && print "opened." \
  || print -u2 "(could not open it — tap the icon)"
