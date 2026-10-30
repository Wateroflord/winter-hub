import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'catalog.dart';

bool get isWindows => Platform.isWindows;
bool get isAndroid => Platform.isAndroid;

const _ch = MethodChannel('winterhub/apps');

/// Номер установленной сборки: null — не установлено, 0 — установлено, но номер неизвестен.
Future<int?> installedBuild(AppEntry a) async {
  if (isAndroid) {
    final pkg = a.androidPackage;
    if (pkg == null) return null;
    try {
      final v = await _ch.invokeMethod<int>('version', {'pkg': pkg});
      return v == null || v < 0 ? null : v;
    } catch (_) {
      return null;
    }
  }
  if (isWindows) {
    final key = _uninstallKey(a);
    if (key != null) {
      final v = await _regValue(key, 'DisplayVersion');
      if (v != null) {
        final m = RegExp(r'(\d+)$').firstMatch(v.trim());
        return int.tryParse(m?.group(1) ?? '') ?? 0;
      }
    }
    final exe = winExePath(a);
    if (exe != null && File(exe).existsSync()) return 0;
  }
  return null;
}

String? _uninstallKey(AppEntry a) =>
    a.winAppId == null ? null : r'HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\' '${a.winAppId}_is1';

Future<String?> _regValue(String key, String name) async {
  try {
    final r = await Process.run('reg', ['query', key, '/v', name]);
    if (r.exitCode != 0) return null;
    for (final line in '${r.stdout}'.split('\n')) {
      final t = line.trim();
      if (t.startsWith(name)) {
        final parts = t.split(RegExp(r'\s{2,}|\t'));
        if (parts.length >= 3) return parts.sublist(2).join(' ').trim();
      }
    }
  } catch (_) {}
  return null;
}

/// Путь к exe на ПК (установщик ставит в %LOCALAPPDATA%\Programs).
String? winExePath(AppEntry a) {
  final rel = a.winExe;
  final base = Platform.environment['LOCALAPPDATA'];
  if (rel == null || base == null) return null;
  return '$base\\Programs\\$rel';
}

Future<String?> launch(AppEntry a) async {
  try {
    if (isAndroid) {
      final ok = await _ch.invokeMethod<bool>('launch', {'pkg': a.androidPackage});
      return ok == true ? null : 'Не удалось открыть приложение';
    }
    final exe = winExePath(a);
    if (exe == null || !File(exe).existsSync()) return 'Приложение не найдено — переустанови его';
    await Process.start(exe, [], mode: ProcessStartMode.detached, workingDirectory: File(exe).parent.path);
    return null;
  } catch (e) {
    return '$e';
  }
}

Future<String?> uninstall(AppEntry a) async {
  try {
    if (isAndroid) {
      await _ch.invokeMethod('uninstall', {'pkg': a.androidPackage});
      return null;
    }
    final key = _uninstallKey(a);
    final cmd = key == null ? null : await _regValue(key, 'UninstallString');
    if (cmd == null) return 'Не нашёл программу удаления';
    final exe = cmd.replaceAll('"', '').trim();
    final p = await Process.start(exe, ['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART']);
    await p.exitCode;
    return null;
  } catch (e) {
    return '$e';
  }
}

/// Скачать файл с прогрессом.
Future<File> download(String url, String name, void Function(double) progress) async {
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}${Platform.pathSeparator}$name');
  final client = http.Client();
  try {
    final res = await client.send(http.Request('GET', Uri.parse(url)));
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    final total = res.contentLength ?? 0;
    final sink = f.openWrite();
    var got = 0;
    await for (final chunk in res.stream) {
      sink.add(chunk);
      got += chunk.length;
      if (total > 0) progress(got / total);
    }
    await sink.close();
    return f;
  } finally {
    client.close();
  }
}

/// Установить скачанный файл. На телефоне откроется системное окно установки.
Future<String?> installFile(File f, {bool silent = true}) async {
  try {
    if (isAndroid) {
      final can = await _ch.invokeMethod<bool>('canInstall') ?? true;
      if (!can) {
        await _ch.invokeMethod('installSettings');
        return 'Разреши Winter Hub устанавливать приложения и нажми кнопку ещё раз';
      }
      await _ch.invokeMethod('install', {'path': f.path});
      return null;
    }
    final p = await Process.start(f.path, [if (silent) ...['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART']]);
    final code = await p.exitCode;
    return code == 0 ? null : 'Установка не завершилась (код $code)';
  } catch (e) {
    return '$e';
  }
}

/// Обновить сам хаб: на ПК установщик закроет хаб и запустит новую версию.
Future<void> runSelfInstaller(File f) async {
  if (isWindows) {
    await Process.start(f.path, ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS'], mode: ProcessStartMode.detached);
    exit(0);
  } else {
    await installFile(f);
  }
}
