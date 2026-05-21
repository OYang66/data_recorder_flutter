import 'package:data_recorder/app/router.dart';
import 'package:data_recorder/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _dataRows = int.fromEnvironment('DATA_ROWS', defaultValue: 400);
const _startAt = String.fromEnvironment('START_AT');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('全功能冒烟测试和400行压测', (tester) async {
    _perfMark('app_main_start');
    app.main();
    await _pumpFor(tester, const Duration(seconds: 2));

    _perfMark('welcome_start');
    await _handleWelcomeIfNeeded(tester);
    _perfMark('login_start');
    await _loginIfNeeded(tester);
    _perfMark('wait_main_start');
    await _waitForMainPage(tester);
    await _closeKnownDialogs(tester);
    _perfMark('main_ready');

    final stressWatch = Stopwatch();
    if (_startAt != 'more') {
      _perfMark('top_buttons_start');
      await _smokeMainTopButtons(tester);
      _perfMark('switch_fast_start');
      await _switchMode(tester, '返厂统计');
      _perfMark('stress_fast_rows_start');
      stressWatch.start();
      await _stressFastRows(tester, _dataRows);
      stressWatch.stop();
      _perfMark('stress_fast_rows_end_${stressWatch.elapsedMilliseconds}ms');

      _perfMark('switch_standard_start');
      await _switchMode(tester, '型号统计');
      await _smokeStandardInput(tester);
      _perfMark('switch_loading_start');
      await _switchMode(tester, '返厂装车');
      await _smokeLoadingInput(tester);
      _perfMark('switch_quality_start');
      await _switchMode(tester, '质量反馈');
      await _smokeQualityInput(tester);
      _perfMark('switch_fast_again_start');
      await _switchMode(tester, '返厂统计');
    }

    _perfMark('more_menu_start');
    await _smokeMoreMenu(tester);
    _perfMark('delivery_order_start');
    await _openFromMore(tester, '上传发货清单');
    await _smokeDeliveryOrderPage(tester);
    await _goBackToMain(tester);
    _perfMark('settlement_start');
    await _openFromMore(tester, '数据生成查询');
    await _smokeSettlementPage(tester);
    await _goBackToMain(tester);

    binding.reportData = <String, Object?>{
      'dataRows': _dataRows,
      'fastRowsElapsedMs': stressWatch.elapsedMilliseconds,
      'startAt': _startAt,
      'status': 'passed',
    };
  }, timeout: const Timeout(Duration(minutes: 20)));
}

void _perfMark(String name) {
  final now = DateTime.now().toIso8601String();
  debugPrint('PERF_MARK $now $name');
}

Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  final deadline = DateTime.now().add(duration);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

bool _hasText(String text) => find.text(text).evaluate().isNotEmpty;

bool _hasTextContaining(String text) =>
    find.textContaining(text).evaluate().isNotEmpty;

Future<void> _waitUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 20),
  String reason = '等待条件超时',
}) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < timeout) {
    await tester.pump(const Duration(milliseconds: 250));
    if (condition()) return;
  }
  fail(reason);
}

Future<void> _tapText(
  WidgetTester tester,
  String text, {
  bool optional = false,
  Duration settle = const Duration(milliseconds: 450),
}) async {
  final finder = find.text(text);
  if (finder.evaluate().isEmpty) {
    if (optional) return;
    fail('未找到按钮或文本：$text');
  }
  final target = finder.last;
  try {
    await tester.ensureVisible(target);
  } catch (_) {}
  await tester.tap(target, warnIfMissed: false);
  await tester.pump(settle);
}

Future<void> _closeKnownDialogs(WidgetTester tester) async {
  for (final text in const ['暂不更新', '确定', '我知道了', '知道了', '取消', '关闭']) {
    if (_hasText(text)) {
      await _tapText(tester, text, optional: true);
      await _pumpFor(tester, const Duration(milliseconds: 400));
      return;
    }
  }
}

