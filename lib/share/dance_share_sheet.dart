import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../annotation/compare_materials.dart';
import '../annotation/learning_segment_attributes.dart';
import '../core/clock_text.dart';
import '../core/system_page_text_colors.dart';
import '../dance/dance_library.dart';
import '../package/susume_package.dart';
import '../persistence/material_manifest.dart';
import '../persistence/video_document_providers.dart';
import '../persistence/video_document_store.dart';
import '../share_channel/share_channel.dart';
import 'dance_share.dart';
import 'outbound_scheme_id.dart';

/// 分享面：详情页「⋯」→「分享」弹出的那一面——
/// 源视频／熟练度／练习录像三项勾选 + 包体预检 + 确认递出。
///
/// 默认值：源视频勾（对方可能没有这支舞）、熟练度与练习录像不勾。素材库
/// 「发给小组」入口走**同一个面、同一套勾选框**，
/// 只换初始勾选：熟练度与该条练习录像勾、源视频不勾（[initialIncludeMastery]
/// / [initialClipIds] / [initialIncludeSourceVideo]）。分享只含**我的标注
/// 方案**（`markers_<hash>.json` 原文），不含组员方案。确认后装配
/// `.susume` 到 [susumeShareDirectoryProvider]（应用目录内、出站
/// FileProvider 覆盖的位置），经 [shareChannelProvider] 递出**原文件**
/// （零复制，不产生缓存副本）。装配或递出失败 SnackBar 出声，不静默。
class DanceShareSheet extends ConsumerStatefulWidget {
  const DanceShareSheet({
    super.key,
    required this.dance,
    this.initialIncludeSourceVideo = true,
    this.initialIncludeMastery = false,
    this.initialClipIds = const <String>[],
  });

  final DanceSnapshot dance;
  final bool initialIncludeSourceVideo;
  final bool initialIncludeMastery;
  final List<String> initialClipIds;

  @override
  ConsumerState<DanceShareSheet> createState() => _DanceShareSheetState();
}

