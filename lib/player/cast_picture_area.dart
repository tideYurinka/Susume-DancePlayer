/// 投屏态的画面区与投屏胶囊（票 #32）：这一族只在投屏态出现，画面区不画源片。
///
/// - [CastPictureArea]：画面区两种面——**黑底 + 一行指路提示**（默认）与
///   **静音本地预览**（画面开关打开后）。预览**只画视频画面本身**：贴纸、
///   数拍、节拍动画与画面标识都不画（它们已在电视上），且**不可交互**——
///   本件不挂任何手势，落在它上面的手势归画面层既有那条手势面（遥控电视）。
/// - [CastStatusCapsule]：**投屏-观看态**下屏上那枚只读状态件，写明
///   「投屏中 · 接收端名」。它自身不接任何手势、不接任何动作，落在它身上的
///   点按被它吞掉（防误触）——要操作就先点画面（胶囊之外）展开控制层。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cast_preview.dart' show castPreviewEngineProvider, castPreviewProvider;
import 'cast_run.dart' show castRunProvider;
import 'visual_tokens.dart' show kNoticeTextStyle;

/// 投屏态的画面区：默认黑底 + 指路提示，画面开关打开后切静音本地预览。
class CastPictureArea extends ConsumerWidget {
  const CastPictureArea({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(castPreviewProvider);
    return ColoredBox(
      key: const Key('cast_picture_area'),
      color: Colors.black,
      child: on ? const _CastPreviewSurface() : const _CastPictureHint(),
    );
  }
}

/// 默认面：黑底 + 一行「画面显示从哪里开」的指路提示。
///
/// 这一行是**唯一**的指路手段：投屏态不本地放源片（两份不同步的画面只会互相
/// 干扰），要看就自己去顶栏打开那枚开关。
class _CastPictureHint extends StatelessWidget {
  const _CastPictureHint();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          '想看画面就打开顶栏的「画面开关」',
          key: Key('cast_picture_hint'),
          style: kNoticeTextStyle,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

/// 预览面：兄弟内核那条画面件（画面由内核自供，本件只摆位）。
///
/// 画面件取一次即缓存（`buildVideoSurface` 契约：返回的控件自持资源、跨
/// rebuild 复用）；本件只在开关打开时挂载，关掉即整件退场。
class _CastPreviewSurface extends ConsumerStatefulWidget {
  const _CastPreviewSurface();

  @override
  ConsumerState<_CastPreviewSurface> createState() =>
      _CastPreviewSurfaceState();
}

class _CastPreviewSurfaceState extends ConsumerState<_CastPreviewSurface> {
  late final Widget _surface = KeyedSubtree(
    key: const Key('cast_preview_surface'),
    child: ref.read(castPreviewEngineProvider).buildVideoSurface(),
  );

  @override
  Widget build(BuildContext context) => _surface;
}

/// 投屏胶囊：**投屏-观看态**下屏上那枚只读状态件（「投屏中 · 接收端名」）。
///
/// **它不接任何手势**：点按落在它身上被 [AbsorbPointer] 吞掉，不产生任何状态
/// 变化（防误触——练习时手上有汗也不至于一碰就把控制层唤出来）。要操作就点
/// 画面（胶囊之外）：那条是既有画面点按路径，不新增手势。
class CastStatusCapsule extends ConsumerWidget {
  const CastStatusCapsule({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receiver = ref.watch(
      castRunProvider.select((state) => state.receiver),
    );
    if (receiver == null) return const SizedBox.shrink();
    final gesture = MediaQuery.systemGestureInsetsOf(context);
    return Positioned(
      left: 0,
      right: 0,
      bottom: 12 + gesture.bottom,
      child: Center(
        child: AbsorbPointer(
          child: Semantics(
            key: const Key('cast_status_capsule'),
            readOnly: true,
            label: '投屏中 · ${receiver.friendlyName}',
            child: ExcludeSemantics(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cast, size: 18, color: Colors.white70),
                    const SizedBox(width: 6),
                    Text(
                      '投屏中 · ${receiver.friendlyName}',
                      style: kNoticeTextStyle,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
