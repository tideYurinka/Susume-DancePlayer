part of 'annotation_editor.dart';

// 练习视频轨的在轨片段 store（落库，随片段
// 激活回看收进标注编辑模块库——激活互斥的清除写缝在模块库内 library
// 私有，片段激活与学习段/临时衔接段激活同属一条激活单值纪律）。

/// 练习视频轨的在轨片段：当前舞的练习片段列表
/// 会话态。恢复读随舞私密 `prefs.practiceClips`（settings_persistence）；
/// 录制完成经 [PracticeClipsModel.addFromMaterial] 入轨——重录重叠只清理
/// 轨道引用（纯函数 [pruneClipsOverlappedBy]），素材与库内条目不动。
///
/// 写回口径：本 lane 是 `prefs.practiceClips` 整表字段的会话真值。打开装载
/// 把该文档既有片段恢复进本 lane（[restore]）后，写回即会话的完整视图。
///
/// 写面收口（见词条「练习视频轨」）：对外只开三类
/// 具名入口——装载（[restore]，以文档值为准）/ 登记录制产出
/// （[addFromMaterial]）/ 按素材删除引用（[removeByMaterial]）；整表写只有
/// 库内一条私有写缝 [_replace]，编辑 verb 提交与撤销/重做回放经它落表
/// （本模型与标注编辑模块同 library）。装载与入轨经
/// [normalizePracticeClipTable] 落表：乱序或重叠输入落表后恒按源起点升序、
/// 两两不重叠。落盘归属不动：仍归随舞 prefs 编排唯一写入者。
class PracticeClipsModel extends Notifier<List<PracticeClip>> {
  @override
  List<PracticeClip> build() => const [];

  /// 装载（以文档值为准）：换会话 `装载(空)`、读到文档后
  /// `装载(doc.practiceClips)`，两次都在装载门窗口内（装载门与一个
  /// loader / 一个 persister 不变）。装载不自动播放、不改播放位置；经规范
  /// 化落表。
  void restore(List<PracticeClip> clips) =>
      _replace(normalizePracticeClipTable(clips));

  /// 库内整表写缝（私有）：截取提交、装载与撤销/重做回放共用的终值整表
  /// 写回。写后不变量：表里没有的片段不能还在
  /// 回看——写后激活片段已不在表上即清激活（[PracticeClipActivationModel]
  /// 的 `exitReview` 是激活清写的唯一入口；部件层退出收口
  /// `exitPracticeClipReview` 在其上叠加清选中槽，模型层不持 WidgetRef）。
  /// verb 删除 / 素材连带删除 / 回放移除三条删除路径由此在同一次写里清
  /// 激活，练习半区回落实时预览，悬空激活不可表达。
  void _replace(List<PracticeClip> clips) {
    state = clips;
    final active = ref.read(practiceClipActivationProvider);
    if (active != null && practiceClipById(clips, active.clipId) == null) {
      ref.read(practiceClipActivationProvider.notifier).exitReview();
    }
  }

  /// 登记录制产出：建 1:1 片段（截取范围 = 素材全长 − 前言：入点 = 前言
  /// 长度），先按新片段的源时间区间清理旧引用（完全覆盖删除、部分
  /// 重叠裁到不重叠），再经规范化落表（恒升序、不重叠）。
  void addFromMaterial(MaterialRecord record, {int preambleMs = 0}) {
    final clip = PracticeClip.fullLength(
      id: 'clip_${record.id}',
      material: record,
      preambleMs: preambleMs,
    );
    _replace(
      normalizePracticeClipTable([
        ...pruneClipsOverlappedBy(
          state,
          IntervalSpan(startMs: clip.sourceStartMs, endMs: clip.sourceEndMs),
        ),
        clip,
      ]),
    );
  }

  /// 素材删除连带：移除引用该素材的全部轨道片段（截取范围各异的
  /// 多条引用一并清）。素材清单与文件归素材库删除路径；写回以本 lane 终值
  /// 为准，删掉的引用不被放回。
  void removeByMaterial(String materialId) {
    _replace([
      for (final clip in state)
        if (clip.materialId != materialId) clip,
    ]);
  }
}

final practiceClipsProvider =
    NotifierProvider<PracticeClipsModel, List<PracticeClip>>(
      PracticeClipsModel.new,
    );

/// 选中的练习片段 id（落读取缝；落写点与清理）：对比-控制
/// 层「删除」槽的作用对象（选中槽）。
/// 写点 = 练习视频轨块体点选（再点同片段取消）；选中片段被移出轨道（删除/
/// 撤销/重叠清理）时自动整清，槽随之回「无对象」置灰。
class SelectedPracticeClipModel extends Notifier<String?> {
  @override
  String? build() {
    ref.listen<List<PracticeClip>>(practiceClipsProvider, (_, clips) {
      final selected = state;
      if (selected != null && !clips.any((clip) => clip.id == selected)) {
        state = null;
      }
    });
    return null;
  }

  void select(String? clipId) {
    state = clipId;
  }
}

final selectedPracticeClipIdProvider =
    NotifierProvider<SelectedPracticeClipModel, String?>(
      SelectedPracticeClipModel.new,
    );

/// 退出练习片段回看：清激活（落盘）并清选中槽——画面常驻出口件与编辑态
/// 回看浮条共用的唯一退出写入口；无回看时幂等 no-op。
void exitPracticeClipReview(WidgetRef ref) {
  ref.read(practiceClipActivationProvider.notifier).exitReview();
  ref.read(selectedPracticeClipIdProvider.notifier).select(null);
}
