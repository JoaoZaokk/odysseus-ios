#!/bin/sh
# Fails the build when a SF Symbol used in the sources needs a newer OS than the
# deployment floor. `Image(systemName:)` with a symbol the device does not have
# renders nothing — no crash, no log, just a button that is not there (1.9
# shipped "wand.and.sparkles", SF Symbols 6 / iOS 18, on an iOS 17 floor).
# Reads the availability table shipped with macOS; skips with a warning when
# that table is missing so the build never depends on it.
PLIST=/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/name_availability.plist
SRC="${SRCROOT:-.}/Odysseus"
FLOOR_IOS="${IPHONEOS_DEPLOYMENT_TARGET:-17.0}"
FLOOR_MAC="${MACOSX_DEPLOYMENT_TARGET:-14.0}"
if [ ! -f "$PLIST" ]; then
  echo "warning: SF Symbols availability table not found at $PLIST — symbol floor check skipped"
  exit 0
fi
python3 - "$PLIST" "$SRC" "$FLOOR_IOS" "$FLOOR_MAC" <<'PY'
import plistlib, re, sys, glob
plist, src, floor_ios, floor_mac = sys.argv[1:5]
d = plistlib.load(open(plist, 'rb'))
symbols, years = d['symbols'], d['year_to_release']
def v(s): return tuple(int(x) for x in s.split('.'))
bad = 0
for f in sorted(glob.glob(f'{src}/**/*.swift', recursive=True)):
    text = open(f, encoding='utf-8').read()
    for m in re.finditer(r'system(?:Name|Image):\s*"([a-z0-9.]+)"', text):
        name = m.group(1); line = text.count('\n', 0, m.start()) + 1
        year = symbols.get(name)
        if year is None:
            print(f'{f}:{line}: error: SF Symbol "{name}" is not in the availability table (typo?)'); bad += 1; continue
        need_ios, need_mac = years[year]['iOS'], years[year]['macOS']
        if v(need_ios) > v(floor_ios) or v(need_mac) > v(floor_mac):
            print(f'{f}:{line}: error: SF Symbol "{name}" needs iOS {need_ios} / macOS {need_mac}; floor is iOS {floor_ios} / macOS {floor_mac}'); bad += 1
sys.exit(1 if bad else 0)
PY
