#!/bin/bash
# Ставит каждое приложение на эмулятор, запускает, делает скриншот и проверяет, что оно не упало.
# В out/status.txt: «OK», «FAIL» (упало при запуске) или «skip» (APK только для ARM-телефонов).
BT=$(ls -d "$ANDROID_HOME"/build-tools/* | sort -V | tail -1)
for apk in apks/*.apk; do
  name=$(basename "$apk" .apk)
  pkg=$("$BT/aapt2" dump packagename "$apk" 2>/dev/null | tr -d '\r')
  [ -n "$pkg" ] || pkg=$(echo "$name" | tr 'A-Z-' 'a-z_' | sed 's/^/com.winterhub./')
  libs=$(unzip -l "$apk" | grep -o 'lib/[^/]*/' | sort -u | tr '\n' ' ')
  if [ -n "$libs" ] && ! echo "$libs" | grep -q 'lib/x86_64/'; then
    echo "$name skip (только ARM: $libs)" >> out/status.txt
    continue
  fi
  adb install -r "$apk" >/dev/null 2>&1 || { echo "$name install-failed" >> out/status.txt; continue; }
  adb logcat -c
  adb shell monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  sleep 15
  pid=$(adb shell pidof "$pkg" | tr -d '\r')
  adb exec-out screencap -p > "out/$name.png"
  adb logcat -d -s AndroidRuntime:E flutter:E | tail -20 > "out/$name.log"
  if [ -n "$pid" ]; then echo "$name OK" >> out/status.txt; else echo "$name FAIL (pkg=$pkg)" >> out/status.txt; fi
  adb shell am force-stop "$pkg"
done
cat out/status.txt
