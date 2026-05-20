import 'package:data_recorder/features/splash/splash_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('显示启动页', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SplashPage()));

    expect(find.text('铝模工作录'), findsOneWidget);
    expect(find.text('正在检查更新...'), findsOneWidget);
  });
}
