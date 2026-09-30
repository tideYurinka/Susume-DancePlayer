import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../annotation/compare_materials.dart';
import '../core/clock_text.dart';
import '../dance/dance_library.dart';
import '../dance/dance_library_providers.dart';
import '../persistence/material_manifest.dart';
import '../share/dance_share_sheet.dart';
import 'annotation_editor.dart' show practiceClipsProvider;

/// 当前舞的 videoId 会话值：播放页在署名解析监听里写入，素材库
/// 子页据此装载当前舞的素材；未解析为 null（子页按空态呈现）。
class CurrentVideoIdModel extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? videoId) => state = videoId;
}

final currentVideoIdProvider = NotifierProvider<CurrentVideoIdModel, String?>(
  CurrentVideoIdModel.new,
);

/// 练习素材库会话态：当前舞的素材列表。装载读素材清单（按
/// videoId 过滤）；删除 = 素材文件 + 清单条目 + 该素材在轨道上的全部
/// 引用一起消失。
class MaterialLibraryModel extends Notifier<List<MaterialRecord>> {
  @override
  List<MaterialRecord> build() => const [];

  /// 打开子页的装载入口：先清上一舞残留（跨舞切换/未解析都不得呈现旧
  /// 列表），再按 videoId 读清单装载；videoId 为 null 保持空态。
  Future<void> openFor(String? videoId) async {
    state = const [];
    if (videoId != null) await loadFor(videoId);
  }

  /// 装载当前舞的素材（读清单按 videoId 过滤）。清单不可读维持现态、不抛错。
  Future<void> loadFor(String videoId) async {
    try {
      final doc = await ref.read(materialManifestStoreProvider).read();
      state = [
        for (final entry in doc.materials)
          if (entry.videoId == videoId) entry,
      ];
    } on Object {
      // 清单不可读：维持现态（首次打开即空态）。
    }
  }

  /// 删除一条素材：先删文件与清单条目（各自尽力而为，互不阻断），再连带
  /// 删轨道引用与会话列表。
  Future<void> remove(MaterialRecord record) async {
    try {
      final base = await ref.read(materialsBaseDirectoryProvider)();
      final file = File(
        materialFilePathIn(base.path, record.videoId, record.fileName),
      );
      if (file.existsSync()) file.deleteSync();
    } on Object {
      // 文件已缺或删除失败：继续清引用侧，不留下幽灵条目。
    }
    try {
      await ref.read(materialManifestStoreProvider).remove(record.id);
    } on Object {
      // 清单写失败：会话内仍删，文件侧下次装载按清单现态呈现。
    }
    if (!ref.mounted) return;
    ref.read(practiceClipsProvider.notifier).removeByMaterial(record.id);
    state = [
      for (final entry in state)
        if (entry.id != record.id) entry,
    ];
  }
}

final materialLibraryProvider =
    NotifierProvider<MaterialLibraryModel, List<MaterialRecord>>(
      MaterialLibraryModel.new,
    );

/// 录制时刻显示（yyyy-MM-dd HH:mm）。
String formatMaterialTimestamp(DateTime time) =>
    '${time.year}-${time.month.toString().padLeft(2, '0')}-'
    '${time.day.toString().padLeft(2, '0')} '
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';

/// 练习素材库子页（入口在详情页接线）：当前舞素材列表——条目显示录制区间 /
/// 时长 / 录制时刻；删除需确认（提示连带删除全部轨道引用），确认后文件、
/// 清单条目与轨道引用一起消失。
class MaterialLibraryPage extends ConsumerStatefulWidget {
  const MaterialLibraryPage({super.key});

  @override
  ConsumerState<MaterialLibraryPage> createState() =>
      _MaterialLibraryPageState();
}

class _MaterialLibraryPageState extends ConsumerState<MaterialLibraryPage> {
  @override
  void initState() {
    super.initState();
    // openFor 同步清 state：推迟到首帧后，不在 build 期改 provider。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(materialLibraryProvider.notifier)
          .openFor(ref.read(currentVideoIdProvider));
    });
  }

  /// 发给小组：按 videoId 取舞快照，走与详情页
  /// 「分享」同一个分享面，只换初始勾选——熟练度与该条录像勾、源视频不勾。
  /// 单支舞入口由整库读面派生，这里因此装入整库（每舞两份小 JSON）；分享是
  /// 用户点按的低频动作，量小可接受，不为它另开窄读面。
  Future<void> _sendToGroup(MaterialRecord record) async {
    DanceSnapshot? dance;
    try {
      dance = await ref.read(danceSnapshotProvider(record.videoId).future);
    } on Object {
      dance = null;
    }
    if (!mounted) return;
    if (dance == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('暂时无法分享这支舞')));
      return;
    }
    final snapshot = dance;
    await showDialog<void>(
      context: context,
      builder: (_) => DanceShareSheet(
        dance: snapshot,
        initialIncludeSourceVideo: false,
        initialIncludeMastery: true,
        initialClipIds: [record.id],
      ),
    );
  }

  Future<void> _confirmRemove(MaterialRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('material_library_delete_dialog'),
        content: const Text('将连其全部轨道引用一并删除'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('material_library_confirm_delete'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(materialLibraryProvider.notifier).remove(record);
    }
  }

  @override
  Widget build(BuildContext context) {
    final materials = ref.watch(materialLibraryProvider);
    return SafeArea(
      child: SizedBox(
        key: const Key('material_library_page'),
        // 素材库浮层底板高 320：吃**竖屏**屏高（横屏下底板会占可用高近九
        // 成，"约半屏"只在竖屏口径下成立）。取值按内容论证：标题一行 +
        // 约三行条目 + 余量；条目更多时列表区内滚动，底板高不随行数增长。
        height: 320,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('练习素材库', style: TextStyle(fontSize: 16)),
            ),
            const Divider(height: 1),
            Expanded(
              child: materials.isEmpty
                  ? const Center(
                      child: Text('暂无练习素材', key: Key('material_library_empty')),
                    )
                  : ListView.builder(
                      itemCount: materials.length,
                      itemBuilder: (context, index) {
                        final record = materials[index];
                        return ListTile(
                          key: Key('material_library_entry_$index'),
                          title: Text(
                            '${clockMmSs(Duration(milliseconds: record.sourceStartMs))}'
                            ' - '
                            '${clockMmSs(Duration(milliseconds: record.sourceStartMs + record.durationMs))}',
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '时长 ${clockMmSs(Duration(milliseconds: record.durationMs))}',
                              ),
                              Text(
                                '录制于 ${formatMaterialTimestamp(record.createdAt)}',
                              ),
                            ],
                          ),
                          isThreeLine: true,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                key: Key('material_library_send_$index'),
                                icon: const Icon(Icons.send_outlined),
                                tooltip: '发给小组',
                                onPressed: () => _sendToGroup(record),
                              ),
                              IconButton(
                                key: Key('material_library_delete_$index'),
                                icon: const Icon(Icons.delete_outline),
                                tooltip: '删除',
                                onPressed: () => _confirmRemove(record),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
