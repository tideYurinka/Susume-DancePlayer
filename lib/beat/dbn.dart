/// Faithful pure-Dart port of madmom's `DBNDownBeatTrackingProcessor`
/// (HMM / Viterbi joint beat + downbeat decoding).
///
/// Reference sources:
///  - madmom/features/downbeats.py  (DBNDownBeatTrackingProcessor.process)
///  - madmom/features/beats_hmm.py  (BarStateSpace, BarTransitionModel,
///                                   RNNDownBeatTrackingObservationModel,
///                                   exponential_transition)
///  - madmom/ml/hmm.pyx             (HiddenMarkovModel.viterbi)
///    https://github.com/CPJKU/madmom/blob/master/madmom/ml/hmm.pyx
///  - madmom/features/beats.py      (threshold_activations)
///
/// ---------------------------------------------------------------------------
/// NUMERICAL VALIDATION (env: conda `beat-proto-c`, madmom 0.17.dev0)
/// ---------------------------------------------------------------------------
/// Data: /tmp/smoke_click.wav -> RNNDownBeatProcessor -> activations
///       (3000 x 2, float32), saved to /tmp/dbn_val/act.npy.
/// Reference: DBNDownBeatTrackingProcessor(beats_per_bar=4, fps=100) ->
///       /tmp/dbn_val/ref_beats.npy (60 beats).
/// Validation results (prototype research branch, tool/dbn_check.dart):
///       sparse transition model vs madmom CSR arrays: states & pointers
///       identical (21648 transitions); log-probabilities match to
///       3.8e-15 relative (1 ulp).
///       /tmp/smoke_click.wav (3000 frames): 60 beats vs 60, all beat
///       times identical (max |dt| = 0.000 ms), all beat numbers equal.
///       tiled 27000 frames (~4.5 min): 540 vs 540 beats, max |dt| =
///       0.000 ms, beat numbers equal. Decode time ~1.8 s (debug-mode
///       `dart run` on x86-64; AOT/mobile will differ).
///
/// NOTE ON STATE SPACE SIZE: the task description said "3840 states"; the
/// real madmom state space for these parameters is
///   num_intervals(60 log-spaced tempi, intervals 28..109 frames)
///   -> beat states = sum(intervals) = 3719, bar states = 4 * 3719 = 14876.
/// We port madmom faithfully (14876 states).
///
/// ---------------------------------------------------------------------------
/// FAITHFULNESS NOTES / APPROXIMATIONS (all annotated inline as well)
/// ---------------------------------------------------------------------------
///  * Initial Viterbi distribution: uniform (madmom default when
///    `initial_distribution=None`), used in log domain as log(1/N).
///  * `correct=True` peak alignment: replicated exactly, including the
///    quirk that the peak search uses `argmax` over the *flattened*
///    (frames x 2) thresholded activation segment (beat and downbeat
///    columns compete; downbeat may win), first-max-wins, then `// 2`.
///  * Transitions are stored CSR-style (madmom `TransitionModel`):
///    for destination state s the predecessors are
///    tmStates[tmPointers[s] .. tmPointers[s+1]) with probabilities
///    tmProbabilities[...] . Predecessors within a row are ascending, like
///    scipy's csr_matrix used by `make_sparse`.
///  * Memory optimisation (no numerical effect): madmom stores a full
///    (frames x states) back-tracking table. Only the 240 "beat-first"
///    states have >1 predecessor; all other states backtrack deterministically
///    to state-1. We therefore store back-pointers only for those 240 states
///    (local predecessor index, Uint16), reducing memory from
///    frames*14876*4 B (~1.5 GB at 26k frames) to frames*240*2 B (~13 MB).
///  * Ties in the Viterbi max are resolved by strict `>` (first maximum
///    wins), same as madmom's Cython loop; predecessor iteration order
///    matches the CSR order, so ties resolve identically.
///  * Transition probability ties / float rounding: we use f64 throughout,
///    same as madmom (double in Cython).
///
/// No third-party dependencies (dart:typed_data, dart:math only).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../core/beat_grid.dart' show kBeatsPerBar;
import 'dbn_native.dart';
import 'preprocess.dart' show kBeatFps;

