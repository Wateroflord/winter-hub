import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:winter_sprites/sprite.dart';

/// Лента из [n] кадров [s]×[s]: кадр i залит своим цветом, последний — пустой.
img.Image strip(int n, int s, {bool lastEmpty = false}) {
  final im = img.Image(width: n * s, height: s, numChannels: 4);
  for (var i = 0; i < n; i++) {
    if (lastEmpty && i == n - 1) continue;
    for (var y = 0; y < s; y++) {
      for (var x = 0; x < s; x++) {
        im.setPixelRgba(i * s + x, y, 10 * (i + 1), 0, 0, 255);
      }
    }
  }
  return im;
}

void main() {
  test('нарезка: размер кадра, отступы, сетка', () {
    final r = sliceRects(64, 32, const SliceSpec(16, 16));
    expect(r.length, 8);
    expect((r[5].x, r[5].y, r[5].col, r[5].row), (16, 16, 1, 1));
    // Отступ 1 и промежуток 2: 1 + 16 + 2 + 16 = 35 → 2 кадра в 36 пикселях.
    expect(gridSize(36, 16, const SliceSpec(16, 16, offX: 1, gapX: 2)), (2, 1));
    expect(sliceRects(10, 10, const SliceSpec(16, 16)), isEmpty);
    final g = specFromGrid(96, 64, 3, 2);
    expect((g.fw, g.fh), (32, 32));
  });

  test('угадывание размера кадра', () {
    expect(guessSpec(256, 32), const SliceSpec(32, 32));
    expect(guessSpec(48, 192), const SliceSpec(48, 48));
    expect(guessSpec(128, 96), const SliceSpec(32, 32));
    expect(guessSpec(50, 30), const SliceSpec(50, 30));
  });

  test('кадры, пустые кадры и сборка листа', () {
    final s = strip(4, 8, lastEmpty: true);
    final rects = sliceRects(s.width, s.height, guessSpec(s.width, s.height));
    expect(rects.length, 4);
    final frames = [for (final r in rects) crop(s, r)];
    expect(isEmptyFrame(frames[3]), isTrue);
    expect(isEmptyFrame(frames[0]), isFalse);
    expect(frames[1].getPixel(3, 3).r, 20);
    final sheet = pack(frames.take(3).toList(), cols: 2, padding: 1);
    expect((sheet.width, sheet.height), (17, 17));
    expect(sheet.getPixel(9, 0).r, 20); // второй кадр после промежутка
    expect(sheet.getPixel(0, 9).r, 30); // третий — во втором ряду
    final rr = packedRects(3, 8, 8, cols: 2, padding: 1);
    expect((rr[2].x, rr[2].y), (0, 9));
  });

  test('кадры разного размера: по центру и по низу ячейки', () {
    final big = img.Image(width: 4, height: 4, numChannels: 4)..setPixelRgba(0, 0, 1, 1, 1, 255);
    final small = img.Image(width: 2, height: 2, numChannels: 4)..setPixelRgba(0, 0, 9, 9, 9, 255);
    final sheet = pack([big, small]);
    expect((sheet.width, sheet.height), (8, 4));
    expect(sheet.getPixel(4 + 1, 2).r, 9);
  });

  test('увеличение без размытия', () {
    final f = img.Image(width: 2, height: 1, numChannels: 4)
      ..setPixelRgba(0, 0, 255, 0, 0, 255)
      ..setPixelRgba(1, 0, 0, 0, 255, 255);
    final b = scaleNearest(f, 3);
    expect((b.width, b.height), (6, 3));
    expect(b.getPixel(2, 2).r, 255);
    expect(b.getPixel(3, 0).b, 255);
  });

  test('палитра и замена цвета', () {
    final s = strip(3, 2);
    final pal = palette(s);
    expect(pal.length, 3);
    final red10 = argb(10, 0, 0, 255);
    expect(pal.any((e) => e.key == red10 && e.value == 4), isTrue);
    final (out, n) = recolor(s, red10, 0xFF00FF00);
    expect(n, 4);
    expect(out.getPixel(0, 0).g, 255);
    expect(s.getPixel(0, 0).g, 0); // исходник не тронут
    final (clear, m) = recolor(s, red10, 0x00000000);
    expect(m, 4);
    expect(clear.getPixel(1, 1).a, 0);
  });

  test('HEX, .gpl, пинг-понг, GIF и json', () {
    expect(parseHex('#fa0'), 0xFFFFAA00);
    expect(parseHex('7FD8FF'), 0xFF7FD8FF);
    expect(parseHex('zz'), isNull);
    final g = gplText([0xFF7FD8FF], 'Лёд');
    expect(g, contains('GIMP Palette'));
    expect(g, contains('127 216 255'));
    expect(hexText([0xFF000000, 0xFFFFFFFF]), '000000\nFFFFFF');
    expect(pingPongOrder(4), [0, 1, 2, 3, 2, 1]);
    expect(pingPongOrder(2), [0, 1]);
    final frames = [for (final r in sliceRects(16, 8, const SliceSpec(8, 8))) crop(strip(2, 8), r)];
    final gif = gifOf(frames, 10);
    expect(String.fromCharCodes(gif.take(3)), 'GIF');
    final anim = img.decodeGif(gif)!;
    expect(anim.numFrames, 2);
    final j = metaJson(name: 'hero', rects: packedRects(2, 8, 8), sheetW: 16, sheetH: 8, fps: 10);
    expect(j, contains('"frames"'));
  });

  test('PNG с палитрой и без прозрачности → RGBA', () {
    final rgb = img.Image(width: 2, height: 2)..setPixelRgb(0, 0, 200, 100, 50);
    final bytes = img.encodePng(rgb);
    final back = decode(bytes)!;
    expect(back.numChannels, 4);
    expect(back.getPixel(0, 0).a, 255);
    expect(back.getPixel(0, 0).r, 200);
  });
}
