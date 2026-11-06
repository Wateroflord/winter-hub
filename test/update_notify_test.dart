import 'package:flutter_test/flutter_test.dart';
import 'package:winter_hub/update_notify.dart';

void main() {
  test('уведомление только о новых сборках установленных приложений и только один раз', () {
    final installed = {
      'apps': [
        {'repo': 'W/mines', 'asset': 'M.apk', 'name': 'Сапёр', 'build': 3},
        {'repo': 'W/chess', 'asset': 'C.apk', 'name': 'Шахматы', 'build': 6},
        {'repo': 'W/music', 'asset': 'Mu.apk', 'name': 'Музыка', 'build': 2},
      ],
    };
    final versions = {
      'releases': {
        'W/mines|M.apk': {'b': 5},
        'W/chess|C.apk': {'b': 6},
        'W/music|Mu.apk': {'b': 4},
      },
    };
    expect(UpdateNotify.outdated(installed, versions, {}), ['Сапёр', 'Музыка']);
    expect(UpdateNotify.outdated(installed, versions, {'W/mines|M.apk': 5}), ['Музыка']);
    expect(UpdateNotify.outdated(installed, versions, {'W/mines|M.apk': 5, 'W/music|Mu.apk': 4}), isEmpty);
    expect(UpdateNotify.outdated({'apps': []}, versions, {}), isEmpty);
    expect(UpdateNotify.outdated(installed, {}, {}), isEmpty);
  });
}
