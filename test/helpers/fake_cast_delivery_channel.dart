import 'dart:io';

import 'package:dance_learning_app/cast/cast_delivery_channel.dart';

/// 脚本化的假递出通道：记录被递出的文件、给出的地址与停服次数；可注入
/// 递出失败——投屏准备与投屏态的门与失败面经它测，不起真服务。
///
/// **如实建模真通道的一次性**：[close] 之后 [serve] 抛 [CastDeliveryClosed]
/// （与 `LanCastDeliveryChannel` 同一契约，那份合同由
/// `test/cast/cast_delivery_channel_test.dart` 对真实现钉住）。替身不这么做的
/// 话，「断开 → 重选 → 再投」这条路上复用一份已停服的通道会悄悄过关——
/// 那正是这条契约在运行域上一次真实的违例。
class FakeCastDeliveryChannel implements CastDeliveryChannel {
  /// 被 [serve] 递出过的文件，按顺序。
  final List<File> served = [];

  /// [serve] 返回的地址（默认是一个像真递出地址的串）。
  Uri url = Uri.parse('http://192.168.1.7:54321/cast/fake-token/投屏副本.mp4');

  /// 非 null 时 [serve] 抛出它（递出失败用例）。
  Object? serveError;

  /// 非 null 时 [close] 抛出它（停服失败用例：不阻断断连、不向上抛）。
  Object? closeError;

  /// [close] 的调用次数。
  int closeCalls = 0;

  /// 停过服（一次性通道的终态；之后的 [serve] 一律抛 [CastDeliveryClosed]）。
  bool get closed => closeCalls > 0;

  @override
  Future<Uri> serve(File file) async {
    if (closed) throw const CastDeliveryClosed();
    served.add(file);
    final error = serveError;
    if (error != null) throw error;
    return url;
  }

  @override
  Future<void> close() async {
    // 终态先落定（与真实现同一次序：`_closed = true` 在先、关服务在后），
    // 于是「停服本身抛」也不会让这一份变回可用的。
    closeCalls++;
    final error = closeError;
    if (error != null) throw error;
  }
}

/// **取一份新递出通道**的脚本化替身工厂：每次调用给一份**新的**
/// [FakeCastDeliveryChannel]，并把发出去的每一份记进 [channels]。
///
/// 真通道是一次性的（见上），而「投 → 断开 → 重选 → 再投」在会话之外要反复
/// 进行——生产装配每次起投取一份新的，替身因此也必须每次给新的；喂同一份
/// 会在第二次起投当场抛 [CastDeliveryClosed]。
///
/// 本类可调用（[call]），所以能直接当 `CastDeliveryChannel Function()` 用。
/// 各聚合读面（[served] / [closed] / [closeCalls] …）与单个替身同名同义，
/// 「一次投屏一份通道」的既有用例因此读法不变。
class FakeCastDeliveryChannelFactory {
  /// 发出去的每一份通道，按起投次序。
  final List<FakeCastDeliveryChannel> channels = [];

  /// 每份新通道的地址前缀：逐份加序号，好断言「第二次拿到的是新路径」。
  static const String urlPrefix = 'http://192.168.1.7:54321/cast/fake';

  Object? _serveError;
  Object? _closeError;

  /// 被递出过的文件（跨通道、按次序）。
  List<File> get served => [
    for (final channel in channels) ...channel.served,
  ];

  /// 发出去的任何一份停过服（收尾漏了停服时它不会说谎）。
  bool get closed => channels.any((channel) => channel.closed);

  /// [close] 的总调用次数。
  int get closeCalls =>
      channels.fold(0, (sum, channel) => sum + channel.closeCalls);

  /// 最近一份新通道的地址（还没发过通道时先给第 0 份的串）。
  Uri get url => channels.isEmpty ? _defaultUrl(0) : channels.last.url;

  /// 换掉地址（对已经发出去与之后要发的通道一并生效）。
  set url(Uri value) {
    for (final channel in channels) {
      channel.url = value;
    }
  }

  /// 非 null 时每份通道 [FakeCastDeliveryChannel.serve] 都抛它（对已经发出去
  /// 的那一份同样生效——用例可以起投之后再布景）。
  Object? get serveError => _serveError;

  set serveError(Object? error) {
    _serveError = error;
    for (final channel in channels) {
      channel.serveError = error;
    }
  }

  /// 非 null 时每份通道 [FakeCastDeliveryChannel.close] 都抛它。
  Object? get closeError => _closeError;

  set closeError(Object? error) {
    _closeError = error;
    for (final channel in channels) {
      channel.closeError = error;
    }
  }

  /// 发一份新通道（起投那一刻调用）。
  FakeCastDeliveryChannel call() {
    final channel = FakeCastDeliveryChannel()
      ..url = _defaultUrl(channels.length)
      ..serveError = _serveError
      ..closeError = _closeError;
    channels.add(channel);
    return channel;
  }

  static Uri _defaultUrl(int index) =>
      Uri.parse('$urlPrefix-$index/投屏副本.mp4');
}
