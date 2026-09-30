import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// DBN Viterbi 原生实现（android/app/src/main/cpp/beat_native.cpp，NDK
/// 编译为 libbeat_native.so）。加载失败（非 Android 平台/单测宿主）返回
/// null，调用方回退纯 Dart 实现，数值逐位一致。
class BeatDbnNative {
  BeatDbnNative._(this._viterbi);

  final int Function(
    Pointer<Double> logDens,
    int segLen,
    int numStates,
    int numBnd,
    Pointer<Int32> tmPointers,
    Pointer<Int32> tmStates,
    Pointer<Double> tmLogProb,
    Pointer<Uint8> omPointers,
    Pointer<Int32> bndOfState,
    Pointer<Uint16> btOut,
    Pointer<Double> finalScores,
  ) _viterbi;

  static BeatDbnNative? _instance;

  static BeatDbnNative? get instance => _instance ??= _tryLoad();

  static BeatDbnNative? _tryLoad() {
    try {
      final lib = DynamicLibrary.open('libbeat_native.so');
      final viterbi = lib
          .lookupFunction<
            Int32 Function(
              Pointer<Double>,
              Int32,
              Int32,
              Int32,
              Pointer<Int32>,
              Pointer<Int32>,
              Pointer<Double>,
              Pointer<Uint8>,
              Pointer<Int32>,
              Pointer<Uint16>,
              Pointer<Double>,
            ),
            int Function(
              Pointer<Double>,
              int,
              int,
              int,
              Pointer<Int32>,
              Pointer<Int32>,
              Pointer<Double>,
              Pointer<Uint8>,
              Pointer<Int32>,
              Pointer<Uint16>,
              Pointer<Double>,
            )
          >('beat_dbn_viterbi');
      return BeatDbnNative._(viterbi);
    } on Object {
      return null;
    }
  }

  /// 运行 Viterbi，返回（最佳终态，回溯指针表 bt，各状态终局得分）。
  /// 数组布局与 [lib/beat/dbn.dart] 的纯 Dart 实现一致。
  ({int bestState, Uint16List bt, Float64List finalScores}) viterbi({
    required Float64List logDens,
    required int segLen,
    required int numStates,
    required int numBnd,
    required Int32List tmPointers,
    required Int32List tmStates,
    required Float64List tmLogProb,
    required Uint8List omPointers,
    required Int32List bndOfState,
  }) {
    final pLogDens = malloc<Double>(logDens.length);
    final pPointers = malloc<Int32>(tmPointers.length);
    final pStates = malloc<Int32>(tmStates.length);
    final pLogProb = malloc<Double>(tmLogProb.length);
    final pOm = malloc<Uint8>(omPointers.length);
    final pBnd = malloc<Int32>(bndOfState.length);
    final pBt = malloc<Uint16>(segLen * numBnd);
    final pScores = malloc<Double>(numStates);
    try {
      pLogDens.asTypedList(logDens.length).setAll(0, logDens);
      pPointers.asTypedList(tmPointers.length).setAll(0, tmPointers);
      pStates.asTypedList(tmStates.length).setAll(0, tmStates);
      pLogProb.asTypedList(tmLogProb.length).setAll(0, tmLogProb);
      pOm.asTypedList(omPointers.length).setAll(0, omPointers);
      pBnd.asTypedList(bndOfState.length).setAll(0, bndOfState);
      final bestState = _viterbi(
        pLogDens,
        segLen,
        numStates,
        numBnd,
        pPointers,
        pStates,
        pLogProb,
        pOm,
        pBnd,
        pBt,
        pScores,
      );
      final bt = Uint16List(segLen * numBnd)
        ..setAll(0, pBt.asTypedList(segLen * numBnd));
      final scores = Float64List(numStates)
        ..setAll(0, pScores.asTypedList(numStates));
      return (bestState: bestState, bt: bt, finalScores: scores);
    } finally {
      malloc
        ..free(pLogDens)
        ..free(pPointers)
        ..free(pStates)
        ..free(pLogProb)
        ..free(pOm)
        ..free(pBnd)
        ..free(pBt)
        ..free(pScores);
    }
  }
}
