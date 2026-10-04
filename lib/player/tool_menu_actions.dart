/// 工具菜单动作编排（「添加」与「自动分段」两张菜单）。
///
/// 菜单打开时读一次现势事实，并把**条目标识 → 动作闭包**的映射一次性装配
/// 好；动作的「提交 → applied? → 停播 → 找新产物 → 记角标 → 特有收尾」次序
/// 全在本模块，control_layer 只做数据驱动的 `PopupMenuItem` 渲染与点击派发。
///
/// 仿 `load_gate.dart` 先例持 [WidgetRef]：只在菜单打开/动作执行的同步上下文
/// 内读写 provider。
library;

import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../annotation/annotation_timeline.dart';
import '../beat_track_state/beat_track_state.dart'
    show BeatTrackPhase, BeatTrackState, beatTrackStateProvider;
import '../core/playback/playback_engine_providers.dart'
    show playbackEngineProvider, playbackPositionProvider;
import '../help/content_registry.dart'
    show
        badgeHalfBeatUnitId,
        badgeLocalMirrorUnitId,
        badgeSegmentFlagUnitId,
        badgeThreeFingerJumpUnitId;
import '../help/guide_state.dart' show guideSessionProvider;
import 'annotation_edit.dart'
    show
        AddHalfBeatLine,
        AddLocalMirrorFragment,
        ClearSegmentLines,
        InsertNote,
        ToggleSegmentFlag;
import 'annotation_editor.dart';
import 'load_gate.dart' show loadGateActiveProvider;
import 'mirror.dart' show MirrorController;
import 'notice.dart' show NoticeId, noticeTriggerProvider;
import 'note_editor.dart' show noteTextEditorTargetProvider;
import 'tool_slots.dart';
import 'track_band_session.dart' show TrackBandSession;
import 'track_time.dart' show kMinZoomVisibleDuration;

/// 预览线（播放位置）是否落在有效区间内（开区间）——底排门事实与「添加」
/// 菜单的门事实共用这一处判据。
bool previewLineInBounds(Duration position, AnnotationTimeline timeline) =>
    position > timeline.rangeStart && position < timeline.rangeEnd;

/// 预览线位置：位置流现值，未报位时取引擎现值。
Duration _previewPosition(WidgetRef ref) {
  final engine = ref.read(playbackEngineProvider);
  return ref.read(playbackPositionProvider).value ?? engine.position;
}

/// 「添加」菜单此刻成立的门事实（条目判定与槽面同源）。
ToolFacts addMenuFacts(WidgetRef ref) {
  final timeline = ref.read(annotationTimelineProvider);
  final position = _previewPosition(ref);
  return ToolFacts(
    loading: ref.read(loadGateActiveProvider),
    locked: ref.read(layoutLockedProvider),
    previewOutOfBounds: !previewLineInBounds(position, timeline),
    selectedSegmentLine: ref.read(selectedSegmentLineIndexProvider) != null,
  );
}

/// 「标记分段线」条目文案随选中线的 flag 现态二选一：未标记「标记分段线」、
/// 已标记「取消标记」；其余条目用表内声明的标签。
String addEntryLabel(WidgetRef ref, AddEntry entry) {
  if (entry.id != AddEntryId.segmentFlag) return entry.label;
  final line = ref.read(selectedSegmentLineIndexProvider);
  if (line == null) return entry.label;
  final lines = ref.read(annotationTimelineProvider).segmentLines;
  return lines[line].flagged ? '取消标记' : entry.label;
}

