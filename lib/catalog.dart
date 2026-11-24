import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

const hubRepo = 'Wateroflord/winter-hub';
const _catalogUrl = 'https://raw.githubusercontent.com/$hubRepo/main/catalog.json';

class NewsItem {
  final String date, text;
  const NewsItem(this.date, this.text);
  static List<NewsItem> parse(dynamic l) => [
        for (final n in (l is List ? l : const []))
          if (n is Map) NewsItem('${n['date'] ?? ''}', '${n['text'] ?? ''}'),
      ];
}

class AppEntry {
  final String id, name, tagline, description, repo, color, icon;
  final String? androidPackage, androidAsset;
  final String? winAsset, winAppId, winExe;
  final List<NewsItem> news;

  /// Приложение стало плагином другого (id «хозяина», например kbju).
  /// Хаб его больше не ставит: показывает, только если оно ещё стоит, — чтобы удалить.
  final String? mergedInto;
  const AppEntry({
    required this.id,
    required this.name,
    required this.tagline,
    required this.description,
    required this.repo,
    required this.color,
    required this.icon,
    this.androidPackage,
    this.androidAsset,
    this.winAsset,
    this.winAppId,
    this.winExe,
    this.news = const [],
    this.mergedInto,
  });

  static AppEntry fromJson(Map j) {
    final a = j['android'] is Map ? j['android'] as Map : const {};
    final w = j['windows'] is Map ? j['windows'] as Map : const {};
    return AppEntry(
      id: '${j['id']}',
      name: '${j['name'] ?? ''}',
      tagline: '${j['tagline'] ?? ''}',
      description: '${j['description'] ?? ''}',
      repo: '${j['repo'] ?? ''}',
      color: '${j['color'] ?? '#7FD8FF'}',
      icon: '${j['icon'] ?? ''}',
      androidPackage: a['package']?.toString(),
      androidAsset: a['asset']?.toString(),
      winAsset: w['asset']?.toString(),
      winAppId: w['appId']?.toString(),
      winExe: w['exe']?.toString(),
      news: NewsItem.parse(j['news']),
      mergedInto: j['mergedInto']?.toString(),
    );
  }
}

/// Сам хаб — тоже «приложение» (для самообновления).
const hubEntry = AppEntry(
  id: 'hub',
  name: 'Winter Hub',
  tagline: '',
  description: '',
  repo: hubRepo,
  color: '#7FD8FF',
  icon: '',
  androidPackage: 'com.winterhub.winter_hub',
  androidAsset: 'Winter-Hub.apk',
  winAsset: 'Winter-Hub-Setup.exe',
  winAppId: '{6E2F4A80-1C3B-4D57-9E68-0A7B2C4D5E91}',
  winExe: 'Winter Hub\\winter_hub.exe',
);

class Catalog {
  final List<AppEntry> apps;
  final List<NewsItem> hubNews;

  /// Каталог только что скачан из интернета (а не взят из кэша).
  final bool online;
  const Catalog(this.apps, this.hubNews, {this.online = false});

  static Catalog parse(Map j, {bool online = false}) => Catalog(
        [for (final a in (j['apps'] as List? ?? const [])) if (a is Map) AppEntry.fromJson(a)],
        NewsItem.parse(j['hubNews']),
        online: online,
      );
}

/// Встроенный каталог (если нет интернета при первом запуске) — копия catalog.json,
/// которая попадает в приложение при сборке (assets в pubspec.yaml).
Future<Map> _builtin() async {
  try {
    return jsonDecode(await rootBundle.loadString('catalog.json')) as Map;
  } catch (_) {
    return const {'apps': []};
  }
}

Future<File?> _cacheFile(String name) async {
  try {
    final d = await getApplicationSupportDirectory();
    await d.create(recursive: true);
    return File('${d.path}${Platform.pathSeparator}$name');
  } catch (_) {
    return null;
  }
}

/// Сохранённая копия (для работы без интернета).
Future<Map?> readCache(String name) async {
  try {
    final f = await _cacheFile(name);
    if (f != null && await f.exists()) return jsonDecode(await f.readAsString()) as Map;
  } catch (_) {}
  return null;
}

Future<void> writeCache(String name, Object data) async {
  try {
    await (await _cacheFile(name))?.writeAsString(jsonEncode(data));
  } catch (_) {}
}

Future<Catalog> loadCatalog({bool online = true}) async {
  if (online) {
    try {
      final r = await http.get(Uri.parse('$_catalogUrl?t=${DateTime.now().millisecondsSinceEpoch ~/ 60000}')).timeout(const Duration(seconds: 12));
      if (r.statusCode == 200) {
        final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
        await writeCache('catalog.json', j);
        return Catalog.parse(j, online: true);
      }
    } catch (_) {}
  }
  final c = await readCache('catalog.json');
  return Catalog.parse(c ?? await _builtin());
}

/// Последний выпуск приложения на GitHub.
class Release {
  final int build;
  final String date;
  final Map<String, String> assets; // имя → ссылка
  final Map<String, int> sizes;

  /// SHA-256 файлов (имя → hex). GitHub считает его сам для каждого файла релиза.
  final Map<String, String> hashes;
  const Release(this.build, this.date, this.assets, this.sizes, [this.hashes = const {}]);

