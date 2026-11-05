#!/bin/bash
# Ставит каждое приложение на эмулятор, запускает, делает скриншот и проверяет, что оно не упало.
for apk in apks/*.apk; do
  name=$(basename "$apk" .apk)
  BT=$(ls -d "$ANDROID_HOME"/build-tools/* | sort -V | tail -1)
  pkg=$("$BT/aapt2" dump packagename "$apk" 2>/dev/null | tr -d '\r')
  [ -n "$pkg" ] || pkg=$(echo "$name" | tr 'A-Z-' 'a-z_' | sed 's/^/com.winterhub./')
  adb install -r "$apk" >/dev/null 2>&1 || { echo "$name install-failed" >> out/status.txt; continue; }
  adb logcat -c
  adb shell monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  sleep 15
  pid=$(adb shell pidof "$pkg" | tr -d '\r')
  adb exec-out screencap -p > "out/$name.png"
  adb logcat -d -s AndroidRuntime:E flutter:E | tail -20 > "out/$name.log"
  echo "$name pkg=$pkg running=${pid:+yes}" >> out/status.txt
  adb shell am force-stop "$pkg"
done
cat out/status.txt
