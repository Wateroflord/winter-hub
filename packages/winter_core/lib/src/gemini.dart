import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Почему запрос к Gemini не удался. Текст ошибки на нужном языке пишет само приложение.
enum GeminiFail {
  /// Ключ не введён.
  noKey,

  /// Ключ неверный или не принят.
  badKey,

  /// Сервер долго не отвечал.
  timeout,

  /// Нет интернета.
  offline,

  /// Превышен лимит запросов (429).
  rateLimit,

  /// Ни одна модель из списка не ответила (404 / 5xx / модель не подходит).
  unavailable,

  /// Ответ заблокирован фильтрами (blockReason в [GeminiError.detail]).
  blocked,

  /// Пустой ответ.
  empty,

  /// Непонятный ответ сервера.
  badResponse,

  /// Другая ошибка HTTP ([GeminiError.code], текст в [GeminiError.detail]).
  http,
}

class GeminiError implements Exception {
  final GeminiFail kind;
  final int code;
  final String detail;
  final String model;
  const GeminiError(this.kind, {this.code = 0, this.detail = '', this.model = ''});

  @override
  String toString() => 'Gemini ${kind.name}${code > 0 ? ' $code' : ''}${detail.isEmpty ? '' : ': $detail'}';
}

/// Общий клиент Google Gemini для всех приложений Winter.
/// Ключ бесплатный: aistudio.google.com/apikey.
class WinterGemini {
  WinterGemini._();

  static const base = 'https://generativelanguage.googleapis.com/v1beta';

  /// Если выбранная модель недоступна, пробуем следующие.
  static const models = [
    'gemini-flash-latest',
    'gemini-3.8-flash',
    'gemini-3.6-flash',
    'gemini-3.5-flash-lite',
  ];

  /// Порядок моделей: сначала выбранная, потом остальные из [models].
  static List<String> order(String preferred) {
    final first = preferred.trim().isEmpty ? models.first : preferred.trim();
    return [first, ...models.where((m) => m != first)];
  }

  /// Часть запроса с текстом.
  static Map<String, dynamic> text(String t) => {'text': t};

  /// Часть запроса с картинкой (JPEG / PNG / WebP определяется по байтам).
  static Map<String, dynamic> image(Uint8List bytes) => {
        'inlineData': {'mimeType': mime(bytes), 'data': base64Encode(bytes)},
      };

  static String mime(Uint8List b) {
    if (b.length > 4 && b[0] == 0x89 && b[1] == 0x50) return 'image/png';
    if (b.length > 12 && b[0] == 0x52 && b[1] == 0x49 && b[8] == 0x57 && b[9] == 0x45) return 'image/webp';
    return 'image/jpeg';
  }

  /// Запрос к ИИ. [parts] — текст и картинки ([text], [image]).
  /// [json] — просить ответ в JSON. Возвращает текст ответа (без «мыслей» модели).
  /// [onlyModel] — не перебирать модели: спросить только [model] (ошибка unavailable — если она недоступна).
  static Future<String> generate({
    required String key,
    required List<Map<String, dynamic>> parts,
    String model = '',
    bool json = false,
    Map<String, dynamic>? config,
    Duration timeout = const Duration(seconds: 90),
    bool onlyModel = false,
  }) async {
    final k = key.trim();
    if (k.isEmpty) throw const GeminiError(GeminiFail.noKey);
    GeminiError last = const GeminiError(GeminiFail.unavailable);
    final list = order(model);
    for (final m in onlyModel ? list.take(1) : list) {
      try {
        return await _post(k, m, parts, json, config, timeout);
      } on _Next catch (e) {
        last = e.error;
      }
    }
    throw last;
  }

