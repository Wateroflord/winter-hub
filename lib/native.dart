import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'catalog.dart';

bool get isWindows => Platform.isWindows;
bool get isAndroid => Platform.isAndroid;

const _ch = MethodChannel('winterhub/apps');

/// Типы процессоров, под которые собираются APK (в порядке «чаще всего встречается»).
const apkAbis = ['arm64-v8a', 'armeabi-v7a', 'x86_64'];

/// Понятное название версии APK.
String abiTitle(String abi) => switch (abi) {
      'arm64-v8a' => 'ARM64',
      'armeabi-v7a' => 'ARMv7',
      'x86_64' => 'x86_64',
      _ => abi,
    };

/// Для кого эта версия.
String abiHint(String abi) => switch (abi) {
      'arm64-v8a' => 'почти все телефоны (2017 года и новее)',
      'armeabi-v7a' => 'очень старые и самые дешёвые телефоны',
      'x86_64' => 'эмуляторы на ПК и планшеты на Intel',
      _ => '',
    };

/// Какие типы процессора поддерживает телефон (первый — родной).
Future<List<String>> deviceAbis() async {
  if (!isAndroid) return const [];
  try {
    return await _ch.invokeListMethod<String>('abis') ?? const [];
  } catch (_) {
    return const [];
  }
}

/// Рекомендуемая версия APK: первая из поддерживаемых телефоном, под которую есть сборка.
String recommendedAbi(List<String> device) {
  for (final d in device) {
    if (apkAbis.contains(d)) return d;
  }
  return apkAbis.first;
}

/// Под какой процессор стоит APK — по коду версии (Flutter: 1xxx, 2xxx, 4xxx). null — общая сборка.
String? abiFromVersionCode(int code) => switch (code ~/ 1000) {
      1 => 'armeabi-v7a',
      2 => 'arm64-v8a',
      4 => 'x86_64',
      _ => null,
    };

/// Номер сборки по versionName «1.0.N» (у версий под процессор код версии = 1000·k + N).
int buildFromVersion(String name, int code) {
  final m = RegExp(r'(\d+)$').firstMatch(name.trim());
  return int.tryParse(m?.group(1) ?? '') ?? code % 1000;
}

/// Установленный APK на телефоне: номер сборки и тип процессора (null — общая сборка или неизвестно).
Future<({int build, String? abi})?> androidInstall(String pkg) async {
  try {
    final m = await _ch.invokeMapMethod<String, dynamic>('info', {'pkg': pkg});
    if (m == null) return null;
    final code = (m['code'] as num?)?.toInt() ?? 0;
    return (build: buildFromVersion('${m['name'] ?? ''}', code), abi: abiFromVersionCode(code));
  } catch (_) {
    try {
      final v = await _ch.invokeMethod<int>('version', {'pkg': pkg});
      return v == null || v < 0 ? null : (build: v % 1000, abi: abiFromVersionCode(v));
    } catch (_) {
      return null;
    }
  }
}

