#!/bin/zsh
set -e
cd "$(dirname "$0")"
swift build -c release 2>&1 | grep -E "error|warning: unre|Compiling|Build" | tail -20
if [ ! -f AppIcon.icns ]; then
  swift ikon.swift /tmp/ikon1024.png
  mkdir -p AppIcon.iconset
  for n in 16 32 128 256 512; do
    sips -z $n $n /tmp/ikon1024.png --out AppIcon.iconset/icon_${n}x${n}.png >/dev/null
    sips -z $((n*2)) $((n*2)) /tmp/ikon1024.png --out AppIcon.iconset/icon_${n}x${n}@2x.png >/dev/null
  done
  iconutil -c icns AppIcon.iconset && rm -rf AppIcon.iconset
fi
APP="$HOME/Applications/Ollama Sohbet.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/OllamaSohbet "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"; cp AppIcon.icns "$APP/Contents/Resources/"
codesign --force -s - "$APP" 2>/dev/null
echo "KURULDU: $APP"
