// 节拍 DBN 解码的 Viterbi 热循环（lib/beat/dbn.dart 的纯 Dart 实现的
// 原生移植，经 dart:ffi 调用）。逐帧遍历 14876 个状态是 O(segLen×states)
// 的标量循环，Dart 实现在移动端约 46s/20k 帧，原生实现大幅加速。
//
// 逐位一致约束：与 Dart 版完全相同的双精度运算顺序（(prev+tmLogProb)+dens、
// 严格 > 取首最大、单前驱快路径），构建禁用 FMA 收缩（-ffp-contract=off），
// 不开 fast-math，保证与 Dart 输出逐位一致。
#include <math.h>
#include <stdint.h>
#include <string.h>

extern "C" __attribute__((visibility("default"))) int32_t
beat_dbn_viterbi(
    // logDens: segLen*3 观测对数密度（非拍/拍/强拍）。
    const double *logDens, int32_t segLen, int32_t numStates, int32_t numBnd,
    // 转移模型 CSR：前驱区间 [tmPointers[s], tmPointers[s+1])。
    const int32_t *tmPointers, const int32_t *tmStates,
    const double *tmLogProb,
    // 观测指针：0=非拍 1=拍 2=强拍。
    const uint8_t *omPointers,
    // 状态 -> 边界槽位（>1 前驱的状态），-1 表示无。
    const int32_t *bndOfState,
    // 输出：segLen*numBnd 回溯指针（仅边界槽位有效）。
    uint16_t *btOut,
    // 输出：最终帧各状态得分（供 Dart 侧做与参考一致的 argmax）。
    double *finalScores) {
  double *prev = new double[numStates];
  double *cur = new double[numStates];
  const double logInit = -log(static_cast<double>(numStates));
  for (int32_t s = 0; s < numStates; s++) prev[s] = logInit;

  for (int32_t f = 0; f < segLen; f++) {
    const double d0 = logDens[f * 3];
    const double d1 = logDens[f * 3 + 1];
    const double d2 = logDens[f * 3 + 2];
    uint16_t *btRow = btOut + static_cast<size_t>(f) * numBnd;
    for (int32_t s = 0; s < numStates; s++) {
      const uint8_t op = omPointers[s];
      const double dens = op == 0 ? d0 : (op == 1 ? d1 : d2);
      const int32_t lo = tmPointers[s];
      const int32_t hi = tmPointers[s + 1];
      double best;
      uint16_t bestLocal = 0;
      if (hi - lo == 1) {
        // 单前驱快路径（拍内状态）。
        best = prev[tmStates[lo]] + tmLogProb[lo] + dens;
      } else {
        best = -INFINITY;
        for (int32_t p = lo; p < hi; p++) {
          const double v = prev[tmStates[p]] + tmLogProb[p] + dens;
          if (v > best) {
            best = v;
            bestLocal = static_cast<uint16_t>(p - lo);
          }
        }
      }
      cur[s] = best;
      const int32_t b = bndOfState[s];
      if (b >= 0) {
        btRow[b] = bestLocal;
      }
    }
    double *tmp = prev;
    prev = cur;
    cur = tmp;
  }

  memcpy(finalScores, prev, sizeof(double) * numStates);
  int32_t bestState = 0;
  double bestVal = prev[0];
  for (int32_t s = 1; s < numStates; s++) {
    if (prev[s] > bestVal) {
      bestVal = prev[s];
      bestState = s;
    }
  }
  delete[] prev;
  delete[] cur;
  return bestState;
}

// ---------------------------------------------------------------------------
// 前处理热循环（lib/beat/preprocess.dart 的 _range 中「加窗+FFT+幅度+
// filterbank 矩阵乘」段的原生移植，逐位一致约束同上）。
// Hanning/旋转因子/位反转表由 Dart 侧生成传入（避免 transcendental 函数
// 跨实现舍入差异）；log/diff/交织仍在 Dart 侧。
// ---------------------------------------------------------------------------
extern "C" __attribute__((visibility("default"))) void
beat_filt_range(
    // padded：已加 pad 的 PCM（padded[i] = pcm[i - pad]），长度 paddedLen。
    const float *padded, int32_t paddedLen,
    int32_t size, int32_t cols,
    const double *win, const uint32_t *rev,
    const double *twRe, const double *twIm,
    // fbT：cols×(size/2)，按 band 连续（fbT[c*half + b]）。
    const float *fbT,
    int32_t lo, int32_t hi, int32_t sampleStart,
    // 输出：(hi-lo)×cols 的 filterbank 特征（float32）。
    float *out) {
  const int half = size / 2;
  const int32_t nFrames = hi - lo;
  double *re = new double[size];
  double *im = new double[size];
  float *specRow = new float[half];

  for (int32_t i = 0; i < nFrames; i++) {
    const int32_t base = (lo + i) * 441 - sampleStart;
    for (int k = 0; k < size; k++) {
      const double v = static_cast<double>(padded[base + k]) * win[k];
      re[k] = v;
      im[k] = 0.0;
    }
    // radix-2 迭代 FFT，与 Dart 版同序。
    for (int n = 0; n < size; n++) {
      const uint32_t j = rev[n];
      if (j > static_cast<uint32_t>(n)) {
        double t = re[n]; re[n] = re[j]; re[j] = t;
        t = im[n]; im[n] = im[j]; im[j] = t;
      }
    }
    for (int32_t len = 1; len < size; len *= 2) {
      const int32_t step = len * 2;
      for (int32_t block = 0; block < size; block += step) {
        for (int32_t j = block, k = 0; j < block + len; j++, k++) {
          const int32_t tIdx = k * (size / step);
          const double wr = twRe[tIdx];
          const double wi = twIm[tIdx];
          const double tr = wr * re[j + len] - wi * im[j + len];
          const double ti = wr * im[j + len] + wi * re[j + len];
          re[j + len] = re[j] - tr;
          im[j + len] = im[j] - ti;
          re[j] = re[j] + tr;
          im[j] = im[j] + ti;
        }
      }
    }
    for (int b = 0; b < half; b++) {
      specRow[b] = static_cast<float>(
          sqrt(re[b] * re[b] + im[b] * im[b]));
    }
    float *outRow = out + static_cast<size_t>(i) * cols;
    for (int32_t c = 0; c < cols; c++) {
      const float *row = fbT + static_cast<size_t>(c) * half;
      double acc = 0.0;
      for (int b = 0; b < half; b++) {
        acc += static_cast<double>(specRow[b]) * row[b];
      }
      outRow[c] = static_cast<float>(acc);
    }
  }
  delete[] re;
  delete[] im;
  delete[] specRow;
}