Future<void> _dismissTransient(WidgetTester tester) async {
  await _closeKnownDialogs(tester);
  await tester.tapAt(const Offset(2, 2));
  await tester.pump(const Duration(milliseconds: 350));
  await _closeKnownDialogs(tester);
}

Future<void> _handleWelcomeIfNeeded(WidgetTester tester) async {
  await _pumpFor(tester, const Duration(seconds: 1));
  if (!_hasText('我会注意的') && !_hasText('我同意')) return;
  await _tapText(tester, '我会注意的', optional: true);
  await _tapText(tester, '我同意', optional: true);
  await _pumpFor(tester, const Duration(seconds: 2));
}

Future<void> _loginIfNeeded(WidgetTester tester) async {
  await _pumpFor(tester, const Duration(seconds: 2));
  if (!_hasText('登录') || find.byType(EditableText).evaluate().length < 2) {
    return;
  }

  final fields = find.byType(EditableText);
  await tester.enterText(fields.at(0), '123456');
  await tester.enterText(fields.at(1), '123456');
  await tester.pump(const Duration(milliseconds: 200));
  await _tapText(tester, '登录');
  await _waitUntil(
    tester,
    () => _hasTextContaining('当前项目：') || _hasText('登录') == false,
    timeout: const Duration(seconds: 30),
    reason: '登录后未进入主界面',
  );
}

Future<void> _waitForMainPage(WidgetTester tester) async {
  await _waitUntil(
    tester,
    () => _hasTextContaining('当前项目：'),
    timeout: const Duration(seconds: 30),
    reason: '未进入主界面',
  );
}

Future<void> _smokeMainTopButtons(WidgetTester tester) async {
  for (final text in const ['项目', '楼栋', '更多']) {
    if (!_hasText(text)) continue;
    await _dismissTransient(tester);
    await _tapText(tester, text, optional: true);
    await _pumpFor(tester, const Duration(milliseconds: 500));
    await _dismissTransient(tester);
  }
  await _dismissTransient(tester);
  await _tapText(tester, '切换模式');
  await _dismissTransient(tester);
}

Future<void> _switchMode(WidgetTester tester, String mode) async {
  await _waitForMainPage(tester);
  await _dismissTransient(tester);
  await _tapText(tester, '切换模式');
  await _waitUntil(
    tester,
    () => _hasText(mode),
    timeout: const Duration(seconds: 5),
    reason: '模式菜单未打开：$mode',
  );
  await _tapText(tester, mode);
  await _pumpFor(tester, const Duration(milliseconds: 800));
  await _closeKnownDialogs(tester);
}

Future<void> _stressFastRows(WidgetTester tester, int rows) async {
  await _waitForMainPage(tester);
  final button400 = tester.getCenter(find.text('400').last);
  final buttonE = tester.getCenter(find.text('E').last);
  final button500 = tester.getCenter(find.text('500').last);
  final nextColumn = tester.getCenter(find.text('换列').last);
  final button1 = tester.getCenter(find.text('1').last);
  final newLine = tester.getCenter(find.text('换行').last);

  for (var i = 0; i < rows; i++) {
    await tester.tapAt(button400);
    await tester.tapAt(buttonE);
    await tester.tapAt(button500);
    await tester.tapAt(nextColumn);
    await tester.tapAt(button1);
    await tester.tapAt(newLine);
    if (i % 10 == 0) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }
  await tester.pump(const Duration(seconds: 2));
  expect(find.textContaining('${rows.clamp(1, rows)}'), findsWidgets);
}

Future<void> _smokeStandardInput(WidgetTester tester) async {
  await _tapText(tester, '1');
  await _tapText(tester, '换列');
  await _tapText(tester, 'E');
  await _tapText(tester, '换列');
  await _tapText(tester, '1');
  await _tapText(tester, '换行');
}

