import 'package:dance_learning_app/cast/cast_session.dart';
import 'package:dance_learning_app/cast/dlna_values.dart';
import 'package:flutter_test/flutter_test.dart';

/// DLNA 应答里那些**字符串取值**的读法：支持的动作、播放状态、位置、音量。
/// 纯件；设备报的格式参差（缺字段、`NOT_IMPLEMENTED`、大小写不一）时一律
/// 落到显式兜底，不抛。
void main() {
  group('当前支持的传输动作', () {
    test('读 CSV：认得出六个动作，大小写与空白都容忍', () {
      final actions = parseCastTransportActions('Play,Stop, Pause ,Seek');

      expect(actions.actions, {
        CastTransportAction.play,
        CastTransportAction.stop,
        CastTransportAction.pause,
        CastTransportAction.seek,
      });
    });

    test('不认识的词忽略；重复的不重复', () {
      final actions = parseCastTransportActions('Play,Record,play,Previous');

      expect(actions.actions, {
        CastTransportAction.play,
        CastTransportAction.previous,
      });
    });

    test('缺字段（null）或空串：空集——探测失败与自述什么都没有同一口径', () {
      expect(parseCastTransportActions(null).isEmpty, isTrue);
      expect(parseCastTransportActions('').isEmpty, isTrue);
      expect(parseCastTransportActions('  ,  ').isEmpty, isTrue);
      expect(parseCastTransportActions('NOT_IMPLEMENTED').isEmpty, isTrue);
    });

    test('遥控项判据：动作集 + 有没有音量端点', () {
      final full = CastRemoteControls.of(
        actions: parseCastTransportActions('Play,Pause,Stop,Seek'),
        hasVolumeControl: true,
      );
      expect(full.showsPlayPause, isTrue);
      expect(full.showsStop, isTrue);
      expect(full.showsSeek, isTrue);
      expect(full.showsVolume, isTrue);

      final onlyPlay = CastRemoteControls.of(
        actions: parseCastTransportActions('Play'),
        hasVolumeControl: false,
      );
      expect(onlyPlay.showsPlayPause, isTrue, reason: '只会播的设备也给播放暂停项');
      expect(onlyPlay.showsStop, isFalse);
      expect(onlyPlay.showsSeek, isFalse);
      expect(onlyPlay.showsVolume, isFalse);

      final none = CastRemoteControls.of(
        actions: const CastTransportActions.none(),
        hasVolumeControl: false,
      );
      expect(none, const CastRemoteControls.none());
    });
  });

  group('播放状态', () {
    test('读 CurrentTransportState 的取值', () {
      expect(parseCastPlaybackState('PLAYING'), CastPlaybackState.playing);
      expect(
        parseCastPlaybackState('PAUSED_PLAYBACK'),
        CastPlaybackState.paused,
      );
      expect(parseCastPlaybackState('paused'), CastPlaybackState.paused);
      expect(parseCastPlaybackState('STOPPED'), CastPlaybackState.stopped);
      expect(
        parseCastPlaybackState('TRANSITIONING'),
        CastPlaybackState.transitioning,
      );
      expect(
        parseCastPlaybackState('NO_MEDIA_PRESENT'),
        CastPlaybackState.noMedia,
      );
    });

    test('缺字段或陌生取值：unknown（不猜成停止）', () {
      expect(parseCastPlaybackState(null), CastPlaybackState.unknown);
      expect(parseCastPlaybackState(''), CastPlaybackState.unknown);
      expect(parseCastPlaybackState('RECORDING'), CastPlaybackState.unknown);
    });
  });

  group('位置', () {
    test('读 RelTime / AbsTime 的 `H:MM:SS[.F]`', () {
      expect(parseCastDuration('0:00:30'), const Duration(seconds: 30));
      expect(
        parseCastDuration('00:01:02'),
        const Duration(minutes: 1, seconds: 2),
      );
      expect(
        parseCastDuration('1:02:03.500'),
        const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 500),
      );
    });

    test('缺字段 / NOT_IMPLEMENTED / 格式不对：零（片头就是零，不抛）', () {
      for (final value in [
        null,
        '',
        'NOT_IMPLEMENTED',
        '30',
        'abc:def:ghi',
        '-1:00:00',
      ]) {
        expect(parseCastDuration(value), Duration.zero, reason: '输入：$value');
      }
    });

    test('装配 Seek 的 Target 串：时:分:秒，分秒补零', () {
      expect(formatCastDuration(Duration.zero), '0:00:00');
      expect(formatCastDuration(const Duration(seconds: 30)), '0:00:30');
      expect(
        formatCastDuration(
          const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 900),
        ),
        '1:02:03',
        reason: 'REL_TIME 只到秒，毫秒截掉',
      );
      expect(formatCastDuration(const Duration(seconds: -5)), '0:00:00');
    });
  });

  group('音量', () {
    test('UPnP 的 0–100 整数读成 0..1', () {
      expect(parseCastVolume('0'), 0);
      expect(parseCastVolume('40'), 0.4);
      expect(parseCastVolume('100'), 1);
      expect(parseCastVolume(' 55 '), 0.55);
    });

    test('读不出（缺字段 / 非数字）：null——不假装音量是零', () {
      expect(parseCastVolume(null), isNull);
      expect(parseCastVolume(''), isNull);
      expect(parseCastVolume('NOT_IMPLEMENTED'), isNull);
      expect(parseCastVolume('101'), isNull);
    });

    test('装配 DesiredVolume：0..1 钳到 0–100 的整数串', () {
      expect(formatCastVolume(0), '0');
      expect(formatCastVolume(0.4), '40');
      expect(formatCastVolume(1), '100');
      expect(formatCastVolume(1.4), '100');
      expect(formatCastVolume(-0.2), '0');
      expect(formatCastVolume(0.555), '56');
    });
  });
}
