import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// 前处理「加窗+FFT+幅度+filterbank 矩阵乘」热循环的原生实现
/// （android/app/src/main/cpp/beat_native.cpp）。加载失败（非 Android
/// 平台/单测宿主）返回 null，调用方回退纯 Dart 实现，数值逐位一致。
class BeatPreprocessNative {
  BeatPreprocessNative._(this._filtRange);

  /// 与 beat_native.cpp 的 beat_filt_range 签名一致。
  final void Function(
    Pointer<Float> padded,
    int paddedLen,
    int size,
    int cols,
    Pointer<Double> win,
    Pointer<Uint32> rev,
    Pointer<Double> twRe,
    Pointer<Double> twIm,
    Pointer<Float> fbT,
    int lo,
    int hi,
    int sampleStart,
    Pointer<Float> out,
  )
  _filtRange;

  static BeatPreprocessNative? _instance;

  static BeatPreprocessNative? get instance => _instance ??= _tryLoad();

  static BeatPreprocessNative? _tryLoad() {
    try {
      final lib = DynamicLibrary.open('libbeat_native.so');
      final filtRange = lib
          .lookupFunction<
            Void Function(
              Pointer<Float>,
              Int32,
              Int32,
              Int32,
              Pointer<Double>,
              Pointer<Uint32>,
              Pointer<Double>,
              Pointer<Double>,
              Pointer<Float>,
              Int32,
              Int32,
              Int32,
              Pointer<Float>,
            ),
            void Function(
              Pointer<Float>,
              int,
              int,
              int,
              Pointer<Double>,
              Pointer<Uint32>,
              Pointer<Double>,
              Pointer<Double>,
              Pointer<Float>,
              int,
              int,
              int,
              Pointer<Float>,
            )
          >('beat_filt_range');
      return BeatPreprocessNative._(filtRange);
    } on Object {
      return null;
    }
  }

  /// 计算帧区间 [lo, hi) 的 filterbank 特征（(hi-lo)×cols，float32）。
  /// [padded] 为已含 pad 的 PCM 缓冲；数值与纯 Dart 实现逐位一致。
  Float32List filtRange({
    required Float32List padded,
    required int size,
    required int cols,
    required Float64List win,
    required Uint32List rev,
    required Float64List twRe,
    required Float64List twIm,
    required Float32List fbT,
    required int lo,
    required int hi,
    required int sampleStart,
  }) {
    final nFrames = hi - lo;
    final pPadded = malloc<Float>(padded.length);
    final pWin = malloc<Double>(win.length);
    final pRev = malloc<Uint32>(rev.length);
    final pTwRe = malloc<Double>(twRe.length);
    final pTwIm = malloc<Double>(twIm.length);
    final pFbT = malloc<Float>(fbT.length);
    final pOut = malloc<Float>(nFrames * cols);
    try {
      pPadded.asTypedList(padded.length).setAll(0, padded);
      pWin.asTypedList(win.length).setAll(0, win);
      pRev.asTypedList(rev.length).setAll(0, rev);
      pTwRe.asTypedList(twRe.length).setAll(0, twRe);
      pTwIm.asTypedList(twIm.length).setAll(0, twIm);
      pFbT.asTypedList(fbT.length).setAll(0, fbT);
      _filtRange(
        pPadded,
        padded.length,
        size,
        cols,
        pWin,
        pRev,
        pTwRe,
        pTwIm,
        pFbT,
        lo,
        hi,
        sampleStart,
        pOut,
      );
      return Float32List.fromList(pOut.asTypedList(nFrames * cols));
    } finally {
      malloc
        ..free(pPadded)
        ..free(pWin)
        ..free(pRev)
        ..free(pTwRe)
        ..free(pTwIm)
        ..free(pFbT)
        ..free(pOut);
    }
  }
}
