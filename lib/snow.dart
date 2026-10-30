import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Медленно падающий снег на фоне.
class Snow extends StatefulWidget {
  const Snow({super.key});

  @override
  State<Snow> createState() => _SnowState();
}

class _Flake {
  double x, y, r, speed, drift;
  _Flake(this.x, this.y, this.r, this.speed, this.drift);
}

class _SnowState extends State<Snow> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _rnd = math.Random();
  late final List<_Flake> _flakes;
  Duration _last = Duration.zero;
  double _t = 0;

  @override
  void initState() {
    super.initState();
    _flakes = List.generate(45, (_) => _new(randomY: true));
    _ticker = createTicker((d) {
      final dt = (d - _last).inMicroseconds / 1e6;
      _last = d;
      _t += dt;
      for (final f in _flakes) {
        f.y += f.speed * dt;
        f.x += math.sin(_t * 0.6 + f.drift) * 0.004 * dt * 10;
        if (f.y > 1.05) {
          final n = _new();
          f
            ..x = n.x
            ..y = -0.05
            ..r = n.r
            ..speed = n.speed;
        }
      }
      setState(() {});
    })
      ..start();
  }

  _Flake _new({bool randomY = false}) => _Flake(
        _rnd.nextDouble(),
        randomY ? _rnd.nextDouble() : -0.05,
        0.8 + _rnd.nextDouble() * 2.2,
        0.015 + _rnd.nextDouble() * 0.035,
        _rnd.nextDouble() * 6,
      );

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(child: CustomPaint(painter: _SnowPainter(_flakes), size: Size.infinite));
}

class _SnowPainter extends CustomPainter {
  final List<_Flake> flakes;
  _SnowPainter(this.flakes);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint();
    for (final f in flakes) {
      p.color = Colors.white.withValues(alpha: 0.12 + f.r * 0.08);
      canvas.drawCircle(Offset(f.x * size.width, f.y * size.height), f.r, p);
    }
  }

  @override
  bool shouldRepaint(covariant _SnowPainter old) => true;
}
