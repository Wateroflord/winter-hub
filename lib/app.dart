import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import 'sprite.dart';

// ───────────────────────────── Стиль ─────────────────────────────

class W {
  static const bg = Color(0xFF0A1020);
  static const surface = Color(0xFF111A2E);
  static const surface2 = Color(0xFF17223A);
  static const border = Color(0xFF243350);
  static const text = Color(0xFFE8F1FF);
  static const muted = Color(0xFF8FA3C4);
  static const ice = Color(0xFF7FD8FF);
  static const good = Color(0xFF5EE6A8);
  static const bad = Color(0xFFFF6B7A);
  static const h2 = TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: text);
  static const body = TextStyle(fontSize: 14, color: text, height: 1.35);
  static const small = TextStyle(fontSize: 12.5, color: muted, height: 1.35);
}

ThemeData _theme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: W.bg,
    colorScheme: base.colorScheme.copyWith(primary: W.ice, onPrimary: W.bg, secondary: W.ice, surface: W.surface),
    appBarTheme: const AppBarTheme(backgroundColor: W.bg, foregroundColor: W.text, elevation: 0),
    cardColor: W.surface,
    dividerColor: W.border,
    inputDecorationTheme: const InputDecorationTheme(isDense: true, border: OutlineInputBorder()),
  );
}

class SpritesApp extends StatelessWidget {
  const SpritesApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Winter Sprites',
        debugShowCheckedModeBanner: false,
        theme: _theme(),
        home: const Home(),
      );
}

void toast(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

Widget card({required Widget child, EdgeInsets padding = const EdgeInsets.all(14)}) => Container(
      padding: padding,
      decoration: BoxDecoration(color: W.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: W.border)),
      child: child,
    );

// ───────────────────────────── Документ ─────────────────────────────

/// Открытый лист и всё, что с ним сделали.
class Doc extends ChangeNotifier {
  String name = '';
  img.Image? src;
  Uint8List? srcPng;
  img.Image? _undo;
  SliceSpec spec = const SliceSpec(32, 32);
  bool skipEmpty = true;
  List<FrameRect> rects = [];
  Set<int> empty = {};
  Set<int> selected = {}; // пусто — значит все непустые
  final _pngCache = <int, Uint8List>{};
  int fps = 10;
  bool pingPong = false;

  bool get open => src != null;
  bool get canUndo => _undo != null;

  void load(img.Image image, String fileName) {
    src = image;
    name = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
    _undo = null;
    srcPng = png(image);
    selected = {};
    setSpec(guessSpec(image.width, image.height));
  }

  void setSpec(SliceSpec s) {
    final im = src;
    if (im == null) return;
    spec = s;
    rects = sliceRects(im.width, im.height, s);
    _pngCache.clear();
    empty = {
      for (var i = 0; i < rects.length; i++)
        if (rects.length <= 4096 && isEmptyFrame(crop(im, rects[i]))) i,
    };
    selected = selected.where((i) => i < rects.length).toSet();
    notifyListeners();
  }

  /// Кадры анимации по порядку.
  List<int> get animFrames {
    if (selected.isNotEmpty) return selected.toList()..sort();
    return [
      for (var i = 0; i < rects.length; i++)
        if (!(skipEmpty && empty.contains(i))) i,
    ];
  }

  img.Image frame(int i) => crop(src!, rects[i]);

  Uint8List framePng(int i) => _pngCache[i] ??= png(frame(i));

  void toggle(int i) {
    selected = {...selected};
    if (!selected.remove(i)) selected.add(i);
    notifyListeners();
  }

  void selectRow(int row) {
    selected = {
      for (var i = 0; i < rects.length; i++)
        if (rects[i].row == row && !(skipEmpty && empty.contains(i))) i,
    };
    notifyListeners();
  }

  void clearSelection() {
    selected = {};
    notifyListeners();
  }

  void setFps(int v) {
    fps = v;
    notifyListeners();
  }

  void setPingPong(bool v) {
    pingPong = v;
    notifyListeners();
  }

  void setSkipEmpty(bool v) {
    skipEmpty = v;
    notifyListeners();
  }

  int recolorAll(int from, int to) {
    final im = src;
    if (im == null) return 0;
    final (out, n) = recolor(im, from, to);
    if (n == 0) return 0;
    _undo = im;
    src = out;
    srcPng = png(out);
    _pngCache.clear();
    notifyListeners();
    return n;
  }

  void undo() {
    final u = _undo;
    if (u == null) return;
    src = u;
    _undo = null;
    srcPng = png(u);
    _pngCache.clear();
    setSpec(spec);
  }
}

final doc = Doc();

// ───────────────────────────── Файлы ─────────────────────────────