/// Result entry: beat time in seconds and beat number inside the bar (1-based).
/// (Record type; use DbnBeat if you need to support older Dart SDKs.)
typedef DbnBeat = ({double t, int beatNumber});

/// Fixed madmom defaults for this port.
class DbnConfig {
  final int beatsPerBar;
  final double minBpm;
  final double maxBpm;
  final int numTempi;
  final double transitionLambda;
  final int observationLambda;
  final double threshold;
  final bool correct;
  final int fps;

  const DbnConfig({
    this.beatsPerBar = kBeatsPerBar,
    this.minBpm = 55.0,
    this.maxBpm = 215.0,
    this.numTempi = 60,
    this.transitionLambda = 100.0,
    this.observationLambda = 16,
    this.threshold = 0.05,
    this.correct = true,
    this.fps = kBeatFps,
  });
}

/// Decode joint beat/downbeat activations with the DBN.
///
/// [beatAct] and [downbeatAct] are the two columns of
/// `RNNDownBeatProcessor` output (frames x 2), sampled at [fps] (default
/// [kBeatFps]).
///
/// Returns the detected beats as (time [s], beat number starting at 1).
List<({double t, int beatNumber})> dbnDecode(
  Float32List beatAct,
  Float32List downbeatAct, {
  int fps = kBeatFps,
}) {
  final cfg = DbnConfig(fps: fps);
  return DbnDownBeatTracker(cfg).decode(beatAct, downbeatAct);
}

/// Reusable tracker (build the state/transition models once, decode often).
class DbnDownBeatTracker {
  final DbnConfig cfg;

  late final _BarStateSpace _st;
  late final Int32List _tmPointers; // numStates + 1
  late final Int32List _tmStates; // predecessor states, CSR order
  late final Float64List _tmLogProb; // log transition probabilities
  late final Uint8List _omPointers; // 0=non-beat, 1=beat, 2=downbeat
  late final Int32List _boundaryStateIdx; // states with >1 predecessor
  late final Int32List _boundaryOfState; // state -> boundary slot, -1 if none
  final double _negInf = double.negativeInfinity;

  DbnDownBeatTracker([DbnConfig? config]) : cfg = config ?? const DbnConfig() {
    _build();
  }

  // -------------------------------------------------------------------------
  // Model construction (madmom: BeatStateSpace / BarStateSpace /
  // BarTransitionModel / RNNDownBeatTrackingObservationModel)
  // -------------------------------------------------------------------------

