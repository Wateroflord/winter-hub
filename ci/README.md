# Общие CI-инструменты приложений Winter

## Общая сборка (`.github/workflows/flutter-app.yml`)

Вся сборка приложения — Android (отдельный APK под каждый процессор), подпись, релиз и Windows — описана один раз
в winter-hub. В приложении остаётся короткий `build.yml`:

```yaml
jobs:
  app:
    uses: Wateroflord/winter-hub/.github/workflows/flutter-app.yml@main
    secrets: inherit
    with:
      project: kbju_tracker
      org: com.kbju
      asset: KBJU-Tracker        # KBJU-Tracker-arm64-v8a.apk, …, KBJU-Tracker-Setup.exe
      title: КБЖУ Трекер
      win_title: KBJU Tracker
```

В релизе: `<asset>-arm64-v8a.apk`, `<asset>-armeabi-v7a.apk`, `<asset>-x86_64.apk` и `<asset>.apk`
(копия arm64 — старое имя, чтобы не сломать старые версии хаба). Хаб сам выбирает версию под телефон.
Версия Flutter зафиксирована (`flutter_version`), чтобы новый Flutter не ломал все сборки разом.
Версии пакетов фиксирует `pubspec.lock`: после удачного выпуска бот сам кладёт его в репозиторий приложения.
Проверить сборку без релиза: Actions → Build → Run workflow → снять галочку «publish».

Все приложения (`winter-mines`, `kbju-tracker`, `dota-draft`, …) берут эти скрипты отсюда
шагом `actions/checkout` с `repository: Wateroflord/winter-hub`, `path: .winter`, `sparse-checkout: /ci/` (без cone-режима).
Исправил здесь — исправилось во всех сборках.

| Файл | Что делает |
|---|---|
| `annotate.py` | Превращает ошибки анализатора, сборки и тестов в аннотации GitHub |
| `sign_apk.py` | Подписывает APK постоянным секретным ключом из секрета `WINTER_SIGNING` |
| `patch_windows.py` | Общая настройка Windows-проекта (если в приложении нет своего `tools/patch_windows.py`) |
| `make_versions.py` | Собирает `versions.json` — свежие сборки всех приложений для хаба (с SHA-256 файлов). Лежит в ветке `data` одним коммитом; в `main` попадает, только когда вышли новые сборки |
| `legacy/shared-old.keystore` | Старый **публичный** ключ. Нужен только как запасной вариант, пока секрет не добавлен, и для «смены ключа» |

## Подпись APK

Раньше каждая сборка подписывалась новым случайным ключом, поэтому обновления на телефоне
не вставали поверх. Теперь `sign_apk.py` подписывает APK одним ключом из секрета `WINTER_SIGNING`
(Settings → Secrets and variables → Actions в каждом репозитории приложения).

- Секрет не задан → выпуск останавливается с ошибкой (тестовая сборка без релиза подписывается старым публичным ключом с предупреждением).
- Секрет задан → APK подписан новым ключом со «сменой ключа» (APK Signature Scheme v3):
  сборки со старым ключом обновляются без удаления, а APK только со старым ключом поверх уже не встанет.

Проверка на эмуляторе — workflow `sign-test.yml` (запускается пушем в ветку `ci-sign-test`).

Секрет достаточно добавить только в winter-hub (вместе с токеном `ADMIN_TOKEN`, право
«Secrets: Read and write»): workflow `secrets-sync.yml` раз в сутки копирует `WINTER_SIGNING`
во все репозитории из `catalog.json`.

**Файл ключа и пароль храни в надёжном месте.** Если ключ потерять, обновления снова перестанут
вставать поверх — придётся удалять и ставить приложения заново.
