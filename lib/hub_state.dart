import 'package:flutter/foundation.dart';

import 'catalog.dart';
import 'native.dart';
import 'update_notify.dart';

/// Номер сборки хаба (передаётся при сборке: --dart-define=BUILD=N).
const hubBuild = int.fromEnvironment('BUILD', defaultValue: 0);

class Job {
  final String text;
  final double? progress;

  /// Можно ли сейчас нажать «Отмена» (только пока идёт скачивание).
  final bool canCancel;
  const Job(this.text, [this.progress, this.canCancel = false]);
}

class HubState extends ChangeNotifier {
  Catalog catalog = const Catalog([], []);
  final Map<String, Release?> releases = {};
  final Map<String, int?> installed = {};
  final Map<String, Job> jobs = {};
  final Map<String, DownloadCancel> _cancels = {};

  /// Обновления, запущенные на телефоне: id → ожидаемая сборка.
  final Map<String, int> _pending = {};

  /// Приложения, обновление которых не встало (старая версия подписана другим ключом).
  final Set<String> stuck = {};
  Release? hubRelease;
  bool loading = true;
  bool offline = false;

  /// Типы процессора телефона (первый — родной) и рекомендуемая версия APK.
  List<String> deviceAbiList = const [];
  String get recommended => recommendedAbi(deviceAbiList);

  /// Под какой процессор стоит установленное приложение (null — общая сборка/неизвестно).
  final Map<String, String?> installedAbi = {};

  /// Версия, которую пользователь выбрал сам (id → abi).
  final Map<String, String> abiChoice = {};

  /// Файл в сводке версий (старое общее имя — по нему ищется выпуск).
  String? assetOf(AppEntry a) => isAndroid ? a.androidAsset : a.winAsset;

  /// Какая версия APK будет скачана: выбранная вручную → та, что уже стоит → рекомендуемая.
  String abiFor(AppEntry a) => abiChoice[a.id] ?? installedAbi[a.id] ?? recommended;

  /// Имя файла версии под процессор: KBJU-Tracker.apk → KBJU-Tracker-arm64-v8a.apk.
  static String abiAsset(String legacy, String abi) =>
      legacy.endsWith('.apk') ? '${legacy.substring(0, legacy.length - 4)}-$abi.apk' : legacy;

  /// Какой файл скачивать. Если у выпуска нет версий под процессор (старая сборка) — общий файл.
  String? downloadAsset(AppEntry a, [Release? rel]) {
    final legacy = assetOf(a);
    if (legacy == null || !isAndroid) return legacy;
    final r = rel ?? (a.id == hubEntry.id ? hubRelease : releases[a.id]);
    final split = abiAsset(legacy, abiFor(a));
    return r != null && r.assets.containsKey(split) ? split : legacy;
  }

  /// Есть ли у последнего выпуска отдельные версии под процессор.
  bool hasSplit(AppEntry a) {
    final legacy = assetOf(a), r = releases[a.id];
    return isAndroid && legacy != null && r != null && apkAbis.any((x) => r.assets.containsKey(abiAsset(legacy, x)));
  }

  Future<void> chooseAbi(AppEntry a, String? abi) async {
    if (abi == null) {
      abiChoice.remove(a.id);
    } else {
      abiChoice[a.id] = abi;
    }
    await writeCache('abi_choice.json', abiChoice);
    notifyListeners();
  }

  Future<void> load() async {
    if (isAndroid) {
      deviceAbiList = await deviceAbis();
      final saved = await readCache('abi_choice.json');
      if (saved != null) {
        for (final e in saved.entries) {
          if (apkAbis.contains('${e.value}')) abiChoice['${e.key}'] = '${e.value}';
        }
      }
    }
    catalog = await loadCatalog(online: false);
    loading = catalog.apps.isEmpty;
    notifyListeners();
    await cleanDownloads(legacyNames: [
      for (final a in [...catalog.apps, hubEntry]) ...[
        if (assetOf(a) != null) assetOf(a)!,
        if (assetOf(a) != null) for (final x in apkAbis) HubState.abiAsset(assetOf(a)!, x),
      ],
    ]);
    await refreshInstalled();
    await refresh();
  }

  Future<void> refreshInstalled() async {
    for (final a in catalog.apps) {
      if (isAndroid && a.androidPackage != null) {
        final i = await androidInstall(a.androidPackage!);
        installed[a.id] = i?.build;
        installedAbi[a.id] = i?.abi;
      } else {
        installed[a.id] = await installedBuild(a);
      }
    }
    notifyListeners();
    if (isAndroid) {
      await UpdateNotify.remember([
        for (final a in catalog.apps) (repo: a.repo, asset: assetOf(a), name: a.name, build: installed[a.id]),
        (repo: hubEntry.repo, asset: assetOf(hubEntry), name: 'Winter Hub', build: hubBuild > 0 ? hubBuild : null),
      ]);
    }
  }