  Map<String, dynamic> toJson() => {'b': build, 'd': date, 'a': assets, 's': sizes, 'h': hashes};
  static Release fromJson(Map j) => Release(
        (j['b'] as num?)?.toInt() ?? 0,
        '${j['d'] ?? ''}',
        {for (final e in ((j['a'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'},
        {for (final e in ((j['s'] as Map?) ?? const {}).entries) if (e.value is num) '${e.key}': (e.value as num).toInt()},
        {for (final e in ((j['h'] as Map?) ?? const {}).entries) if (e.value is String) '${e.key}': '${e.value}'},
      );
}

/// «sha256:abc…» из ответа GitHub → «abc…». Пустая строка — хэша нет.
String digestHex(Object? d) {
  final s = '${d ?? ''}'.trim().toLowerCase();
  if (!s.startsWith('sha256:')) return '';
  final h = s.substring(7);
  return RegExp(r'^[0-9a-f]{64}$').hasMatch(h) ? h : '';
}

/// Сводка лежит в ветке data (одна запись, без истории). Старые сборки хаба читают main —
/// туда сводка попадает, только когда выходят новые сборки.
const versionsUrls = [
  'https://raw.githubusercontent.com/$hubRepo/data/versions.json',
  'https://raw.githubusercontent.com/$hubRepo/main/versions.json',
];

/// Скачать versions.json как есть (null — нет связи).
Future<Map?> fetchVersionsJson({Duration timeout = const Duration(seconds: 12)}) async {
  final t = DateTime.now().millisecondsSinceEpoch ~/ 60000;
  for (final u in versionsUrls) {
    try {
      final r = await http.get(Uri.parse('$u?t=$t')).timeout(timeout);
      if (r.statusCode == 200) return jsonDecode(utf8.decode(r.bodyBytes)) as Map;
    } catch (_) {}
  }
  return null;
}

/// Сводка свежих сборок всех приложений (ключ «repo|файл»).
/// Её раз в 15 минут собирает GitHub Actions в репозитории хаба, поэтому хаб
/// делает один запрос вместо 13 к GitHub API (без ключа там лимит 60 в час).
class Versions {
  final DateTime? updated;
  final Map<String, Release> releases;
  const Versions(this.updated, this.releases);

  Release? of(String repo, String? asset) => asset == null ? null : releases['$repo|$asset'];

  static Versions parse(Map j) => Versions(
        DateTime.tryParse('${j['updated'] ?? ''}'),
        {
          for (final e in ((j['releases'] as Map?) ?? const {}).entries)
            if (e.value is Map) '${e.key}': Release.fromJson(e.value as Map),
        },
      );
}

Future<Versions?> loadVersions() async {
  final j = await fetchVersionsJson();
  return j == null ? null : Versions.parse(j);
}

/// Ищем свежий выпуск через GitHub API, где уже есть нужный файл
/// (Windows-файлы появляются на несколько минут позже APK).
/// Запрос условный (ETag): если ничего не изменилось, GitHub отвечает 304 и не присылает
/// список заново. Лимит (60 запросов в час без ключа) такой ответ всё равно тратит —
/// поэтому хаб спрашивает API только про приложения, которые сам ставит.
Future<Release?> latestRelease(String repo, String? asset) async {
  final cacheName = 'rel_${repo.replaceAll('/', '_')}_$asset.json';
  final etagName = 'etag2_${repo.replaceAll('/', '_')}.json';
  try {
    final etag = (await readCache(etagName))?['etag']?.toString();
    final cachedList = await readCache('list2_${repo.replaceAll('/', '_')}.json');
    final r = await http.get(Uri.parse('https://api.github.com/repos/$repo/releases?per_page=5'), headers: {
      'Accept': 'application/vnd.github+json',
      if (etag != null && cachedList != null) 'If-None-Match': etag,
    }).timeout(const Duration(seconds: 15));
    List list;
    if (r.statusCode == 304 && cachedList != null) {
      list = (cachedList['l'] as List?) ?? const [];
    } else if (r.statusCode == 200) {
      list = jsonDecode(utf8.decode(r.bodyBytes)) as List;
      final tag = r.headers['etag'];
      if (tag != null) {
        await writeCache(etagName, {'etag': tag});
        await writeCache('list2_${repo.replaceAll('/', '_')}.json', {'l': _slim(list)});
      }
    } else {
      throw Exception('HTTP ${r.statusCode}');
    }
    final out = pickRelease(list, asset);
    if (out != null) {
      await writeCache(cacheName, out.toJson());
      return out;
    }
  } catch (_) {
    final c = await readCache(cacheName);
    if (c != null) return Release.fromJson(c);
  }
  return null;
}

/// Только нужные поля ответа GitHub (чтобы кэш был маленьким).
List _slim(List list) => [
      for (final rel in list.whereType<Map>())
        {
          'tag_name': rel['tag_name'],
          'published_at': rel['published_at'],
          'draft': rel['draft'],
          'prerelease': rel['prerelease'],
          'assets': [
            for (final a in (rel['assets'] as List? ?? const []).whereType<Map>())
              {'name': a['name'], 'browser_download_url': a['browser_download_url'], 'size': a['size'], 'digest': a['digest']},
          ],
        },
    ];

/// Самый свежий выпуск, в котором есть нужный файл.
Release? pickRelease(List list, String? asset) {
  for (final rel in list.whereType<Map>()) {
    if (rel['draft'] == true || rel['prerelease'] == true) continue;
    final assets = <String, String>{}, sizes = <String, int>{}, hashes = <String, String>{};
    for (final a in (rel['assets'] as List? ?? const []).whereType<Map>()) {
      assets['${a['name']}'] = '${a['browser_download_url']}';
      sizes['${a['name']}'] = (a['size'] as num?)?.toInt() ?? 0;
      final h = digestHex(a['digest']);
      if (h.isNotEmpty) hashes['${a['name']}'] = h;
    }
    if (asset != null && !assets.containsKey(asset)) continue;
    final tag = '${rel['tag_name'] ?? ''}';
    final b = int.tryParse(RegExp(r'(\d+)$').firstMatch(tag)?.group(1) ?? '') ?? 0;
    return Release(b, '${rel['published_at'] ?? ''}'.split('T').first, assets, sizes, hashes);
  }
  return null;
}
