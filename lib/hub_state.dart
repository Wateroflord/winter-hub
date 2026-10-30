import 'package:flutter/foundation.dart';

import 'catalog.dart';
import 'native.dart';

/// Номер сборки хаба (передаётся при сборке: --dart-define=BUILD=N).
const hubBuild = int.fromEnvironment('BUILD', defaultValue: 0);

class Job {
  final String text;
  final double? progress;
  const Job(this.text, [this.progress]);
}

class HubState extends ChangeNotifier {
  Catalog catalog = const Catalog([], []);
  final Map<String, Release?> releases = {};
  final Map<String, int?> installed = {};
  final Map<String, Job> jobs = {};
  Release? hubRelease;
  bool loading = true;
  bool offline = false;

  String? assetOf(AppEntry a) => isAndroid ? a.androidAsset : a.winAsset;

  Future<void> load() async {
    catalog = await loadCatalog(online: false);
    loading = catalog.apps.isEmpty;
    notifyListeners();
    await refreshInstalled();
    await refresh();
  }

  Future<void> refreshInstalled() async {
    for (final a in catalog.apps) {
      installed[a.id] = await installedBuild(a);
    }
    notifyListeners();
  }

  Future<void> refresh() async {
    catalog = await loadCatalog();
    var anyOnline = false;
    for (final a in catalog.apps) {
      final r = await latestRelease(a.repo, assetOf(a));
      releases[a.id] = r;
      anyOnline = anyOnline || r != null;
    }
    hubRelease = await latestRelease(hubEntry.repo, assetOf(hubEntry));
    offline = !anyOnline;
    loading = false;
    await refreshInstalled();
  }

  bool hasUpdate(AppEntry a) {
    final i = installed[a.id], r = releases[a.id];
    return i != null && r != null && r.build > i;
  }

  bool get hubUpdate => hubBuild > 0 && (hubRelease?.build ?? 0) > hubBuild;

  void _job(String id, Job? j) {
    if (j == null) {
      jobs.remove(id);
    } else {
      jobs[id] = j;
    }
    notifyListeners();
  }

  /// Скачать и установить (или обновить). Возвращает текст ошибки.
  Future<String?> install(AppEntry a) async {
    final r = releases[a.id];
    final asset = assetOf(a);
    final url = asset == null ? null : r?.assets[asset];
    if (url == null) return 'Файл для этой системы ещё не готов — попробуй через пару минут';
    try {
      _job(a.id, const Job('Скачиваю…', 0));
      final f = await download(url, asset!, (p) => _job(a.id, Job('Скачиваю… ${(p * 100).round()}%', p)));
      _job(a.id, const Job('Устанавливаю…'));
      final err = await installFile(f);
      return err;
    } catch (e) {
      return 'Не удалось скачать: $e';
    } finally {
      _job(a.id, null);
      await refreshInstalled();
    }
  }

  Future<String?> remove(AppEntry a) async {
    _job(a.id, const Job('Удаляю…'));
    final err = await uninstall(a);
    _job(a.id, null);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await refreshInstalled();
    return err;
  }

  Future<String?> updateHub() async {
    final asset = assetOf(hubEntry);
    final url = asset == null ? null : hubRelease?.assets[asset];
    if (url == null) return 'Обновление ещё не готово';
    try {
      _job('hub', const Job('Скачиваю обновление…', 0));
      final f = await download(url, asset!, (p) => _job('hub', Job('Скачиваю обновление… ${(p * 100).round()}%', p)));
      await runSelfInstaller(f);
      return null;
    } catch (e) {
      return '$e';
    } finally {
      _job('hub', null);
    }
  }
}
