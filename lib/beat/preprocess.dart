/// Pure-Dart port of the madmom `RNNDownBeatProcessor` front-end:
/// framing -> Hanning -> STFT (radix-2 FFT) -> magnitude -> log-filterbank
/// -> log10(1+x) -> positive temporal diff -> concat, producing the exact
/// [n_frames, 314] feature tensor the pure-RNN ONNX model consumes.
///
/// Reference (python, conda env `beat-proto-c`): `gen_features.py` /
/// `preproc_ref.py::my_preproc`, which reproduce madmom to ~1e-7.
/// Cross-check (prototype research branch): Dart front-end vs the .npy
/// written by `gen_features.py`; numeric alignment target max err < 1e-3.
///
/// Numerical-faithfulness notes vs the python reference:
///  * Frame indexes / hop / padding follow preproc_ref exactly
///    (origin=0, zero-pad to the right by `hop` + left by `frame//2`).
///  * Hanning windows use numpy's formula 0.5-0.5*cos(2*pi*k/(n-1)).
///  * FFT computed in double (like numpy's rfft over float32 frames), the
///    magnitude cast to float32 before the filterbank matmul.
///  * Filterbank matrices are the exact madmom `LogarithmicFilterbank`
///    float32 constants (assets/models/filterbanks_f32.bin).
///  * log10 over float64(1+float32) rounded to float32 (== np.log10(...)).
///
/// Feature layout (314 cols, fixed order), per frame_size then concat over
/// sizes 1024 -> 2048 -> 4096:
///   [ res: log(21|45|91) | res: diff(21|45|91) ]  (2*157 = 314)
///
/// Parallelism: `preprocessPcm` is single-threaded (kept as numeric
/// reference). `preprocessPcmParallel` splits the frame range across Dart
/// isolates (each frame is independent except a 1-2 frame diff lookback,
/// handled by a small leading overlap that is discarded), then assembles in
/// order. `preprocessPcmParallel` must produce EXACTLY the same flat output
/// as `preprocessPcm` (verified in the prototype research branch).
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'preprocess_native.dart';

const int kSampleRate = 44100;
const int kBeatFps = 100;
const int kHop = kSampleRate ~/ kBeatFps;
const List<int> kFrameSizes = [1024, 2048, 4096];
const List<int> kLogDims = [21, 45, 91]; // unique filters per size
const List<int> kDiffLags = [1, 1, 2]; // madmom _diff_frames(diff_ratio=0.5)
const int kFeatureDim = 314;
const int kLogFeatureDim = 157; // 21+45+91 log columns

/// A packed filterbank for one frame size: [bins, bands], row-major.
class Filterbank {
  final int rows; // bins = frameSize/2
  final int cols; // unique filters
  final Float32List data;
  Filterbank(this.rows, this.cols, this.data);

  static List<Filterbank> unpack(Float32List payload) {
    final out = <Filterbank>[];
    var off = 0;
    for (var i = 0; i < kFrameSizes.length; i++) {
      final rows = kFrameSizes[i] ~/ 2;
      final cols = kLogDims[i];
      final n = rows * cols;
      final slice = Float32List(n);
      slice.setRange(0, n, payload, off);
      out.add(Filterbank(rows, cols, slice));
      off += n;
    }
    return out;
  }

  static Float32List payloadFromBytes(Uint8List bytes) {
    final bd = ByteData.sublistView(bytes);
    final out = Float32List(bytes.lengthInBytes ~/ 4);
    for (var i = 0; i < out.length; i++) {
      out[i] = bd.getFloat32(i * 4, Endian.little);
    }
    return out;
  }
}

/// Single-threaded reference: features for frames [0, nFrames).
Float32List preprocessPcm(Float32List pcm, List<Filterbank> fbs) {
  final n = nFramesOf(pcm.length);
  return _range(pcm, fbs, 0, n);
}

int nFramesOf(int samples) => samples > 0 ? (samples - 1) ~/ kHop + 1 : 0;

