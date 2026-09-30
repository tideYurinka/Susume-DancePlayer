import 'package:flutter/material.dart';

/// 封面占位图：灰底 + 影片图标——封面未就绪、缓存引用取不到或图片读取
/// 失败时的共同退路（首页卡片与舞详情横幅共用同一处样式）。
///
/// 尺寸由外层决定（卡片按图片自身比例、详情按固定高度横条），本件只画
/// 内容，不参与布局比例。
class CoverPlaceholder extends StatelessWidget {
  const CoverPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.movie_outlined,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
