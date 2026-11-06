import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:winter_core/winter_core.dart';

void main() {
  test('ссылка на отчёт ведёт в репозиторий приложения', () {
    WinterCrash.repo = 'winter-mines';
    WinterCrash.appName = 'Сапёр';
    final u = WinterCrash.reportUri('=== 2026-11-06\nBad state: boom\n#0 main');
    expect(u.host, 'github.com');
    expect(u.path, '/Wateroflord/winter-mines/issues/new');
    expect(u.queryParameters['title'], 'Падение: Bad state: boom');
    expect(u.queryParameters['body'], contains('Сапёр'));
    expect(u.queryParameters['body'], contains('Bad state: boom'));
  });

  test('длинный журнал обрезается', () {
    final body = WinterCrash.reportBody('x' * 20000);
    expect(body.length, lessThan(6000));
  });

  testWidgets('плашка появляется только после падения', (tester) async {
    await tester.pumpWidget(const WinterCrashBanner(child: MaterialApp(home: Text('app'))));
    expect(find.textContaining('приложение упало'), findsNothing);
    WinterCrash.pending.value = 'Bad state: boom';
    await tester.pump();
    expect(find.textContaining('приложение упало'), findsOneWidget);
    WinterCrash.pending.value = null;
    await tester.pump();
    expect(find.textContaining('приложение упало'), findsNothing);
  });
}