/// Parallel preprocessing over Dart isolates.
/// Splits the frame range into ~2 segments for longer audio; short audio
/// (<~1500 frames) runs serial because isolate spawn + PCM copy overhead
/// would exceed any speedup.
/// Numerically identical to [preprocessPcm] (bit-for-bit, verified).
Future<Float32List> preprocessPcmParallel(
  Float32List pcm,
  List<Filterbank> fbs,
) async {
  final nFrames = nFramesOf(pcm.length);
  if (nFrames == 0) return Float32List(0);

  // 分段切片后单 worker 消息与缓冲都很小（~18MB），数值与串行逐位一致。
  // 并发 2：短音频串行（spawn/copy 开销大于收益）；较长音频固定 2 worker
  // （切片互不重叠、消息缓冲小，不复制整轨 PCM；UI 心跳在真机验收）。
  final wantSegments = nFrames < 1500 ? 1 : 2;
  final segs = <(int, int)>[]; // (f0, f1)
  final size = (nFrames / wantSegments).ceil();
  for (var f0 = 0; f0 < nFrames; f0 += size) {
    final f1 = (f0 + size) < nFrames ? f0 + size : nFrames;
    segs.add((f0, f1));
  }
  const lookback = 4; // covers max diff lag (2) + margin
  final results = await Future.wait(
    segs.map((s) async {
      final lo = (s.$1 == 0) ? 0 : (s.$1 - lookback);
      // compute [lo, f1), discard the leading `lookback` rows (except seg 0)
      // 分段切片：worker 只拿本段采样窗（±最大半帧长 2048，size 4096 的
      // half），避免整轨 PCM 复制与 3×整轨 padded 分配。
      final s0 = (lo * kHop - 2048).clamp(0, pcm.length);
      final s1 = ((s.$2 - 1) * kHop + 2048).clamp(0, pcm.length);
      final slice = Float32List(s1 - s0);
      slice.setRange(0, slice.length, pcm, s0);
      final rows = await Isolate.run(
        () => _range(slice, fbs, lo, s.$2, sampleStart: s0),
      );
      final skip = s.$1 - lo; // 0 for seg0
      return _sliceRows(rows, skip, s.$2 - s.$1);
    }),
  );
  final out = Float32List(nFrames * kFeatureDim);
  var rowOff = 0;
  for (final r in results) {
    out.setRange(rowOff, rowOff + r.length, r);
    rowOff += r.length;
  }
  return out;
}

Float32List _sliceRows(Float32List full, int skipRows, int wantRows) {
  if (skipRows == 0) return full;
  final out = Float32List(wantRows * kFeatureDim);
  out.setRange(0, out.length, full, skipRows * kFeatureDim);
  return out;
}

