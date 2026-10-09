import 'package:dance_learning_app/cast/cast_screen_awake.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_guard.dart';

/// 投屏期屏幕唤醒接缝的**计数语义**（票 #39，规格 #21）：与播放内核画面件
/// 那份唤醒同款——重复持有只真的拿一次，放开只在计数归零那一刻发生，一份
/// 都没持时的放开是空操作。
///
/// 断言落在这条接缝上（注入一个记录调用的 [toggle] 替身），不碰真平台通道：
/// 真机上「屏幕到底熄不熄」归真机验收（步骤见
/// `lib/cast/docs/real-device-acceptance.md`）。
void main() {
  late List<bool> toggles;
  late RefCountedCastScreenAwake awake;

  setUp(() {
    toggles = [];
    awake = RefCountedCastScreenAwake((on) async => toggles.add(on));
  });

  test('一份持有：拿 → 放开，各落到平台一次', () async {
    await awake.hold();
    expect(toggles, [true], reason: '拿到唤醒 = 屏幕常亮');

    await awake.release();
    expect(toggles, [true, false], reason: '放开 = 恢复系统行为');
  });

  test('重复持有只拿一次：两份持有只有一次「拿」', () async {
    await awake.hold();
    await awake.hold();
    await awake.hold();

    expect(toggles, [true], reason: '引用计数式：第二次以后的持有不再打平台');
  });

  test('计数归零才真的放开：还有一份持着时不放开', () async {
    await awake.hold();
    await awake.hold();

    await awake.release();
    expect(toggles, [true], reason: '还剩一份持有：屏幕仍要常亮（不打架）');

    await awake.release();
    expect(toggles, [true, false], reason: '最后一份放开才回系统行为');
  });

  test('没持有时放开是空操作：不欠账、也不把别人的唤醒关掉', () async {
    await awake.release();
    expect(toggles, isEmpty);

    await awake.hold();
    await awake.release();
    await awake.release();
    expect(toggles, [true, false], reason: '多余的放开不再打平台');
  });

  test('放开后可以再拿：计数不粘在零以外的状态上', () async {
    await awake.hold();
    await awake.release();
    await awake.hold();

    expect(toggles, [true, false, true]);
  });

  test('再确认只重复「开」：不动计数，也不是第二份持有', () async {
    await awake.hold();
    await awake.reassert();

    expect(toggles, [true, true], reason: '平台开关不是引用计数的：源画面件退场后要把「开」重新按一遍');
    expect(awake.count, 1, reason: '再确认不新增持有');

    await awake.release();
    expect(toggles, [true, true, false], reason: '放开仍只在计数归零那一刻');
  });

  test('没持有时再确认是空操作：不凭空把屏幕点亮', () async {
    await awake.reassert();
    expect(toggles, isEmpty);

    await awake.hold();
    await awake.release();
    await awake.reassert();
    expect(toggles, [true, false], reason: '放开之后不该再被点亮');
  });

  group('装配的结构护栏（谁在持、谁不打平台）', () {
    test('平台唤醒只有一条路：lib/ 里唯一 import wakelock_plus 的是那条真实现', () {
      final hits = libDartFilesWhere(
        (source) => codeLinesOf(source).contains('package:wakelock_plus/'),
      )..sort();

      expect(hits, [
        'lib/cast/wakelock_cast_screen_awake.dart',
      ], reason: '冒出第二条打平台的路：$hits（唤醒只经投屏这条接缝）');
    });

    test('只有投屏本地预览关掉画面件那一份唤醒，其余内核走缺省（非投屏态逐位不变）', () {
      final hits = libDartFilesWhere(
        (source) => codeLinesOf(source).contains('holdsScreenAwake:'),
      )..sort();

      expect(
        hits,
        ['lib/player/cast_preview.dart'],
        reason:
            '预览件再有第二份持有者，画面开关一开一关就会把投屏期常亮一并放掉；'
            '别的内核被改动则非投屏态的唤醒行为不再逐位不变：$hits',
      );
    });

    test('唤醒的持有者只有投屏运行域一处（进出各一处，不在三处各写一遍）', () {
      final holders = libDartFilesWhere(
        (source) => source.contains('castScreenAwakeProvider'),
        except: 'lib/cast/cast_screen_awake.dart',
      )..sort();

      expect(holders, [
        'lib/player/cast_run.dart',
      ], reason: '冒出第二个持有者：$holders（持有归投屏运行域，进出各一处）');
    });
  });
}
