import 'dart:io';

import 'package:dance_learning_app/cast/cast_delivery_channel.dart';

/// 脚本化的假递出通道：记录被递出的文件、给出的地址与停服次数；可注入
/// 递出失败——投屏准备与投屏态的门与失败面经它测，不起真服务。
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

  bool get closed => closeCalls > 0;

  @override
  Future<Uri> serve(File file) async {
    served.add(file);
    final error = serveError;
    if (error != null) throw error;
    return url;
  }

  @override
  Future<void> close() async {
    closeCalls++;
    final error = closeError;
    if (error != null) throw error;
  }
}
