/// 节拍提示记忆的会话槽与生效值基座。
///
/// - **记忆槽**（[beatPromptMemoryProvider]）：当前这支舞的节拍提示记忆
///   （五个值逐字段可缺席；null = 这支舞没有任何记忆记录）。打开恢复与
///   随舞落盘由设置持久化接线；用户经各设置槽写入口写入的字段落在这里。
/// - **生效值基座**（[BeatPromptEffectiveModel]）：记忆里有值就用记忆值，
///   缺席取设备级「新舞默认」那一层的当前值；形态/音源/半拍声的设置槽
///   `set(value)` 在此基座内双写记忆与设备级字段（写入口只此一处，消费方
///   只调 `.set(value)`），不散落在 UI。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../beat_track_state/beat_track_state.dart' show beatGridProvider;
import '../core/beat_grid.dart' show BeatGridReads;
import '../persistence/local_document.dart' show BeatPromptMemoryFields;

/// 当前舞的节拍提示记忆（打开/落盘两端的接线点）。
final beatPromptMemoryProvider =
    NotifierProvider<BeatPromptMemoryModel, BeatPromptMemoryFields?>(
      BeatPromptMemoryModel.new,
    );

class BeatPromptMemoryModel extends Notifier<BeatPromptMemoryFields?> {
  @override
  BeatPromptMemoryFields? build() => null;

  /// 「这支舞的记忆已经读到了」的标记：与视频身份对齐——
  /// 只在 [restoreFor] 按该身份装载过才置位。它让自动置开判据能区分
  /// 「还没读到」（盘上可能有本该恢复的关，不得据此置开）与「读到且
  /// 无记录」（这支舞真的没有记忆，置开安全）。
  String? _loadedVideoId;

  /// 本支舞读入后用户是否扳动过任何节拍提示开关：手动扳动
  /// 算用户表态，此后本轮会话不再自动置开。只在换舞 [clear] 时复位。
  bool _touchedByUser = false;

  /// 本轮会话已自动置开过（「一次的口径」的显式闸）：置开即写
  /// 记忆、一个舞至多自动一次。不依赖「记录非空」隐式闭死，避免写入口
  /// 或判据次序将来调整时静默失效。只在换舞 [clear] 时复位。
  bool _autoEnabledOnce = false;

  /// 换会话复位（换视频清空语义 + 读到标记一并复位）。
  void clear() {
    _loadedVideoId = null;
    _touchedByUser = false;
    _autoEnabledOnce = false;
    state = null;
  }

  /// 恢复装载：整份记录落会话槽并按身份落「已读到」标记；null =
  /// 这支舞无记忆记录。恢复是只读装载，不触发任何落盘。
  void restoreFor(String videoId, BeatPromptMemoryFields? memory) {
    _loadedVideoId = videoId;
    state = memory;
  }

  /// 自动置开一次的唯一落点（两条路径共用）：三条件同时成立
  /// 才把两个总开关各置开一次并写进这支舞的记忆——
  ///
  /// ① 这支舞没有任何记忆记录；例外：**新分析成功**这条路径上，盘上
  /// 那份「用户没在本轮会话动过」的旧记录（典型 = 早已存下的关）按
  /// 「关掉后重做一次识别会再置开一次」的既定后果处理——本轮用户扳动过
  /// （[_touchedByUser]）则绝不翻动（不出现「我关掉了、识别成功后它自己
  /// 又开了」）；
  /// ② 节拍网格**真实就绪**（占位/异常一律不动）；
  /// ③ 这支舞的记忆**已经读到**且与本支舞身份对齐（未读到时「无记录」
  /// 只是「还没读到」，置开会覆盖本该恢复的值）。
  ///
  /// 置开即写记忆，一个舞本轮会话至多自动一次（[_autoEnabledOnce] 显式
  /// 闸）；写的是记忆槽，设备级字段不碰。
  void autoEnableFor(String videoId, {required bool freshAnalysis}) {
    if (_autoEnabledOnce) return;
    if (_loadedVideoId != videoId) return;
    final record = state;
    if (record != null && !(freshAnalysis && !_touchedByUser)) return;
    if (!ref.read(beatGridProvider).hasRealBeats) return;
    // 先落闸再写入：本次置开与其后任何补触发（如订阅就绪后的再判）都
    // 按「已自动过」收口。
    _autoEnabledOnce = true;
    setAnimation(true);
    setSound(true);
  }

  void setAnimation(bool animation) =>
      _update((f) => f.copyWith(animation: animation));

  void setAnimationStyle(String animationStyle) =>
      _update((f) => f.copyWith(animationStyle: animationStyle));

  void setSound(bool sound) => _update((f) => f.copyWith(sound: sound));

  void setSoundType(String soundType) =>
      _update((f) => f.copyWith(soundType: soundType));

  void setHalfBeat(bool halfBeat) =>
      _update((f) => f.copyWith(halfBeat: halfBeat));

  BeatPromptMemoryFields _update(
    BeatPromptMemoryFields Function(BeatPromptMemoryFields fields) mutate,
  ) {
    final next = mutate(state ?? const BeatPromptMemoryFields());
    state = next;
    // 任何写入口都算用户表态（自动置开自身的写入已被
    // [_autoEnabledOnce] 先行落闸，不依赖此处闭死）。
    _touchedByUser = true;
    return next;
  }
}

/// 记忆字段缺席回落设备级「新舞默认」的生效值基座：读 = 记忆解码值 ??
/// 设备级当前值；用户设置动作 `set` 双写记忆与设备级字段（设备级因此始终
/// 等于最后一次选择，且只被用户设置动作改写）。
abstract class BeatPromptEffectiveModel<T> extends Notifier<T> {
  @override
  T build() {
    final fromMemory = memoryValueOf(ref.watch(beatPromptMemoryProvider));
    if (fromMemory != null) return fromMemory;
    return watchDeviceDefault();
  }

  void set(T value) {
    if (!ref.mounted) return;
    // 重选同值也是一次用户表态（记进这支舞）——
    // 记忆字段必须落，否则这支舞仍是「无记录」；设备级槽自身按值相等
    // 跳过写盘。
    writeMemoryField(value);
    persistDeviceDefault(value);
  }

  /// 从记忆记录解码本字段；字段缺席（或词表外）返回 null——按缺席回落
  /// 设备级默认。
  T? memoryValueOf(BeatPromptMemoryFields? memory);

  /// 设备级「新舞默认」那一层的当前值。
  T watchDeviceDefault();

  /// 设备级字段的用户设置动作写入口（该层自身落盘 `metronomeSettings`）。
  void persistDeviceDefault(T value);

  /// 记忆字段的写入口。
  void writeMemoryField(T value);
}