/// Compute feature rows for frames [lo, hi), writing row (fr-lo) -> output.
/// [sampleStart]：pcm 相对整轨的采样偏移（分段切片时 >0），帧 base 采样
/// 索引按 fr*kHop-sampleStart 换算；=0 时与串行参考逐位一致。
///
/// 实现：逐帧 FFT 后立即做 filterbank 乘（不落整轨中间数组，
/// 峰值内存从 O(frames×bins) 降到 O(frames×bands)）；filterbank 预转置为
/// 按 band 连续存储使内层乘加顺序访问。每个输出元素的累加顺序仍为
/// b 升序，与madmom 参考逐位一致。
Float32List _range(
  Float32List pcm,
  List<Filterbank> fbs,
  int lo,
  int hi, {
  int sampleStart = 0,
}) {
  final t = pcm.length;
  final nFrames = hi - lo;
  if (nFrames <= 0) return Float32List(0);
  final out = Float32List(nFrames * kFeatureDim);
  var col = 0;
  for (var si = 0; si < kFrameSizes.length; si++) {
    final size = kFrameSizes[si];
    final fb = fbs[si];
    final half = size ~/ 2;
    final cols = fb.cols;
    final pad = half;
    final paddedLen = t + 2 * pad + kHop;
    final padded = Float32List(paddedLen);
    padded.setRange(pad, pad + t, pcm);
    final win = _hanning(size);
    // 转置副本：fbT[c * half + b]，使 matmul 内层对 b 顺序访问。
    final fbT = Float32List(cols * half);
    for (var b = 0; b < half; b++) {
      for (var c = 0; c < cols; c++) {
        fbT[c * half + b] = fb.data[b * cols + c];
      }
    }

    final re = Float64List(size);
    final im = Float64List(size);
    final rev = Uint32List(size);
    _bitReverseIndices(size, rev);
    final twRe = Float64List(size);
    final twIm = Float64List(size);
    _twiddles(size, twRe, twIm);

    // 「加窗+FFT+幅度+filterbank 乘」热循环：原生实现优先（逐位一致），
    // 加载失败回退纯 Dart。
    final Float32List filt;
    final native = BeatPreprocessNative.instance;
    if (native != null) {
      filt = native.filtRange(
        padded: padded,
        size: size,
        cols: cols,
        win: Float64List.fromList(win),
        rev: rev,
        twRe: twRe,
        twIm: twIm,
        fbT: fbT,
        lo: lo,
        hi: hi,
        sampleStart: sampleStart,
      );
    } else {
      filt = Float32List(nFrames * cols);
      final specRow = Float32List(half);
      for (var i = 0; i < nFrames; i++) {
        final fr = lo + i;
        final base = fr * kHop - sampleStart;
        for (var k = 0; k < size; k++) {
          final v = padded[base + k] * win[k];
          re[k] = v;
          im[k] = 0.0;
        }
        _fftInPlace(re, im, size, rev, twRe, twIm);
        for (var b = 0; b < half; b++) {
          specRow[b] = math.sqrt(re[b] * re[b] + im[b] * im[b]).toFloat();
        }
        final fBase = i * cols;
        for (var c = 0; c < cols; c++) {
          final cb = c * half;
          var acc = 0.0;
          for (var b = 0; b < half; b++) {
            acc += specRow[b] * fbT[cb + b];
          }
          filt[fBase + c] = acc.toFloat();
        }
      }
    }

    final logFeat = Float32List(nFrames * fb.cols);
    const invLn10 = 1.0 / math.ln10;
    for (var i = 0; i < filt.length; i++) {
      logFeat[i] = (math.log(filt[i] + 1.0) * invLn10).toFloat();
    }

    final lag = kDiffLags[si];
    final diffFeat = Float32List(nFrames * fb.cols);
    for (var i = 0; i < nFrames; i++) {
      if (i >= lag) {
        for (var c = 0; c < fb.cols; c++) {
          final v = logFeat[i * fb.cols + c] - logFeat[(i - lag) * fb.cols + c];
          diffFeat[i * fb.cols + c] = v > 0 ? v : 0.0;
        }
      }
    }

    // write [log | diff] columns for this resolution
    for (var i = 0; i < nFrames; i++) {
      final dst = i * kFeatureDim + col;
      for (var c = 0; c < fb.cols; c++) {
        out[dst + c] = logFeat[i * fb.cols + c];
        out[dst + fb.cols + c] = diffFeat[i * fb.cols + c];
      }
    }
    col += 2 * fb.cols;
  }
  return out;
}

extension _F32 on double {
  double toFloat() => _f32Round(this);
}

final Float32List _scratch = Float32List(1);
double _f32Round(double x) {
  _scratch[0] = x;
  return _scratch[0];
}

Float32List _hanning(int n) {
  final w = Float32List(n);
  for (var k = 0; k < n; k++) {
    w[k] = (0.5 - 0.5 * math.cos(2.0 * math.pi * k / (n - 1))).toFloat();
  }
  return w;
}

void _bitReverseIndices(int n, Uint32List rev) {
  var log2n = 0;
  while ((1 << log2n) < n) {
    log2n++;
  }
  for (var i = 0; i < n; i++) {
    var r = 0;
    for (var b = 0; b < log2n; b++) {
      if (((i >> b) & 1) != 0) {
        r |= 1 << (log2n - 1 - b);
      }
    }
    rev[i] = r;
  }
}

void _twiddles(int n, Float64List re, Float64List im) {
  for (var k = 0; k < n; k++) {
    final ang = -2.0 * math.pi * k / n;
    re[k] = math.cos(ang);
    im[k] = math.sin(ang);
  }
}

void _fftInPlace(
  Float64List re,
  Float64List im,
  int n,
  Uint32List rev,
  Float64List twRe,
  Float64List twIm,
) {
  for (var i = 0; i < n; i++) {
    final j = rev[i];
    if (j > i) {
      var tmp = re[i];
      re[i] = re[j];
      re[j] = tmp;
      tmp = im[i];
      im[i] = im[j];
      im[j] = tmp;
    }
  }
  var half = 1;
  while (half < n) {
    final step = half * 2;
    for (var i = 0; i < n; i += step) {
      for (var j = i, k = 0; j < i + half; j++, k++) {
        final tIdx = k * (n ~/ step);
        final wr = twRe[tIdx];
        final wi = twIm[tIdx];
        final tr = wr * re[j + half] - wi * im[j + half];
        final ti = wr * im[j + half] + wi * re[j + half];
        re[j + half] = re[j] - tr;
        im[j + half] = im[j] - ti;
        re[j] = re[j] + tr;
        im[j] = im[j] + ti;
      }
    }
    half = step;
  }
}
