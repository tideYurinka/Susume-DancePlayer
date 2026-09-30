import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/player/editor_entry.dart';
import 'package:dance_learning_app/player_session/player_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 编辑器入口编排域直测：不 pump widget，直接驱动
/// 域，断言它交出的外部可观察事实——入口门禁是否落待办、待办编排的提交/取消
/// 与画布准备、模式取值经唯一 owner 落定、收起与退出。
///
/// 模式取值仍归 [PlayerSessionModel]（单一 owner）；本域只收它并消费，测试为
/// 取得该 owner 建一个 [ProviderContainer]，域本身不注容器。
void main() {
  late ProviderContainer container;
  late PlayerSessionModel session;
  late EditorEntry entry;

  bool mounted = true;
  bool blocksWrite = false;
  bool takenOver = false;
  bool avSyncActive = false;
  bool cameraGranted = true;
  int cameraGateCalls = 0;
  AnnotationTimeline timeline = AnnotationTimeline.wholeVideo(Duration.zero);
  Duration? videoDuration;
  final resetCalls = <Duration>[];
  int clearSelectionCalls = 0;

  PlayerSession readSession() => container.read(playerSessionProvider);

  /// 把时间线摆成给定有效时长（整片区间）。
  void putTimeline({required Duration duration}) {
    timeline = AnnotationTimeline.wholeVideo(duration);
  }

  void build() {
    mounted = true;
    blocksWrite = false;
    takenOver = false;
    avSyncActive = false;
    cameraGranted = true;
    cameraGateCalls = 0;
    timeline = AnnotationTimeline.wholeVideo(Duration.zero);
    videoDuration = null;
    resetCalls.clear();
    clearSelectionCalls = 0;
    entry = EditorEntry(
      session: session,
      readSession: readSession,
      blocksWrite: () => blocksWrite,
      takenOver: () => takenOver,
      avSyncActive: () => avSyncActive,
      requestCameraPermission: () {
        cameraGateCalls++;
        return Future<bool>.value(cameraGranted);
      },
      readTimeline: () => timeline,
      readVideoDuration: () => videoDuration,
      resetTimeline: resetCalls.add,
      clearExclusiveSelections: () => clearSelectionCalls++,
      isMounted: () => mounted,
    );
  }

  /// 把模式值摆到 [mode]（观看态经复位；其余经唯一写路径 enter）。
  void setMode(PlayerSessionMode mode) {
    session.reset();
    if (mode != PlayerSessionMode.watching) session.enter(mode);
  }

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
    session = container.read(playerSessionProvider.notifier);
    build();
  });

  group('入口请求（宿主单击画面）', () {
    test('观看态请求：落待办至编辑取值', () {
      entry.requestEntry();
      expect(readSession().pendingEntry?.target, PlayerSessionMode.editing);
      expect(readSession().mode, PlayerSessionMode.watching);
    });

    test('对比-播放态请求：落待办至对比-控制层', () {
      setMode(PlayerSessionMode.compareWatching);
      entry.requestEntry();
      expect(
        readSession().pendingEntry?.target,
        PlayerSessionMode.compareEditing,
      );
    });

    test('控制层已展开：不落待办', () {
      setMode(PlayerSessionMode.editing);
      entry.requestEntry();
      expect(readSession().pendingEntry, isNull);
    });

    test('未挂载：不落待办', () {
      mounted = false;
      entry.requestEntry();
      expect(readSession().pendingEntry, isNull);
    });

    test('装载门挡下：不落待办', () {
      blocksWrite = true;
      entry.requestEntry();
      expect(readSession().pendingEntry, isNull);
    });

    test('录制接管期：不落待办', () {
      takenOver = true;
      entry.requestEntry();
      expect(readSession().pendingEntry, isNull);
    });
  });

  group('待办编排（唯一提交入口）', () {
    test('无待办：不编排、模式值一位不动', () async {
      await entry.orchestratePendingEntry();
      expect(readSession().mode, PlayerSessionMode.watching);
      expect(resetCalls, isEmpty);
      expect(clearSelectionCalls, 0);
    });

    test('观看态编辑待办：画布准备后提交——清排他选中、模式落编辑', () async {
      session.requestEntry(PlayerSessionMode.editing);
      putTimeline(duration: const Duration(minutes: 3));
      await entry.orchestratePendingEntry();

      expect(clearSelectionCalls, 1, reason: '进入编辑面即清其余选中');
      expect(readSession().mode, PlayerSessionMode.editing);
      expect(readSession().pendingEntry, isNull, reason: '提交后待办清空');
    });

    test('画布兜底：时间线零时长且引擎时长就绪 → 以引擎时长重建', () async {
      session.requestEntry(PlayerSessionMode.editing);
      videoDuration = const Duration(minutes: 3);
      await entry.orchestratePendingEntry();

      expect(resetCalls, [const Duration(minutes: 3)]);
      expect(readSession().mode, PlayerSessionMode.editing);
    });

    test('画布兜底：时间线已有有效时长 → 不重建，仍清排他选中', () async {
      session.requestEntry(PlayerSessionMode.editing);
      putTimeline(duration: const Duration(minutes: 2));
      videoDuration = const Duration(minutes: 3);
      await entry.orchestratePendingEntry();

      expect(resetCalls, isEmpty);
      expect(clearSelectionCalls, 1);
    });

    test('控制层已展开：走画布准备快路径后提交', () async {
      setMode(PlayerSessionMode.beatCorrectionStandby);
      session.requestEntry(PlayerSessionMode.editing);
      await entry.orchestratePendingEntry();

      expect(clearSelectionCalls, 1);
      expect(readSession().mode, PlayerSessionMode.editing);
      expect(readSession().pendingEntry, isNull);
    });

    test('音画同步校准会话中：对比类目标取消待办、模式值一位不动', () async {
      setMode(PlayerSessionMode.editing);
      session.requestEntry(PlayerSessionMode.compareWatching);
      avSyncActive = true;
      await entry.orchestratePendingEntry();

      expect(readSession().mode, PlayerSessionMode.editing);
      expect(readSession().pendingEntry, isNull);
      expect(cameraGateCalls, 0, reason: '取消先于相机门');
    });

    test('音画同步校准会话中：编辑类目标照常提交', () async {
      session.requestEntry(PlayerSessionMode.editing);
      avSyncActive = true;
      await entry.orchestratePendingEntry();

      expect(readSession().mode, PlayerSessionMode.editing);
    });

    test('录制接管期：单画面取景目标取消待办、模式值一位不动', () async {
      setMode(PlayerSessionMode.editing);
      session.requestEntry(PlayerSessionMode.framing);
      takenOver = true;
      await entry.orchestratePendingEntry();
      expect(readSession().pendingEntry, isNull);
      expect(readSession().mode, PlayerSessionMode.editing);
    });

    test('录制接管期：对比类目标取消待办、模式值一位不动', () async {
      setMode(PlayerSessionMode.editing);
      session.requestEntry(PlayerSessionMode.compareFraming);
      takenOver = true;
      await entry.orchestratePendingEntry();

      expect(readSession().mode, PlayerSessionMode.editing);
      expect(readSession().pendingEntry, isNull);
    });

    test('录制接管期：编辑类目标照常提交', () async {
      session.requestEntry(PlayerSessionMode.editing);
      takenOver = true;
      await entry.orchestratePendingEntry();

      expect(readSession().mode, PlayerSessionMode.editing);
    });

    test('对比-播放态待办：先问相机授权，放行后提交进入对比态', () async {
      session.requestEntry(PlayerSessionMode.compareWatching);
      await entry.orchestratePendingEntry();

      expect(cameraGateCalls, 1);
      expect(readSession().mode, PlayerSessionMode.compareWatching);
      expect(readSession().pendingEntry, isNull);
    });

    test('相机授权被拒：取消待办、模式值一位不动', () async {
      session.requestEntry(PlayerSessionMode.compareWatching);
      cameraGranted = false;
      await entry.orchestratePendingEntry();

      expect(cameraGateCalls, 1);
      expect(readSession().mode, PlayerSessionMode.watching);
      expect(readSession().pendingEntry, isNull);
    });

    test('编辑类目标不经过相机门', () async {
      session.requestEntry(PlayerSessionMode.editing);
      await entry.orchestratePendingEntry();
      expect(cameraGateCalls, 0);
    });

    test('相机门返回时待办已被取消：不提交、模式值一位不动', () async {
      session.requestEntry(PlayerSessionMode.compareWatching);
      final pending = entry.orchestratePendingEntry();
      session.cancelPendingEntry();
      await pending;

      expect(readSession().mode, PlayerSessionMode.watching);
    });

    test('相机门返回时页面已卸载：不提交', () async {
      session.requestEntry(PlayerSessionMode.compareWatching);
      final pending = entry.orchestratePendingEntry();
      mounted = false;
      await pending;

      expect(readSession().mode, PlayerSessionMode.watching);
      expect(
        readSession().pendingEntry?.target,
        PlayerSessionMode.compareWatching,
      );
    });
  });

  group('收起与退出', () {
    test('收起控制层：模式值经 owner 回观看态', () {
      setMode(PlayerSessionMode.editing);
      entry.collapse();
      expect(readSession().mode, PlayerSessionMode.watching);
      expect(readSession().controlOpen, isFalse);
    });

    test('已在观看态收起：幂等 no-op', () {
      entry.collapse();
      expect(readSession().mode, PlayerSessionMode.watching);
    });

    test('未挂载收起：模式值一位不动', () {
      setMode(PlayerSessionMode.editing);
      mounted = false;
      entry.collapse();
      expect(readSession().mode, PlayerSessionMode.editing);
    });

    test('退出对比-控制层：回观看态', () {
      setMode(PlayerSessionMode.compareEditing);
      entry.exitCompare();
      expect(readSession().mode, PlayerSessionMode.watching);
    });

    test('非对比态退出：幂等 no-op', () {
      setMode(PlayerSessionMode.editing);
      entry.exitCompare();
      expect(readSession().mode, PlayerSessionMode.editing);
    });

    test('退出对比取景调节态：回对比-控制层', () {
      setMode(PlayerSessionMode.compareFraming);
      entry.exitFraming();
      expect(readSession().mode, PlayerSessionMode.compareEditing);
    });

    test('退出单画面取景调节态：回编辑态（退出三同路同分支）', () {
      setMode(PlayerSessionMode.framing);
      entry.exitFraming();
      expect(readSession().mode, PlayerSessionMode.editing);
    });
  });
}