bool get _mobile => Platform.isAndroid || Platform.isIOS;

Future<(img.Image, String)?> pickImage(BuildContext context) async {
  try {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['png', 'gif', 'bmp', 'webp', 'jpg', 'jpeg'], withData: true);
    final f = r?.files.single;
    if (f == null) return null;
    final bytes = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
    if (bytes == null) return null;
    final im = decode(bytes);
    if (im == null) {
      if (context.mounted) toast(context, 'Не получилось открыть «${f.name}» — это картинка?');
      return null;
    }
    return (im, f.name);
  } catch (e) {
    if (context.mounted) toast(context, 'Не удалось открыть файл: $e');
    return null;
  }
}

/// Сохранить один файл (на ПК — окно «Сохранить как»).
Future<String?> saveBytes(BuildContext context, String fileName, Uint8List bytes) async {
  try {
    final path = await FilePicker.platform.saveFile(dialogTitle: 'Сохранить', fileName: fileName, bytes: _mobile ? bytes : null);
    if (path == null) return null;
    if (!_mobile) await File(path).writeAsBytes(bytes, flush: true);
    return path;
  } catch (e) {
    if (context.mounted) toast(context, 'Не удалось сохранить: $e');
    return null;
  }
}

/// Сохранить несколько файлов в выбранную папку.
Future<String?> saveMany(BuildContext context, Map<String, Uint8List> files) async {
  try {
    final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Куда сохранить кадры');
    if (dir == null) return null;
    for (final e in files.entries) {
      await File('$dir${Platform.pathSeparator}${e.key}').writeAsBytes(e.value, flush: true);
    }
    return dir;
  } catch (e) {
    if (context.mounted) toast(context, 'Не удалось сохранить: $e');
    return null;
  }
}

// ───────────────────────────── Главный экран ─────────────────────────────

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0;

  static const _tabs = [
    (Icons.grid_on, 'Нарезка'),
    (Icons.play_circle_outline, 'Анимация'),
    (Icons.palette_outlined, 'Палитра'),
    (Icons.ios_share, 'Экспорт'),
    (Icons.dashboard_customize_outlined, 'Собрать лист'),
  ];

  @override
  void initState() {
    super.initState();
    doc.addListener(_changed);
  }

  @override
  void dispose() {
    doc.removeListener(_changed);
    super.dispose();
  }

  void _changed() => mounted ? setState(() {}) : null;

  Future<void> _open() async {
    final r = await pickImage(context);
    if (r == null) return;
    doc.load(r.$1, r.$2);
    if (tab == 4) setState(() => tab = 0);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 820;
    final page = switch (tab) {
      0 => SliceTab(onOpen: _open),
      1 => const AnimTab(),
      2 => const PaletteTab(),
      3 => const ExportTab(),
      _ => PackTab(onOpenSheet: () => setState(() => tab = 0)),
    };
    final needDoc = tab != 4 && !doc.open;
    final body = needDoc ? _Empty(onOpen: _open) : page;
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const Icon(Icons.ac_unit, color: W.ice, size: 20),
          const SizedBox(width: 8),
          const Text('Winter Sprites'),
          if (doc.open) ...[
            const SizedBox(width: 14),
            Flexible(
              child: Text('${doc.name} · ${doc.src!.width}×${doc.src!.height}', style: W.small, overflow: TextOverflow.ellipsis),
            ),
          ],
        ]),
        actions: [
          if (doc.canUndo) IconButton(tooltip: 'Отменить замену цвета', onPressed: doc.undo, icon: const Icon(Icons.undo)),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: FilledButton.icon(onPressed: _open, icon: const Icon(Icons.folder_open), label: const Text('Открыть PNG')),
          ),
        ],
      ),
      body: wide
          ? Row(children: [
              NavigationRail(
                backgroundColor: W.surface,
                selectedIndex: tab,
                onDestinationSelected: (i) => setState(() => tab = i),
                labelType: NavigationRailLabelType.all,
                destinations: [for (final t in _tabs) NavigationRailDestination(icon: Icon(t.$1), label: Text(t.$2))],
              ),
              const VerticalDivider(width: 1, color: W.border),
              Expanded(child: body),
            ])
          : body,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: (i) => setState(() => tab = i),
              destinations: [for (final t in _tabs) NavigationDestination(icon: Icon(t.$1), label: t.$2)],
            ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.grid_on, size: 64, color: W.ice),
            const SizedBox(height: 12),
            const Text('Открой спрайт-лист', style: W.h2),
            const SizedBox(height: 6),
            const Text(
              'PNG из Aseprite, Piskel или Winter Paint. Нарежу на кадры, покажу анимацию, '
              'помогу с палитрой и соберу лист под Unity или Roblox.',
              style: W.small,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: onOpen, icon: const Icon(Icons.folder_open), label: const Text('Открыть PNG')),
          ]),
        ),
      );
}