class _DanceShareSheetState extends ConsumerState<DanceShareSheet> {
  late bool _includeSourceVideo = widget.initialIncludeSourceVideo;
  late bool _includeMastery = widget.initialIncludeMastery;
  late final Set<String> _selectedClipIds = Set.of(widget.initialClipIds);
  bool _sending = false;
  _SharePrecheck? _precheck;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final markers =
          await ref
              .read(videoDocumentStorageProvider(widget.dance.videoId))
              .loadShareableMarkersOrNull() ??
          const <String, dynamic>{};
      final manifest = await ref.read(materialManifestStoreProvider).read();
      final base = await ref.watch(materialsBaseDirectoryProvider)();
      final clips = [
        for (final record in manifest.materials)
          if (record.videoId == widget.dance.videoId)
            _ClipFile(
              record: record,
              file: File(
                materialFilePathIn(
                  base.path,
                  widget.dance.videoId,
                  record.fileName,
                ),
              ),
            ),
      ];
      if (!mounted) return;
      setState(
        () => _precheck = _SharePrecheck(markers: markers, clips: clips),
      );
    } on Object {
      if (!mounted) return;
      setState(() => _loadFailed = true);
    }
  }

  /// 按当前勾选组装媒体条目（预检估算与实包装配共用同一构造；条目自带
  /// 源文件，估算只用 sizeBytes，装配用 [SusumeMediaEntry.file]）。
  List<SusumeMediaEntry> _selectedMedia(_SharePrecheck precheck) {
    return [
      if (_includeSourceVideo)
        SusumeMediaEntry(
          kind: SusumeMediaKind.sourceVideo,
          fileName: p.basename(widget.dance.entry.filePath),
          // 大小取索引条目记录值：与包体预检同源，不为此多一次文件 IO。
          sizeBytes: widget.dance.entry.sizeBytes,
          file: File(widget.dance.entry.filePath),
        ),
      for (final clip in precheck.clips)
        if (_selectedClipIds.contains(clip.record.id))
          SusumeMediaEntry(
            kind: SusumeMediaKind.practiceClip,
            fileName: clip.record.fileName,
            sizeBytes: clip.record.sizeBytes,
            file: clip.file,
          ),
    ];
  }

  /// 装配清单：身份 + 逐段熟练度快照（只带显式设置过的段，缺项即未练，
  /// 与本地文档口径一致）+ 勾选媒体。
  Future<SusumeManifest> _buildManifest(
    _SharePrecheck precheck,
    List<SusumeMediaEntry> media,
  ) async => SusumeManifest(
    videoId: widget.dance.videoId,
    // 未署名（无歌名）时回落显示名——清单 schemeName 必填非空。
    schemeName: widget.dance.signature?.song.isNotEmpty == true
        ? widget.dance.signature!.song
        : widget.dance.title,
    schemeDancer: widget.dance.signature?.dancer ?? '',
    schemeRemark: widget.dance.signature?.remark ?? '',
    schemeId: await ref
        .read(outboundSchemeIdStoreProvider)
        .idFor(widget.dance.videoId),
    mastery: _includeMastery
        ? {
            for (final segment in widget.dance.segments)
              if (segment.mastery != LearningMastery.unlearned)
                segment.order: segment.mastery.index,
          }
        : null,
    media: media,
  );

  Future<void> _send() async {
    final precheck = _precheck;
    if (precheck == null || _sending) return;
    setState(() => _sending = true);
    try {
      final manifest = await _buildManifest(precheck, _selectedMedia(precheck));
      final output = await assembleDancePackage(
        outputDir: await ref.read(susumeShareDirectoryProvider.future),
        manifest: manifest,
        markers: precheck.markers,
        videoFileName: widget.dance.entry.displayName,
      );
      await ref.read(shareChannelProvider).shareFile(output);
      if (!mounted) return;
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    } on Object {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('分享失败，包未递出')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final precheck = _precheck;
    return Dialog(
      key: const Key('share_sheet'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '分享「${widget.dance.title}」',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '只分享「我的标注方案」，不含组员方案',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            // Flexible + 内部滚动：素材勾选区随
            // 素材条数增长，超高时勾选区滚动，「取消 / 分享」在滚动区之外、
            // 始终可达。
            if (precheck == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: _loadFailed
                    ? const Text('读取标注失败，暂时无法分享')
                    : const Center(
                        key: Key('share_sheet_loading'),
                        child: CircularProgressIndicator(),
                      ),
              )
            else
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CheckboxListTile(
                        key: const Key('share_sheet_source_video'),
                        title: const Text('带源视频'),
                        value: _includeSourceVideo,
                        onChanged: (v) =>
                            setState(() => _includeSourceVideo = v ?? false),
                      ),
                      CheckboxListTile(
                        key: const Key('share_sheet_mastery'),
                        title: const Text('带熟练度'),
                        value: _includeMastery,
                        onChanged: (v) =>
                            setState(() => _includeMastery = v ?? false),
                      ),
                      for (final clip in precheck.clips)
                        CheckboxListTile(
                          key: Key('share_sheet_clips_${clip.record.id}'),
                          title: Text(
                            precheck.clips.length == 1
                                ? '带练习录像'
                                // 多条时按录制区间区分，不暴露素材文件名。
                                : '带练习录像 '
                                      '${clockMmSs(Duration(milliseconds: clip.record.sourceStartMs))} - '
                                      '${clockMmSs(Duration(milliseconds: clip.record.sourceStartMs + clip.record.durationMs))}',
                          ),
                          value: _selectedClipIds.contains(clip.record.id),
                          onChanged: (v) => setState(() {
                            if (v ?? false) {
                              _selectedClipIds.add(clip.record.id);
                            } else {
                              _selectedClipIds.remove(clip.record.id);
                            }
                          }),
                        ),
                      Builder(
                        builder: (context) {
                          final estimate = estimateSusumeSizeBytes(
                            markers: precheck.markers,
                            media: _selectedMedia(precheck),
                          );
                          final nearLimit = susumeSizeNearWechatLimit(estimate);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              KeyedSubtree(
                                key: const Key('share_sheet_size'),
                                child: Text(
                                  '包体约 ${_formatBytes(estimate)}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                              if (nearLimit)
                                const KeyedSubtree(
                                  key: Key('share_sheet_size_warning'),
                                  child: Text(
                                    '接近微信单文件上限（1 GB），发送可能失败；仍可尝试递出',
                                    style: TextStyle(
                                      color: kShareWarningTextColor,
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key: const Key('share_sheet_cancel'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('share_sheet_send'),
                  onPressed: precheck == null || _loadFailed || _sending
                      ? null
                      : _send,
                  child: Text(_sending ? '正在打包…' : '分享'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

class _SharePrecheck {
  const _SharePrecheck({required this.markers, required this.clips});

  final Map<String, Object?> markers;
  final List<_ClipFile> clips;
}

class _ClipFile {
  const _ClipFile({required this.record, required this.file});

  final MaterialRecord record;
  final File file;
}