  void _build() {
    final fps = cfg.fps;

    _st = _BarStateSpace(
        60.0 * fps / cfg.maxBpm, 60.0 * fps / cfg.minBpm, cfg.numTempi,
        cfg.beatsPerBar);
    final numStates = _st.numStates;

    // ---- Transition model (madmom BarTransitionModel) ----------------------
    // exponential_transition(from_int, to_int, lambda) per beat boundary.
    // beat 0 connects from the *last* beat (Python last_states[-1] wraps).
    final rows = List<List<int>>.generate(numStates, (_) => <int>[]);
    final rowProb = List<List<double>>.generate(numStates, (_) => <double>[]);

    // Same-tempo within-beat transitions: s <- s-1 with probability 1,
    // for all states except the first states of each beat.
    final isFirst = Uint8List(numStates);
    for (final fs in _st.firstStates) {
      for (final s in fs) {
        isFirst[s] = 1;
      }
    }
    for (var s = 0; s < numStates; s++) {
      if (isFirst[s] == 0) {
        rows[s].add(s - 1);
        rowProb[s].add(1.0);
      }
    }

    // Tempo-change transitions at beat boundaries.
    for (var beat = 0; beat < cfg.beatsPerBar; beat++) {
      final toStates = _st.firstStates[beat];
      // Python last_states[beat - 1]: negative index wraps to the last beat.
      final fromStates =
          _st.lastStates[(beat - 1 + cfg.beatsPerBar) % cfg.beatsPerBar];
      final fromInt = Int32List(fromStates.length);
      for (var i = 0; i < fromStates.length; i++) {
        fromInt[i] = _st.stateIntervals[fromStates[i]];
      }
      final toInt = Int32List(toStates.length);
      for (var i = 0; i < toStates.length; i++) {
        toInt[i] = _st.stateIntervals[toStates[i]];
      }
      final prob = _exponentialTransition(fromInt, toInt, cfg.transitionLambda);
      for (var f = 0; f < fromStates.length; f++) {
        for (var t = 0; t < toStates.length; t++) {
          final p = prob[f * toStates.length + t];
          if (p != 0.0) {
            rows[toStates[t]].add(fromStates[f]);
            rowProb[toStates[t]].add(p);
          }
        }
      }
    }

    // CSR-ify with rows sorted ascending by predecessor (scipy csr_matrix
    // ordering used by TransitionModel.make_sparse).
    var total = 0;
    for (var s = 0; s < numStates; s++) {
      final order = List<int>.generate(rows[s].length, (i) => i)
        ..sort((a, b) => rows[s][a] - rows[s][b]);
      for (var i = 0; i < order.length; i++) {
        rows[s][i] = rows[s][order[i]];
        rowProb[s][i] = rowProb[s][order[i]];
      }
      total += rows[s].length;
    }
    _tmPointers = Int32List(numStates + 1);
    _tmStates = Int32List(total);
    _tmLogProb = Float64List(total);
    var k = 0;
    for (var s = 0; s < numStates; s++) {
      _tmPointers[s] = k;
      for (var i = 0; i < rows[s].length; i++) {
        _tmStates[k] = rows[s][i];
        _tmLogProb[k] = rowProb[s][i] <= 0.0
            ? _negInf
            : math.log(rowProb[s][i]);
        k++;
      }
    }
    _tmPointers[numStates] = k;

    // Boundary states (>1 predecessor) get back-tracking storage.
    final boundaryOf = Int32List(numStates);
    final bnd = <int>[];
    for (var s = 0; s < numStates; s++) {
      if (_tmPointers[s + 1] - _tmPointers[s] > 1) {
        boundaryOf[s] = bnd.length;
        bnd.add(s);
      }
    }
    _boundaryStateIdx = Int32List.fromList(bnd);
    _boundaryOfState = boundaryOf;

    // ---- Observation model (madmom RNNDownBeatTrackingObservationModel) ----
    // pointers: 0 = non-beat, 1 = (down-)beat, 2 = downbeat.
    final border = 1.0 / cfg.observationLambda;
    _omPointers = Uint8List(numStates);
    for (var s = 0; s < numStates; s++) {
      final pos = _st.statePositions[s];
      if (pos < border) {
        _omPointers[s] = 2;
      } else if ((pos % 1.0) < border) {
        _omPointers[s] = 1;
      } else {
        _omPointers[s] = 0;
      }
    }
  }

  /// madmom exponential_transition with threshold=np.spacing(1), norm=True.
  Float64List _exponentialTransition(
      Int32List fromInt, Int32List toInt, double lambda) {
    final nf = fromInt.length;
    final nt = toInt.length;
    final out = Float64List(nf * nt);
    const eps = 2.220446049250313e-16; // np.spacing(1)
    for (var f = 0; f < nf; f++) {
      var sum = 0.0;
      for (var t = 0; t < nt; t++) {
        final ratio = toInt[t] / fromInt[f];
        var p = math.exp(-lambda * (ratio - 1.0).abs());
        if (p <= eps) {
          p = 0.0;
        }
        out[f * nt + t] = p;
        sum += p;
      }
      if (sum > 0.0) {
        for (var t = 0; t < nt; t++) {
          out[f * nt + t] /= sum;
        }
      }
    }
    return out;
  }