/// Номер установленной сборки: null — не установлено, 0 — установлено, но номер неизвестен.
Future<int?> installedBuild(AppEntry a) async {
  if (isAndroid) {
    final pkg = a.androidPackage;
    if (pkg == null) return null;
    return (await androidInstall(pkg))?.build;
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

/// Скачивание отменили кнопкой «Отмена».
class DownloadCancelled implements Exception {
  const DownloadCancelled();
  @override
  String toString() => 'Отменено';
}

/// Понятная ошибка скачивания (текст сразу для пользователя).
class DownloadError implements Exception {
  final String message;

  /// Файл не совпал по размеру или контрольной сумме (возможно, сводка версий устарела).
  final bool mismatch;
  const DownloadError(this.message, {this.mismatch = false});
  @override
  String toString() => message;
}

/// Ручка для отмены скачивания.
class DownloadCancel {
  http.Client? _client;
  bool cancelled = false;
  void cancel() {
    cancelled = true;
    _client?.close();
  }
}

/// Папка для скачанных установщиков (её хаб сам чистит).
Future<Directory> downloadsDir() async {
  final d = Directory('${(await getTemporaryDirectory()).path}${Platform.pathSeparator}winter-hub-downloads');
  await d.create(recursive: true);
  return d;
}

/// Удалить старые скачанные установщики. [legacyNames] — файлы, которые старые версии хаба
/// клали прямо во временную папку.
Future<void> cleanDownloads({Iterable<String> legacyNames = const []}) async {
  final now = DateTime.now();
  try {
    final d = await downloadsDir();
    await for (final f in d.list()) {
      if (f is! File) continue;
      // Свежий файл может прямо сейчас ставиться — его не трогаем.
      final age = now.difference(await f.lastModified());
      if (age > const Duration(minutes: 10)) await f.delete();
    }
  } catch (_) {}
  try {
    final tmp = await getTemporaryDirectory();
    for (final n in legacyNames) {
      final f = File('${tmp.path}${Platform.pathSeparator}$n');
      if (await f.exists()) await f.delete();
    }
  } catch (_) {}
}

/// Скачать файл с прогрессом.
///
/// [size] и [sha256Hex] — что должно получиться (из сводки версий); если файл не совпал,
/// он удаляется и возвращается ошибка — недокачанный или битый установщик не запустится.
/// Если связь пропала (20 секунд нет данных) — ошибка, а не вечное «Скачиваю…».
Future<File> download(
  String url,
  String name,
  void Function(double) progress, {
  int size = 0,
  String sha256Hex = '',
  DownloadCancel? cancel,
}) async {
  final dir = await downloadsDir();
  final f = File('${dir.path}${Platform.pathSeparator}$name');
  final part = File('${f.path}.part');
  final client = http.Client();
  cancel?._client = client;
  IOSink? sink;
  try {
    final http.StreamedResponse res;
    try {
      res = await client.send(http.Request('GET', Uri.parse(url))).timeout(const Duration(seconds: 25));
    } on TimeoutException {
      throw const DownloadError('Сервер GitHub не отвечает — проверь интернет и попробуй ещё раз');
    }
    if (res.statusCode != 200) throw DownloadError('Не удалось скачать (ошибка ${res.statusCode}) — попробуй через пару минут');
    final total = res.contentLength ?? size;
    sink = part.openWrite();
    final digest = _DigestSink();
    final hasher = sha256.startChunkedConversion(digest);
    var got = 0;
    await for (final chunk in res.stream.timeout(const Duration(seconds: 20))) {
      sink.add(chunk);
      hasher.add(chunk);
      got += chunk.length;
      if (total > 0) progress((got / total).clamp(0.0, 1.0));
    }
    await sink.close();
    sink = null;
    hasher.close();
    if (size > 0 && got != size) {
      throw DownloadError('Файл скачался не полностью (${_mb(got)} из ${_mb(size)}) — попробуй ещё раз', mismatch: true);
    }
    if (sha256Hex.isNotEmpty && digest.value.toString() != sha256Hex.toLowerCase()) {
      throw const DownloadError('Файл скачался с ошибкой (не совпала контрольная сумма) — попробуй ещё раз', mismatch: true);
    }
    if (await f.exists()) await f.delete();
    return await part.rename(f.path);
  } on TimeoutException {
    if (cancel?.cancelled ?? false) throw const DownloadCancelled();
    throw const DownloadError('Связь пропала во время скачивания — попробуй ещё раз');
  } catch (e) {
    if (cancel?.cancelled ?? false) throw const DownloadCancelled();
    if (e is DownloadError) rethrow;
    throw DownloadError('Не удалось скачать: ${e is SocketException || e is http.ClientException ? 'нет связи с интернетом' : e}');
  } finally {
    client.close();
    try {
      await sink?.close();
    } catch (_) {}
    try {
      if (await part.exists()) await part.delete();
    } catch (_) {}
  }
}

String _mb(int bytes) => '${(bytes / 1048576).toStringAsFixed(1)} МБ';

class _DigestSink implements Sink<Digest> {
  Digest? _v;
  Digest get value => _v!;
  @override
  void add(Digest data) => _v = data;
  @override
  void close() {}
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
    try {
      await f.delete();
    } catch (_) {}
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
