import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'catalog.dart';
import 'hub_state.dart';
import 'native.dart';
import 'snow.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: W.bg,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const WinterHubApp());
}

class WinterHubApp extends StatelessWidget {
  const WinterHubApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Winter Hub',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const HomeScreen(),
      );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final hub = HubState();
  final Set<String> open = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    hub.load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Вернулись из окна установки/удаления — обновить состояние.
    if (state == AppLifecycleState.resumed) hub.onResume();
  }

  void _toast(String? msg) {
    if (msg == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0E1A33), W.bg],
              ),
            ),
          ),
        ),
        const Positioned.fill(child: Snow()),
        SafeArea(
          child: ListenableBuilder(
            listenable: hub,
            builder: (context, _) => RefreshIndicator(
              color: W.ice,
              backgroundColor: W.surface,
              onRefresh: () => hub.refresh(manual: true),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: [
                      _header(),
                      if (hub.hubUpdate) _hubUpdate(),
                      if (hub.offline)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text('Нет связи с интернетом — показываю сохранённые данные.', style: W.small.copyWith(color: W.warn)),
                        ),
                      const SizedBox(height: 14),
                      if (hub.loading)
                        const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
                      else
                        for (final a in hub.catalog.apps)
                          if (hub.assetOf(a) != null) _appCard(a),
                      if (hub.catalog.hubNews.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        const Text('Новости хаба', style: W.h2),
                        const SizedBox(height: 8),
                        for (final n in hub.catalog.hubNews) _news(n),
                      ],
                      const SizedBox(height: 18),
                      Center(
                        child: Text(
                          hubBuild == 0 ? 'Winter Hub' : 'Winter Hub · сборка $hubBuild',
                          style: W.small,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _header() => Row(children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(colors: [Color(0xFF1D3A66), Color(0xFF0E1A33)]),
            border: Border.all(color: W.ice.withValues(alpha: 0.4)),
            boxShadow: [BoxShadow(color: W.ice.withValues(alpha: 0.25), blurRadius: 18)],
          ),
          child: const Icon(Icons.ac_unit, color: W.iceLight, size: 30),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Winter Hub', style: W.h1),
            Text('Все твои приложения в одном месте', style: W.small),
          ]),
        ),
        IconButton(
          tooltip: 'Обновить',
          onPressed: hub.loading ? null : () => hub.refresh(manual: true),
          icon: const Icon(Icons.refresh, color: W.ice),
        ),
      ]);

  Widget _hubUpdate() {
    final job = hub.jobs['hub'];
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: _Glass(
        borderColor: W.ice,
        child: Row(children: [
          const Icon(Icons.system_update, color: W.ice),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              job?.text ?? 'Вышла новая версия хаба (сборка ${hub.hubRelease!.build})',
              style: W.body,
            ),
          ),
          if (job == null)
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: W.ice, foregroundColor: W.bg),
              onPressed: () async => _toast(await hub.updateHub()),
              child: const Text('Обновить'),
            ),
        ]),
      ),
    );
  }

  Widget _appCard(AppEntry a) {
    final color = hexColor(a.color);
    final inst = hub.installed[a.id];
    final rel = hub.releases[a.id];
    final job = hub.jobs[a.id];
    final update = hub.hasUpdate(a);
    final asset = hub.assetOf(a);
    final available = asset != null && rel?.assets.containsKey(asset) == true;
    final size = available ? rel!.sizes[asset] ?? 0 : 0;
    final expanded = open.contains(a.id);

    String status;
    Color statusColor;
    if (inst == null) {
      status = available ? 'Не установлено' : 'Скоро будет для этой системы';
      statusColor = W.muted;
    } else if (update) {
      status = inst == 0 ? 'Есть новая версия (сборка ${rel!.build})' : 'Есть обновление: сборка $inst → ${rel!.build}';
      statusColor = W.warn;
    } else {
      status = inst == 0 ? 'Установлено' : 'Установлено · сборка $inst';
      statusColor = W.good;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _Glass(
        borderColor: update ? W.warn.withValues(alpha: 0.6) : W.border,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => expanded ? open.remove(a.id) : open.add(a.id)),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.network(
                  a.icon,
                  width: 60,
                  height: 60,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 60,
                    height: 60,
                    color: color.withValues(alpha: 0.25),
                    alignment: Alignment.center,
                    child: Text(a.name.characters.first, style: TextStyle(color: color, fontSize: 26, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a.name, style: W.h2),
                  Text(a.tagline, style: W.small),
                  const SizedBox(height: 4),
                  Text(status, style: W.small.copyWith(color: statusColor, fontWeight: FontWeight.w600)),
                ]),
              ),
              Icon(expanded ? Icons.expand_less : Icons.expand_more, color: W.muted),
            ]),
          ),
          const SizedBox(height: 12),
          if (hub.stuck.contains(a.id) && job == null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: W.warn.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Text(
                'Обновление не встало? Если телефон пишет «Приложение не установлено», у старой версии другая подпись. '
                'Нажми «Удалить», потом «Установить» — это нужно один раз. Данные приложения при этом сотрутся, '
                'поэтому сначала сохрани их, если в приложении есть экспорт.',
                style: W.small.copyWith(color: W.warn),
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (job != null) ...[
            Text(job.text, style: W.small.copyWith(color: W.ice)),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: job.progress, minHeight: 6, backgroundColor: W.surface2),
            ),
          ] else
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (inst == null && available)
                _btn(Icons.download, 'Установить${size > 0 ? ' · ${(size / 1048576).toStringAsFixed(0)} МБ' : ''}', W.ice,
                    () async => _toast(await hub.install(a)), filled: true),
              if (update && available) _btn(Icons.system_update_alt, 'Обновить', W.warn, () async => _toast(await hub.install(a)), filled: true),
              if (inst != null) _btn(Icons.play_arrow_rounded, 'Открыть', W.good, () async => _toast(await launch(a))),
              if (inst != null)
                _btn(Icons.delete_outline, 'Удалить', W.bad, () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: W.surface,
                      title: Text('Удалить ${a.name}?', style: W.h2),
                      content: Text(
                        isWindows ? 'Программа будет удалена с ПК. Твои данные в ней сохранятся, если поставишь её снова.' : 'Откроется системное окно удаления.',
                        style: W.body,
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить', style: TextStyle(color: W.bad))),
                      ],
                    ),
                  );
                  if (ok == true) _toast(await hub.remove(a));
                }),
            ]),
          if (expanded) ...[
            const SizedBox(height: 14),
            Text(a.description, style: W.body),
            if (rel != null) ...[
              const SizedBox(height: 6),
              Text('Последняя версия: сборка ${rel.build}${rel.date.isEmpty ? '' : ' от ${_date(rel.date)}'}', style: W.small),
            ],
            if (a.news.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Что нового', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: W.iceLight)),
              const SizedBox(height: 6),
              for (final n in a.news) _news(n),
            ],
          ],
        ]),
      ),
    );
  }

  String _date(String iso) {
    final p = iso.split('-');
    return p.length == 3 ? '${p[2]}.${p[1]}.${p[0]}' : iso;
  }

  Widget _news(NewsItem n) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.only(top: 3), child: Icon(Icons.ac_unit, size: 12, color: W.ice)),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(TextSpan(children: [
              if (n.date.isNotEmpty) TextSpan(text: '${_date(n.date)}  ', style: W.small.copyWith(color: W.muted)),
              TextSpan(text: n.text, style: W.body.copyWith(fontSize: 13.5)),
            ])),
          ),
        ]),
      );

  Widget _btn(IconData icon, String text, Color color, VoidCallback onTap, {bool filled = false}) => filled
      ? FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: color, foregroundColor: W.bg, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          onPressed: onTap,
          icon: Icon(icon, size: 18),
          label: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
        )
      : OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: color,
            side: BorderSide(color: color.withValues(alpha: 0.5)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: onTap,
          icon: Icon(icon, size: 18),
          label: Text(text),
        );
}

/// Полупрозрачная «ледяная» карточка.
class _Glass extends StatelessWidget {
  final Widget child;
  final Color borderColor;
  const _Glass({required this.child, this.borderColor = W.border});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: W.surface.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: child,
      );
}