  // -------------------------------------------------------------------------
  // Decoding (madmom HiddenMarkovModel.viterbi + DBNDownBeatTrackingProcessor
  // .process incl. threshold_activations and correct=True peak alignment)
  // -------------------------------------------------------------------------

  List<({double t, int beatNumber})> decode(
      Float32List beatAct, Float32List downbeatAct) {
    final fps = cfg.fps;
    final numFrames = math.min(beatAct.length, downbeatAct.length);

    // threshold_activations: keep only the segment from the first to the last
    // frame where *any* column >= threshold (flattened nonzero over the 2D
    // array), return (segment, first index offset).
    var first = 0;
    var last = 0;
    for (var f = 0; f < numFrames; f++) {
      if (beatAct[f] >= cfg.threshold || downbeatAct[f] >= cfg.threshold) {
        if (first == 0 && last == 0) {
          first = f;
        }
        last = f + 1;
      }
    }
    final segLen = last - first;
    if (segLen <= 0) {
      return <({double t, int beatNumber})>[];
    }

    final numStates = _st.numStates;

    // Observation log densities, 3 per frame: non-beat / beat / downbeat.
    // madmom: log((1 - sum(obs)) / (observation_lambda - 1)),
    //         log(obs[:, 0]), log(obs[:, 1]).
    final logDens = Float64List(segLen * 3);
    final lam1 = cfg.observationLambda - 1;
    for (var f = 0; f < segLen; f++) {
      final b = beatAct[first + f].toDouble();
      final d = downbeatAct[first + f].toDouble();
      final rest = (1.0 - b - d) / lam1;
      logDens[f * 3] = rest > 0.0 ? math.log(rest) : _negInf;
      logDens[f * 3 + 1] = b > 0.0 ? math.log(b) : _negInf;
      logDens[f * 3 + 2] = d > 0.0 ? math.log(d) : _negInf;
    }

    // ---- Viterbi -----------------------------------------------------------
    // 原生实现（Android）优先，热循环在 C++（逐位一致，见 dbn_native.cpp）；
    // 加载失败回退等价的纯 Dart 循环。
    final numBnd = _boundaryStateIdx.length;
    Uint16List bt;
    var state = 0;
    var bestVal = 0.0;
    final native = BeatDbnNative.instance;
    if (native != null) {
      final r = native.viterbi(
        logDens: logDens,
        segLen: segLen,
        numStates: numStates,
        numBnd: numBnd,
        tmPointers: _tmPointers,
        tmStates: _tmStates,
        tmLogProb: _tmLogProb,
        omPointers: _omPointers,
        bndOfState: _boundaryOfState,
      );
      bt = r.bt;
      state = r.bestState;
      bestVal = r.finalScores[state];
    } else {
      // Initial distribution: uniform (madmom default), log domain.
      final logInit = -math.log(numStates.toDouble());
      var prev = Float64List(numStates)..fillRange(0, numStates, logInit);
      var cur = Float64List(numStates);
      bt = Uint16List(segLen * numBnd);

      final omP = _omPointers;
      final tmP = _tmPointers;
      final tmS = _tmStates;
      final tmL = _tmLogProb;
      final bndOf = _boundaryOfState;

      for (var f = 0; f < segLen; f++) {
        final d0 = logDens[f * 3];
        final d1 = logDens[f * 3 + 1];
        final d2 = logDens[f * 3 + 2];
        final btBase = f * numBnd;
        for (var s = 0; s < numStates; s++) {
          // Per-state density selected via the observation pointer.
          final op = omP[s];
          final dens = op == 0 ? d0 : (op == 1 ? d1 : d2);
          var best = _negInf;
          var bestLocal = 0;
          final lo = tmP[s], hi = tmP[s + 1];
          if (hi - lo == 1) {
            // Fast path: single predecessor (within-beat states).
            best = prev[tmS[lo]] + tmL[lo] + dens;
          } else {
            for (var p = lo; p < hi; p++) {
              final v = prev[tmS[p]] + tmL[p] + dens;
              if (v > best) {
                best = v;
                bestLocal = p - lo;
              }
            }
          }
          cur[s] = best;
          final b = bndOf[s];
          if (b >= 0) {
            bt[btBase + b] = bestLocal;
          }
        }
        final tmp = prev;
        prev = cur;
        cur = tmp;
      }

      // Best final state.
      state = 0;
      bestVal = prev[0];
      for (var s = 1; s < numStates; s++) {
        if (prev[s] > bestVal) {
          bestVal = prev[s];
          state = s;
        }
      }
    }
    if (bestVal.isInfinite && bestVal < 0) {
      // -inf log probability: no valid path (mirrors madmom's warning branch).
      return <({double t, int beatNumber})>[];
    }

    // Backtrack. Non-boundary states have exactly one predecessor (state-1),
    // boundary states use the stored local index.
    final tmP = _tmPointers;
    final tmS = _tmStates;
    final bndOf = _boundaryOfState;
    final path = Uint32List(segLen);
    for (var f = segLen - 1; f >= 0; f--) {
      path[f] = state;
      final b = bndOf[state];
      if (b >= 0) {
        state = tmS[tmP[state] + bt[f * numBnd + b]];
      } else {
        state = state - 1;
      }
    }

    // ---- Post-processing (madmom DBNDownBeatTrackingProcessor.process) -----
    // beat_numbers = state_positions[path] + 1
    // correct=True: find beat ranges (om.pointers[path] >= 1), then within
    // each range pick the frame with the highest activation (argmax over the
    // flattened 2-column segment, i.e. beat and downbeat compete; // 2).
    final positions = _st.statePositions;
    final out = <({double t, int beatNumber})>[];
    // Build beat ranges from om pointers along the path.
    final starts = <int>[], ends = <int>[];
    var inBeat = _omPointers[path[0]] >= 1;
    if (inBeat) {
      starts.add(0);
    }
    for (var f = 1; f < segLen; f++) {
      final now = _omPointers[path[f]] >= 1;
      if (now && !inBeat) {
        starts.add(f);
      } else if (!now && inBeat) {
        ends.add(f);
      }
      inBeat = now;
    }
    if (inBeat) {
      ends.add(segLen);
    }
    for (var r = 0; r < starts.length; r++) {
      final left = starts[r], right = ends[r];
      // argmax over flattened activations[left:right] (2 columns, row-major),
      // first occurrence of the maximum wins (np.argmax semantics).
      var bestFlat = left * 2;
      var bestV = _max2(beatAct[first + left], downbeatAct[first + left]);
      for (var f = left + 1; f < right; f++) {
        final b = beatAct[first + f];
        if (b > bestV) {
          bestV = b;
          bestFlat = f * 2;
        }
        final dd = downbeatAct[first + f];
        if (dd > bestV) {
          bestV = dd;
          bestFlat = f * 2 + 1;
        }
      }
      final peak = bestFlat ~/ 2;
      out.add((
        t: (peak + first) / fps,
        beatNumber: positions[path[peak]].toInt() + 1,
      ));
    }
    return out;
  }