/// 「添加」菜单条目动作（条目标识 → 动作闭包；动作真正发生时按序提交、
/// 停播、记新产物角标并做各条目特有收尾）。
///
/// - 半拍线：在预览线处提交 [AddHalfBeatLine]（落点解析收模块）；落成后收
///   视野到刚落的线附近。
/// - 标记分段线：翻转选中线的 flag；只有「做上标记」才算第一次标记（取消
///   标记不触达、不消耗），同时触达三指跳转单元（同一次动作）。
/// - 局部镜像片段：提交 [AddLocalMirrorFragment]；创建真的成立时按「创建即
///   生效」自动打开局部镜像总开关并写盘。
/// - 备注贴纸：预览线已落在既有备注窗内 → 转开那条备注的编辑器（不提交）；
///   否则新建 [InsertNote]，落成后弹新备注的编辑器。
Map<AddEntryId, VoidCallback> addEntryActions(
  WidgetRef ref, {
  required MirrorController mirror,
  required TrackBandSession session,
}) {
  final engine = ref.read(playbackEngineProvider);
  final position = _previewPosition(ref);
  // 提交前的备注快照（「备注贴纸」条目建出备注后取新增者弹编辑器）。
  final notesBefore = ref.read(noteStickersProvider);
  // 选中索引带外校验（越界/错位即 null）。「标记分段线」条目的作用对象事实
  // 与动作都取这里。
  final selectedLine = ref.read(selectedSegmentLineIndexProvider);

  /// 添加即暂停：动作真正发生后停播——在播才调（与「帧步进先暂停再 seek」
  /// 同款守卫），已暂停时不产生任何播放动作。只改播放态：不 seek、不自动
  /// 续播、不弹提示。
  void pauseAfterCommit() {
    if (engine.isPlaying) engine.pause();
  }

  return {
    AddEntryId.halfBeat: () {
      final before = ref.read(annotationTimelineProvider).halfBeatLines;
      final outcome = ref
          .read(annotationEditorProvider)
          .submit(AddHalfBeatLine(at: position));
      // 落点越界 / 同位既有的线 → EditNoop：没落成，不触达不消耗、也不停播。
      if (!outcome.applied) return;
      pauseAfterCommit();
      final index = indexOfNewItem(
        before,
        ref.read(annotationTimelineProvider).halfBeatLines,
        (a, b) => a.position == b.position,
      );
      if (index == null) return;
      recordGuideArtifact(ref, badgeHalfBeatUnitId, index);
      // 落成即收视野：每次落成都把可视窗口收拢到刚落的线附近——可视宽取
      // 缩放条拉满对应的最短窗口。
      final landed = ref
          .read(annotationTimelineProvider)
          .halfBeatLines[index]
          .position;
      session.collapseAround(landed, span: kMinZoomVisibleDuration);
    },
    AddEntryId.segmentFlag: () {
      // 菜单开着期间选中被清除/越界时静默无动作，不带外提交。
      final line = selectedLine;
      if (line == null) return;
      final outcome = ref
          .read(annotationEditorProvider)
          .submit(ToggleSegmentFlag(index: line));
      if (!outcome.applied) return;
      // 标记真实发生（做上或取消）即停播。
      pauseAfterCommit();
      if (!ref.read(annotationTimelineProvider).segmentLines[line].flagged) {
        return;
      }
      recordGuideArtifact(ref, badgeSegmentFlagUnitId, line);
      // 三指跳转单元与「标记分段线」触发时点相同：都挂在标记动作真正做成的
      // 这一处产物序号上。
      recordGuideArtifact(ref, badgeThreeFingerJumpUnitId, line);
    },
    AddEntryId.localMirror: () {
      final before = ref.read(localMirrorFragmentsProvider);
      final outcome = ref
          .read(annotationEditorProvider)
          .submit(AddLocalMirrorFragment(at: position));
      if (!outcome.applied) return;
      mirror.enableLocalMirrorForNewFragment();
      // 创建与开关翻转都落定后才停播。
      pauseAfterCommit();
      final index = indexOfNewItem(
        before,
        ref.read(localMirrorFragmentsProvider),
        (a, b) => a.startMs == b.startMs && a.endMs == b.endMs,
      );
      if (index == null) return;
      recordGuideArtifact(ref, badgeLocalMirrorUnitId, index);
    },
    AddEntryId.noteSticker: () {
      // 落点已占转编辑：按预览线（原始请求位置）读既有只读备注列表路由——
      // 半开窗 [startMs, endMs) 含预览线即打开那条既有备注的编辑器，不提交
      // 创建、不入史。
      final at = position.inMilliseconds;
      final occupied = notesBefore.where(
        (n) => at >= n.startMs && at < n.endMs,
      );
      if (occupied.isNotEmpty) {
        pauseAfterCommit();
        ref
            .read(noteTextEditorTargetProvider.notifier)
            .open(occupied.first.startMs);
        return;
      }
      final outcome = ref
          .read(annotationEditorProvider)
          .submit(InsertNote(at: position));
      // 新建即弹编辑器：以建出备注的起点为编辑目标；被门禁拒绝或落点不成立
      // （EditNoop）时无备注产生、不弹。
      if (!outcome.applied) return;
      pauseAfterCommit();
      final notes = ref.read(noteStickersProvider);
      final index = indexOfNewItem(
        notesBefore,
        notes,
        (a, b) => a.startMs == b.startMs,
      );
      if (index == null) return;
      ref
          .read(noteTextEditorTargetProvider.notifier)
          .open(notes[index].startMs);
    },
  };
}

