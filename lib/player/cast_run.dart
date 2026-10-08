/// 投屏运行域（播放页侧）：把「这次投的**投屏会话** + 那条**递出通道**」的
/// 持有、起投、断开与遥控镜像收在一处。
///
/// ## 它回答什么
///
/// - **现在投的是谁**：[state] 的接收端（null = 没投）——投屏胶囊、断开面与
///   后续倍速档切换都读它；
/// - **起投**：[start] = 起递出通道 → 连上接收端 → 推片 → 起播。任一步失败
///   即把已起的部分收干净（停服 + 断连）、状态回未投屏，异常向上抛——
///   零残留（准备面板与宿主据此给失败面）；
/// - **断开**：[disconnect] 是唯一出口——先停服（在飞连接一并断）、再断连，
///   随后 [PlayerSessionModel.exitCast] 回编辑态。重复调用与未投屏时都是
///   空操作；
/// - **遥控镜像**（[CastMirror]）：投屏态内本机的播放 / 暂停 / 跳转**同时**
///   作用于接收端（手机在这一票里就是遥控器——学习段激活、三指跳转、
///   进度拖动收口都经本机播放面，故镜像点在这一层，投屏态内无需第二套
///   控件）。三个动作都**不抛**：失败由本域收口（断开 + 回编辑态 + 短暂
///   提示），本机播放不因一次投屏失败被带停。
///
/// ## 断开触发点收在既有复位一处
///
/// 换视频与离开播放页都经 [PlayerSessionModel.reset]（见
/// `open_restore.dart` 与播放页 dispose），本域只听「离开投屏态」这一条
/// 边沿即断开——**不新增手写退出点**。主动断开走 [disconnect]：它自己收完
/// 会话与通道再翻模式值，那条边沿随之再走一遍是幂等空操作。
///
/// ## 边界
///
/// 本域不读构建上下文、不构控件；模式值仍归其既有单一 owner
/// [PlayerSessionModel]（本域只消费它的读面与写缝）。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart'
    show BuildContext, Key, Text, Widget;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cast/cast_delivery_channel.dart';
import '../cast/cast_receiver.dart';
import '../cast/cast_session.dart';
import '../player_session/player_session.dart';
import 'cast_mirror.dart';
import 'notice.dart' show NoticeId, NoticeSpec, noticeTriggerProvider;
import 'visual_tokens.dart' show kNoticeTextStyle;

/// 投屏遥控镜像口：投屏态内本机的播放动作同时作用于接收端。
///
/// 实现（[CastRunModel]）自身收口失败——本口不抛（见库头「遥控镜像」）。
/// 未接投屏的宿主与测试用 [NoCastMirror]（三动作皆空操作）。
export 'cast_mirror.dart' show CastMirror, NoCastMirror;

/// 「投屏断了」提示内容：一句话说明已回到编辑态。
Widget _castInterruptedNoticeContent(BuildContext _) =>
    const Text('投屏断了，回到编辑态', style: kNoticeTextStyle);

const castInterruptedNoticeSpec = NoticeSpec(
  id: NoticeId.castInterrupted,
  content: _castInterruptedNoticeContent,
  noticeKey: Key('cast_interrupted_prompt'),
);

/// 「没接上接收端」提示内容：起投失败（连不上 / 被拒 / 递出通道起不来）
/// 时那一句——准备面板已关，这是唯一的失败面。
Widget _castNotStartedNoticeContent(BuildContext _) =>
    const Text('没接上这台接收端', style: kNoticeTextStyle);

const castNotStartedNoticeSpec = NoticeSpec(
  id: NoticeId.castNotStarted,
  content: _castNotStartedNoticeContent,
  noticeKey: Key('cast_not_started_prompt'),
);

/// 投屏运行状态：没投 / 正投到某台接收端。
class CastRunState {
  const CastRunState.idle() : receiver = null;

  const CastRunState.casting(this.receiver);

  /// 正投的那台接收端；null = 没投。
  final CastReceiver? receiver;

  bool get active => receiver != null;

  @override
  bool operator ==(Object other) =>
      other is CastRunState && other.receiver == receiver;

  @override
  int get hashCode => receiver.hashCode;

  @override
  String toString() => active ? 'CastRunState.casting(${receiver!})' : 'idle';
}

