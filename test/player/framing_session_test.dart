import 'dart:io';
import 'dart:ui' show Offset, Rect, Size;

import 'package:dance_learning_app/annotation/framing_selection.dart';
import 'package:dance_learning_app/player/framing_session.dart';
import 'package:dance_learning_app/player/framing_session_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// 取景域宿主会话：取景调节态内「起手取基准
/// → 拖动按对角圈出选区 → 松手按实际看到的框定格」的编排直测——不 pump
/// widget、不注容器，只经模块接口驱动。
///
/// 断言用**取景选区**形状（四边按源画面原相归一化、恒在整帧内、不小于最小
/// 边）。取景只剩源画面一个作用对象，故没有侧别分支。
void main() {
  /// 横屏 960 × 540 源侧半区（缝 2dp）：pane 479 × 540，16:9 画面 contain =
  /// 479 × 269.4375、垂直居中（top 135.28125）。
  const picture = Rect.fromLTWH(0, 135.28125, 479, 269.4375);
  final minEdge = 24 / picture.height;

  late FramingViewport viewport;
  late FramingState committed;
  late bool active;
  late FramingSelection? applied;
  late int exitCount;
  late FramingSessionHost host;

  /// 源画面归一化坐标 → 屏幕落点。
  Offset at(double x, double y) => Offset(
    picture.left + x * picture.width,
    picture.top + y * picture.height,
  );

  setUp(() {
    viewport = const FramingViewport(
      size: Size(960, 540),
      landscape: true,
      sourceAspectRatio: 16 / 9,
    );
    committed = const FramingState();
    active = true;
    applied = null;
    exitCount = 0;
    host = FramingSessionHost(
      readViewport: () => viewport,
      isActive: () => active,
      readCommitted: () => committed,
      applySource: (selection) {
        applied = selection;
        committed = FramingState(source: selection);
      },
      exitFraming: () => exitCount++,
    );
  });

  group('起手', () {
    test('画面内起手：只取基准，不写取值', () {
      host.begin(focal: at(0.5, 0.5), pointerCount: 1);

      expect(host.hasSession, isTrue);
      expect(applied, isNull, reason: '起手只取基准，不写取值');
    });

    test('黑边起手：本场拖动不写取值、也不退出', () {
      // (0.5, -0.2) 在画面上缘之外的黑边里。
      host.begin(focal: Offset(picture.center.dx, 10), pointerCount: 1);
      final handled = host.adjust(focal: at(0.9, 0.9), pointerCount: 1);

      expect(handled, isTrue, reason: '黑边起手仍由取景吞帧，不回落播放语义');
      expect(applied, isNull, reason: '黑边起手不动作');
      expect(exitCount, 0, reason: '拖动不退出取景');
    });

    test('宽高比未知（画面即容器）：没有可映射的画面矩形，本场不建框', () {
      viewport = const FramingViewport(
        size: Size(960, 540),
        landscape: true,
        sourceAspectRatio: null,
      );
      host.begin(focal: at(0.5, 0.5), pointerCount: 1);
      host.adjust(focal: at(0.9, 0.9), pointerCount: 1);

      expect(applied, isNull);
      expect(exitCount, 0);
    });
  });

  group('建框：跟手橡皮筋', () {
    test('按对角圈出矩形：四边按源画面原相归一化', () {
      host.begin(focal: at(0.2, 0.2), pointerCount: 1);
      host.adjust(focal: at(0.6, 0.8), pointerCount: 1);

      expect(applied!.left, closeTo(0.2, 1e-6));
      expect(applied!.top, closeTo(0.2, 1e-6));
      expect(applied!.right, closeTo(0.6, 1e-6));
      expect(applied!.bottom, closeTo(0.8, 1e-6));
    });

    test('反向拖动仍按对角成框', () {
      host.begin(focal: at(0.6, 0.8), pointerCount: 1);
      host.adjust(focal: at(0.2, 0.2), pointerCount: 1);

      expect(applied!.left, closeTo(0.2, 1e-6));
      expect(applied!.top, closeTo(0.2, 1e-6));
      expect(applied!.right, closeTo(0.6, 1e-6));
      expect(applied!.bottom, closeTo(0.8, 1e-6));
    });

    test('拖出整帧：取交集，框恒落在画面内', () {
      host.begin(focal: at(0.5, 0.5), pointerCount: 1);
      host.adjust(focal: at(1.8, 2.2), pointerCount: 1);

      expect(applied!.right, 1.0);
      expect(applied!.bottom, 1.0);
      expect(applied!.left, closeTo(0.5, 1e-6));
      expect(applied!.top, closeTo(0.5, 1e-6));
    });
  });

  group('调整已有框：控制点 > 框内 > 框外', () {
    const preset = FramingSelection(
      left: 0.25,
      top: 0.25,
      right: 0.75,
      bottom: 0.75,
    );

    setUp(() => committed = const FramingState(source: preset));

    test('框内拖动整体平移：形状不变', () {
      host.begin(focal: at(0.5, 0.5), pointerCount: 1);
      host.adjust(focal: at(0.6, 0.6), pointerCount: 1);

      expect(applied!.left, closeTo(0.35, 1e-9));
      expect(applied!.top, closeTo(0.35, 1e-9));
      expect(applied!.right, closeTo(0.85, 1e-9));
      expect(applied!.bottom, closeTo(0.85, 1e-9));
      expect(applied!.width, closeTo(preset.width, 1e-9));
      expect(applied!.height, closeTo(preset.height, 1e-9));
    });

    test('角点拖动同时改两轴、对侧不动', () {
      host.begin(focal: at(0.25, 0.25), pointerCount: 1);
      host.adjust(focal: at(0.15, 0.2), pointerCount: 1);

      expect(applied!.left, closeTo(0.15, 1e-9));
      expect(applied!.top, closeTo(0.2, 1e-9));
      expect(applied!.right, closeTo(0.75, 1e-9));
      expect(applied!.bottom, closeTo(0.75, 1e-9));
    });

    test('边中点只改那一条边：另一轴的位移不生效', () {
      host.begin(focal: at(0.75, 0.5), pointerCount: 1);
      host.adjust(focal: at(0.9, 0.9), pointerCount: 1);

      expect(applied!.right, closeTo(0.9, 1e-9));
      expect(applied!.left, closeTo(0.25, 1e-9));
      expect(applied!.top, closeTo(0.25, 1e-9));
      expect(applied!.bottom, closeTo(0.75, 1e-9));
    });

    test('命中优先级：角点压在框上时是控制点而不是整体平移', () {
      // 角点既在框上（边框）也在命中盒里：按控制点调形，而不是平移。
      host.begin(focal: at(0.25, 0.25), pointerCount: 1);
      host.adjust(focal: at(0.35, 0.35), pointerCount: 1);

      expect(applied!.left, closeTo(0.35, 1e-9), reason: '左缘跟手改');
      expect(applied!.top, closeTo(0.35, 1e-9), reason: '上缘跟手改');
      expect(applied!.right, closeTo(0.75, 1e-9), reason: '对侧不动');
      expect(applied!.bottom, closeTo(0.75, 1e-9));
    });

    test('边线本体不是控制点：上边线上按下是整体平移，不是调形', () {
      // 上边线上距两个上缘控制点各约 48dp / 72dp：命中盒之外。
      host.begin(focal: at(0.35, 0.25), pointerCount: 1);
      host.adjust(focal: at(0.45, 0.15), pointerCount: 1);

      expect(applied!.width, closeTo(preset.width, 1e-9), reason: '不调形');
      expect(applied!.height, closeTo(preset.height, 1e-9));
      expect(applied!.left, closeTo(0.35, 1e-9));
      expect(applied!.top, closeTo(0.15, 1e-9));
    });

    test('边线本体不是控制点：右/下边线上按下同样是整体平移', () {
      // 右缘 (0.75, 0.4)：距右中点 26.9dp、距右上角 40.4dp，均在 24dp 之外。
      host.begin(focal: at(0.75, 0.4), pointerCount: 1);
      host.adjust(focal: at(0.65, 0.4), pointerCount: 1);
      expect(applied!.width, closeTo(preset.width, 1e-9), reason: '不调形');
      expect(applied!.height, closeTo(preset.height, 1e-9));
      expect(applied!.left, closeTo(0.15, 1e-9));
      expect(applied!.top, closeTo(0.25, 1e-9));
      host.end();

      // 平移后的框 [0.15, 0.25, 0.65, 0.75]：下缘 (0.3, 0.75) 距下中点 47.9dp、
      // 距左下角 71.9dp。
      host.begin(focal: at(0.3, 0.75), pointerCount: 1);
      host.adjust(focal: at(0.35, 0.65), pointerCount: 1);
      expect(applied!.width, closeTo(preset.width, 1e-9), reason: '不调形');
      expect(applied!.height, closeTo(preset.height, 1e-9));
      expect(applied!.left, closeTo(0.2, 1e-9));
      expect(applied!.bottom, closeTo(0.65, 1e-9));
    });

    test('框外拖动替换成新框（不是平移）', () {
      host.begin(focal: at(0.05, 0.05), pointerCount: 1);
      host.adjust(focal: at(0.35, 0.35), pointerCount: 1);
      host.end();

      expect(applied, isNotNull);
      expect(applied!.left, closeTo(0.05, 1e-9));
      expect(applied!.top, closeTo(0.05, 1e-9));
      expect(applied!.right, closeTo(0.35, 1e-9));
      expect(applied!.bottom, closeTo(0.35, 1e-9));
    });

    test('整体平移贴到边即停：框整体停住、尺寸不变（无越界量）', () {
      host.begin(focal: at(0.5, 0.5), pointerCount: 1);
      host.adjust(focal: at(1.5, 0.5), pointerCount: 1);
      final atEdge = applied!;
      expect(atEdge.right, closeTo(1, 1e-9));
      expect(atEdge.left, closeTo(0.5, 1e-9), reason: '宽度原样、框整体停住');
      expect(atEdge.width, closeTo(preset.width, 1e-9));
      expect(atEdge.top, closeTo(0.25, 1e-9));
      expect(atEdge.bottom, closeTo(0.75, 1e-9));

      host.adjust(focal: at(2.5, 0.5), pointerCount: 1);
      expect(applied, atEdge, reason: '继续外拖仍停在同一处');
    });

    test('同一次手势里往回拖即随手指回缩', () {
      host.begin(focal: at(0.5, 0.5), pointerCount: 1);
      // 先往右越界：框整体停住。
      host.adjust(focal: at(1.5, 0.5), pointerCount: 1);
      // 再拖回框内：立刻跟手（不是先抵消越界量）。
      host.adjust(focal: at(0.7, 0.5), pointerCount: 1);
      expect(applied!.left, closeTo(0.45, 1e-9));
      expect(applied!.right, closeTo(0.95, 1e-9));
      // 拖回起手处：原样。
      host.adjust(focal: at(0.5, 0.5), pointerCount: 1);
      expect(applied, preset);
    });

    test('控制点贴边外拖停住、往回拖跟手（无尺寸记忆）', () {
      // 起手基准：已贴到画面右缘的框（右缘 1.0、宽 0.75）。
      const atRight = FramingSelection(
        left: 0.25,
        top: 0.25,
        right: 1.0,
        bottom: 0.75,
      );
      committed = const FramingState(source: atRight);

      // 抓右缘继续外拖：该边停在整帧缘、形状不变。
      host.begin(focal: at(1.0, 0.5), pointerCount: 1);
      host.adjust(focal: at(1.4, 0.5), pointerCount: 1);
      expect(applied!.right, closeTo(1, 1e-9), reason: '外拖停在整帧缘');
      expect(applied!.left, closeTo(0.25, 1e-9));

      // 同一次手势往回拖：该边立刻跟手。
      host.adjust(focal: at(0.8, 0.5), pointerCount: 1);
      expect(applied!.right, closeTo(0.8, 1e-9), reason: '往回拖立刻跟手');
      expect(applied!.left, closeTo(0.25, 1e-9), reason: '对侧不动');

      // 拖回起手处：原样，无越界量要抵消。
      host.adjust(focal: at(1.0, 0.5), pointerCount: 1);
      expect(applied!.right, closeTo(1, 1e-9));
      expect(applied!.width, closeTo(0.75, 1e-9));
    });

    test('控制点收缩不足最小边：停在 24dp 最小边、对侧不动', () {
      const atRight = FramingSelection(
        left: 0.25,
        top: 0.25,
        right: 1.0,
        bottom: 0.75,
      );
      committed = const FramingState(source: atRight);

      // 右缘反向拖出左缘之外：停在最小边（24dp 等效），左缘不动。
      host.begin(focal: at(1.0, 0.5), pointerCount: 1);
      host.adjust(focal: at(-0.5, 0.5), pointerCount: 1);
      expect(applied!.width, closeTo(minEdge, 1e-9), reason: '停在最小边');
      expect(applied!.right, closeTo(0.25 + minEdge, 1e-9));
      expect(applied!.left, closeTo(0.25, 1e-9), reason: '对侧不动');
    });

    test('小框中央按下是整体平移（逐轴自适应命中盒）', () {
      // 屏幕 40×40dp 的小框（短边 < 96dp）：命中盒收缩到 10dp 半径，中央留出
      // 可整体平移的空带。
      final w = 40 / picture.width;
      final h = 40 / picture.height;
      const left = 0.45;
      const top = 0.4;
      final small = FramingSelection(
        left: left,
        top: top,
        right: left + w,
        bottom: top + h,
      );
      committed = FramingState(source: small);

      // 框中心按下并拖动：整体平移（形状不变），不是控制点调形。
      host.begin(focal: at(left + w / 2, top + h / 2), pointerCount: 1);
      host.adjust(focal: at(left + w / 2 + 20 / picture.width, top + h / 2), pointerCount: 1);
      expect(applied!.width, closeTo(small.width, 1e-9), reason: '不调形');
      expect(applied!.height, closeTo(small.height, 1e-9));
      expect(applied!.left, closeTo(left + 20 / picture.width, 1e-9));

      // 距角点 11dp（旧 48dp 命中盒内、自适应命中盒外）同样落到整体平移。
      host.end();
      committed = FramingState(source: small);
      host.begin(
        focal: at(left + 11 / picture.width, top + 11 / picture.height),
        pointerCount: 1,
      );
      host.adjust(
        focal: at(
          left + 16 / picture.width,
          top + 16 / picture.height,
        ),
        pointerCount: 1,
      );
      expect(applied!.width, closeTo(small.width, 1e-9), reason: '小框上角点外仍是平移');
      expect(applied!.height, closeTo(small.height, 1e-9));
    });
  });

  group('松手：是否成框', () {
    test('不足最小边：不成框，保留手势前状态（原未调过）', () {
      host.begin(focal: at(0.5, 0.5), pointerCount: 1);
      host.adjust(focal: at(0.5 + minEdge / 2, 0.5 + minEdge / 2), pointerCount: 1);
      final tooSmall = applied;
      expect(tooSmall, isNotNull, reason: '跟手期间照常画橡皮筋');

      host.end();

      expect(applied, isNull, reason: '松手不成框 → 回退到起手前（未调过）');
      expect(committed.source, isNull);
    });

    test('不足最小边：回退到起手前的选区', () {
      const preset = FramingSelection(
        left: 0.25,
        top: 0.25,
        right: 0.75,
        bottom: 0.75,
      );
      committed = const FramingState(source: preset);
      // 框外起手 → 建框（框内起手是整体平移，见上一组）。
      host.begin(focal: at(0.05, 0.05), pointerCount: 1);
      host.adjust(focal: at(0.06, 0.06), pointerCount: 1);
      expect(applied, isNot(preset));

      host.end();

      expect(applied, preset, reason: '松手不成框 → 回到起手前选区');
      expect(committed.source, preset);
    });

    test('够大：按实际看到的框定格，不再回退', () {
      host.begin(focal: at(0.2, 0.2), pointerCount: 1);
      host.adjust(focal: at(0.7, 0.8), pointerCount: 1);
      final built = applied;

      host.end();

      expect(committed.source, built);
    });

    test('中途退出取景（未松手）：不足最小边仍回退，不留退化框', () {
      host.begin(focal: at(0.5, 0.5), pointerCount: 1);
      host.adjust(
        focal: at(0.5 + minEdge / 2, 0.5 + minEdge / 2),
        pointerCount: 1,
      );

      active = false;
      host.end();

      expect(committed.source, isNull, reason: '松手判定与退出无关');
    });
  });

  group('多指与让路', () {
    test('多指起手拖动：一律不写取值、不产生缩放或旋转语义', () {
      host.begin(focal: at(0.5, 0.5), pointerCount: 2);
      host.adjust(focal: at(0.8, 0.8), pointerCount: 2);
      host.adjust(focal: at(0.9, 0.9), pointerCount: 2);

      expect(applied, isNull);
      expect(exitCount, 0);
    });

    test('单指起手后加指：加指起不再写取值', () {
      host.begin(focal: at(0.2, 0.2), pointerCount: 1);
      host.adjust(focal: at(0.4, 0.4), pointerCount: 1);
      final built = applied;

      host.adjust(focal: at(0.6, 0.6), pointerCount: 2);
      host.adjust(focal: at(0.8, 0.8), pointerCount: 2);

      expect(applied, built, reason: '多指帧不再改建框');
    });

    test('让路会话：单指帧被吞但不写取值', () {
      host.begin(focal: at(0.5, 0.5), pointerCount: 1, panYielded: true);
      final handled = host.adjust(focal: at(0.8, 0.8), pointerCount: 1);

      expect(handled, isTrue, reason: '帧仍由取景吞掉，不回落播放语义');
      expect(applied, isNull, reason: '让路期间不写取值');
    });
  });

  group('退出', () {
    test('burst 中途退出取景：余帧只吞、不再改建框', () {
      host.begin(focal: at(0.2, 0.2), pointerCount: 1);
      host.adjust(focal: at(0.5, 0.5), pointerCount: 1);
      final built = applied;
      expect(built, isNotNull);

      active = false;
      final handled = host.adjust(focal: at(0.9, 0.9), pointerCount: 1);

      expect(handled, isTrue, reason: '会话在即整场由取景接手，不回播放语义');
      expect(applied, built);
    });

    test('end 清空会话：下个 burst 重新取基准', () {
      host.begin(focal: at(0.5, 0.5), pointerCount: 1);
      expect(host.hasSession, isTrue);

      host.end();
      expect(host.hasSession, isFalse);
      expect(host.adjust(focal: at(0.5, 0.5), pointerCount: 1), isFalse);
    });

    test('点画面内不退出；点黑边退出', () {
      host.handleTap(at(0.5, 0.5));
      expect(exitCount, 0, reason: '画面内落点不退出');

      host.handleTap(Offset(picture.center.dx, 30));
      expect(exitCount, 1);
    });

    test('无起手落点：不退出（单击仲裁回调不带位置）', () {
      host.handleTap(null);
      expect(exitCount, 0);
    });
  });

  group('模块护栏', () {
    const sourcePath = 'lib/player/framing_session.dart';

    test('不 import 中枢、不碰构建上下文；依赖方向单向', () {
      final source = File(sourcePath).readAsStringSync();
      final code = source
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');
      final imports = RegExp(
        "^import '([^']+)'",
        multiLine: true,
      ).allMatches(code).map((m) => m.group(1)!).toList();
      expect(imports, isNotEmpty, reason: sourcePath);
      for (final import in imports) {
        final allowed = import == 'dart:ui' ||
            import == '../annotation/framing_selection.dart' ||
            import == '../core/hit_target.dart' ||
            import == 'framing_session_state.dart' ||
            import == 'compare_framing_view.dart' ||
            import == 'editor_skeleton.dart' ||
            import == 'framing_stage.dart';
        expect(allowed, isTrue, reason: '取景域模块仅允许纯域/几何纯件依赖：$import');
      }
      expect(code.contains('BuildContext'), isFalse);
      expect(code.contains('MediaQuery'), isFalse);
    });

    test('播放页单向依赖本模块；本模块反向不 import 播放页', () {
      final source = File(sourcePath).readAsStringSync();
      expect(
        RegExp(r"^import .*player_page\.dart", multiLine: true).hasMatch(source),
        isFalse,
      );
      final page = File('lib/player/player_page.dart').readAsStringSync();
      expect(page.contains("import 'framing_session.dart'"), isTrue);
    });
  });
}