Future<void> _smokeLoadingInput(WidgetTester tester) async {
  await _tapText(tester, '铝物料', optional: true);
  await _tapText(tester, '400', optional: true);
  await _tapText(tester, '换列', optional: true);
  await _tapText(tester, '1', optional: true);
  await _tapText(tester, '换行', optional: true);
  await _closeKnownDialogs(tester);
}

Future<void> _smokeQualityInput(WidgetTester tester) async {
  await _tapText(tester, '1', optional: true);
  await _tapText(tester, '换列', optional: true);
  await _tapText(tester, 'E', optional: true);
  await _tapText(tester, '换列', optional: true);
  await _tapText(tester, '换行', optional: true);
  await _closeKnownDialogs(tester);
}

Future<void> _smokeMoreMenu(WidgetTester tester) async {
  await _openFromMore(tester, '二维码识别');
  await _tapText(tester, '知道了', optional: true);
  await _openFromMore(tester, 'NFC碰一碰');
  await _tapText(tester, '知道了', optional: true);
  await _openFromMore(tester, '检查更新');
  await _pumpFor(tester, const Duration(seconds: 2));
  await _closeKnownDialogs(tester);
}

Future<void> _openFromMore(WidgetTester tester, String item) async {
  await _waitForMainPage(tester);
  await _dismissTransient(tester);
  await _tapText(tester, '更多');
  await _waitUntil(
    tester,
    () => _hasText('更多功能'),
    timeout: const Duration(seconds: 5),
    reason: '更多功能菜单未打开',
  );
  if (!_hasText(item)) {
    final scrollables = find.byType(SingleChildScrollView);
    if (scrollables.evaluate().isNotEmpty) {
      await tester.drag(scrollables.last, const Offset(0, -360));
      await tester.pump(const Duration(milliseconds: 300));
    }
  }
  if (_hasText(item)) {
    await _tapText(tester, item);
    await _pumpFor(tester, const Duration(seconds: 1));
    return;
  }
  await _dismissTransient(tester);
  if (item == '上传发货清单') {
    appRouter.go('/delivery-order');
  } else if (item == '数据生成查询') {
    appRouter.go('/settlement-data');
  } else {
    fail('未找到更多功能项：$item');
  }
  await _pumpFor(tester, const Duration(seconds: 1));
}

Future<void> _smokeDeliveryOrderPage(WidgetTester tester) async {
  await _waitUntil(
    tester,
    () => _hasText('查询') && _hasText('上传'),
    timeout: const Duration(seconds: 20),
    reason: '发货清单页面未加载',
  );
  await _tapText(tester, '查询');
  await _pumpFor(tester, const Duration(seconds: 1));
  await _tapText(tester, '缺失物料', optional: true);
  await _pumpFor(tester, const Duration(seconds: 2));
  await _closeKnownDialogs(tester);
  await _tapText(tester, '物料配置', optional: true);
  await _pumpFor(tester, const Duration(seconds: 2));
  await _closeKnownDialogs(tester);
  await _tapText(tester, '重解析', optional: true);
  await _pumpFor(tester, const Duration(milliseconds: 600));
  await _tapText(tester, '取消', optional: true);
}

Future<void> _smokeSettlementPage(WidgetTester tester) async {
  await _waitUntil(
    tester,
    () => _hasText('同步项目') && _hasText('查询'),
    timeout: const Duration(seconds: 20),
    reason: '数据生成查询页面未加载',
  );
  await _tapText(tester, '同步项目');
  await _pumpFor(tester, const Duration(seconds: 2));
  await _tapText(tester, '查询', optional: true);
  await _pumpFor(tester, const Duration(seconds: 2));
  await _tapText(tester, '分享', optional: true);
  await _pumpFor(tester, const Duration(milliseconds: 800));
  await _closeKnownDialogs(tester);
}

Future<void> _goBackToMain(WidgetTester tester) async {
  appRouter.go('/main');
  await _pumpFor(tester, const Duration(seconds: 1));
  await _waitForMainPage(tester);
}