  static double _max2(double a, double b) => a >= b ? a : b;
}

// ---------------------------------------------------------------------------
// State space (madmom BeatStateSpace / BarStateSpace)
// ---------------------------------------------------------------------------

class _BarStateSpace {
  /// Number of intervals (tempi) actually modelled.
  final Int32List intervals;

  /// Per beat: first state index of each interval block.
  final List<Int32List> firstStates;

  /// Per beat: last state index of each interval block.
  final List<Int32List> lastStates;

  /// Position inside the bar (0 .. numBeats) of every state.
  final Float64List statePositions;

  /// Beat interval (1/tempo, in frames) of every state.
  final Int32List stateIntervals;

  int get numStates => statePositions.length;

  /// madmom BarStateSpace(num_beats, min_interval, max_interval, num_intervals)
  /// stacking a BeatStateSpace `num_beats` times (one traversal of the tempo
  /// state space per beat of the bar; positions offset by the beat counter).
  factory _BarStateSpace(double minIntervalIn, double maxIntervalIn,
      int numIntervals, int numBeats) {
    // BeatStateSpace interval selection: linear spacing by default; if
    // num_intervals is given and smaller than the linear count, iteratively
    // increase the log-space resolution until >= num_intervals unique rounded
    // intervals remain (see madmom beats_hmm.BeatStateSpace.__init__).
    // Note: madmom rounds the interval bounds only for the *linear* branch
    // (np.arange(round(min), round(max)+1)); the log-space branch uses the
    // unrounded floats as log2 endpoints.
    final minInterval = minIntervalIn.round();
    final maxInterval = maxIntervalIn.round();
    var intervals = <int>[];
    for (var i = minInterval; i <= maxInterval; i++) {
      intervals.add(i);
    }
    if (numIntervals != 0 && numIntervals < intervals.length) {
      var numLogIntervals = numIntervals;
      intervals = <int>[];
      while (intervals.length < numIntervals) {
        final lg = Float64List(numLogIntervals);
        final lo = math.log(minIntervalIn) / math.ln2;
        final hi = math.log(maxIntervalIn) / math.ln2;
        for (var i = 0; i < numLogIntervals; i++) {
          lg[i] = math.pow(2.0, lo + (hi - lo) * i / (numLogIntervals - 1))
              .toDouble();
        }
        final rounded = <int>{};
        for (final v in lg) {
          rounded.add(_npRound(v).toInt());
        }
        intervals = rounded.toList()..sort();
        numLogIntervals++;
      }
    }

    final nInt = intervals.length;
    final beatStates = intervals.fold<int>(0, (a, b) => a + b);
    final numStates = numBeats * beatStates;

    final firstStates = <Int32List>[];
    final lastStates = <Int32List>[];
    // per-beat first/last states within one BeatStateSpace pass
    final bssFirst = Int32List(nInt);
    final bssLast = Int32List(nInt);
    var idx = 0;
    for (var i = 0; i < nInt; i++) {
      bssFirst[i] = idx;
      bssLast[i] = idx + intervals[i] - 1;
      idx += intervals[i];
    }
    for (var b = 0; b < numBeats; b++) {
      final off = b * beatStates;
      final fs = Int32List(nInt), ls = Int32List(nInt);
      for (var i = 0; i < nInt; i++) {
        fs[i] = bssFirst[i] + off;
        ls[i] = bssLast[i] + off;
      }
      firstStates.add(fs);
      lastStates.add(ls);
    }

    final positions = Float64List(numStates);
    final stateIntervals = Int32List(numStates);
    idx = 0;
    for (var b = 0; b < numBeats; b++) {
      for (var i = 0; i < nInt; i++) {
        final n = intervals[i];
        // np.linspace(0, 1, n, endpoint=False)
        for (var j = 0; j < n; j++) {
          positions[idx + j] = b + j / n;
          stateIntervals[idx + j] = n;
        }
        idx += n;
      }
    }

    return _BarStateSpace._(Int32List.fromList(intervals), firstStates,
        lastStates, positions, stateIntervals);
  }

  _BarStateSpace._(this.intervals, this.firstStates, this.lastStates,
      this.statePositions, this.stateIntervals);
}

/// np.round: round half to even (Dart's `round` rounds half away from zero).
double _npRound(double x) {
  final fl = x.floorToDouble();
  final diff = x - fl;
  if (diff > 0.5) {
    return fl + 1;
  }
  if (diff < 0.5) {
    return fl;
  }
  return fl.toInt().isOdd ? fl + 1 : fl; // exactly .5 -> nearest even
}
