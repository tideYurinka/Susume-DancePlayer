import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/current_beat.dart' show LeadingBeatCount;
import 'compare_recording.dart' show recordingPrepBeatProvider;
import 'beat_presentation_providers.dart'
    show delayAnchorProvider, publishedBeatProvider;

/// 视频区正中的大数字键：录制准备期与延迟预备期显示前导数拍，
/// 起录 / 越延迟起点即消失。
const Key kPrepCenterBigNumberKey = Key('prep_center_big_number');

/// 大数字字号：录制准备期须一眼看出还没开录——数字在视频区中央要足够
/// 醒目（80），同时仍让人看得见画面。
const double kPrepCenterBigNumberFontSize = 80;

/// 居中大数字的字面：与浮层数拍**同一份** `八拍号｜拍号`。
String prepCenterBigNumberOf(LeadingBeatCount display) =>
    '${display.eightCount}｜${display.beatCount}';

/// 录制准备期 / 延迟预备期的**视频区正中大数字**（并入同一条求值）。
///
/// 数据源 = 节拍呈现对象的**发布值**（[publishedBeatProvider]）——与浮层数
/// 拍、节拍动画同一次求值、同一份 `八拍号｜拍号`，逐拍一致（不新开第二套
/// 前导计数）。数字只在发布值为**前导区**（八拍号 0，即录制锚 / 延迟锚就位
/// 且位置在锚点之前）时出现；越起录点 / 越延迟起点前导分支退出，数字即消
/// 失。网格异常与无锚可数已被「发布空值」吸收——无数字、不猜一个数。
///
/// 显示范围钉在**两支预备期**，不是一切前导（「录制准备与延迟预备的
/// 居中大数字并入同一条求值」；普通练习里锚点链推出的前导——如激活段首
/// 晚于当前位置——只有浮层亮，居中大数字不跟）：
/// - 录制准备 = [recordingPrepBeatProvider] 非空（宿主在准备期写入）；其中
///   秒制兜底支（`showsContent` = false：异常网格 / 起录点前无可用拍点）
///   整段不显示——「没有网格 / 没有可数拍点」与「有网格但不足」要可分辨，
///   与浮层存在性同一道门，数字本身仍只出自发布值；
/// - 延迟预备 = [delayAnchorProvider] 非空（触发延迟播放即交锚；打断 /
///   越点后位置不在锚前，数字自然不显）。
///
/// 位置 = 视频区几何中心（分屏态下跨素材侧/练习侧，不落在任一半区中心）。
/// 纯视觉、不拦截触摸。
class PrepCenterBigNumber extends ConsumerWidget {
  const PrepCenterBigNumber({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prepVisual = ref.watch(recordingPrepBeatProvider);
    final inRecordingPrep = prepVisual != null;
    final inDelayedPrep = ref.watch(delayAnchorProvider) != null;
    if (inRecordingPrep ? !prepVisual.showsContent : !inDelayedPrep) {
      return const SizedBox.shrink();
    }
    final value = ref.watch(publishedBeatProvider);
    final display = value?.display;
    if (display is! LeadingBeatCount) return const SizedBox.shrink();
    return IgnorePointer(
      child: Center(
        child: Container(
          key: kPrepCenterBigNumberKey,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(20),
          ),
          // 数字与既有数拍浮层同色系（白·粗），但字号大一个量级——「中心
          // 大数字」与角落浮层一眼可分辨。
          child: Text(
            prepCenterBigNumberOf(display),
            style: const TextStyle(
              color: Colors.white,
              fontSize: kPrepCenterBigNumberFontSize,
              height: 1.0,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
