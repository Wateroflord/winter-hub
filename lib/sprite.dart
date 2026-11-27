/// Работа со спрайтами — чистая логика без интерфейса (проверяется тестами).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Как резать лист: размер кадра, отступ от края и промежутки между кадрами (в пикселях).
class SliceSpec {
  final int fw, fh, offX, offY, gapX, gapY;
  const SliceSpec(this.fw, this.fh, {this.offX = 0, this.offY = 0, this.gapX = 0, this.gapY = 0});

  SliceSpec copyWith({int? fw, int? fh, int? offX, int? offY, int? gapX, int? gapY}) => SliceSpec(
        fw ?? this.fw,
        fh ?? this.fh,
        offX: offX ?? this.offX,
        offY: offY ?? this.offY,
        gapX: gapX ?? this.gapX,
        gapY: gapY ?? this.gapY,
      );

  @override
  bool operator ==(Object o) =>
      o is SliceSpec && o.fw == fw && o.fh == fh && o.offX == offX && o.offY == offY && o.gapX == gapX && o.gapY == gapY;

  @override
  int get hashCode => Object.hash(fw, fh, offX, offY, gapX, gapY);
}

/// Прямоугольник кадра на листе.
class FrameRect {
  final int x, y, w, h, col, row;
  const FrameRect(this.x, this.y, this.w, this.h, this.col, this.row);
}

/// Сколько кадров помещается по горизонтали и вертикали.
(int cols, int rows) gridSize(int w, int h, SliceSpec s) {
  if (s.fw <= 0 || s.fh <= 0) return (0, 0);
  int fit(int total, int off, int size, int gap) {
    final free = total - off;
    if (free < size) return 0;
    return 1 + (free - size) ~/ (size + gap);
  }

  return (fit(w, s.offX, s.fw, s.gapX), fit(h, s.offY, s.fh, s.gapY));
}

/// Все целые кадры по рядам: слева направо, сверху вниз.
List<FrameRect> sliceRects(int w, int h, SliceSpec s) {
  final (cols, rows) = gridSize(w, h, s);
  return [
    for (var r = 0; r < rows; r++)
      for (var c = 0; c < cols; c++) FrameRect(s.offX + c * (s.fw + s.gapX), s.offY + r * (s.fh + s.gapY), s.fw, s.fh, c, r),
  ];
}

/// Нарезка по сетке «колонки × строки».
SliceSpec specFromGrid(int w, int h, int cols, int rows) =>
    SliceSpec(cols > 0 ? w ~/ cols : w, rows > 0 ? h ~/ rows : h);

/// Угадать размер кадра: лента квадратных кадров, частые размеры пиксель-арта, иначе — весь лист.
SliceSpec guessSpec(int w, int h) {
  if (w <= 0 || h <= 0) return const SliceSpec(1, 1);
  if (w > h && w % h == 0) return SliceSpec(h, h);
  if (h > w && h % w == 0) return SliceSpec(w, w);
  for (final s in const [32, 16, 64, 48, 24, 128]) {
    if (w % s == 0 && h % s == 0 && (w > s || h > s)) return SliceSpec(s, s);
  }
  return SliceSpec(w, h);
}

/// Привести любой PNG (с палитрой, 16 бит, без прозрачности) к RGBA 8 бит.
img.Image toRgba(img.Image src) {
  final out = img.Image(width: src.width, height: src.height, numChannels: 4);
  for (final p in src) {
    out.setPixelRgba(
      p.x,
      p.y,
      (p.rNormalized * 255).round(),
      (p.gNormalized * 255).round(),
      (p.bNormalized * 255).round(),
      src.hasAlpha ? (p.aNormalized * 255).round() : 255,
    );
  }
  return out;
}

img.Image? decode(Uint8List bytes) {
  final d = img.decodeImage(bytes);
  return d == null ? null : toRgba(d);
}

img.Image crop(img.Image src, FrameRect r) {
  final out = img.Image(width: r.w, height: r.h, numChannels: 4);
  for (var y = 0; y < r.h; y++) {
    for (var x = 0; x < r.w; x++) {
      final sx = r.x + x, sy = r.y + y;
      if (sx >= src.width || sy >= src.height) continue;
      final p = src.getPixel(sx, sy);
      out.setPixelRgba(x, y, p.r, p.g, p.b, p.a);
    }
  }
  return out;
}

/// Кадр полностью прозрачный.
bool isEmptyFrame(img.Image f) {
  for (final p in f) {
    if (p.a > 0) return false;
  }
  return true;
}

/// Собрать кадры в лист: [cols] колонок, [padding] пикселей между ячейками.
/// Ячейка — по самому большому кадру; кадры меньше — по центру внизу (как стоит персонаж).
img.Image pack(List<img.Image> frames, {int cols = 0, int padding = 0}) {
  if (frames.isEmpty) return img.Image(width: 1, height: 1, numChannels: 4);
  final n = frames.length;
  final c = cols <= 0 ? n : (cols > n ? n : cols);
  final rows = (n + c - 1) ~/ c;
  var cw = 0, ch = 0;
  for (final f in frames) {
    if (f.width > cw) cw = f.width;
    if (f.height > ch) ch = f.height;
  }
  final out = img.Image(width: c * cw + (c - 1) * padding, height: rows * ch + (rows - 1) * padding, numChannels: 4);
  for (var i = 0; i < n; i++) {
    final f = frames[i];
    final ox = (i % c) * (cw + padding) + (cw - f.width) ~/ 2;
    final oy = (i ~/ c) * (ch + padding) + (ch - f.height);
    for (final p in f) {
      if (p.a == 0) continue;
      out.setPixelRgba(ox + p.x, oy + p.y, p.r, p.g, p.b, p.a);
    }
  }
  return out;
}

