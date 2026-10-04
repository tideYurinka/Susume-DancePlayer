/// 节拍分析库：节拍分析运行器与它的管线注入 seam；节拍网格
/// 读取面（`beatGridProvider`）归 beat_track_state 小库——声音链与其余
/// 消费方同读它，落盘拍点即规整产物，声音侧没有第二套网格。
///
/// 契约：触发/取消/落盘/重试规则见 [BeatAnalysisRunner]；管线注入点见
/// [beatAnalysisPipelineProvider]。
///
/// 依赖方向（单向）：只依赖 beat 纯域/管线、beat_track_state 小库、
/// persistence 文档类型、标注编辑模块与节拍提示/声音设置小库，零 import
/// 中枢；反向不可。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../annotation/auto_segment.dart' show kAutoSegmentDefaultTier;
import '../beat/beat_pipeline.dart';
import '../beat/preprocess.dart' show kBeatFps;
import '../beat_track_state/beat_track_state.dart'
    show BeatTrackState, beatTrackStateProvider;
// BeatGrid 文档类与 core/beat_grid.dart 的网格 seam 接口同名，别名引入。
import '../persistence/annotation_save_orchestrator.dart'
    show AnnotationSaveSeed, firstBuildSeeded;
import '../persistence/document_read_outcome.dart';
import '../persistence/marker_document.dart'
    as marker_doc
    show BeatGrid, MarkersDocument;
import '../persistence/video_document_store.dart' show VideoDocumentCoordinator;
import 'annotation_editor.dart' show annotationEditorProvider;
import 'beat_prompt_memory.dart' show beatPromptMemoryProvider;
import 'song_loudness.dart' show songLoudnessCoordinatorProvider;

/// 节拍分析管线注入点：生产实现为 ffmpeg + Dart 前处理 +
/// 纯 RNN ONNX + Dart DBN（真机验证方案）；测试注入 fake（不依赖真实
/// 解码/推理）。
final beatAnalysisPipelineProvider = Provider<BeatAnalysisPipeline>(
  (ref) => OnnxBeatAnalysisPipeline(),
);

/// 节拍分析运行器：打开视频且
/// markers 无 beat → 后台自动分析一次（不阻塞播放、不排队，一次只一个）；
/// 完成经协调器原子写 `markers.beat`（字段级 patch，署名等并发写不覆盖）
/// 并即时切真实网格；离开页面/新分析接管取消——不写半截；失败置异常态、
/// markers 仍无 beat，下次打开自动重试；已有 beat 永不重算。
class BeatAnalysisRunner {
  BeatAnalysisRunner(this._ref);

  final Ref _ref;

  /// 代际号：自增即取消在途分析（离开页面/新视频打开/新分析接管）。
  int _generation = 0;