/// Шахматка — фон под прозрачные пиксели.
class Checker extends CustomPainter {
  const Checker({this.cell = 8});
  final double cell;

  @override
  void paint(Canvas canvas, Size size) {
    final a = Paint()..color = const Color(0xFF1B2640);
    final b = Paint()..color = const Color(0xFF233152);
    canvas.drawRect(Offset.zero & size, a);
    for (var y = 0.0; y < size.height; y += cell) {
      for (var x = ((y / cell).floor() % 2) * cell; x < size.width; x += cell * 2) {
        canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), b);
      }
    }
  }

  @override
  bool shouldRepaint(Checker old) => old.cell != cell;
}

Widget pixelImage(Uint8List bytes, {double? width, double? height}) => Image.memory(
      bytes,
      width: width,
      height: height,
      filterQuality: FilterQuality.none,
      gaplessPlayback: true,
      fit: BoxFit.contain,
    );

// ───────────────────────────── Нарезка ─────────────────────────────

class SliceTab extends StatefulWidget {
  const SliceTab({super.key, required this.onOpen});
  final VoidCallback onOpen;

  @override
  State<SliceTab> createState() => _SliceTabState();
}

class _SliceTabState extends State<SliceTab> {
  late final fw = TextEditingController(), fh = TextEditingController();
  late final ox = TextEditingController(), oy = TextEditingController();
  late final gx = TextEditingController(), gy = TextEditingController();
  late final cols = TextEditingController(), rows = TextEditingController();
  SliceSpec? _shown;
  double zoom = 0; // 0 — вписать

  void _fill() {
    final s = doc.spec;
    if (_shown == s) return;
    _shown = s;
    fw.text = '${s.fw}';
    fh.text = '${s.fh}';
    ox.text = '${s.offX}';
    oy.text = '${s.offY}';
    gx.text = '${s.gapX}';
    gy.text = '${s.gapY}';
    final (c, r) = gridSize(doc.src!.width, doc.src!.height, s);
    cols.text = '$c';
    rows.text = '$r';
  }

  int _n(TextEditingController c, int def) => int.tryParse(c.text.trim()) ?? def;

  void _applySize() {
    final s = SliceSpec(
      _n(fw, doc.spec.fw).clamp(1, 4096),
      _n(fh, doc.spec.fh).clamp(1, 4096),
      offX: _n(ox, 0).clamp(0, 4096),
      offY: _n(oy, 0).clamp(0, 4096),
      gapX: _n(gx, 0).clamp(0, 512),
      gapY: _n(gy, 0).clamp(0, 512),
    );
    doc.setSpec(s);
  }

  void _applyGrid() {
    final c = _n(cols, 1).clamp(1, 512), r = _n(rows, 1).clamp(1, 512);
    doc.setSpec(specFromGrid(doc.src!.width, doc.src!.height, c, r));
  }

  @override
  void dispose() {
    for (final c in [fw, fh, ox, oy, gx, gy, cols, rows]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _num(TextEditingController c, String label, VoidCallback apply) => SizedBox(
        width: 84,
        child: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: label),
          onSubmitted: (_) => apply(),
        ),
      );

  @override
  Widget build(BuildContext context) {
    _fill();
    final im = doc.src!;
    final rowsCount = doc.rects.isEmpty ? 0 : doc.rects.last.row + 1;
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 900;
      final controls = ListView(padding: const EdgeInsets.all(14), children: [
        card(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Размер кадра', style: W.h2),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 10, children: [
              _num(fw, 'Ширина', _applySize),
              _num(fh, 'Высота', _applySize),
              _num(ox, 'Отступ X', _applySize),
              _num(oy, 'Отступ Y', _applySize),
              _num(gx, 'Шаг X', _applySize),
              _num(gy, 'Шаг Y', _applySize),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 8, children: [
              FilledButton(onPressed: _applySize, child: const Text('Нарезать')),
              OutlinedButton(
                onPressed: () => doc.setSpec(guessSpec(im.width, im.height)),
                child: const Text('Угадать'),
              ),
            ]),
            const SizedBox(height: 6),
            const Text('Отступ — пустое поле от края листа, шаг — промежуток между кадрами.', style: W.small),
          ]),
        ),
        const SizedBox(height: 10),
        card(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Или по сетке', style: W.h2),
            const SizedBox(height: 10),
            Row(children: [
              _num(cols, 'Колонки', _applyGrid),
              const SizedBox(width: 8),
              _num(rows, 'Строки', _applyGrid),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: _applyGrid, child: const Text('Применить')),
            ]),
          ]),
        ),
        const SizedBox(height: 10),
        card(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Кадров: ${doc.rects.length}${doc.empty.isNotEmpty ? ' (пустых ${doc.empty.length})' : ''}', style: W.h2),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: doc.skipEmpty,
              onChanged: doc.setSkipEmpty,
              title: const Text('Пропускать пустые кадры', style: W.body),
            ),
            Text(
              doc.selected.isEmpty
                  ? 'В анимацию идут все кадры. Нажми на кадры на листе, чтобы выбрать только нужные.'
                  : 'Выбрано для анимации: ${doc.selected.length}',
              style: W.small,
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (var r = 0; r < rowsCount && r < 24; r++) ActionChip(label: Text('Ряд ${r + 1}'), onPressed: () => doc.selectRow(r)),
              if (doc.selected.isNotEmpty) ActionChip(label: const Text('Сбросить выбор'), onPressed: doc.clearSelection),
            ]),
          ]),
        ),
      ]);
      final sheet = _SheetView(zoom: zoom, onZoom: (z) => setState(() => zoom = z));
      return wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(width: 360, child: controls),
              Expanded(child: sheet),
            ])
          : Column(children: [Expanded(flex: 3, child: sheet), Expanded(flex: 4, child: controls)]);
    });
  }
}

