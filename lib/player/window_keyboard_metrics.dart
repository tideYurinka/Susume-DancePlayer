import 'package:flutter/widgets.dart';

/// 窗口键盘感知取数共用件。
///
/// 对外只回答一件事：当前窗口的真实键盘下沿 inset 与视口尺寸，并在窗口
/// metrics 变化时驱动消费方重建。消费者（倍速气泡 / 命名对话框 / 横屏输入
/// 条）不能依赖 context 的 MediaQuery——Scaffold body 内 viewInsets 被清零，
/// inherited 值不变不触发重建；因此直接取窗口值。
class WindowMetricsWatcher extends StatefulWidget {
  const WindowMetricsWatcher({super.key, required this.builder});

  final Widget Function(BuildContext context, MediaQueryData viewData) builder;

  @override
  State<WindowMetricsWatcher> createState() => _WindowMetricsWatcherState();
}

class _WindowMetricsWatcherState extends State<WindowMetricsWatcher>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, MediaQueryData.fromView(View.of(context)));
  }
}
