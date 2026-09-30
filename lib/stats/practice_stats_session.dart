import 'dart:async';

import '../persistence/four_beat_bucket_store.dart';
import '../persistence/practice_stats.dart';
import '../persistence/practice_stats_recorder.dart';
import '../persistence/song_signature.dart';
import 'song_signature.dart';

/// 练舞统计记账域的会话：自持「随打开启动、当前是哪支舞的
/// 更新、离开收尾」，宿主不再逐处把 videoId/署名推给记录器。
///
/// **依赖方向（单向，护栏钉住）**：统计域 → 署名域。本会话从署名域
/// [SongSignatureController] 取当前视频标识（videoId）与署名快照；署名域
/// 不反向依赖统计域。宿主只注入回调 [onVideoIdChanged]（练习素材库等对
/// 「当前视频」的读取面在宿主侧接线）。
///
/// - [start]：清空记录器上下文（复用同一引擎重开视频时，解析窗口内的
///   播放不得记到上一个视频名下）并订阅署名域；此后署名域每次解析通知即
///   把现值同步进记录器，每次**提交**通知（命名/改名落盘）即把该视频的
///   统计记录与四拍桶分片署名快照迁移到新署名；
/// - [syncVideoContext]：把署名域现值同步进记录器并交回宿主的「当前视频」
///   读取面。打开流程在署名解析落定后调用一次（标识未解析时署名域不发
///   通知，故这一次调用不可省——读取面同样要收到 null）；
/// - [settle]：结算开放缓冲并落盘（离开播放器/切后台）；
/// - [dispose]：摘除署名域订阅。记录器生命周期归它的注入方，本会话不
///   负责销毁它。
///
/// 记录器为 null 时（未接统计的环境）仍跟随署名域并交出 videoId，只是
/// 不入账。
class PracticeStatsSession {
  PracticeStatsSession({
    required this._recorder,
    required this._signatureController,
    required this._fallbackName,
    required this._statsStore,
    required this._bucketStore,
    this._onVideoIdChanged,
  });

  final PracticeStatsRecorder? _recorder;

  /// 署名域（当前视频标识与署名快照的唯一来源）。
  final SongSignatureController _signatureController;

  /// 未署名时的回退名（视频文件名；与顶栏回退一致）。
  final String Function() _fallbackName;

  /// 署名迁移写-through 的两个落点（该视频的统计记录与四拍桶分片）。
  final PracticeStatsStore _statsStore;
  final FourBeatBucketStore _bucketStore;

  final void Function(String? videoId)? _onVideoIdChanged;

  bool _started = false;

  /// 会话启动（打开流程在署名解析前调用）：清空上下文并开始跟随即刻起
  /// 的署名域变化。重复调用只重清上下文、不重复订阅。
  void start() {
    _recorder?.updateVideo(
      videoId: null,
      signature: null,
      fallbackName: _fallbackName(),
    );
    if (_started) return;
    _started = true;
    _signatureController.addListener(syncVideoContext);
    _signatureController.addCommitListener(_migrateSignature);
  }

  /// 结算开放缓冲并落盘（退出播放器/切后台）。
  Future<void> settle() async {
    await _recorder?.settleAndFlush();
  }

  /// 把署名域现值同步进记录器并交回宿主的「当前视频」读取面（打开流程
  /// 在署名解析落定后调用一次；署名域之后的每次变化走同一条同步）。
  void syncVideoContext() {
    final videoId = _signatureController.videoId;
    _onVideoIdChanged?.call(videoId);
    _recorder?.updateVideo(
      videoId: videoId,
      signature: _signatureController.signature,
      fallbackName: _fallbackName(),
    );
  }

  /// 摘除署名域订阅。记录器由它的注入方销毁，本方法不触碰它。
  void dispose() {
    if (!_started) return;
    _started = false;
    _signatureController.removeListener(syncVideoContext);
    _signatureController.removeCommitListener(_migrateSignature);
  }

  /// 改名/补命名写-through（见词条「四拍桶」桶分片同款）：署名域
  /// 提交落定即把该视频全部统计记录（含未 flush 的开放缓冲）与该舞的四拍桶
  /// 分片署名快照迁移到新署名；videoId 未解析时本就没有以旧名入账的记录，
  /// 跳过。
  void _migrateSignature(SongSignature signature) {
    final videoId = _signatureController.videoId;
    if (videoId == null) return;
    unawaited(_statsStore.migrateSignature(videoId, signature));
    unawaited(_bucketStore.migrateSignature(videoId, signature));
  }
}
