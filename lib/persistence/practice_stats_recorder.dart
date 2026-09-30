import 'dart:async';

import '../core/beat_grid.dart';
import '../stats/four_beat_bucket.dart';
import 'four_beat_bucket_store.dart';
import 'practice_accounting.dart';
import 'practice_stats.dart';
import 'song_signature.dart';

/// 练习统计记录器（收口）：消费注入的
/// 练习记账**事实流**，判定在纯件门（[evaluatePracticeAccounting]）——
/// 记录器只消费判定，不读 provider、不自行推导。事实从「计」翻到「不计」
/// ⇒ 在翻转点结算当前区间；从「不计」翻回「计」且引擎在播 ⇒ 从当下新开
/// 区间；不计期间的播放态边沿不入账。
///
/// - 公开面三项：[updateVideo]（关联视频：videoId / 署名快照 / 回退文件名）、
///   [settleAndFlush]（结算落盘）、[dispose]（释放）。没有排除语义、没有
///   计数器——离开播放页不需要任何配平调用（排除泄漏在结构上不可表示）；
/// - 记账都经 [PracticeStatsStore.recordPlaying]（合并/跨零点分桶规则在
///   store 收口），本类只做判定翻转到「连续播放区间」的翻译；
/// - 暂停/到尾停止（引擎不在播）即结算并落盘；退出播放器/切后台由宿主调
///   [settleAndFlush]（含未结算的开放缓冲）；
/// - [updateVideo]：打开视频解析出 videoId/署名后关联（videoId null =
///   解析窗口、这一刻不计）。标识事实由本类的关联状态交出：解析落定且引擎
///   在播 ⇒ 从当下新开区间，解析窗口内的播放不记到任何视频名下；署名 null
///   或歌曲名为空按回退文件名计入（与顶栏回退一致）。
///
/// **四拍桶接线**（见词条「四拍桶」）：构造可传入引擎位置流 [positions]、
/// 每舞桶分片 store [buckets] 与网格源 [grid]。记账判定仍只有 [evaluatePracticeAccounting]
/// 一处；位置 → 桶的换算与分摊全在纯件 [FourBeatBucketLedger] 里，本类只把
/// 「判定为计」的采样点喂给账本，并把账本产出的桶账写进分片 store。网格
/// 未就绪（[grid] 返回 null 或网格无真实拍点）不产桶；暂停/拖动/翻看由
/// 「引擎转停即断点」覆盖；倍速不折算（dt 一律墙钟）。
class PracticeStatsRecorder {
  PracticeStatsRecorder({
    required Stream<PracticeAccountingFacts> facts,
    required this.store,
    DateTime Function()? clock,
    Stream<Duration>? positions,
    this.buckets,
    this.grid,
    this.density,
  }) : _clock = clock ?? DateTime.now {
    _subscription = facts.listen(
      (facts) => _chain = _chain.then((_) => _onFacts(facts)),
    );
    _positionSubscription = positions?.listen(
      (position) => _chain = _chain.then((_) => _onPosition(position)),
    );
  }

  /// 会话记录入账的全局 store（[PracticeStatsStore] 的唯一实例，由注入方
  /// 持有生命周期）。
  final PracticeStatsStore store;

  final DateTime Function() _clock;

  /// 位置流订阅（未接线四拍桶时为 null）。
  late final StreamSubscription<Duration>? _positionSubscription;

  /// 每舞桶分片 store（未接线时为 null：桶记录整体不生效）。
  final FourBeatBucketStore? buckets;

  /// 当前网格源（null 或返回 null/未就绪网格 = 不产桶）。
  final BeatGrid? Function()? grid;

  /// 记账时的节拍倍频源（桶键带记录时的倍频身份；null 或值不
  /// 在五档内按 1 = 原样落裸整数键）。桶格取**落盘网格**（不含会话期
  /// 预览偏移/预览档），预览期间不污染桶格。
  final double Function()? density;

  /// 位置 → 桶分摊账本（纯件；记录器只喂采样点与读桶账）。
  final FourBeatBucketLedger _ledger = FourBeatBucketLedger();

  late final StreamSubscription<PracticeAccountingFacts> _subscription;

  /// 事件处理串行链：事件到达次序即结算次序。
  Future<void> _chain = Future<void>.value();