/// Лист с сеткой кадров: нажми на кадр — выбрать для анимации.
class _SheetView extends StatelessWidget {
  const _SheetView({required this.zoom, required this.onZoom});
  final double zoom;
  final ValueChanged<double> onZoom;

  @override
  Widget build(BuildContext context) {
    final im = doc.src!;
    return LayoutBuilder(builder: (context, box) {
      final fit = ((box.maxWidth - 32) / im.width).clamp(0.05, 64.0).toDouble();
      final fitH = ((box.maxHeight - 80) / im.height).clamp(0.05, 64.0).toDouble();
      final k = zoom > 0 ? zoom : (fit < fitH ? fit : fitH);
      final w = im.width * k, h = im.height * k;
      return Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(children: [
            const Text('Масштаб', style: W.small),
            Expanded(
              child: Slider(
                min: 0,
                max: 16,
                divisions: 32,
                value: zoom.clamp(0, 16).toDouble(),
                label: zoom == 0 ? 'вписать' : '×${zoom.toStringAsFixed(1)}',
                onChanged: onZoom,
              ),
            ),
            Text(zoom == 0 ? 'вписать' : '×${zoom.toStringAsFixed(1)}', style: W.small),
          ]),
        ),
        Expanded(
          child: InteractiveViewer(
            constrained: false,
            minScale: 0.2,
            maxScale: 8,
            boundaryMargin: const EdgeInsets.all(200),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: GestureDetector(
                onTapUp: (d) {
                  final x = d.localPosition.dx / k, y = d.localPosition.dy / k;
                  for (var i = 0; i < doc.rects.length; i++) {
                    final r = doc.rects[i];
                    if (x >= r.x && x < r.x + r.w && y >= r.y && y < r.y + r.h) {
                      doc.toggle(i);
                      break;
                    }
                  }
                },
                child: SizedBox(
                  width: w,
                  height: h,
                  child: Stack(children: [
                    Positioned.fill(child: CustomPaint(painter: Checker(cell: (8 * k).clamp(4, 16).toDouble()))),
                    Positioned.fill(child: pixelImage(doc.srcPng!, width: w, height: h)),
                    Positioned.fill(child: CustomPaint(painter: _Grid(k))),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ]);
    });
  }
}

class _Grid extends CustomPainter {
  _Grid(this.k);
  final double k;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = W.ice.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final sel = Paint()..color = W.ice.withValues(alpha: 0.25);
    final dim = Paint()..color = Colors.black.withValues(alpha: 0.45);
    final showNums = doc.rects.length <= 400 && doc.spec.fw * k >= 18;
    for (var i = 0; i < doc.rects.length; i++) {
      final r = doc.rects[i];
      final rect = Rect.fromLTWH(r.x * k, r.y * k, r.w * k, r.h * k);
      if (doc.selected.contains(i)) canvas.drawRect(rect, sel);
      if (doc.skipEmpty && doc.empty.contains(i)) canvas.drawRect(rect, dim);
      canvas.drawRect(rect, line);
      if (showNums) {
        final tp = TextPainter(
          text: TextSpan(text: '${i + 1}', style: TextStyle(fontSize: 10, color: doc.selected.contains(i) ? W.text : W.ice)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, rect.topLeft + const Offset(2, 1));
      }
    }
  }

  @override
  bool shouldRepaint(_Grid old) => true;
}

// ───────────────────────────── Анимация ─────────────────────────────

class AnimTab extends StatefulWidget {
  const AnimTab({super.key});

  @override
  State<AnimTab> createState() => _AnimTabState();
}

class _AnimTabState extends State<AnimTab> {
  Timer? _t;
  int step = 0;
  bool playing = true;
  double zoom = 6;
  int bg = 0; // 0 шахматка, 1 тёмный, 2 светлый, 3 зелёный

  @override
  void initState() {
    super.initState();
    _restart();
    doc.addListener(_restart);
  }

  @override
  void dispose() {
    _t?.cancel();
    doc.removeListener(_restart);
    super.dispose();
  }

  void _restart() {
    _t?.cancel();
    if (!playing) return;
    _t = Timer.periodic(Duration(milliseconds: (1000 / doc.fps).round()), (_) {
      if (mounted) setState(() => step++);
    });
  }

  List<int> get order {
    final f = doc.animFrames;
    if (!doc.pingPong) return f;
    return [for (final i in pingPongOrder(f.length)) f[i]];
  }

  @override
  Widget build(BuildContext context) {
    final o = order;
    if (o.isEmpty) return const Center(child: Text('Нет кадров — проверь нарезку', style: W.body));
    final i = o[step % o.length];
    final r = doc.rects[i];
    final w = r.w * zoom, h = r.h * zoom;
    final bgColor = switch (bg) { 1 => const Color(0xFF05070D), 2 => const Color(0xFFF2F4F8), 3 => const Color(0xFF00B140), _ => null };
    return ListView(padding: const EdgeInsets.all(14), children: [
      Center(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: W.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: W.border)),
          child: SizedBox(
            width: w,
            height: h,
            child: Stack(children: [
              Positioned.fill(
                child: bgColor == null ? CustomPaint(painter: Checker(cell: (r.w * zoom / 8).clamp(4, 24).toDouble())) : ColoredBox(color: bgColor),
              ),
              Positioned.fill(child: pixelImage(doc.framePng(i), width: w, height: h)),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Center(child: Text('Кадр ${i + 1} · ${(step % o.length) + 1} из ${o.length}', style: W.small)),
      const SizedBox(height: 10),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(
          tooltip: 'Назад',
          onPressed: () => setState(() {
            playing = false;
            _t?.cancel();
            step = (step - 1) % o.length;
          }),
          icon: const Icon(Icons.skip_previous),
        ),
        FilledButton.icon(
          onPressed: () {
            setState(() => playing = !playing);
            _restart();
            if (!playing) _t?.cancel();
          },
          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
          label: Text(playing ? 'Пауза' : 'Играть'),
        ),
        IconButton(
          tooltip: 'Вперёд',
          onPressed: () => setState(() {
            playing = false;
            _t?.cancel();
            step++;
          }),
          icon: const Icon(Icons.skip_next),
        ),
      ]),
      const SizedBox(height: 10),
      card(
        child: Column(children: [
          _slider('Скорость', '${doc.fps} кадр/с', doc.fps.toDouble(), 1, 30, (v) => doc.setFps(v.round())),
          _slider('Размер', '×${zoom.round()}', zoom, 1, 16, (v) => setState(() => zoom = v.roundToDouble())),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: doc.pingPong,
            onChanged: doc.setPingPong,
            title: const Text('Туда-обратно (пинг-понг)', style: W.body),
          ),
          Row(children: [
            const Text('Фон', style: W.small),
            const SizedBox(width: 10),
            for (final b in const [(0, 'шахматка'), (1, 'тёмный'), (2, 'светлый'), (3, 'хромакей')])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(label: Text(b.$2), selected: bg == b.$1, onSelected: (_) => setState(() => bg = b.$1)),
              ),
          ]),
        ]),
      ),
      const SizedBox(height: 10),
      Text('Порядок: ${o.map((x) => x + 1).join(' ')}', style: W.small),
    ]);
  }

  Widget _slider(String t, String v, double value, double min, double max, ValueChanged<double> ch) => Row(children: [
        SizedBox(width: 80, child: Text(t, style: W.small)),
        Expanded(child: Slider(min: min, max: max, divisions: (max - min).round(), value: value.clamp(min, max).toDouble(), onChanged: ch)),
        SizedBox(width: 80, child: Text(v, style: W.body, textAlign: TextAlign.right)),
      ]);
}

// ───────────────────────────── Палитра ─────────────────────────────

class PaletteTab extends StatelessWidget {
  const PaletteTab({super.key});

