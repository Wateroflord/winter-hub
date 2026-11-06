import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Отчёты о падениях.
///
/// Ошибки записываются в файл на устройстве. При следующем запуске внизу
/// экрана появляется плашка «Приложение упало в прошлый раз» с кнопкой
/// «Сообщить» — она открывает на GitHub готовый отчёт (issue) в репозитории
/// приложения. Ничего не отправляется без нажатия.
class WinterCrash {
  WinterCrash._();

  static String repo = '';
  static String appName = '';
  static File? _file;

  /// Ошибки прошлого запуска (их показывает [WinterCrashBanner]).
  static final ValueNotifier<String?> pending = ValueNotifier(null);

  static const _maxBytes = 24 * 1024;
  static final _seen = <String>{};

  static Future<void> init({required String repo, required String appName}) async {
    WinterCrash.repo = repo;
    WinterCrash.appName = appName;
    try {
      final dir = await getApplicationSupportDirectory();
      await dir.create(recursive: true);
      _file = File('${dir.path}/winter_crash.log');
      if (await _file!.exists()) {
        final t = (await _file!.readAsString()).trim();
        if (t.isNotEmpty) pending.value = t;
      }
    } catch (_) {}
  }

  /// Записать ошибку. Одинаковые ошибки за один запуск пишутся один раз.
  static void record(Object error, StackTrace? stack, {String where = ''}) {
    final head = '$error'.split('\n').first;
    if (!_seen.add(head) || _seen.length > 20) return;
    final text = StringBuffer()
      ..writeln('=== ${DateTime.now().toIso8601String()} ${where.isEmpty ? '' : '($where)'}')
      ..writeln(error)
      ..writeln(_trim(stack));
    debugPrint(text.toString());
    final f = _file;
    if (f == null) return;
    try {
      var old = f.existsSync() ? f.readAsStringSync() : '';
      if (old.length > _maxBytes) old = old.substring(old.length - _maxBytes ~/ 2);
      f.writeAsStringSync('$old$text', flush: true);
    } catch (_) {}
  }

  static String _trim(StackTrace? s) {
    if (s == null) return '';
    final lines = '$s'.split('\n').where((l) => l.trim().isNotEmpty).take(25);
    return lines.join('\n');
  }

  /// Текст отчёта для GitHub.
  static String reportBody(String log) {
    final body = StringBuffer()
      ..writeln('Приложение: $appName')
      ..writeln('Система: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}')
      ..writeln('Отправлено из приложения.')
      ..writeln()
      ..writeln('```')
      ..writeln(log.length > 5000 ? log.substring(log.length - 5000) : log)
      ..writeln('```');
    return body.toString();
  }

  static Uri reportUri(String log) {
    final first = log.split('\n').firstWhere((l) => l.trim().isNotEmpty && !l.startsWith('==='), orElse: () => 'ошибка');
    final title = 'Падение: ${first.length > 80 ? first.substring(0, 80) : first}';
    return Uri.https('github.com', '/Wateroflord/$repo/issues/new', {'title': title, 'body': reportBody(log), 'labels': 'crash'});
  }

  /// Открыть готовый отчёт на GitHub и очистить журнал.
  static Future<void> send() async {
    final log = pending.value;
    if (log == null) return;
    try {
      await launchUrl(reportUri(log), mode: LaunchMode.externalApplication);
    } catch (_) {}
    await dismiss();
  }

  static Future<void> dismiss() async {
    pending.value = null;
    try {
      if (_file != null && await _file!.exists()) await _file!.writeAsString('');
    } catch (_) {}
  }
}

/// Запуск приложения с перехватом всех ошибок.
///
/// ```dart
/// void main() => runWinterApp(repo: 'winter-mines', appName: 'Сапёр', body: _main);
/// ```
Future<void> runWinterApp({required String repo, required String appName, required FutureOr<void> Function() body}) async {
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await WinterCrash.init(repo: repo, appName: appName);
    final prevFlutter = FlutterError.onError;
    FlutterError.onError = (d) {
      prevFlutter?.call(d);
      WinterCrash.record(d.exception, d.stack, where: d.library ?? 'flutter');
    };
    PlatformDispatcher.instance.onError = (e, s) {
      WinterCrash.record(e, s, where: 'platform');
      return true;
    };
    await body();
  }, (e, s) => WinterCrash.record(e, s, where: 'zone'));
}

/// Плашка внизу экрана после падения. Оборачивает корневой виджет:
/// `runApp(WinterCrashBanner(child: MyApp()))`.
class WinterCrashBanner extends StatelessWidget {
  final Widget child;
  const WinterCrashBanner({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          Positioned.fill(child: child),
          ValueListenableBuilder<String?>(
            valueListenable: WinterCrash.pending,
            builder: (context, log, _) {
              if (log == null) return const SizedBox.shrink();
              final pad = MediaQueryData.fromView(View.of(context)).padding;
              return Positioned(
                left: 12,
                right: 12,
                bottom: pad.bottom + 12,
                child: Material(
                  color: const Color(0xFF1C2536),
                  elevation: 8,
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                    child: Row(
                      children: [
                        const Icon(Icons.bug_report_outlined, color: Color(0xFFFFB547)),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'В прошлый раз приложение упало. Отправить отчёт разработчику?',
                            style: TextStyle(color: Colors.white, fontSize: 13, height: 1.3),
                          ),
                        ),
                        TextButton(
                          onPressed: WinterCrash.send,
                          child: const Text('Сообщить', style: TextStyle(color: Color(0xFF7ADCFF), fontWeight: FontWeight.w700)),
                        ),
                        IconButton(
                          onPressed: WinterCrash.dismiss,
                          icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