  String? _videoId;
  SongSignature? _signature;
  String _fallbackName = '';

  /// 最近一次收到的事实（[updateVideo] 改变标识事实后按它重判）。
  PracticeAccountingFacts _facts = const PracticeAccountingFacts();

  /// 当前是否处于「计」的区间（[evaluatePracticeAccounting] 的输出）。
  bool _counted = false;

  /// 当前连续播放区间的起点（null = 不在记账播放中）。
  DateTime? _runStart;

  bool _disposed = false;

  /// 关联当前视频（打开解析后与署名变化时调用；videoId null = 不记账）。
  void updateVideo({
    required String? videoId,
    required SongSignature? signature,
    required String fallbackName,
  }) {
    _videoId = videoId;
    _signature = signature;
    _fallbackName = fallbackName;
    // 换视频/标识翻转即断开连续推进：桶账不跨视频。
    _ledger.breakRun();
    // 标识事实翻转（解析落定 / 重开清空）即刻按当前事实重判。
    _chain = _chain.then((_) => _onFacts(_facts));
  }

  /// 结算开放缓冲并强制落盘（退出播放器/切后台）。
  Future<void> settleAndFlush() async {
    final runStart = _runStart;
    final end = _clock();
    _runStart = null;
    _ledger.breakRun();
    await _chain;
    if (runStart != null && end.isAfter(runStart)) {
      await _settleRun(runStart, end);
    }
    await store.settle();
    await buckets?.settle();
  }

  /// 取消事实订阅与位置订阅；已积累的区间经 [settleAndFlush] 收口，本方法
  /// 不落盘。
  Future<void> dispose() async {
    _disposed = true;
    _ledger.breakRun();
    await _subscription.cancel();
    await _positionSubscription?.cancel();
  }

  Future<void> _onFacts(PracticeAccountingFacts facts) async {
    if (_disposed) return;
    _facts = facts;
    // 标识事实由本类的关联状态交出（解析窗口内不计）。
    final counted = evaluatePracticeAccounting(
      PracticeAccountingFacts(
        enginePlaying: facts.enginePlaying,
        clipReviewInFlight: facts.clipReviewInFlight,
        recordingPreparing: facts.recordingPreparing,
        delayedPlayPreparing: facts.delayedPlayPreparing,
        videoIdentified: _videoId != null && _videoId!.isNotEmpty,
      ),
    ).counted;
    final runStart = _runStart;
    final now = _clock();
    _counted = counted;
    if (counted) {
      // 回「计」且引擎在播（counted 蕴含在播）：从当下新开/延续区间。
      _runStart ??= now;
      return;
    }
    // 翻到「不计」：在翻转点结算当前区间，并断开桶的连续推进；不计期间
    // 保持不在账。
    _runStart = null;
    _ledger.breakRun();
    if (runStart != null && now.isAfter(runStart)) {
      await _settleRun(runStart, now);
    }
  }

  /// 位置采样：把判定为「计」的采样点喂给四拍桶账本，桶账写进该舞分片。
  Future<void> _onPosition(Duration position) async {
    if (_disposed) return;
    final bucketStore = buckets;
    if (bucketStore == null) return;
    final videoId = _videoId;
    if (!_counted || videoId == null || videoId.isEmpty) {
      _ledger.breakRun();
      return;
    }
    final credits = _ledger.addSample(
      wall: _clock(),
      mediaPosition: position,
      grid: grid?.call(),
      density: density?.call() ?? 1,
    );
    if (credits.isEmpty) return;
    await bucketStore.recordCredits(
      videoId: videoId,
      signature: _recordSignature,
      credits: credits,
    );
  }

  Future<void> _settleRun(DateTime runStart, DateTime end) async {
    final videoId = _videoId;
    if (videoId == null || videoId.isEmpty) return;
    await store.recordPlaying(
      videoId: videoId,
      signature: _recordSignature,
      start: runStart,
      end: end,
    );
    // 暂停/到尾即结算落盘（结算时机）。
    await store.settle();
    await buckets?.settle();
  }

  /// 记账署名快照：署名歌曲名为空（未署名）时回退文件名。
  SongSignature get _recordSignature {
    final signature = _signature;
    if (signature != null && signature.song.isNotEmpty) return signature;
    return SongSignature(song: _fallbackName);
  }
}