  Future<void> _replace(BuildContext context, int from) async {
    final ctl = TextEditingController(text: '#${hex6(from)}');
    var transparent = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text('Заменить #${hex6(from)}'),
          content: SizedBox(
            width: 340,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: ctl,
              enabled: !transparent,
              decoration: const InputDecoration(labelText: 'Новый цвет (HEX)', hintText: '#FF7A6B'),
              onChanged: (_) => set(() {}),
            ),
            const SizedBox(height: 10),
            Container(
              height: 32,
              decoration: BoxDecoration(
                color: transparent ? null : Color(parseHex(ctl.text) ?? 0x00000000),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: W.border),
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: transparent,
              onChanged: (v) => set(() => transparent = v == true),
              title: const Text('Сделать прозрачным (убрать фон)'),
            ),
          ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Заменить')),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final to = transparent ? 0x00000000 : parseHex(ctl.text);
    if (to == null) {
      toast(context, 'Не понял цвет — нужно, например, #FF7A6B');
      return;
    }
    final n = doc.recolorAll(from, to);
    if (context.mounted) toast(context, n == 0 ? 'Ничего не поменялось' : 'Заменено пикселей: $n (отменить — стрелка вверху)');
  }

  @override
  Widget build(BuildContext context) {
    final pal = palette(doc.src!);
    final colors = [for (final e in pal) e.key];
    final total = pal.fold<int>(0, (s, e) => s + e.value);
    return ListView(padding: const EdgeInsets.all(14), children: [
      Row(children: [
        Expanded(child: Text('Цветов: ${pal.length}', style: W.h2)),
        OutlinedButton(
          onPressed: colors.isEmpty
              ? null
              : () async {
                  final p = await saveBytes(context, '${doc.name}.gpl', Uint8List.fromList(utf8.encode(gplText(colors, doc.name))));
                  if (p != null && context.mounted) toast(context, 'Палитра сохранена — открой её в Aseprite или GIMP');
                },
          child: const Text('Сохранить .gpl'),
        ),
        const SizedBox(width: 6),
        OutlinedButton(
          onPressed: colors.isEmpty
              ? null
              : () async {
                  await Clipboard.setData(ClipboardData(text: hexText(colors)));
                  if (context.mounted) toast(context, 'HEX-коды скопированы');
                },
          child: const Text('Копировать HEX'),
        ),
      ]),
      const SizedBox(height: 4),
      Text(
        pal.length > 256
            ? 'Много цветов — похоже на сглаженную картинку, а не пиксель-арт. Замена цвета работает только при точном совпадении.'
            : 'Нажми на цвет, чтобы заменить его на всём листе (перекрасить скин, убрать фон).',
        style: W.small,
      ),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final e in pal.take(512))
          Tooltip(
            message: '#${hex6(e.key)}${(e.key >> 24) != 0xFF ? ' · прозрачность ${((e.key >> 24) * 100 / 255).round()}%' : ''}\n${e.value} пикс. (${(e.value * 100 / total).toStringAsFixed(1)}%)',
            child: InkWell(
              onTap: () => _replace(context, e.key),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 56,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: W.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: W.border)),
                child: Column(children: [
                  Container(height: 34, decoration: BoxDecoration(color: Color(e.key), borderRadius: BorderRadius.circular(5))),
                  const SizedBox(height: 3),
                  Text(hex6(e.key), style: const TextStyle(fontSize: 9.5, color: W.muted)),
                ]),
              ),
            ),
          ),
      ]),
      if (pal.length > 512) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Показаны 512 самых частых цветов.', style: W.small)),
    ]);
  }
}

