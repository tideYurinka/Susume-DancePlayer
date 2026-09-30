/// 录制期播放接管域直测（新增 seam 二）。
///
/// 不注容器、不 pump widget：直接以闭包假件驱动 [RecordingPlaybackTakeover]，
/// 断言它的接口事实——接管事实、三个播放面纪律的施加/复位、次序不变量、
/// 退出幂等、scrub 会话收尾与播放态同步。录制域与引擎/seek 域的行为不在此
/// 断言（各归原域套件）。
library;

import 'package:dance_learning_app/player/recording_playback_takeover.dart';
import 'package:flutter_test/flutter_test.dart';

/// 闭包假件：记录每次调用与调用次序，并持有可读的纪律状态。
class _FakePlaybackSide {
  final List<String> calls = <String>[];

  bool marker = false;

  int disableSegmentLoopCount = 0;
  int restoreSegmentLoopCount = 0;
  int endScrubCount = 0;
  int interruptDelayedCount = 0;
  int stopRecordingCount = 0;

  void disableSegmentLoop() {
    calls.add('disableLoop');
    disableSegmentLoopCount++;
  }

  void restoreSegmentLoop() {
    calls.add('restoreLoop');
    restoreSegmentLoopCount++;
  }

  void setRecordingMarker(bool active) {
    calls.add('marker:$active');
    marker = active;
  }

  Future<void> endScrubSession() async {
    calls.add('endScrub');
    endScrubCount++;
  }

  void interruptPendingDelayedPlay() {
    calls.add('interruptDelayed');
    interruptDelayedCount++;
  }

  Future<void> stopRecordingSession() async {
    calls.add('stopRecording');
    stopRecordingCount++;
  }

  RecordingPlaybackTakeover build() => RecordingPlaybackTakeover(
    disableRecordingLoop: disableSegmentLoop,
    restoreLearningSegmentLoop: restoreSegmentLoop,
    setRecordingMarker: setRecordingMarker,
    endScrubSession: endScrubSession,
    interruptPendingDelayedPlay: interruptPendingDelayedPlay,
    stopRecordingSession: stopRecordingSession,
  );
}

void main() {
  late _FakePlaybackSide side;
  late RecordingPlaybackTakeover takeover;

  setUp(() {
    side = _FakePlaybackSide();
    takeover = side.build();
  });

  group('进入录制：三个播放面纪律就位', () {
    test('准备期：接管事实就位、录制态标记就位、撤在途延迟起播；循环不动作', () {
      takeover.engage(suppressLoop: false);

      expect(takeover.active, isTrue, reason: '准备期同样处于接管期（录制期拒绝 scrub 的判据）');
      expect(side.marker, isTrue, reason: '录制态标记就位');
      expect(side.interruptDelayedCount, 1, reason: '播放态同步：撤掉在途的延迟起播');
      expect(
        side.disableSegmentLoopCount,
        0,
        reason: '准备期只落标记与收挂账，循环停用属录制本体',
      );
    });

    test('录制本体：循环被停用', () {
      takeover.engage(suppressLoop: true);

      expect(takeover.active, isTrue);
      expect(side.marker, isTrue);
      expect(side.disableSegmentLoopCount, 1, reason: '录制期循环停用');
    });

    test('准备期推进到录制本体：同一次会话里循环被停用一次', () {
      takeover.engage(suppressLoop: false);
      expect(side.disableSegmentLoopCount, 0);

      takeover.engage(suppressLoop: true);
      expect(takeover.active, isTrue);
      expect(side.disableSegmentLoopCount, 1, reason: '相位推进不重开接管、只补上循环停用');
    });

    test('进入次序不变量：录制态标记 → 撤延迟挂账 → 循环停用', () {
      takeover.engage(suppressLoop: true);

      expect(side.calls, ['marker:true', 'interruptDelayed', 'disableLoop']);
    });
  });

  group('退出录制：三项各自复位且幂等', () {
    test('退出：接管事实复位、标记复位、学段循环同步复位（次序同此）', () {
      takeover.engage(suppressLoop: true);
      side.calls.clear();

      takeover.disengage();

      expect(takeover.active, isFalse, reason: 'scrub 拒绝判据复位');
      expect(side.marker, isFalse, reason: '录制态标记复位');
      expect(side.restoreSegmentLoopCount, 1, reason: '学段循环同步复位');
      expect(
        side.calls,
        ['marker:false', 'restoreLoop'],
        reason: '次序不变量：录制态标记复位先于学段循环同步复位',
      );
    });

    test('退出幂等：未处于接管期时为 no-op，不施加第二遍复位', () {
      takeover.disengage();
      expect(takeover.active, isFalse);
      expect(side.calls, isEmpty, reason: '从未接管就不该复位任何东西');

      takeover.engage(suppressLoop: true);
      takeover.disengage();
      final afterFirst = side.calls.length;
      takeover.disengage();

      expect(
        side.calls.length,
        afterFirst,
        reason: '重复退出不得再写标记或再走一次学段循环同步',
      );
      expect(side.restoreSegmentLoopCount, 1, reason: '学段循环同步在北向次序上只有一条路径');
    });

    test('准备期直接取消：循环未被停用也会走一次作用域复位（沿既有口径）', () {
      takeover.engage(suppressLoop: false);
      takeover.disengage();

      expect(side.disableSegmentLoopCount, 0);
      expect(side.restoreSegmentLoopCount, 1);
      expect(takeover.active, isFalse);
    });
  });

  group('scrub 会话收尾（接管的第一面）', () {
    test('起录前的 scrub 会话收尾走本域、不改变接管事实', () async {
      await takeover.endScrubBeforeStart();

      expect(side.endScrubCount, 1, reason: '在途定格预览在录制会话起步之前收口');
      expect(takeover.active, isFalse, reason: '收尾本身不进入接管期');
      expect(side.calls, ['endScrub']);
    });

    test('起录接管次序：scrub 会话收尾早于进入接管（收口先于录制会话起步）', () async {
      await takeover.endScrubBeforeStart();
      takeover.engage(suppressLoop: true);

      expect(
        side.calls,
        ['endScrub', 'marker:true', 'interruptDelayed', 'disableLoop'],
        reason: '收尾必须先于接管：否则 scrub 的收尾会在起录之后回写播放态与位置',
      );
    });
  });

  group('播放态同步', () {
    test('未接管：播放动作不被消费，不产生停录请求', () async {
      final consumed = await takeover.handlePlaybackToggle();

      expect(consumed, isFalse);
      expect(side.stopRecordingCount, 0);
    });

    test('接管期（含准备期）：播放动作转成停录请求并被消费', () async {
      takeover.engage(suppressLoop: false);

      final consumed = await takeover.handlePlaybackToggle();

      expect(consumed, isTrue);
      expect(side.stopRecordingCount, 1, reason: '与录制钮同一个动作：停录/取消');
    });

    test('退出接管后播放动作回到普通语义', () async {
      takeover.engage(suppressLoop: true);
      takeover.disengage();

      final consumed = await takeover.handlePlaybackToggle();

      expect(consumed, isFalse);
      expect(side.stopRecordingCount, 0);
    });
  });
}
