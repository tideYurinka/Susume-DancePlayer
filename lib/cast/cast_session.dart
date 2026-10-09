/// **投屏会话**接缝：一次从推到断的连接，绑定一台**接收端**。
///
/// 投屏准备面板、投屏态、倍速切换与失败面全部经这条接缝测，不碰真网络：
/// 接口 + 真实实现（`dlna_cast_session.dart`）+ Provider 注入 + 脚本化替身
/// （`test/helpers/fake_cast_session.dart`）。
///
/// 失败口径（三类，见 `cast_failure.dart`）：[CastSessionFactory.connect]
/// 连不上抛 `CastReceiverUnreachable`；会话建立后某次动作被设备回绝抛
/// `CastActionRefused`；会话建立后**连接断了**抛 `CastSessionDropped`。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cast_failure.dart';
import 'cast_receiver.dart';
import 'dlna_cast_session.dart';

/// 接收端此刻支持哪些传输动作（`GetCurrentTransportActions` 的应答）。
///
/// **探测不到或探测失败一律是空集**：宁可少显示一枚遥控项，也不显示一个按
/// 下去没反应的。
class CastTransportActions {
  const CastTransportActions(this.actions);

  /// 一个都不支持：探测失败与设备自述空表同一口径。
  const CastTransportActions.none() : actions = const {};

  final Set<CastTransportAction> actions;

  bool contains(CastTransportAction action) => actions.contains(action);

  bool get isEmpty => actions.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is CastTransportActions &&
      other.actions.length == actions.length &&
      other.actions.containsAll(actions);

  @override
  int get hashCode => Object.hashAllUnordered(actions);

  @override
  String toString() =>
      'CastTransportActions(${actions.map((a) => a.name).join(',')})';
}

/// UPnP 的传输动作名。
enum CastTransportAction { play, pause, stop, seek, next, previous }

/// 投屏态里**现有的三枚遥控项**：界面上的既有控件——**进度**（画面横向拖动
/// 与帧步进）、**播放暂停**（底排播放键与双击）、**音量**（右半屏纵向滑的
/// 滑条）。判据 [CastRemoteControls] 逐项回答「显不显示」——**这是唯一判据**，
/// 界面只问这一处，不各自另判（见 [CastRemoteControls.shows]）。
enum CastRemoteItem { progress, playPause, volume }

/// 播放状态：`CurrentTransportState` 的取值 + 「问不到」。
enum CastPlaybackState {
  playing,
  paused,
  stopped,
  transitioning,
  noMedia,

  /// 问不到（设备没报、或报了个我们不认识的词）。
  unknown,
}

/// 「哪些遥控项显示」的判据：接收端上报的**当前支持传输动作** + 音量能不能
/// 读得到（RenderingControl 端点**且**这次探测真读到了上报值）。纯件——判据
/// 不进网络实现里。
///
/// ## 「有没有端点」不是「能不能读」
///
/// UPnP 设备描述里挂着 RenderingControl 服务，不等于它答得上 `GetVolume`：
/// 端点缺失与探测失败都收敛到同一个出口——**音量这一项不显示**（静默降级，
/// 与动作集探测失败一律空集同款，见 [CastTransportActions]）。
/// [CastRemoteControls.of] 的 [hasVolumeControl] 因此收的是**已经折过探测**
/// 的那一位：调用方把「有端点 ∧ 探测到值」按 [castVolumeReported] 算好再传，
/// 界面侧不再有第二个判据。
class CastRemoteControls {
  const CastRemoteControls({
    required this.showsPlayPause,
    required this.showsStop,
    required this.showsSeek,
    required this.showsVolume,
  });

  /// 全不显示（探测失败 / 不是投屏对象的兜底）。
  const CastRemoteControls.none()
    : showsPlayPause = false,
      showsStop = false,
      showsSeek = false,
      showsVolume = false;

  factory CastRemoteControls.of({
    required CastTransportActions actions,
    required bool hasVolumeControl,
  }) => CastRemoteControls(
    showsPlayPause:
        actions.contains(CastTransportAction.play) ||
        actions.contains(CastTransportAction.pause),
    showsStop: actions.contains(CastTransportAction.stop),
    showsSeek: actions.contains(CastTransportAction.seek),
    showsVolume: hasVolumeControl,
  );