// ───────────────────────────── Экспорт ─────────────────────────────

class ExportTab extends StatefulWidget {
  const ExportTab({super.key});

  @override
  State<ExportTab> createState() => _ExportTabState();
}

class _ExportTabState extends State<ExportTab> {
  int scale = 1;
  final cols = TextEditingController();
  final pad = TextEditingController(text: '0');
  bool busy = false;

  @override
  void dispose() {
    cols.dispose();
    pad.dispose();
    super.dispose();
  }

  List<img.Image> _frames() => [for (final i in doc.animFrames) scaleNearest(doc.frame(i), scale)];

  Future<void> _run(Future<String?> Function() f, String done) async {
    setState(() => busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 30)); // дать перерисоваться
    try {
      final p = await f();
      if (p != null && mounted) toast(context, '$done: $p');
    } catch (e) {
      if (mounted) toast(context, 'Ошибка: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = doc.animFrames.length;
    final r = doc.rects.isEmpty ? null : doc.rects.first;
    final c = int.tryParse(cols.text.trim()) ?? 0;
    final p = (int.tryParse(pad.text.trim()) ?? 0).clamp(0, 64);
    return AbsorbPointer(
      absorbing: busy,
      child: ListView(padding: const EdgeInsets.all(14), children: [
        if (busy) const LinearProgressIndicator(),
        Text('Кадров к экспорту: $n${doc.selected.isEmpty ? '' : ' (выбранные)'}', style: W.h2),
        if (r != null) Text('Кадр ${r.w}×${r.h} → ${r.w * scale}×${r.h * scale}', style: W.small),
        const SizedBox(height: 10),
        card(
          child: Row(children: [
            const Text('Увеличить', style: W.body),
            const SizedBox(width: 10),
            for (final k in const [1, 2, 4, 8])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(label: Text('×$k'), selected: scale == k, onSelected: (_) => setState(() => scale = k)),
              ),
            const Expanded(child: Text('без размытия — пиксели остаются чёткими', style: W.small, textAlign: TextAlign.right)),
          ]),
        ),
        const SizedBox(height: 10),
        _action(
          Icons.burst_mode_outlined,
          'Кадры отдельными PNG',
          'Папка с файлами ${doc.name}_01.png, _02.png… — для Unity Animation или Roblox.',
          n == 0
              ? null
              : () => _run(() async {
                    final fr = _frames();
                    return saveMany(context, {
                      for (var i = 0; i < fr.length; i++) '${doc.name}_${(i + 1).toString().padLeft(2, '0')}.png': png(fr[i]),
                    });
                  }, 'Кадры сохранены в'),
        ),
        _action(
          Icons.gif_box_outlined,
          'Анимация GIF',
          '${doc.fps} кадров в секунду${doc.pingPong ? ', туда-обратно' : ''} — чтобы скинуть другу или в Winter Chat.',
          n == 0
              ? null
              : () => _run(() async {
                    var fr = _frames();
                    if (doc.pingPong) fr = [for (final i in pingPongOrder(fr.length)) fr[i]];
                    return saveBytes(context, '${doc.name}.gif', gifOf(fr, doc.fps));
                  }, 'GIF сохранён'),
        ),
        card(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.view_module_outlined, color: W.ice),
              SizedBox(width: 10),
              Text('Новый спрайт-лист', style: W.h2),
            ]),
            const SizedBox(height: 4),
            const Text(
              'Пересобрать выбранные кадры ровной сеткой (+ файл .json с координатами кадров). '
              'Пустые кадры уходят, промежутки — как укажешь.',
              style: W.small,
            ),
            const SizedBox(height: 10),
            Row(children: [
              SizedBox(
                width: 120,
                child: TextField(
                  controller: cols,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Колонки', hintText: 'все в ряд'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 120,
                child: TextField(
                  controller: pad,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Промежуток, пикс.'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: n == 0
                    ? null
                    : () => _run(() async {
                          final fr = _frames();
                          final sheet = pack(fr, cols: c, padding: p * scale);
                          final path = await saveBytes(context, '${doc.name}_sheet.png', png(sheet));
                          if (path == null) return null;
                          final json = metaJson(
                            name: doc.name,
                            rects: packedRects(fr.length, fr.first.width, fr.first.height, cols: c, padding: p * scale),
                            sheetW: sheet.width,
                            sheetH: sheet.height,
                            fps: doc.fps,
                          );
                          final jp = path.replaceAll(RegExp(r'\.png$', caseSensitive: false), '.json');
                          if (!_mobile && jp != path) await File(jp).writeAsString(json, flush: true);
                          return path;
                        }, 'Лист сохранён'),
                child: const Text('Сохранить лист'),
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 10),
        _action(
          Icons.zoom_out_map,
          'Весь лист увеличенным',
          'Исходный лист ×$scale — для превью и постов.',
          () => _run(() => saveBytes(context, '${doc.name}_x$scale.png', png(scaleNearest(doc.src!, scale))), 'Сохранено'),
        ),
        const SizedBox(height: 6),
        const Text(
          'Roblox: в ImageLabel задай ImageRectSize = размер кадра и меняй ImageRectOffset по координатам из .json.\n'
          'Unity: Sprite Mode → Multiple → Slice → Grid By Cell Size, Filter Mode → Point (no filter).',
          style: W.small,
        ),
      ]),
    );
  }

  Widget _action(IconData icon, String title, String sub, VoidCallback? onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: W.surface,
          borderRadius: BorderRadius.circular(14),
          child: ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: W.border)),
            leading: Icon(icon, color: W.ice),
            title: Text(title, style: W.h2),
            subtitle: Text(sub, style: W.small),
            trailing: const Icon(Icons.chevron_right),
            enabled: onTap != null,
            onTap: onTap,
          ),
        ),
      );
}

