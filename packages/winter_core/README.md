# winter_core

Общий код приложений Winter Hub. Подключается так:

```yaml
dependencies:
  winter_core:
    git:
      url: https://github.com/Wateroflord/winter-hub.git
      path: packages/winter_core
      ref: 2c2002e2c47b0ae344152f53c0a5b309043c9e9d   # зафиксированная версия winter_core (1.1)
```

`ref` — номер коммита winter-hub. Правки в winter_core не ломают приложения: приложение получает новую версию,
только когда в его pubspec.yaml поменяют `ref` на новый коммит.

## Отчёты о падениях

```dart
void main() => runWinterApp(repo: 'winter-mines', appName: 'Сапёр', body: _main);

Future<void> _main() async {
  runApp(const WinterCrashBanner(child: MinesApp()));
}
```

Ошибки пишутся в файл на устройстве. После падения при следующем запуске внизу появляется плашка
«Сообщить» — она открывает на GitHub готовый отчёт (issue) в репозитории приложения.

## Gemini

```dart
final text = await WinterGemini.generate(
  key: apiKey,
  model: '',                      // пусто — первая из WinterGemini.models
  parts: [WinterGemini.text('Привет'), WinterGemini.image(bytes)],
  json: true,                     // просить ответ в JSON
);
final obj = WinterGemini.jsonObject(text);
```

Ошибки приходят как `GeminiError` с полем `kind` (`noKey`, `badKey`, `timeout`, `offline`, `rateLimit`, `unavailable`, …) —
текст для пользователя на своём языке пишет приложение. Если модель недоступна, клиент сам пробует следующую.