/// 投屏运行域：当前这条投屏会话与递出通道的唯一持有者。
class CastRunModel extends Notifier<CastRunState> implements CastMirror {
  CastSession? _session;
  CastDeliveryChannel? _channel;

  @override
  CastRunState build() {
    // 断开触发点收在既有复位一处：只听「离开投屏态」这一条边沿
    // （换视频与离开播放页都经 [PlayerSessionModel.reset]）。
    ref.listen(playerSessionProvider, (previous, next) {
      final wasCasting = previous?.isCast ?? false;
      if (wasCasting && !next.isCast) unawaited(_teardown());
    });
    return const CastRunState.idle();
  }

  /// 正投的那台接收端（未投屏为 null）。
  CastReceiver? get receiver => _session?.receiver;

  /// 起投：起递出通道 → 连上接收端 → 推 [file] → 起播。
  ///
  /// 一次只投一台：起投前先收掉上一条（换接收端 = 断开重投）。任一步失败即
  /// 零残留地收干净并把异常向上抛——**起投失败不回编辑态**（模式值本就没
  /// 离开过），由调用方给失败面。
  Future<void> start({
    required CastReceiver receiver,
    required File file,
  }) async {
    await _teardown();
    final channel = ref.read(castDeliveryChannelProvider);
    final factory = ref.read(castSessionFactoryProvider);
    try {
      final source = await channel.serve(file);
      // 通道一挂上就记账：接下去任一步失败都要把它停掉（零残留）。
      _channel = channel;
      final session = await factory.connect(receiver);
      _session = session;
      state = CastRunState.casting(receiver);
      await session.push(source);
      await session.play();
    } on Object {
      await _teardown();
      // 起投失败一律回编辑态：新投那条路径本就没离开过编辑态（exitCast 是
      // 幂等 no-op）；换接收端失败那条路径会剩一个「在投屏态却没有会话」的
      // 悬挂面，这里一并收口。
      ref.read(playerSessionProvider.notifier).exitCast();
      rethrow;
    }
  }

  /// 断开：唯一出口——先停服（在飞连接一并断）、再断连，随后模式值回编辑态。
  ///
  /// 递出通道**先停**：会话的收尾动作（停播）可能被设备拖住，停服不该等它
  /// ——「立刻不可达」不依赖接收端的回应。未投屏或重复调用都是空操作。
  Future<void> disconnect() async {
    final wasCasting = _session != null;
    await _teardown();
    if (wasCasting) {
      ref.read(playerSessionProvider.notifier).exitCast();
    }
  }

  /// 遥控镜像：未投屏 = 空操作；失败收口，不向上抛。
  @override
  Future<void> play() => _mirror((session) => session.play());

  @override
  Future<void> pause() => _mirror((session) => session.pause());

  @override
  Future<void> seek(Duration position) =>
      _mirror((session) => session.seek(position));

  Future<void> _mirror(
    Future<void> Function(CastSession session) action,
  ) async {
    final session = _session;
    if (session == null) return;
    try {
      await action(session);
    } on Object {
      await _fail();
    }
  }

  /// 失败收口：断开（含停服）+ 回编辑态 + 短暂提示。无会话时是空操作——
  /// 并发失败只收口一次，不重复弹提示。
  Future<void> _fail() async {
    if (_session == null) return;
    await disconnect();
    ref.read(noticeTriggerProvider(NoticeId.castInterrupted).notifier).show();
  }

  /// 收干净：停服 + 断连 + 状态回未投屏。两步各自 best-effort——收尾失败
  /// 不阻断另一步，也不向上抛（用户按下的那一下不能被一次失败的收尾挡住）。
  Future<void> _teardown() async {
    final session = _session;
    final channel = _channel;
    _session = null;
    _channel = null;
    if (state.active) state = const CastRunState.idle();
    if (channel != null) {
      try {
        await channel.close();
      } on Object {
        // 停服失败不阻断断连：通道是设备级缓存，进程退出即回收。
      }
    }
    if (session != null) {
      try {
        await session.disconnect();
      } on Object {
        // 断开本身不再抛（会话契约）。
      }
    }
  }
}

/// 投屏运行域的注入点（唯一实例）。
final castRunProvider = NotifierProvider<CastRunModel, CastRunState>(
  CastRunModel.new,
);