// ───────────────────────────── Собрать лист ─────────────────────────────

class PackTab extends StatefulWidget {
  const PackTab({super.key, required this.onOpenSheet});
  final VoidCallback onOpenSheet;

  @override
  State<PackTab> createState() => _PackTabState();
}

class _PackTabState extends State<PackTab> {
  final files = <(String, img.Image)>[];
  final cols = TextEditingController();
  final pad = TextEditingController(text: '0');
  img.Image? result;
  Uint8List? resultPng;

  @override
  void dispose() {
    cols.dispose();
    pad.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    try {
      final r = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.custom, allowedExtensions: ['png', 'gif', 'bmp', 'webp'], withData: true);
      if (r == null) return;
      var bad = 0;
      for (final f in r.files) {
        final bytes = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
        final im = bytes == null ? null : decode(bytes);
        if (im == null) {
          bad++;
        } else {
          files.add((f.name, im));
        }
      }
      // По имени: walk_1, walk_2, … walk_10 — в правильном порядке.
      files.sort((a, b) => _natural(a.$1, b.$1));
      _build();
      if (bad > 0 && mounted) toast(context, 'Не открылись: $bad');
    } catch (e) {
      if (mounted) toast(context, 'Не удалось открыть: $e');
    }
  }

  static int _natural(String a, String b) {
    final ra = RegExp(r'(\d+)(?!.*\d)').firstMatch(a), rb = RegExp(r'(\d+)(?!.*\d)').firstMatch(b);
    if (ra != null && rb != null && a.substring(0, ra.start) == b.substring(0, rb.start)) {
      return int.parse(ra.group(1)!).compareTo(int.parse(rb.group(1)!));
    }
    return a.compareTo(b);
  }

  void _build() {
    if (files.isEmpty) {
      setState(() {
        result = null;
        resultPng = null;
      });
      return;
    }
    final c = int.tryParse(cols.text.trim()) ?? 0;
    final p = (int.tryParse(pad.text.trim()) ?? 0).clamp(0, 64);
    final r = pack([for (final f in files) f.$2], cols: c, padding: p);
    setState(() {
      result = r;
      resultPng = png(r);
    });
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(14), children: [
        const Text('Собрать лист из отдельных картинок', style: W.h2),
        const SizedBox(height: 4),
        const Text(
          'Выбери кадры (walk_1.png, walk_2.png…) — соберу их в один лист по порядку номеров. '
          'Разного размера — выровняю по центру и низу.',
          style: W.small,
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add_photo_alternate_outlined), label: const Text('Добавить картинки')),
          if (files.isNotEmpty)
            OutlinedButton(
              onPressed: () {
                files.clear();
                _build();
              },
              child: const Text('Очистить'),
            ),
          SizedBox(
            width: 110,
            child: TextField(
              controller: cols,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Колонки', hintText: 'все в ряд'),
              onChanged: (_) => _build(),
            ),
          ),
          SizedBox(
            width: 110,
            child: TextField(
              controller: pad,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Промежуток'),
              onChanged: (_) => _build(),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        if (files.isNotEmpty)
          Text('${files.length} шт.: ${files.map((f) => f.$1).take(12).join(', ')}${files.length > 12 ? '…' : ''}', style: W.small),
        if (result != null) ...[
          const SizedBox(height: 12),
          card(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Лист ${result!.width}×${result!.height}', style: W.h2),
              const SizedBox(height: 8),
              LayoutBuilder(builder: (context, box) {
                final k = (box.maxWidth / result!.width).clamp(0.05, 8.0).toDouble();
                final w = result!.width * k, h = result!.height * k;
                return SizedBox(
                  width: w,
                  height: h,
                  child: Stack(children: [
                    Positioned.fill(child: CustomPaint(painter: Checker(cell: (6 * k).clamp(4, 12).toDouble()))),
                    Positioned.fill(child: pixelImage(resultPng!, width: w, height: h)),
                  ]),
                );
              }),
              const SizedBox(height: 10),
              Wrap(spacing: 8, children: [
                FilledButton.icon(
                  onPressed: () async {
                    final p = await saveBytes(context, 'sheet.png', resultPng!);
                    if (p != null && context.mounted) toast(context, 'Лист сохранён: $p');
                  },
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Сохранить PNG'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    var cw = 0, ch = 0;
                    for (final f in files) {
                      if (f.$2.width > cw) cw = f.$2.width;
                      if (f.$2.height > ch) ch = f.$2.height;
                    }
                    final p = (int.tryParse(pad.text.trim()) ?? 0).clamp(0, 64);
                    doc.load(result!, 'sheet');
                    doc.setSpec(SliceSpec(cw, ch, gapX: p, gapY: p));
                    widget.onOpenSheet();
                  },
                  icon: const Icon(Icons.play_circle_outline),
                  label: const Text('Открыть как лист (анимация)'),
                ),
              ]),
            ]),
          ),
        ],
      ]);
}
