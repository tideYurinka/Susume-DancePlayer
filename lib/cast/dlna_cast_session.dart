/// 投屏会话的真实实现：**DLNA/UPnP**——设备描述给的 AVTransport 与
/// RenderingControl 控制端点上发 SOAP。**不引第三方投屏包**；本域唯一的
/// 网络落点（除递出通道外）就在这个文件。
library;

import 'dart:convert';
import 'dart:io';

import 'cast_failure.dart';
import 'cast_media.dart';
import 'cast_receiver.dart';
import 'cast_session.dart';
import 'dlna_values.dart';
import 'soap.dart';

/// 会话建立的默认超时：家用局域网里 5 秒足够，长了只是让失败面来得更晚。
const Duration kCastSoapTimeout = Duration(seconds: 5);

/// [CastSessionFactory] 的真实实现：连一次
/// `GetTransportInfo` 确认端点活着，之后再谈推片与遥控。
class DlnaCastSessionFactory implements CastSessionFactory {
  const DlnaCastSessionFactory();

  @override
  Future<CastSession> connect(CastReceiver receiver) async {
    if (receiver.controlUrls.avTransport == null) {
      throw const CastReceiverUnreachable('这台设备没有 AVTransport 控制端点，投不了屏');
    }
    final session = DlnaCastSession(receiver);
    try {
      await session.probe();
    } catch (_) {
      await session.disconnect();
      rethrow;
    }
    return session;
  }
}

/// 一条绑在一台接收端上的 DLNA 会话。
class DlnaCastSession implements CastSession {
  DlnaCastSession(
    this.receiver, {
    HttpClient? client,
    this.timeout = kCastSoapTimeout,
  }) : _client = client ?? HttpClient() {
    _client.connectionTimeout = timeout;
  }

  @override
  final CastReceiver receiver;

  final HttpClient _client;

  /// 单次 SOAP 调用的超时。
  final Duration timeout;

  /// 会话是否建立过：探测成功之前的一切断连都算**连不上**，之后算**中途
  /// 掉线**——这是三类失败里那两类的分界。
  bool _established = false;
  bool _disconnected = false;

  /// 建立会话：问一次传输状态，确认控制端点真的在听。
  ///
  /// 失败时抛 [CastReceiverUnreachable]（端点连不通）或
  /// [CastActionRefused]（端点活着但回绝了这次探测）。
  Future<void> probe() async {
    await _transportInfo();
    _established = true;
  }

  @override
  Future<void> push(Uri source) async {
    final title = _titleOf(source);
    await _call(CastUpnpService.avTransport, 'SetAVTransportURI', {
      'InstanceID': '0',
      'CurrentURI': source.toString(),
      'CurrentURIMetaData': buildCastDidlMetadata(url: source, title: title),
    });
  }

  @override
  Future<void> play() => _call(CastUpnpService.avTransport, 'Play', {
    'InstanceID': '0',
    'Speed': '1',
  }).then((_) {});

  @override
  Future<void> pause() => _call(CastUpnpService.avTransport, 'Pause', {
    'InstanceID': '0',
  }).then((_) {});

  @override
  Future<void> stop() => _call(CastUpnpService.avTransport, 'Stop', {
    'InstanceID': '0',
  }).then((_) {});

  @override
  Future<void> seek(Duration position) =>
      _call(CastUpnpService.avTransport, 'Seek', {
        'InstanceID': '0',
        'Unit': 'REL_TIME',
        'Target': formatCastDuration(position),
      }).then((_) {});

  @override
  Future<void> setVolume(double volume) =>
      _call(CastUpnpService.renderingControl, 'SetVolume', {
        'InstanceID': '0',
        'Channel': 'Master',
        'DesiredVolume': formatCastVolume(volume),
      }).then((_) {});

  @override
  Future<double> volume() async {
    final values = await _call(CastUpnpService.renderingControl, 'GetVolume', {
      'InstanceID': '0',
      'Channel': 'Master',
    });
    final volume = parseCastVolume(values['CurrentVolume']);
    if (volume == null) {
      throw const CastActionRefused('接收端没报当前音量');
    }
    return volume;
  }

