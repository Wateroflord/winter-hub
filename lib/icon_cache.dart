import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Иконка приложения, которая видна и без интернета.
///
/// Раньше иконки грузились через Image.network: в памяти они жили только до закрытия хаба,
/// поэтому без интернета вместо них были буквы. Теперь картинка сохраняется в файл,
/// показывается из него сразу, а раз за запуск хаба тихо обновляется из сети.
class CachedIcon extends StatefulWidget {
  final String url;
  final double size;
  final Widget fallback;
  const CachedIcon({super.key, required this.url, required this.size, required this.fallback});

  @override
  State<CachedIcon> createState() => _CachedIconState();
}

class _CachedIconState extends State<CachedIcon> {
  /// Какие иконки уже обновлены из сети за этот запуск.
  static final _fresh = <String>{};
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CachedIcon old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _bytes = null;
      _load();
    }
  }

  static Future<File?> _file(String url) async {
    try {
      final d = Directory('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}icons');
      await d.create(recursive: true);
      return File('${d.path}${Platform.pathSeparator}${sha1.convert(utf8.encode(url))}.img');
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    final url = widget.url;
    if (url.isEmpty) return;
    final f = await _file(url);
    try {
      if (f != null && await f.exists()) {
        final b = await f.readAsBytes();
        if (b.isNotEmpty && mounted && widget.url == url) setState(() => _bytes = b);
      }
    } catch (_) {}
    if (_fresh.contains(url)) return;
    try {
      final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      final b = r.bodyBytes;
      if (r.statusCode != 200 || b.length < 8) return;
      _fresh.add(url);
      if (f != null) await f.writeAsBytes(b, flush: true);
      if (mounted && widget.url == url && !listEquals(_bytes, b)) setState(() => _bytes = b);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final b = _bytes;
    if (b == null) return widget.fallback;
    return Image.memory(
      b,
      width: widget.size,
      height: widget.size,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => widget.fallback,
    );
  }
}
