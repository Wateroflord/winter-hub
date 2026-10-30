import 'dart:convert';
import 'dart:io';

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
  const Catalog(this.apps, this.hubNews);

  static Catalog parse(Map j) => Catalog(
        [for (final a in (j['apps'] as List? ?? const [])) if (a is Map) AppEntry.fromJson(a)],
        NewsItem.parse(j['hubNews']),
      );
}

/// Встроенный каталог (если нет интернета при первом запуске).
const _builtin = r'''{"apps":[
{"id":"dota","name":"Dota Draft","tagline":"Пики, контрпики и шанс победы в Dota 2","description":"Подсказывает, кого пикать, считает шанс победы. На ПК — оверлей поверх игры.","repo":"Wateroflord/dota-draft","color":"#E04848","icon":"https://raw.githubusercontent.com/Wateroflord/dota-draft/main/assets/icon/icon.png","android":{"package":"com.dotadraft.dota_draft","asset":"Dota-Draft.apk"},"windows":{"asset":"Dota-Draft-Setup.exe","appId":"{8F3C2A51-5D7B-4E1A-9C64-2B7D1E9A0F11}","exe":"Dota Draft\\dota_draft.exe"}},
{"id":"kbju","name":"КБЖУ Трекер","tagline":"Калории и БЖУ по фото еды","description":"Фото еды — и ИИ считает калории и БЖУ. Вес, вода, привычки, тренировки.","repo":"Wateroflord/kbju-tracker","color":"#5B9DFF","icon":"https://raw.githubusercontent.com/Wateroflord/kbju-tracker/main/assets/icon/icon.png","android":{"package":"com.kbju.kbju_tracker","asset":"KBJU-Tracker.apk"},"windows":{"asset":"KBJU-Tracker-Setup.exe","appId":"{3C1B7E62-9A4D-4F8B-B2E7-6D0A5C9F1E24}","exe":"KBJU Tracker\\kbju_tracker.exe"}}
]}''';

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
        return Catalog.parse(j);
      }
    } catch (_) {}
  }
  final c = await readCache('catalog.json');
  return Catalog.parse(c ?? jsonDecode(_builtin) as Map);
}

/// Последний выпуск приложения на GitHub.
class Release {
  final int build;
  final String date;
  final Map<String, String> assets; // имя → ссылка
  final Map<String, int> sizes;
  const Release(this.build, this.date, this.assets, this.sizes);

  Map<String, dynamic> toJson() => {'b': build, 'd': date, 'a': assets, 's': sizes};
  static Release fromJson(Map j) => Release(
        (j['b'] as num?)?.toInt() ?? 0,
        '${j['d'] ?? ''}',
        {for (final e in ((j['a'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'},
        {for (final e in ((j['s'] as Map?) ?? const {}).entries) '${e.key}': (e.value as num).toInt()},
      );
}

/// Ищем свежий выпуск, где уже есть нужный файл (Windows-файлы появляются на несколько минут позже APK).
Future<Release?> latestRelease(String repo, String? asset) async {
  try {
    final r = await http.get(Uri.parse('https://api.github.com/repos/$repo/releases?per_page=5'),
        headers: {'Accept': 'application/vnd.github+json'}).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
    final list = jsonDecode(utf8.decode(r.bodyBytes)) as List;
    for (final rel in list.whereType<Map>()) {
      if (rel['draft'] == true || rel['prerelease'] == true) continue;
      final assets = <String, String>{}, sizes = <String, int>{};
      for (final a in (rel['assets'] as List? ?? const []).whereType<Map>()) {
        assets['${a['name']}'] = '${a['browser_download_url']}';
        sizes['${a['name']}'] = (a['size'] as num?)?.toInt() ?? 0;
      }
      if (asset != null && !assets.containsKey(asset)) continue;
      final tag = '${rel['tag_name'] ?? ''}';
      final b = int.tryParse(RegExp(r'(\d+)$').firstMatch(tag)?.group(1) ?? '') ?? 0;
      final out = Release(b, '${rel['published_at'] ?? ''}'.split('T').first, assets, sizes);
      await writeCache('rel_${repo.replaceAll('/', '_')}_$asset.json', out.toJson());
      return out;
    }
  } catch (_) {
    final c = await readCache('rel_${repo.replaceAll('/', '_')}_$asset.json');
    if (c != null) return Release.fromJson(c);
  }
  return null;
}
