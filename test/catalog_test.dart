import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:winter_hub/catalog.dart';

void main() {
  test('catalog.json читается, у всех приложений есть репозиторий и файлы', () {
    final c = Catalog.parse(jsonDecode(File('catalog.json').readAsStringSync()) as Map);
    expect(c.apps, isNotEmpty);
    final ids = <String>{};
    for (final a in c.apps) {
      expect(ids.add(a.id), isTrue, reason: 'повтор id ${a.id}');
      expect(a.repo, startsWith('Wateroflord/'));
      expect(a.androidAsset != null || a.winAsset != null, isTrue, reason: a.id);
      if (a.androidAsset != null) expect(a.androidPackage, isNotNull, reason: a.id);
      if (a.winAsset != null) expect(a.winExe, isNotNull, reason: a.id);
    }
  });

  test('pickRelease берёт свежий выпуск, где есть нужный файл', () {
    final list = [
      {'tag_name': 'build-9', 'published_at': '2026-11-05T10:00:00Z', 'assets': [
        {'name': 'App.apk', 'browser_download_url': 'u9', 'size': 5},
      ]},
      {'tag_name': 'build-8', 'published_at': '2026-11-04T10:00:00Z', 'assets': [
        {'name': 'App.apk', 'browser_download_url': 'u8', 'size': 5},
        {'name': 'App-Setup.exe', 'browser_download_url': 'w8', 'size': 7},
      ]},
      {'tag_name': 'build-7', 'draft': true, 'assets': []},
    ];
    expect(pickRelease(list, 'App.apk')!.build, 9);
    final w = pickRelease(list, 'App-Setup.exe')!;
    expect(w.build, 8);
    expect(w.assets['App-Setup.exe'], 'w8');
    expect(w.date, '2026-11-04');
    expect(pickRelease(list, 'Nope.apk'), isNull);
    expect(pickRelease([{'tag_name': 'v1.0.42', 'assets': [{'name': 'a.apk', 'browser_download_url': 'x'}]}], 'a.apk')!.build, 42);
  });

  test('versions.json: формат совпадает с Release', () {
    final v = Versions.parse({
      'updated': '2026-11-05T12:00:00Z',
      'releases': {
        'Wateroflord/winter-mines|Winter-Mines.apk': {'b': 3, 'd': '2026-11-05', 'a': {'Winter-Mines.apk': 'u'}, 's': {'Winter-Mines.apk': 10}},
      },
    });
    expect(v.updated, DateTime.utc(2026, 11, 5, 12));
    final r = v.of('Wateroflord/winter-mines', 'Winter-Mines.apk')!;
    expect(r.build, 3);
    expect(r.sizes['Winter-Mines.apk'], 10);
    expect(v.of('Wateroflord/winter-mines', null), isNull);
  });

  test('versions.json в репозитории читается', () {
    final f = File('versions.json');
    if (!f.existsSync()) return;
    final v = Versions.parse(jsonDecode(f.readAsStringSync()) as Map);
    expect(v.releases, isNotEmpty);
  });
}
