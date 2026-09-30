import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../beat_track_state/beat_track_state.dart' show beatGridProvider;
import '../core/beat_grid.dart';
import '../core/private_json.dart';
import 'load_table.dart' show loadPreferenceDefaults;

/// 设备级「预备拍数」三项（`global_private.json` 的
/// `prepBeats` 键）：延迟播放 / 录制准备 / 循环前导。一次设置对所有舞
/// 生效，随整机备份走（`global_private.json` 整份搬运）、不随分享包或
/// 组员方案外传。
class PrepBeats {
  const PrepBeats({
    this.delayedPlay = kDelayedPlayPrepBeatsDefault,
    this.recording = kRecordingPrepBeatsDefault,
    this.loopLead = kLoopLeadPrepBeatsDefault,
  });

  /// 延迟播放预备拍数（2/4/8，默认 4）。
  final int delayedPlay;

  /// 录制准备预备拍数（2/4/8，默认 8）。
  final int recording;

  /// 循环前导拍档（0/2/4/8，默认 4；0 = 不前导）。
  final int loopLead;

  /// 复制并替换部分字段（缺省 = 保持现值）。
  PrepBeats withFields({int? delayedPlay, int? recording, int? loopLead}) =>
      PrepBeats(
        delayedPlay: delayedPlay ?? this.delayedPlay,
        recording: recording ?? this.recording,
        loopLead: loopLead ?? this.loopLead,
      );

  /// 从私密 JSON 键值解码：键缺失/形状不对 → 出厂默认；字段非法值逐字段
  /// 回落各自默认。
  static PrepBeats fromJson(Object? raw) {
    if (raw is! Map) return const PrepBeats();
    return PrepBeats(
      delayedPlay: decodePrepBeatsTier(raw['delayedPlay'], kPrepBeatsTiers,
          kDelayedPlayPrepBeatsDefault),
      recording: decodePrepBeatsTier(
          raw['recording'], kPrepBeatsTiers, kRecordingPrepBeatsDefault),
      loopLead: decodePrepBeatsTier(raw['loopLead'], kLoopLeadPrepBeatsTiers,
          kLoopLeadPrepBeatsDefault),
    );
  }

  Map<String, dynamic> toJson() => {
        'delayedPlay': delayedPlay,
        'recording': recording,
        'loopLead': loopLead,
      };

  @override
  bool operator ==(Object other) =>
      other is PrepBeats &&
      other.delayedPlay == delayedPlay &&
      other.recording == recording &&
      other.loopLead == loopLead;

  @override
  int get hashCode => Object.hash(delayedPlay, recording, loopLead);
}

/// 延迟播放 / 录制准备共用档位（2/4/8）。
const List<int> kPrepBeatsTiers = [2, 4, 8];

/// 循环前导档位（0/2/4/8；0 = 不前导）。
const List<int> kLoopLeadPrepBeatsTiers = [0, 2, 4, 8];

const int kDelayedPlayPrepBeatsDefault = 4;
const int kRecordingPrepBeatsDefault = 8;
const int kLoopLeadPrepBeatsDefault = 4;

/// 单字段档位解码：合法取值原样、缺失/非法回落 [fallback]。
int decodePrepBeatsTier(Object? raw, List<int> tiers, int fallback) =>
    raw is int && tiers.contains(raw) ? raw : fallback;

/// 预备拍数存取 seam（读面 + 写面；先例 = [MetronomeSettingsStore] 形状）。
abstract interface class PrepBeatsStorage {
  /// 读取三项；键缺失/损坏兜底出厂默认。
  Future<PrepBeats> load();

  /// 原子「读 → [mutate] → 写」三项（保留同文件其它键）。
  Future<void> update(
    FutureOr<PrepBeats> Function(PrepBeats current) mutate,
  );
}

/// [PrepBeatsStorage] 的私密 JSON 实现（`prepBeats` 键）。
class PrepBeatsStore implements PrepBeatsStorage {
  PrepBeatsStore(this._storage);

  static const _key = 'prepBeats';

  final PrivateJsonStorage _storage;

  @override
  Future<PrepBeats> load() async =>
      PrepBeats.fromJson((await _storage.read())[_key]);

  @override
  Future<void> update(
    FutureOr<PrepBeats> Function(PrepBeats current) mutate,
  ) {
    return _storage.mutate((json, {required bool present}) async {
      final current = PrepBeats.fromJson(json[_key]);
      final next = await mutate(current);
      json[_key] = next.toJson();
    });
  }
}

/// 预备拍数存取注入点（测试经内存私密 JSON 覆盖）。
final prepBeatsStorageProvider = Provider<PrepBeatsStorage>((ref) {
  return PrepBeatsStore(ref.watch(privateJsonStorageProvider));
});