  final bool showsPlayPause;
  final bool showsStop;
  final bool showsSeek;

  /// 音量这一项显不显示：端点在场**且**起投探测时设备真报得出当前音量
  /// （这一位由 [castVolumeReported] 折出来，不是设备描述单独派生的）。
  final bool showsVolume;

  /// 某一枚遥控项显不显示（**唯一判据的逐项读法**：投屏态的界面只问这一处，
  /// 不各自另判——音量那枚不许再叠第二条件）。穷尽 `switch`：加遥控项即编译
  /// 报错。
  bool shows(CastRemoteItem item) => switch (item) {
    CastRemoteItem.progress => showsSeek,
    CastRemoteItem.playPause => showsPlayPause,
    CastRemoteItem.volume => showsVolume,
  };

  @override
  bool operator ==(Object other) =>
      other is CastRemoteControls &&
      other.showsPlayPause == showsPlayPause &&
      other.showsStop == showsStop &&
      other.showsSeek == showsSeek &&
      other.showsVolume == showsVolume;

  @override
  int get hashCode =>
      Object.hash(showsPlayPause, showsStop, showsSeek, showsVolume);
}

/// 「音量这一项能不能读得到」：把「设备描述里的音量端点」与「起投探测这一次
/// 读到的那条上报值」折成一位，供 [CastRemoteControls.of] 用。
///
/// [probedVolume] 是探测那一次的读取结果（`null` = 没端点 / 设备不答 /
/// 探测失败）：三态在这里收敛到同一个出口——**不显示**。读数取到才是显示，
/// 且显示值就是它（`cast_volume.dart` 的显示路径读同一条上报值）。
bool castVolumeReported({
  required bool hasVolumeEndpoint,
  required double? probedVolume,
}) => hasVolumeEndpoint && probedVolume != null;

/// 一次投屏会话：把一份文件推给接收端自己播，之后的一切遥控都作用于它。
///
/// **会话不写任何文档、不落任何标注**；[disconnect] 是唯一出口，调用后这条
/// 会话不再可用（再调任何动作都抛 [CastSessionDropped]）。
abstract interface class CastSession {
  /// 这次会话绑定的接收端。
  CastReceiver get receiver;

  /// **推片**：把接收端的播放源换成 [source]（递出通道给出的局域网地址）。
  ///
  /// **不自动开播**——什么时候开播由调用方定（换**投屏倍速档**要先跳转再
  /// 播）。接收端回绝（拒播）抛 [CastActionRefused]。
  Future<void> push(Uri source);

  Future<void> play();

  Future<void> pause();

  Future<void> stop();

  /// 跳转到 [position]（相对这支舞的开头）。
  Future<void> seek(Duration position);

  /// 把接收端音量设成 [volume]（0..1）。
  Future<void> setVolume(double volume);

  /// 读接收端当前音量（0..1）；设备不报时抛 [CastActionRefused]。
  Future<double> volume();

  /// 读接收端当前播放位置。
  Future<Duration> position();

  /// 读接收端当前播放状态。
  Future<CastPlaybackState> playbackState();

  /// 读接收端此刻支持的传输动作（探测失败 = 空集，不抛）。
  Future<CastTransportActions> supportedTransportActions();

  /// 断开：尽力让接收端停下并释放连接；重复调用是空操作。**断开本身不再
  /// 抛**——用户按下的那一下不能被一次失败的收尾挡住。
  Future<void> disconnect();
}

/// 投屏会话的建立口：接缝上的注入点是**它**（脚本化替身按脚本给出会话，
/// 或按脚本拒绝连接）。
abstract interface class CastSessionFactory {
  /// 连上 [receiver]：确认控制端点可用、备好连接。
  ///
  /// 端点取不到或连不通抛 [CastReceiverUnreachable]；端点活着但回绝了这次
  /// 探测抛 [CastActionRefused]。
  Future<CastSession> connect(CastReceiver receiver);
}

/// 投屏会话的注入点：真实实现走 DLNA/UPnP 的 SOAP；测试 override 注入
/// 脚本化替身。
final castSessionFactoryProvider = Provider<CastSessionFactory>(
  (ref) => const DlnaCastSessionFactory(),
);
