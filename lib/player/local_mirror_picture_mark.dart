/// 局部镜像画面标识：局部镜像生效那一刻画在画面上的纯显示件——一圈向内
/// 2dp 的琥珀色直角细边框 + 画面矩形右下角内侧 8dp 的「局部镜像」角标。
///
/// **纯显示层**：整件由 [IgnorePointer] 包住，不进命中测试、不与播放手势争。
/// 出现条件、层序与矩形口径都归调用点：调用点在局部镜像生效时把本件按画面
/// 内容矩形（对比态 = 源视频半区矩形）挂进共享 Stack，且在视频画面之上、
/// 节拍动画浮层与备注贴纸之下。本件只按调用点给的矩形安放边框与角标。
library;

import 'package:flutter/material.dart';

import 'visual_tokens.dart';

/// 标识整件的稳定 key（测试按它取整件几何 = 调用点给的画面矩形）。
const Key kLocalMirrorPictureMarkKey = Key('local_mirror_picture_mark');

/// 边框件的稳定 key（测试按它取描边取值与几何）。
const Key kLocalMirrorPictureMarkBorderKey = Key(
  'local_mirror_picture_mark_border',
);

/// 角标件的稳定 key（测试按它取角标几何）。
const Key kLocalMirrorPictureMarkBadgeKey = Key(
  'local_mirror_picture_mark_badge',
);

/// 边框宽度（dp，贴矩形向内画、直角）。
const double kLocalMirrorPictureMarkBorderWidth = 2;

/// 角标贴矩形右下角的内缩（dp）。
const double kLocalMirrorPictureMarkBadgeInset = 8;

/// 角标文案。
const String kLocalMirrorPictureMarkLabel = '局部镜像';

/// 角标图标（与顶栏「局部镜像」槽同款）。
const IconData kLocalMirrorPictureMarkIcon = Icons.flip_camera_android;

/// 角标胶囊底色不透明度（黑底半透明）。
const double kLocalMirrorPictureMarkBadgeFillOpacity = 0.45;

/// 角标胶囊圆角半径。
const double kLocalMirrorPictureMarkBadgeRadius = 12;

/// 局部镜像画面标识（纯显示件，无状态、无回调）。
///
/// 由调用点用 `Positioned.fromRect` 摆在画面矩形上：整件尺寸即该矩形，边框
/// 沿四边向内画，角标贴右下角内侧 [kLocalMirrorPictureMarkBadgeInset]。
class LocalMirrorPictureMark extends StatelessWidget {
  const LocalMirrorPictureMark({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      key: kLocalMirrorPictureMarkKey,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            key: kLocalMirrorPictureMarkBorderKey,
            decoration: BoxDecoration(
              border: Border.fromBorderSide(
                BorderSide(
                  color: kLocalMirrorEnabledColor,
                  width: kLocalMirrorPictureMarkBorderWidth,
                ),
              ),
            ),
          ),
          Positioned(
            right: kLocalMirrorPictureMarkBadgeInset,
            bottom: kLocalMirrorPictureMarkBadgeInset,
            child: DecoratedBox(
              key: kLocalMirrorPictureMarkBadgeKey,
              decoration: BoxDecoration(
                color: Colors.black.withValues(
                  alpha: kLocalMirrorPictureMarkBadgeFillOpacity,
                ),
                borderRadius: BorderRadius.circular(
                  kLocalMirrorPictureMarkBadgeRadius,
                ),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      kLocalMirrorPictureMarkIcon,
                      size: 14,
                      color: kLocalMirrorEnabledColor,
                    ),
                    SizedBox(width: 4),
                    Text(
                      kLocalMirrorPictureMarkLabel,
                      style: TextStyle(
                        color: kLocalMirrorEnabledColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