/// 是否在模型构建时自动恢复持久化的预备拍数（测试可关掉以隔离确定性
/// 初始态）。
final prepBeatsAutoRestoreProvider = Provider<bool>((ref) => true);

/// 预备拍数会话态（启动恢复 + 变更即落盘；先例 =
/// `PersistedSettingModel` 骨架，落点是 `prepBeats` 键整组值）。
final prepBeatsProvider = NotifierProvider<PrepBeatsModel, PrepBeats>(
  PrepBeatsModel.new,
);

class PrepBeatsModel extends Notifier<PrepBeats> {
  bool _mutated = false;
  Future<void> _flush = Future<void>.value();
  Future<void> _restoreDone = Future<void>.value();

  @override
  PrepBeats build() {
    _restore();
    return const PrepBeats();
  }

  /// 启动恢复完成（测试「重启后读态」的同步点）。
  Future<void> get restoreDone => _restoreDone;

  /// 最近一次落盘写入完成（测试同步点）。
  Future<void> get flushDone => _flush;

  void _restore() {
    if (!ref.read(prepBeatsAutoRestoreProvider)) return;
    var disposed = false;
    ref.onDispose(() => disposed = true);
    _restoreDone = () async {
      try {
        final value = await ref.read(prepBeatsStorageProvider).load();
        if (disposed || _mutated || !ref.mounted) return;
        state = value;
      } on Object {
        // 存储不可读：维持默认会话态。
      }
    }();
  }

  /// 变更延迟播放拍数并即时落盘。
  void setDelayedPlay(int value) => _set(delayedPlay: value);

  /// 变更录制准备拍数并即时落盘。
  void setRecording(int value) => _set(recording: value);

  /// 变更循环前导拍档并即时落盘；唯一的循环前导写入口——会话档位
  /// （[delayedLoopProvider]）由本模型派生，不存在第二份拷贝。
  void setLoopLead(int value) => _set(loopLead: value);

  /// 单项变更：会话态整组更新、落盘只改目标字段（字段级读改写——启动
  /// 恢复未完成时的改动不会把另两项的已存值冲成默认）。
  void _set({int? delayedPlay, int? recording, int? loopLead}) {
    if (!ref.mounted) return;
    final next = state.withFields(
      delayedPlay: delayedPlay,
      recording: recording,
      loopLead: loopLead,
    );
    if (next == state) return;
    state = next;
    _mutated = true;
    _flush = _flush.then((_) async {
      try {
        await ref.read(prepBeatsStorageProvider).update(
              (current) => current.withFields(
                delayedPlay: delayedPlay,
                recording: recording,
                loopLead: loopLead,
              ),
            );
      } on Object {
        // 写失败不抛到 UI。
      }
    });
  }
}

/// 延迟循环选项：真实学习段/临时衔接段每圈到段尾静帧等待的
/// 拍数；不延迟 = 现状立即回段首。默认 4 拍。
enum DelayedLoopBeats {
  /// 不延迟：到段尾立即回段首。
  none,

  /// 静帧 2 拍。
  two,

  /// 静帧 4 拍（默认）。
  four,

  /// 静帧 8 拍。
  eight;

  /// 选项对应的拍数（0/2/4/8）。
  int get beats => switch (this) {
    DelayedLoopBeats.none => 0,
    DelayedLoopBeats.two => 2,
    DelayedLoopBeats.four => 4,
    DelayedLoopBeats.eight => 8,
  };
}

/// 拍数 → 选项（文档值 → 取值道）；无法识别的拍数（文档异常、表默认失配）
/// 回落到装载表为偏好行声明的默认拍数——默认值只有一处。
DelayedLoopBeats delayedLoopFromBeats(int beats) {
  for (final value in DelayedLoopBeats.values) {
    if (value.beats == beats) return value;
  }
  final fallback = loadPreferenceDefaults.delayedLoopBeats;
  return DelayedLoopBeats.values.firstWhere((value) => value.beats == fallback);
}

/// 延迟循环会话设置注入点（派生投影）：唯一事实源是设备级
/// `prepBeats.loopLead`——档位枚举与消费方不变，无独立会话拷贝。
final delayedLoopProvider = Provider<DelayedLoopBeats>((ref) {
  return delayedLoopFromBeats(ref.watch(prepBeatsProvider).loopLead);
});

/// 循环前导每圈前导时长（替代「静帧等待」语义）：改读
/// **前导档位基准**——异常态档位数字即秒
/// （2→2s/4→4s/8→8s；不落盘，偏好原值保留，节拍恢复
/// 自动回来），否则档位 × 名义拍长；档位 0 两支天然得零，无特例。播放页
/// 接线到 `PlaybackLoopLayer.updateDelayedLoopWait`。
final delayedLoopWaitProvider = Provider<Duration>((ref) {
  final count = ref.watch(delayedLoopProvider).beats;
  return ref.watch(beatGridProvider).leadTier(count);
});