/// 「自动分段」菜单条目动作：清空分段与两档配额提交共用一节拍轨快照。
Map<AutoSegmentEntryId, VoidCallback> autoSegmentEntryActions(WidgetRef ref) {
  final track = ref.read(beatTrackStateProvider);
  final editor = ref.read(annotationEditorProvider);

  void submitTier(int fullIntervalsPerSegment) {
    final grid = track.grid;
    if (grid == null || grid.beats.isEmpty) {
      showBeatReadinessPrompt(ref, track);
      return;
    }
    editor.submitAutoSegment(
      grid,
      fullIntervalsPerSegment: fullIntervalsPerSegment,
    );
  }

  return {
    AutoSegmentEntryId.clearSegments: () =>
        editor.submit(const ClearSegmentLines()),
    AutoSegmentEntryId.fourBeats: () => submitTier(4),
    AutoSegmentEntryId.eightBeats: () => submitTier(8),
  };
}

/// 「自动分段」菜单条目文案（声明表不存文案，三档固定）。
String autoSegmentEntryLabel(AutoSegmentEntry entry) => switch (entry.id) {
  AutoSegmentEntryId.clearSegments => '清空分段',
  AutoSegmentEntryId.fourBeats => '4 个八拍/段',
  AutoSegmentEntryId.eightBeats => '8 个八拍/段',
};

/// 节拍未就绪的原因提示（分段 / 自动分段两槽共用的 explain 语义）：按节拍轨
/// 状态弹「节拍分析中…」（占位）或「无节拍数据」（异常）；就绪态无可解释
/// （判定表不会在就绪时进入 explain）。
///
/// 【白名单】这是异常态裸直判的两支许可 UI 文案之一处（另一处在
/// `track_band.dart` 异常态小标识）——条款把状态值只留给这两支文案与写读面；
/// 其余可用性判读一律走两个谓词。
void showBeatReadinessPrompt(WidgetRef ref, BeatTrackState track) {
  switch (track.phase) {
    case BeatTrackPhase.placeholder:
      ref.read(noticeTriggerProvider(NoticeId.beatAnalyzing).notifier).show();
    case BeatTrackPhase.error:
      ref.read(noticeTriggerProvider(NoticeId.beatNoData).notifier).show();
    case BeatTrackPhase.ready:
      break;
  }
}

/// 本次新建后新产物在写后表里的序号（按 [sameItem] 判定同一条；查无 = null）
/// ——「添加」菜单四条角标的「新产物是谁」共用这一处算法（半拍线按位置、
/// 镜像片段按区间、备注按起点各自给出判等）。
int? indexOfNewItem<T>(
  List<T> before,
  List<T> after,
  bool Function(T before, T after) sameItem,
) {
  for (var i = 0; i < after.length; i++) {
    if (!before.any((item) => sameItem(item, after[i]))) return i;
  }
  return null;
}

/// 菜单类角标「记新产物序号 + 记触达」的唯一实现：序号只活在本会话，不落盘；
/// 触达幂等。「分段」槽落线成功与「添加」菜单条目动作共用本函数。
void recordGuideArtifact(WidgetRef ref, String unitId, int index) {
  ref.read(guideSessionProvider.notifier).recordArtifact(unitId, index);
  ref.read(guideSessionProvider.notifier).trigger(unitId);
}
