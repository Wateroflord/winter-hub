import 'package:flutter/material.dart';
import 'package:winter_core/winter_core.dart';

import 'app.dart';

void main() => runWinterApp(
      repo: 'winter-sprites',
      appName: 'Winter Sprites',
      body: () => runApp(const WinterCrashBanner(child: SpritesApp())),
    );
