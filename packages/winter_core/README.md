# winter_core

Общий код приложений Winter Hub. Подключается так:

```yaml
dependencies:
  winter_core:
    git:
      url: https://github.com/Wateroflord/winter-hub.git
      path: packages/winter_core
```

## Отчёты о падениях

```dart
void main() => runWinterApp(repo: 'winter-mines', appName: 'Сапёр', body: _main);

Future<void> _main() async {
  runApp(const WinterCrashBanner(child: MinesApp()));
}
```

Ошибки пишутся в файл на устройстве. После падения при следующем запуске внизу появляется плашка
«Сообщить» — она открывает на GitHub готовый отчёт (issue) в репозитории приложения.
