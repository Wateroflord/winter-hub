import 'dart:convert';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

import 'catalog.dart';

/// Уведомление «Есть обновления», даже когда хаб закрыт (Android).
///
/// Хаб запоминает, какие сборки установлены. Раз в 12 часов в фоне скачивается
/// versions.json (один маленький файл) и, если вышла новая сборка установленного
/// приложения, показывается одно уведомление. Об одной и той же сборке —
/// только один раз.
class UpdateNotify {
  static const _alarmId = 7341;
  static final _n = FlutterLocalNotificationsPlugin();

  static Future<void> _initPlugin() async {
    await _n.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
  }

  /// Запуск хаба на телефоне: включить фоновую проверку.
  static Future<void> start() async {
    try {
      await AndroidAlarmManager.initialize();
      await _initPlugin();
      final asked = await readCache('notify_asked.json');
      if (asked == null) {
        await _n.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
        await writeCache('notify_asked.json', {'v': 1});
      }
      await AndroidAlarmManager.periodic(const Duration(hours: 12), _alarmId, updateCheckEntry,
          rescheduleOnReboot: true, allowWhileIdle: true);
    } catch (e) {
      debugPrint('update notify: $e');
    }
  }

  /// Запомнить установленные сборки (вызывается при каждом обновлении списка).
  static Future<void> remember(Iterable<({String repo, String? asset, String name, int? build})> apps) async {
    await writeCache('installed_builds.json', {
      'apps': [
        for (final a in apps)
          if (a.asset != null && a.build != null) {'repo': a.repo, 'asset': a.asset, 'name': a.name, 'build': a.build},
      ],
    });
  }

  /// Какие приложения обновились (чистая логика, проверяется тестами).
  static List<String> outdated(Map installed, Map versions, Map notified) {
    final out = <String>[];
    final rel = (versions['releases'] as Map?) ?? const {};
    for (final a in (installed['apps'] as List? ?? const []).whereType<Map>()) {
      final key = '${a['repo']}|${a['asset']}';
      final latest = ((rel[key] as Map?)?['b'] as num?)?.toInt() ?? 0;
      final have = (a['build'] as num?)?.toInt() ?? 0;
      final told = (notified[key] as num?)?.toInt() ?? 0;
      if (have > 0 && latest > have && latest > told) out.add('${a['name']}');
    }
    return out;
  }

  static Future<void> check() async {
    final installed = await readCache('installed_builds.json');
    if (installed == null) return;
    final r = await http.get(Uri.parse('https://raw.githubusercontent.com/$hubRepo/main/versions.json')).timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) return;
    final versions = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
    final notified = Map<String, dynamic>.from(await readCache('notified_builds.json') ?? const {});
    final names = outdated(installed, versions, notified);
    if (names.isEmpty) return;
    final rel = versions['releases'] as Map;
    for (final a in (installed['apps'] as List).whereType<Map>()) {
      final key = '${a['repo']}|${a['asset']}';
      final b = ((rel[key] as Map?)?['b'] as num?)?.toInt();
      if (b != null) notified[key] = b;
    }
    await writeCache('notified_builds.json', notified);
    await _initPlugin();
    await _n.show(
      _alarmId,
      names.length == 1 ? 'Обновление: ${names.first}' : 'Есть обновления: ${names.length}',
      names.join(', '),
      const NotificationDetails(
        android: AndroidNotificationDetails('updates', 'Обновления приложений', importance: Importance.defaultImportance),
      ),
    );
  }
}

@pragma('vm:entry-point')
Future<void> updateCheckEntry() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await UpdateNotify.check();
  } catch (_) {}
}
