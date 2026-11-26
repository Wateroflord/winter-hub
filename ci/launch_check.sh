#!/bin/bash
# Проверка перед выпуском: APK ставится на эмулятор, запускается и не падает 25 секунд.
# Запуск (внутри android-emulator-runner): bash .winter/ci/launch_check.sh dist/App-x86_64.apk
# Если приложение упало — сборка останавливается, релиз не выходит, в отчёте видна причина.
apk="$1"
mkdir -p launch
BT=$(ls -d "$ANDROID_HOME"/build-tools/* | sort -V | tail -1)
pkg=$("$BT/aapt2" dump packagename "$apk" 2>/dev/null | tr -d '\r')
[ -n "$pkg" ] || { echo "::error title=Проверка на эмуляторе::Не удалось прочитать имя пакета из $apk"; exit 1; }
echo "Пакет: $pkg"

for try in 1 2 3; do
  adb install -r "$apk" > launch/install.txt 2>&1 && break
  echo "Установка не удалась (попытка $try):"; cat launch/install.txt
  [ $try = 3 ] && { echo "::error title=Проверка на эмуляторе::APK не ставится на Android 14: $(tail -1 launch/install.txt)"; exit 1; }
  sleep 10
done

adb logcat -c
adb logcat -b crash -c 2>/dev/null
adb shell monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
alive=1
for i in $(seq 1 25); do
  sleep 1
  if [ -z "$(adb shell pidof "$pkg" | tr -d '\r')" ] && [ $i -ge 5 ]; then alive=0; break; fi
done
adb exec-out screencap -p > launch/screen.png 2>/dev/null
adb logcat -d -b crash > launch/crash.txt 2>/dev/null
adb logcat -d > launch/logcat.txt 2>/dev/null
crash=$(grep -A60 "Process: $pkg" launch/crash.txt)

if [ $alive = 1 ] && [ -z "$crash" ]; then
  echo "Приложение запустилось и работает — можно выпускать."
  exit 0
fi
echo "===== Приложение упало при запуске ====="
if [ -n "$crash" ]; then echo "$crash"; else grep -E "FATAL|AndroidRuntime|Fatal signal|DEBUG" launch/logcat.txt | tail -60; fi
reason=$(echo "$crash" | grep -E "Caused by|Exception|Error" | tail -1 | sed 's/^.*\(Caused by: \)//' | cut -c1-200)
[ -n "$reason" ] || reason="процесс закрылся сам (подробности в логе шага)"
echo "::error title=Проверка на эмуляторе::Приложение падает при запуске — релиз не выпущен. $reason"
exit 1