  @override
  Future<Duration> position() async {
    final values = await _call(CastUpnpService.avTransport, 'GetPositionInfo', {
      'InstanceID': '0',
    });
    return parseCastDuration(values['RelTime']);
  }

  @override
  Future<CastPlaybackState> playbackState() async =>
      parseCastPlaybackState((await _transportInfo())['CurrentTransportState']);

  @override
  Future<CastTransportActions> supportedTransportActions() async {
    try {
      final values = await _call(
        CastUpnpService.avTransport,
        'GetCurrentTransportActions',
        {'InstanceID': '0'},
      );
      return parseCastTransportActions(values['Actions']);
    } on CastFailure {
      // 探测不到或探测失败：哪一项都不显示（静默降级）。
      return const CastTransportActions.none();
    }
  }

  @override
  Future<void> disconnect() async {
    if (_disconnected) return;
    try {
      if (_established) {
        await _call(CastUpnpService.avTransport, 'Stop', {'InstanceID': '0'});
      }
    } catch (_) {
      // 收尾失败（设备已经不在、或回绝了停止）不改「断开」这个事实：
      // 用户按下的那一下不能被一次失败的收尾挡住。
    }
    _disconnected = true;
    _client.close(force: true);
  }

  Future<Map<String, String>> _transportInfo() => _call(
    CastUpnpService.avTransport,
    'GetTransportInfo',
    {'InstanceID': '0'},
  );

  /// 发一条 SOAP 并读应答。
  ///
  /// 三类失败在这里分流：会话建立前连不上 → [CastReceiverUnreachable]；
  /// 接收端回绝（SOAP Fault / 非 2xx）→ [CastActionRefused]；会话建立后
  /// 连接断了 → [CastSessionDropped]。会话断开后再调 → 也是
  /// [CastSessionDropped]（这条会话不再可用）。
  Future<Map<String, String>> _call(
    CastUpnpService service,
    String action,
    Map<String, String> arguments,
  ) async {
    if (_disconnected) {
      throw const CastSessionDropped('会话已断开');
    }
    final endpoint = switch (service) {
      CastUpnpService.avTransport => receiver.controlUrls.avTransport,
      CastUpnpService.renderingControl => receiver.controlUrls.renderingControl,
    };
    if (endpoint == null) {
      throw CastActionRefused('这台接收端没有 $action 需要的控制端点');
    }

    try {
      final request = await _client.postUrl(endpoint).timeout(timeout);
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'text/xml; charset="utf-8"',
      );
      request.headers.set(
        'SOAPAction',
        service.actionHeader(action),
      );
      request.write(
        buildCastSoapEnvelope(
          service: service,
          action: action,
          arguments: arguments,
        ),
      );
      final response = await request.close().timeout(timeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      return _readResponse(action, response.statusCode, body);
    } on CastFailure {
      rethrow;
    } catch (error) {
      throw _established
          ? CastSessionDropped('$action 时与接收端断了：$error')
          : CastReceiverUnreachable('连不上接收端（$action）：$error');
    }
  }

  /// 读一条 SOAP 应答：成功取输出参数，Fault 与非 2xx 都是**拒播**。
  Map<String, String> _readResponse(
    String action,
    int statusCode,
    String body,
  ) {
    final outcome = parseCastSoapResponse(body);
    return switch (outcome) {
      CastSoapSuccess(:final values) =>
        statusCode >= 200 && statusCode < 300
            ? values
            : throw CastActionRefused('接收端对 $action 回了 HTTP $statusCode'),
      CastSoapFault(:final errorCode, :final description) =>
        throw CastActionRefused(
          description.isEmpty ? '接收端回绝了 $action' : description,
          upnpErrorCode: errorCode,
        ),
    };
  }

  /// 推片时的片名：取递出地址最后一段（`pathSegments` 已经是解码后的），
  /// 取不到就用一句兜底。
  String _titleOf(Uri source) {
    final last = source.pathSegments.lastOrNull;
    if (last == null || last.isEmpty) return 'Susume 投屏副本';
    return last;
  }
}
