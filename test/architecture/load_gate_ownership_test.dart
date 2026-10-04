import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_guard.dart';

/// 「装载未完成」门的开合归属护栏（票 #17）：
///
/// 门的开合由**打开恢复自己持有**——建立序列前置位、打开恢复（标注对象集
/// 上时间线那一段）落定即落位。页面不再碰开合：它只读门事实（置灰、可点、
/// 弹「正在装载」）。冒出第二个开合调用点就红——置位与落位会被拆成两处，
/// 「门已经落下、对象集还没上来」的窗口随之回来，而且后段的命名框 / 镜像
/// 询问 / 署名解析又会把门拖住。
void main() {
  test('门的开合只有打开恢复一处调用点，其余只读门事实', () {
    final hits = libDartFilesWhere(
      (source) =>
          codeLinesOf(source).contains('loadGateActiveProvider.notifier'),
    )..sort();

    expect(hits, [
      'lib/player/open_restore.dart',
    ], reason: '冒出第二个开合调用点：$hits（开合归打开恢复，页面只读门事实）');
  });
}
