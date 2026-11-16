# winter_core

Общий код приложений Winter Hub. Подключается так:

```yaml
dependencies:
  winter_core:
    git:
      url: https://github.com/Wateroflord/winter-hub.git
      path: packages/winter_core
      ref: core-v1   # версия winter_core — новые правки в хабе не ломают приложения
```

Новая версия winter_core = новый тег (`core-v2`, …). Приложение переходит на неё, когда поменяешь `ref`.

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