  /// [manual] — пользователь сам нажал «обновить»: тогда дополнительно
  /// спрашиваем GitHub напрямую (сводка versions.json отстаёт до ~15 минут).
  Future<void> refresh({bool manual = false}) async {
    catalog = await loadCatalog();
    final v = await loadVersions();
    final fresh = v?.updated != null && DateTime.now().toUtc().difference(v!.updated!) < const Duration(hours: 7);
    Future<Release?> get(AppEntry a) async {
      final fromSummary = v?.of(a.repo, assetOf(a));
      if (fromSummary != null && fresh && !manual) return fromSummary;
      final direct = await latestRelease(a.repo, assetOf(a));
      if (direct == null) return fromSummary;
      if (fromSummary == null) return direct;
      return direct.build >= fromSummary.build ? direct : fromSummary;
    }

    // Приложения, ставшие плагинами, хаб больше не ставит и не обновляет — про них
    // не спрашиваем GitHub (без ключа там лимит 60 запросов в час на всех в одной сети).
    final list = await Future.wait([
      for (final a in catalog.apps) a.mergedInto == null ? get(a) : Future<Release?>.value(null),
    ]);
    for (var i = 0; i < catalog.apps.length; i++) {
      releases[catalog.apps[i].id] = list[i];
    }
    hubRelease = await get(hubEntry);
    // Раньше «нет связи» почти не показывалось: данные всегда находились в кэше.
    offline = !catalog.online && v == null;
    loading = false;
    await refreshInstalled();
  }

  /// Вернулись в хаб (например, из системного окна установки).
  Future<void> onResume() async {
    await refreshInstalled();
    for (final id in _pending.keys.toList()) {
      final now = installed[id];
      if (now == null || now >= _pending[id]!) {
        _pending.remove(id);
        stuck.remove(id);
      } else {
        stuck.add(id);
      }
    }
    notifyListeners();
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
    final asset = downloadAsset(a, r);
    final url = asset == null ? null : r?.assets[asset];
    if (url == null || r == null) return 'Файл для этой системы ещё не готов — попробуй через пару минут';
    final cancel = _cancels[a.id] = DownloadCancel();
    try {
      _job(a.id, const Job('Скачиваю…', 0, true));
      final f = await download(
        url,
        asset!,
        (p) => _job(a.id, Job(_progressText('Скачиваю…', p, r.sizes[asset] ?? 0), p, true)),
        size: r.sizes[asset] ?? 0,
        sha256Hex: r.hashes[asset] ?? '',
        cancel: cancel,
      );
      _job(a.id, const Job('Устанавливаю…'));
      if (isAndroid && installed[a.id] != null) _pending[a.id] = r.build;
      final err = await installFile(f);
      return err;
    } on DownloadCancelled {
      return 'Скачивание отменено';
    } on DownloadError catch (e) {
      // Файл на GitHub могли перезалить, а сводка ещё старая — берём данные прямо из GitHub,
      // чтобы «Повторить» скачало правильный файл.
      if (e.mismatch) releases[a.id] = await latestRelease(a.repo, assetOf(a)) ?? r;
      return e.message;
    } catch (e) {
      return '$e';
    } finally {
      _cancels.remove(a.id);
      _job(a.id, null);
      await refreshInstalled();
    }
  }

  /// Нажали «Отмена» во время скачивания.
  void cancel(String id) => _cancels[id]?.cancel();

  static String _progressText(String what, double p, int size) {
    final pct = '${(p * 100).round()}%';
    if (size <= 0) return '$what $pct';
    final mb = size / 1048576;
    return '$what $pct · ${(mb * p).toStringAsFixed(1)} из ${mb.toStringAsFixed(1)} МБ';
  }

  Future<String?> remove(AppEntry a) async {
    _pending.remove(a.id);
    stuck.remove(a.id);
    _job(a.id, const Job('Удаляю…'));
    final err = await uninstall(a);
    _job(a.id, null);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await refreshInstalled();
    return err;
  }

  Future<String?> updateHub() async {
    final asset = downloadAsset(hubEntry, hubRelease);
    final url = asset == null ? null : hubRelease?.assets[asset];
    if (url == null) return 'Обновление ещё не готово';
    final r = hubRelease!;
    final cancel = _cancels['hub'] = DownloadCancel();
    try {
      _job('hub', const Job('Скачиваю обновление…', 0, true));
      final f = await download(
        url,
        asset!,
        (p) => _job('hub', Job(_progressText('Скачиваю обновление…', p, r.sizes[asset] ?? 0), p, true)),
        size: r.sizes[asset] ?? 0,
        sha256Hex: r.hashes[asset] ?? '',
        cancel: cancel,
      );
      _job('hub', const Job('Устанавливаю…'));
      await runSelfInstaller(f);
      return null;
    } on DownloadCancelled {
      return 'Скачивание отменено';
    } on DownloadError catch (e) {
      if (e.mismatch) hubRelease = await latestRelease(hubEntry.repo, assetOf(hubEntry)) ?? r;
      return e.message;
    } catch (e) {
      return '$e';
    } finally {
      _cancels.remove('hub');
      _job('hub', null);
    }
  }
}
