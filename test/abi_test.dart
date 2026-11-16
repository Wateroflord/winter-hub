import 'package:flutter_test/flutter_test.dart';
import 'package:winter_hub/hub_state.dart';
import 'package:winter_hub/native.dart';

void main() {
  test('номер сборки берётся из versionName, а не из кода версии', () {
    expect(buildFromVersion('1.0.31', 2031), 31);
    expect(buildFromVersion('1.0.30', 30), 30);
    expect(buildFromVersion('', 2031), 31);
  });

  test('процессор по коду версии', () {
    expect(abiFromVersionCode(1031), 'armeabi-v7a');
    expect(abiFromVersionCode(2031), 'arm64-v8a');
    expect(abiFromVersionCode(4031), 'x86_64');
    expect(abiFromVersionCode(31), isNull);
  });

  test('рекомендуемая версия', () {
    expect(recommendedAbi(['arm64-v8a', 'armeabi-v7a', 'armeabi']), 'arm64-v8a');
    expect(recommendedAbi(['armeabi-v7a', 'armeabi']), 'armeabi-v7a');
    expect(recommendedAbi(['x86_64', 'arm64-v8a']), 'x86_64');
    expect(recommendedAbi([]), 'arm64-v8a');
  });

  test('имя файла под процессор', () {
    expect(HubState.abiAsset('KBJU-Tracker.apk', 'arm64-v8a'), 'KBJU-Tracker-arm64-v8a.apk');
  });
}
