import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'help_image_save.dart';
import 'help_root_navigator.dart';

/// 全屏大图查看器（**大图查看**）：黑底、图按原比例居中显示、可双指缩放与
/// 拖动；关闭三路齐备——点查看器里任意位置（点图与点黑边一个样）、右上角
/// 关闭钮、系统返回。顶部显示该图的 Markdown alt 作标题，没有 alt 就不显示
/// 这一行；除那枚关闭钮外不常驻任何按钮，也不出「长按可保存」之类的提示。
/// 长按大图（含黑边）直接把这张图存进系统相册，与正文缩略图那处长按同一条
/// 链路，长按不关查看器。
class HelpImageViewer extends ConsumerWidget {
  const HelpImageViewer({
    super.key,
    required this.assetKey,
    required this.bundle,
    this.alt,
  });

  /// 正文里那张图的同目录资产 key。
  final String assetKey;

  /// 图的字节所在资产包（渲染件从它自己的那份读，测试里因此仍在环上）。
  final AssetBundle bundle;

  /// 该图的 Markdown alt 文字；null 或空串时不显示标题行。
  final String? alt;

  /// 打开这一层全屏查看器（**大图查看**的唯一入口，三处宿主共用）。
  ///
  /// 走根 Navigator 推入：文档页与关于页本来就在根 Navigator 里；一次性图文卡
  /// 在它**上方**、没有祖先 Navigator 可查，经 [helpRootNavigatorState] 取那棵
  /// 根 Navigator——与卡里「打开完整正文页」同一条通路，查看器才盖得住卡。
  static void open(
    BuildContext context, {
    required String assetKey,
    required AssetBundle bundle,
    String? alt,
  }) {
    final navigator =
        Navigator.maybeOf(context, rootNavigator: true) ??
        helpRootNavigatorState();
    navigator?.push(
      MaterialPageRoute<void>(
        builder: (_) =>
            HelpImageViewer(assetKey: assetKey, bundle: bundle, alt: alt),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      key: const Key('help_image_viewer'),
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
              onLongPress: () => saveHelpImage(
                ref,
                context,
                bundle: bundle,
                assetKey: assetKey,
              ),
              child: InteractiveViewer(
                maxScale: 5,
                child: Image(
                  key: const Key('help_image_viewer_image'),
                  image: AssetImage(assetKey, bundle: bundle),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
          if (alt != null && alt!.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: SafeArea(
                bottom: false,
                child: IgnorePointer(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(56, 12, 56, 12),
                    child: Text(
                      alt!,
                      key: const Key('help_image_viewer_title'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: IconButton(
                key: const Key('help_image_viewer_close'),
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
