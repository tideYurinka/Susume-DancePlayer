import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../annotation/dancer_roster.dart';
import '../persistence/document_read_outcome.dart';
import '../persistence/marker_document.dart';
import '../persistence/video_document_store.dart';
import 'notice.dart' show NoticeId, noticeTriggerProvider;

/// 名册直写控制器注入点（应用级单实例，按视频由 [open_restore] 的打开
/// 流程经 [DancerRosterController.startForVideo] 换接协调器并读回名册）。
final dancerRosterControllerProvider = Provider<DancerRosterController>((ref) {
  final controller = DancerRosterController(
    onWriteRejected: () => ref
        .read(noticeTriggerProvider(NoticeId.documentReadOnly).notifier)
        .show(),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

/// 名册只读面：点名着色的取色源（点名渲染时按当前名册
/// 解析，文本保存不经名册）——**直写控制器现值的活投影**：控制器一通知
/// 就整体替换（文件序，已按名字唯一），名册的增 / 删 / 改色因此对既有
/// 备注实时反映（「点名语法」）。本 provider 不提供写
/// 入口——名册的写入者只有直写控制器。
final dancerRosterProvider =
    NotifierProvider<DancerRosterView, List<DancerRosterEntry>>(
      DancerRosterView.new,
    );

class DancerRosterView extends Notifier<List<DancerRosterEntry>> {
  @override
  List<DancerRosterEntry> build() {
    final controller = ref.watch(dancerRosterControllerProvider);
    void sync() => state = controller.roster;
    controller.addListener(sync);
    ref.onDispose(() => controller.removeListener(sync));
    return controller.roster;
  }
}

/// 舞者名册直写控制器：名册增 / 删 / 改色的持久化执行端。
///
/// **直写**（与歌曲署名编辑同侧）：不经标注编辑模块、
/// 不入撤销史、不受锁定分段与内容锁影响；整表补写、绝对终值、最新
/// 优先；只触碰 markers 的 `roster` 段，不碰 `notes` / `beat` /
/// `corrections` / `annotations`。名册按视频关联、不跨视频。
///
/// - [restore]：打开视频后读回名册现值（缺 markers / 缺 `roster` 段 =
///   空名册，不崩）；读入即按名字去重合并（后出现的颜色胜），历史重复
///   项在显示层先行收敛。
/// - [addDancer] / [removeDancer] / [changeColor]：内存态先生效并通知，
///   随后经协调器整表补写落盘；写失败静默（内存态已更新，下次打开以
///   文件为准）。同名合并：增已有名字不产生重复条目、颜色最新优先；
///   任何一次整表补写都顺带修复表内历史重复项。
///
/// 写法照歌曲署名控制器（`song_signature.dart`）先例：控制器不持有
/// 索引所有权，协调器缺位的环境（未接持久化）只更新内存态。
class DancerRosterController extends ChangeNotifier {
  DancerRosterController({this.coordinator, this.onWriteRejected});

  /// 按视频文档协调器（名册所在视频的 markers 读写入口）。null = 未接
  /// 协调器的环境只更新内存态（测试环境零增量，先例同
  /// 歌曲署名控制器的 `coordinatorFor` 缺位）。
  final VideoDocumentCoordinator? coordinator;

  /// markers 写回被拒（只读文档 / 读与写之间换成只读文件）的呈现缝：
  /// 装配处接到既有短暂提示通道。null = 无提示环境（控制器直测）。
  final void Function()? onWriteRejected;

  List<DancerRosterEntry> _roster = const [];
  VideoDocumentCoordinator? _activeCoordinator;
  bool _disposed = false;

  /// 生效协调器：打开视频接线（[startForVideo]）后以新视频为准，否则
  /// 回落构造注入值。
  VideoDocumentCoordinator? get _coordinator =>
      _activeCoordinator ?? coordinator;

  /// 当前名册（按名字唯一、文件序）。
  List<DancerRosterEntry> get roster => List.unmodifiable(_roster);

  /// 打开视频后调用：读回名册现值（见类文档）。文件缺失/损坏 = 空名
  /// 册，不抛错、不阻塞播放（与歌曲署名控制器同用 `readMarkersOrNull`
  /// 判定）。读入即按名字去重合并（后出现的颜色胜）：内存视图先行收敛
  /// 历史重复项，文件侧在下次整表补写时修复。
  Future<void> restore() async {
    final coordinator = _coordinator;
    if (coordinator == null || _disposed) return;
    try {
      final markers = await coordinator.readMarkersOrNull();
      if (markers == null || _disposed) return;
      _roster = normalizeRoster(markers.roster);
      notifyListeners();
    } on Object {
      // markers 不可读：保持空名册，不阻塞播放。
    }
  }

  /// 打开新视频：换接该视频协调器、名册复位为空（上一
  /// 视频的名册不串入），随后读回本视频 markers 的名册现值（缺 markers /
  /// 缺 `roster` 段 = 空名册，不崩）。null 协调器 = 只复位内存态。
  Future<void> startForVideo(VideoDocumentCoordinator? coordinator) async {
    if (_disposed) return;
    _activeCoordinator = coordinator;
    _roster = const [];
    notifyListeners();
    await restore();
  }

  /// 增（同名合并）：已有名字只更新其代表色，不产生重复条目。
  Future<void> addDancer(String name, {required int color}) async {
    final clean = name.trim();
    if (clean.isEmpty || _disposed) return;
    await _commit(
      (current) => [...current, DancerRosterEntry(name: clean, color: color)],
    );
  }

  /// 删：无此名字时为静默 no-op（名字按 [addDancer] 同一口径净化后匹配）。
  Future<void> removeDancer(String name) async {
    final clean = name.trim();
    if (_disposed) return;
    await _commit(
      (current) => [
        for (final entry in current)
          if (entry.name != clean) entry,
      ],
    );
  }

  /// 改色：无此名字时为静默 no-op（名字按 [addDancer] 同一口径净化后
  /// 匹配）；整表补写顺带修复历史重复项。
  Future<void> changeColor(String name, int color) async {
    final clean = name.trim();
    if (_disposed) return;
    await _commit(
      (current) => [
        for (final entry in current)
          if (entry.name == clean) entry.withColor(color) else entry,
      ],
    );
  }

  /// 直写收口：内存态先生效并通知，再整表补写 `roster` 段（见类文档）。
  /// 表无变化时跳写（协调器净变化判定兜底）。此处与 [restore] 各自去重
  /// 是刻意的：内存表以增入的新条目合并为准（与文件侧 `withRoster` 的
  /// 规范形一致），两层规范形幂等、不会互相打架。
  ///
  /// 落盘串行化：UI 快速连续操作会并发调用本入口，整表补写
  /// 经 `_pending` 链排队——在途写完成前下一次只入队，后写者携带的是
  /// 自己提交时的内存终值且后落盘，「整表补写、最新优先」不被交错的
  /// 在途写打破。
  Future<void> _commit(
    List<DancerRosterEntry> Function(List<DancerRosterEntry> current) mutate,
  ) async {
    final next = normalizeRoster(mutate(_roster));
    if (listEquals(next, _roster)) return;
    _roster = next;
    notifyListeners();
    final pending = _pending;
    _pending = _write(next);
    await pending;
    await _pending;
  }

  Future<void> _pending = Future<void>.value();

  Future<void> _write(List<DancerRosterEntry> next) async {
    final coordinator = _coordinator;
    if (coordinator == null || _disposed) return;
    try {
      final outcome = await coordinator.readMarkersOutcome();
      if (outcome is DocumentReadOnly<MarkersDocument>) {
        onWriteRejected?.call();
        return;
      }
      if (outcome is! WritableDocumentReadOutcome<MarkersDocument>) return;
      final result = await outcome.write(
        (context) => context.document.withRoster(next),
      );
      if (result is DocumentWriteRejected<MarkersDocument>) {
        onWriteRejected?.call();
      }
    } on Object {
      // 写盘失败静默：内存态已更新，下次打开以文件为准。
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
