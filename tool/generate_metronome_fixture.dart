/// 合成标准节拍夹具媒体生成器：把「已知拍点位置的标准节拍
/// 媒体」落成可回录的 WAV。拍点即已知地面真值——每拍一段短促敲击，敲击
/// onset 采样落在 `拍序号 × 60000/bpm × sampleRate/1000`（第 0 拍为
/// downbeat、每 4 拍重音），拍点媒介毫秒与 `fixture_probe.dart` 的夹具口径
/// 一致（真机双轨回录/计数比对参照）。
///
/// 用法（在仓库根目录）：
///   dart run tool/generate_metronome_fixture.dart \
///     --bpm 120 --beats 16 --out assets/fixtures/metronome_fixture_120.wav
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const int _sampleRate = 22050;

Never _fail(String msg) {
  stderr.writeln('generate_metronome_fixture: $msg');
  exit(2);
}

(int bpm, int beats, String out) _parse(List<String> args) {
  var bpm = 120;
  var beats = 16;
  var out = 'assets/fixtures/metronome_fixture.wav';
  String? next(String flag) {
    final i = args.indexOf(flag);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final bpmStr = next('--bpm');
  if (bpmStr != null) bpm = int.tryParse(bpmStr) ?? _fail('--bpm 需整数');
  final beatsStr = next('--beats');
  if (beatsStr != null) beats = int.tryParse(beatsStr) ?? _fail('--beats 需整数');
  final outStr = next('--out');
  if (outStr != null) out = outStr;
  if (bpm <= 0 || beats <= 0) _fail('--bpm/--beats 需为正');
  return (bpm, beats, out);
}

void main(List<String> args) {
  final (bpm, beats, out) = _parse(args);
  const beatPerBar = 4;
  final beatMs = 60000 / bpm;
  final totalFrames = (beatMs * beats * _sampleRate / 1000).ceil();
  final samples = Float32List(totalFrames);

  // 每拍叠加一段短促指数衰减敲击：onset 采样 = 拍序号×拍距（毫秒转采样）。
  for (var i = 0; i < beats; i++) {
    final onset = (i * beatMs * _sampleRate / 1000).round();
    final accent = i % beatPerBar == 0;
    final amp = accent ? 0.9 : 0.55;
    final pulseMs = accent ? 60.0 : 40.0; // 重音稍长，便于回录区分 downbeat
    final n = (pulseMs * _sampleRate / 1000).round();
    for (var j = 0; j < n && onset + j < totalFrames; j++) {
      final env = math.pow(math.e, -4.0 * j / n).toDouble();
      final tone = math.sin(
        2 * math.pi * (accent ? 1000 : 1500) * j / _sampleRate,
      );
      samples[onset + j] += (amp * env * tone);
    }
  }

  _writeWav16(out, samples, _sampleRate);
  stdout.writeln(
    'GREEN: $out（$bpm bpm × $beats 拍，第 0 拍 downbeat，'
    '每 $beatPerBar 拍重音；拍点毫秒随 $bpm bpm 已知）',
  );
}

/// 16-bit 单声道 PCM WAV 写出。
void _writeWav16(String path, Float32List samples, int sampleRate) {
  final dataBytes = samples.length * 2;
  final bytes = ByteData(44 + dataBytes);
  void ascii(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      bytes.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  bytes.setUint32(4, 36 + dataBytes, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little); // PCM
  bytes.setUint16(22, 1, Endian.little); // 单声道
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  bytes.setUint32(40, dataBytes, Endian.little);
  var at = 44;
  for (final s in samples) {
    final v = (s * 32767).round().clamp(-32768, 32767);
    bytes.setInt16(at, v, Endian.little);
    at += 2;
  }
  final file = File(path);
  file.createSync(recursive: true);
  file.writeAsBytesSync(bytes.buffer.asUint8List());
}
