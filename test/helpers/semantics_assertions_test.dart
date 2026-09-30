import 'semantics_assertions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({
  bool button = true,
  String? label,
  bool? enabled,
  bool? selected,
  VoidCallback? onTap,
  Key key = const Key('target'),
}) {
  return MaterialApp(
    home: Scaffold(
      body: Semantics(
        key: key,
        button: button,
        label: label,
        enabled: enabled,
        selected: selected,
        onTap: onTap,
        child: const SizedBox(width: 48, height: 48),
      ),
    ),
  );
}

void main() {
  testWidgets('按钮 + 名字 + 可点：全部符合时通过', (tester) async {
    await tester.pumpWidget(
      _host(label: '删除这段备注', enabled: true, selected: false),
    );
    expectButtonSemantics(
      tester,
      const Key('target'),
      label: '删除这段备注',
      enabled: true,
      selected: false,
    );
  });

  testWidgets('按钮成立即可单独断言（不填名字与门控）', (tester) async {
    await tester.pumpWidget(_host(label: '分段'));
    expectButtonSemantics(tester, const Key('target'));
  });

  testWidgets('键不在 Semantics 上时向下找按钮语义层', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Container(
            key: const Key('wrapped'),
            child: Semantics(
              button: true,
              label: '重点',
              child: const SizedBox(width: 48, height: 48),
            ),
          ),
        ),
      ),
    );
    expectButtonSemantics(tester, const Key('wrapped'), label: '重点');
  });

  testWidgets('否定用例：下探路径无按钮语义层时失败', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Container(
            key: const Key('wrapped'),
            child: const SizedBox(width: 48, height: 48),
          ),
        ),
      ),
    );
    expect(
      () => expectButtonSemantics(tester, const Key('wrapped')),
      throwsA(isA<TestFailure>()),
    );
  });

  testWidgets('Material 按钮：名字来自 IconButton.tooltip 时同样能核对', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IconButton(
            key: const Key('icon_tooltip'),
            tooltip: '关闭数拍浮层',
            onPressed: () {},
            icon: const Icon(Icons.close),
          ),
        ),
      ),
    );
    expectButtonSemantics(
      tester,
      const Key('icon_tooltip'),
      label: '关闭数拍浮层',
    );
    expect(
      () => expectButtonSemantics(
        tester,
        const Key('icon_tooltip'),
        label: '删除这段备注',
      ),
      throwsA(isA<TestFailure>()),
    );
  });

  testWidgets('Material 按钮：名字来自 Icon.semanticLabel 时同样能核对', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IconButton(
            key: const Key('icon_label'),
            onPressed: () {},
            icon: const Icon(Icons.close, semanticLabel: '关闭引导'),
          ),
        ),
      ),
    );
    expectButtonSemantics(tester, const Key('icon_label'), label: '关闭引导');
  });

  testWidgets('否定用例：名字不符时断言失败', (tester) async {
    await tester.pumpWidget(_host(label: '分段'));
    expect(
      () => expectButtonSemantics(tester, const Key('target'), label: '删除'),
      throwsA(isA<TestFailure>()),
    );
  });

  testWidgets('否定用例：可点门控不符时断言失败', (tester) async {
    await tester.pumpWidget(_host(label: '分段', enabled: false));
    expect(
      () => expectButtonSemantics(tester, const Key('target'), enabled: true),
      throwsA(isA<TestFailure>()),
    );
  });

  testWidgets('否定用例：不是按钮时断言失败', (tester) async {
    await tester.pumpWidget(_host(button: false, label: '分段'));
    expect(
      () => expectButtonSemantics(tester, const Key('target')),
      throwsA(isA<TestFailure>()),
    );
  });

  testWidgets('否定用例：选中态不符时断言失败', (tester) async {
    await tester.pumpWidget(_host(label: '熟练度', selected: false));
    expect(
      () => expectButtonSemantics(tester, const Key('target'), selected: true),
      throwsA(isA<TestFailure>()),
    );
  });

  testWidgets('状态播报：全等名字通过，不要求按钮角色', (tester) async {
    await tester.pumpWidget(_host(button: false, label: '已完全掌握'));
    expectSemanticsLabel(tester, const Key('target'), label: '已完全掌握');
  });

  testWidgets('状态播报：包含名字通过（合并节点里的状态词）', (tester) async {
    await tester.pumpWidget(_host(button: false, label: '计划\n待办'));
    expectSemanticsLabel(tester, const Key('target'), labelContains: '待办');
  });

  testWidgets('状态播报：可播报区域旗标', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Semantics(
            key: const Key('target'),
            liveRegion: true,
            label: '音量 60%',
            child: const SizedBox(width: 48, height: 48),
          ),
        ),
      ),
    );
    expectSemanticsLabel(
      tester,
      const Key('target'),
      label: '音量 60%',
      liveRegion: true,
    );
  });

  testWidgets('否定用例：名字不等时断言失败', (tester) async {
    await tester.pumpWidget(_host(button: false, label: '未完全掌握'));
    expect(
      () => expectSemanticsLabel(tester, const Key('target'), label: '已完全掌握'),
      throwsA(isA<TestFailure>()),
    );
  });

  testWidgets('否定用例：不含期望词时断言失败', (tester) async {
    await tester.pumpWidget(_host(button: false, label: '计划'));
    expect(
      () => expectSemanticsLabel(tester, const Key('target'), labelContains: '待办'),
      throwsA(isA<TestFailure>()),
    );
  });

  testWidgets('否定用例：非可播报区域时断言失败', (tester) async {
    await tester.pumpWidget(_host(button: false, label: '音量 60%'));
    expect(
      () => expectSemanticsLabel(tester, const Key('target'), liveRegion: true),
      throwsA(isA<TestFailure>()),
    );
  });

  testWidgets('activateBySemantics：沿无障碍路径派发 tap，动作者被触发一次', (tester) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(
      _host(label: '删除这段备注', onTap: () => taps++),
    );
    activateBySemantics(tester, const Key('target'));
    expect(taps, 1, reason: '语义 tap 应触发一次动作者');
    handle.dispose();
  });

  testWidgets('否定用例：语义节点没有 tap 动作时 activateBySemantics 失败', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(label: '只是名字'));
    expect(
      () => activateBySemantics(tester, const Key('target')),
      throwsA(isA<TestFailure>()),
    );
    handle.dispose();
  });
}
