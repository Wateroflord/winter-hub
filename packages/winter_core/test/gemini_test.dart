import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:winter_core/winter_core.dart';

void main() {
  test('порядок моделей: выбранная первой, без повторов', () {
    final o = WinterGemini.order('gemini-3.6-flash');
    expect(o.first, 'gemini-3.6-flash');
    expect(o.toSet().length, o.length);
    expect(WinterGemini.order('').first, WinterGemini.models.first);
  });

  test('JSON из ответа с лишним текстом', () {
    expect(WinterGemini.jsonObject('вот: {"a": 1} готово')?['a'], 1);
    expect(WinterGemini.jsonObject('нет json'), isNull);
  });

  test('тип картинки по байтам', () {
    expect(WinterGemini.mime(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 0])), 'image/png');
    expect(WinterGemini.mime(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0, 0, 0])), 'image/jpeg');
  });

  test('без ключа — понятная ошибка', () async {
    await expectLater(
      WinterGemini.generate(key: ' ', parts: [WinterGemini.text('x')]),
      throwsA(isA<GeminiError>().having((e) => e.kind, 'kind', GeminiFail.noKey)),
    );
  });
}