  /// 启动一次分析。[videoPath] 为当前视频源文件；[coordinator] 为当前
  /// 视频的文档协调器（写回经其串行 patch）；[seed] 供给 markers 首建
  /// 初值（index 署名缓存 + 镜像过渡值，markers 出生即带完整
  /// 署名与镜像——节拍写回是首建时机之一）。[videoId] 非空时解码顺带
  /// 测量歌曲响度基准（经响度基准编排按视频落盘）。
  Future<void> start({
    required String videoPath,
    required VideoDocumentCoordinator coordinator,
    required Future<AnnotationSaveSeed> Function() seed,
    String? videoId,
  }) async {
    final generation = ++_generation;
    if (!_ref.mounted) return;
    _ref
        .read(beatTrackStateProvider.notifier)
        .replace(const BeatTrackState.placeholder());
    final pipeline = _ref.read(beatAnalysisPipelineProvider);
    try {
      final beats = await pipeline.analyze(
        BeatAnalysisRequest(
          videoPath: videoPath,
          isCancelled: () => generation != _generation,
          onPcmRms: videoId == null
              ? null
              : (rms) {
                  // 代际复核：checkCancelled 与回调之间的竞态窗口内换视频
                  // 时，不写会话基准（旧测量按旧 videoId 落盘无害，但不得
                  // 覆盖新视频已对齐的会话基准）。
                  if (generation != _generation) return;
                  if (!_ref.mounted) return;
                  _ref
                      .read(songLoudnessCoordinatorProvider)
                      .recordRms(videoId, rms);
                },
        ),
      );
      if (generation != _generation) return; // 取消：不写半截。
      final doc = marker_doc.BeatGrid(
        model: kBeatModelAsset,
        fps: kBeatFps,
        generatedAt: DateTime.now().toUtc(),
        beats: beats,
      );
      final outcome = await coordinator.readMarkersOutcome();
      if (outcome is WritableDocumentReadOutcome<marker_doc.MarkersDocument>) {
        await outcome.write((context) async {
          // 已有 beat 永不重算：与打开恢复的触发判定同一口径——beat 段
          // 存在且含拍点才跳写（空 beats 视为缺失/损坏形态，允许重算，
          // 避免空跑推理且结果永不落盘）。
          final existingBeat = context.document.beat;
          if (existingBeat != null && existingBeat.beats.isNotEmpty) {
            return context.document;
          }
          // 文件缺失/损坏的首建时机：以 index 署名/镜像初值立底
          // （firstBuildSeeded 与保存编排器共用同一立底语义）。
          final s = await seed();
          final base = firstBuildSeeded(
            context.document,
            present: context.present,
            seed: s,
          );
          return base.withBeat(doc);
        });
      }
      // 只读文件（低于地板 / 高于本版 / 版本头读不出）写不回去：本次会话
      // 照用刚识别的网格（与既有「写失败静默、内存态可用」同款），下次
      // 打开仍按原文件重试。写回只从可写读结局发生。
      if (generation != _generation || !_ref.mounted) return;
      _ref
          .read(beatTrackStateProvider.notifier)
          .replace(BeatTrackState.ready(doc));
      // 分析完成（占位→就绪）即自动执行一次「自动分段」（自动首尾
      // + 每段 4 个整八拍区间下刀），无弹窗；整动作一次
      // 可撤销标注编辑。仅新分析完成
      // 触发——已有 beat 的打开恢复不重算也不重放（分段沿用落盘值）。
      // 不受「锁定分段」门禁：锁定约束的是用户编辑入口（钮/手势），自动
      // 分段是分析完成的一次性系统动作，且可一步撤销。
      _ref
          .read(annotationEditorProvider)
          .submitAutoSegment(
            doc,
            fullIntervalsPerSegment: kAutoSegmentDefaultTier,
          );
      // 新分析成功落定的同一成功分支、同一同步块内走自动置开
      // 一次的唯一判据落点（三条件：记忆无记录或为「本轮未表态的旧记
      // 录」、网格真实就绪——上一行已切就绪、记忆已读到且与本支舞身份
      // 对齐），置开即写进这支舞的记忆；取消与失败路径不走这里，零写入。
      // 未识别身份（videoId 空）无落盘目标，不置开。
      if (videoId != null) {
        _ref
            .read(beatPromptMemoryProvider.notifier)
            .autoEnableFor(videoId, freshAnalysis: true);
      }
    } on BeatAnalysisCancelled {
      // 中断不置异常：下次打开自动重试。
    } on Object {
      // 容器已销毁（测试收尾/应用退出）则不再触碰 provider。
      if (_ref.mounted && generation == _generation) {
        _ref
            .read(beatTrackStateProvider.notifier)
            .replace(const BeatTrackState.error());
      }
    }
  }

  /// 取消在途分析（离开播放页/打开新视频）。
  void cancel() {
    _generation++;
  }
}

/// 节拍分析运行器注入点：keepAlive（应用会话级单例，代际号跨视频持有，
/// 取消语义不依赖 provider 生命周期）。
final beatAnalysisRunnerProvider = Provider<BeatAnalysisRunner>((ref) {
  ref.keepAlive();
  return BeatAnalysisRunner(ref);
});