  /// Проверка ключа: null — ключ рабочий.
  static Future<GeminiError?> testKey(String key) async {
    try {
      final res = await http
          .get(Uri.parse('$base/models?pageSize=50'), headers: {'x-goog-api-key': key.trim()})
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 200) return null;
      if (res.statusCode == 400 || res.statusCode == 401 || res.statusCode == 403) {
        return GeminiError(GeminiFail.badKey, code: res.statusCode, detail: errorText(res.bodyBytes));
      }
      return GeminiError(GeminiFail.http, code: res.statusCode, detail: errorText(res.bodyBytes));
    } on TimeoutException {
      return const GeminiError(GeminiFail.timeout);
    } catch (e) {
      return GeminiError(GeminiFail.offline, detail: '$e');
    }
  }

  /// Достать JSON-объект из ответа ИИ (даже если вокруг есть лишний текст). null — не получилось.
  static Map<String, dynamic>? jsonObject(String text) {
    final s = text.indexOf('{');
    final e = text.lastIndexOf('}');
    if (s < 0 || e <= s) return null;
    try {
      final d = jsonDecode(text.substring(s, e + 1));
      if (d is Map) return Map<String, dynamic>.from(d);
    } catch (_) {}
    return null;
  }

  /// Текст ошибки из ответа Google.
  static String errorText(List<int> bytes) {
    try {
      final j = jsonDecode(utf8.decode(bytes));
      if (j is Map && j['error'] is Map) return '${(j['error'] as Map)['message'] ?? ''}';
    } catch (_) {}
    return '';
  }

  static Future<String> _post(
    String key,
    String model,
    List<Map<String, dynamic>> parts,
    bool json,
    Map<String, dynamic>? config,
    Duration timeout,
  ) async {
    final gen = <String, dynamic>{
      if (json) 'responseMimeType': 'application/json',
      ...?config,
    };
    final body = jsonEncode({
      'contents': [
        {'role': 'user', 'parts': parts},
      ],
      if (gen.isNotEmpty) 'generationConfig': gen,
    });

    final http.Response res;
    try {
      res = await http
          .post(
            Uri.parse('$base/models/$model:generateContent'),
            headers: {'Content-Type': 'application/json', 'x-goog-api-key': key},
            body: body,
          )
          .timeout(timeout);
    } on TimeoutException {
      throw GeminiError(GeminiFail.timeout, model: model);
    } catch (e) {
      throw GeminiError(GeminiFail.offline, detail: '$e', model: model);
    }

    final code = res.statusCode;
    if (code == 404 || code >= 500) {
      throw _Next(GeminiError(GeminiFail.unavailable, code: code, model: model));
    }
    if (code == 429) throw GeminiError(GeminiFail.rateLimit, code: code, model: model);
    if (code != 200) {
      final msg = errorText(res.bodyBytes);
      final low = msg.toLowerCase();
      if (low.contains('api key') || low.contains('api_key')) {
        throw GeminiError(GeminiFail.badKey, code: code, detail: msg, model: model);
      }
      if (code == 400 && low.contains('model')) {
        throw _Next(GeminiError(GeminiFail.unavailable, code: code, detail: msg, model: model));
      }
      throw GeminiError(GeminiFail.http, code: code, detail: msg, model: model);
    }

    final Map j;
    try {
      j = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
    } catch (_) {
      throw GeminiError(GeminiFail.badResponse, model: model);
    }
    final cands = j['candidates'];
    if (cands is! List || cands.isEmpty) {
      final fb = j['promptFeedback'];
      final reason = fb is Map ? '${fb['blockReason'] ?? ''}' : '';
      throw GeminiError(reason.isEmpty ? GeminiFail.empty : GeminiFail.blocked, detail: reason, model: model);
    }
    final first = cands.first;
    final content = first is Map ? first['content'] : null;
    final rawParts = content is Map ? content['parts'] : null;
    final out = (rawParts is List ? rawParts : const [])
        .whereType<Map>()
        .where((p) => p['thought'] != true && p['text'] is String)
        .map((p) => p['text'] as String)
        .join();
    if (out.trim().isEmpty) {
      final reason = first is Map ? '${first['finishReason'] ?? ''}' : '';
      throw GeminiError(reason == 'SAFETY' ? GeminiFail.blocked : GeminiFail.empty, detail: reason, model: model);
    }
    return out;
  }
}

class _Next implements Exception {
  final GeminiError error;
  const _Next(this.error);
}