/// Увеличить в [k] раз без размытия (каждый пиксель — квадрат k×k).
img.Image scaleNearest(img.Image f, int k) {
  if (k <= 1) return f;
  final out = img.Image(width: f.width * k, height: f.height * k, numChannels: 4);
  for (final p in f) {
    if (p.a == 0) continue;
    for (var dy = 0; dy < k; dy++) {
      for (var dx = 0; dx < k; dx++) {
        out.setPixelRgba(p.x * k + dx, p.y * k + dy, p.r, p.g, p.b, p.a);
      }
    }
  }
  return out;
}

/// Цвет как число 0xAARRGGBB.
int argb(num r, num g, num b, num a) => (a.toInt() << 24) | (r.toInt() << 16) | (g.toInt() << 8) | b.toInt();

/// Цвета листа (без полностью прозрачных) → сколько пикселей. По убыванию частоты.
List<MapEntry<int, int>> palette(img.Image f) {
  final m = <int, int>{};
  for (final p in f) {
    if (p.a == 0) continue;
    final c = argb(p.r, p.g, p.b, p.a);
    m[c] = (m[c] ?? 0) + 1;
  }
  return m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
}

/// Заменить цвет [from] на [to] (оба 0xAARRGGBB). Возвращает новую картинку и сколько пикселей поменялось.
(img.Image, int) recolor(img.Image f, int from, int to) {
  final out = f.clone();
  var n = 0;
  final tr = (to >> 16) & 0xFF, tg = (to >> 8) & 0xFF, tb = to & 0xFF, ta = (to >> 24) & 0xFF;
  for (final p in out) {
    if (p.a == 0) continue;
    if (argb(p.r, p.g, p.b, p.a) == from) {
      p.setRgba(tr, tg, tb, ta);
      n++;
    }
  }
  return (out, n);
}

String hex6(int c) => (c & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

/// «#FFAA00» / «ffaa00» / «#fa0» → 0xFFFFAA00.
int? parseHex(String s) {
  var h = s.trim().replaceFirst('#', '');
  if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(h)) return null;
  return 0xFF000000 | int.parse(h, radix: 16);
}

/// Палитра для GIMP / Aseprite (.gpl).
String gplText(List<int> colors, String name) {
  final b = StringBuffer('GIMP Palette\nName: $name\nColumns: 8\n#\n');
  for (final c in colors) {
    b.writeln('${((c >> 16) & 0xFF).toString().padLeft(3)} ${((c >> 8) & 0xFF).toString().padLeft(3)} ${(c & 0xFF).toString().padLeft(3)}\t#${hex6(c)}');
  }
  return b.toString();
}

/// Палитра списком HEX (как на Lospec).
String hexText(List<int> colors) => colors.map(hex6).join('\n');

/// Порядок кадров «туда-обратно»: 0 1 2 3 2 1.
List<int> pingPongOrder(int n) => n <= 2 ? [for (var i = 0; i < n; i++) i] : [for (var i = 0; i < n; i++) i, for (var i = n - 2; i > 0; i--) i];

/// GIF-анимация из кадров.
Uint8List gifOf(List<img.Image> frames, int fps) {
  final ms = (1000 / (fps <= 0 ? 8 : fps)).round();
  final first = frames.first.clone()..frameDuration = ms;
  for (final f in frames.skip(1)) {
    first.addFrame(f.clone()..frameDuration = ms);
  }
  return img.encodeGif(first);
}

Uint8List png(img.Image f) => img.encodePng(f);

/// Описание листа для движка: кадры, размер, скорость. Unity, Godot, Roblox (ImageRectOffset/ImageRectSize).
String metaJson({required String name, required List<FrameRect> rects, required int sheetW, required int sheetH, required int fps}) =>
    const JsonEncoder.withIndent('  ').convert({
      'name': name,
      'size': {'w': sheetW, 'h': sheetH},
      'fps': fps,
      'frames': [
        for (var i = 0; i < rects.length; i++)
          {
            'i': i,
            'x': rects[i].x,
            'y': rects[i].y,
            'w': rects[i].w,
            'h': rects[i].h,
          },
      ],
    });

/// Прямоугольники кадров в листе, который собрал [pack].
List<FrameRect> packedRects(int n, int cellW, int cellH, {int cols = 0, int padding = 0}) {
  final c = cols <= 0 ? n : (cols > n ? n : cols);
  return [for (var i = 0; i < n; i++) FrameRect((i % c) * (cellW + padding), (i ~/ c) * (cellH + padding), cellW, cellH, i % c, i ~/ c)];
}
