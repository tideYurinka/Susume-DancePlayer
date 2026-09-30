// 节拍声原生排程渲染器：AAudio 常驻低延迟输出流，
// 按消费 seam 的排程指令在流内精确渲染段（段 PCM 预载并重采样到流采样率，
// 段内拍点标记换算采样偏移起播）。哑渲染：不对拍序做任何决策——拍序/门控/
// 音量全部由 Dart 决策层产出，本层只按时把段叠进输出。
//
// AAudio 经 dlopen/dlsym 动态解析：编译 minSdk < 26（AAudio 引入于 26）也
// 可构建；运行时 API < 26 或解析失败 → beat_audio_start 报错，Dart 侧回退
// 哑 sink（不发声，播放链路不受阻，回退纪律）。
//
// 线程模型（每变量单写者，无锁）：
// - 控制线程（Dart/ffi）：写事件槽（head 单调递增）、flushedSeq（flush 游
//   标，只前移）、锚字段；不碰 tail。
// - 音频回调线程：只读事件环与 flushedSeq，独占推进 tail（只回收已消费的
//   队首）与 framePos。回调内无锁、无分配；叠加混合后软钳制防破音。
#include <aaudio/AAudio.h>

#include <atomic>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <ctime>
#include <dlfcn.h>
#include <vector>

namespace {

// 段槽容量：beat_audio_create 创建时由 Dart 下传（注册表最坏音源需求派
// 生，单份事实源）；槽表按容量校验，段 id 是哑编号，本层不解释其语义。

// 事件环容量：一拍一条指令（前导互斥不叠加），256 条远超任何位置帧距窗口。
constexpr int64_t kRingCapacity = 256;

// 一条已换算到流内帧位置的渲染事件（POD，槽位覆写安全）。
struct RenderEvent {
  int64_t startFrame;
  int64_t endFrame;
  uint64_t seq;  // 入队序号：flush = flushedSeq 前移，回调跳过 <= 的槽
  int32_t segment;
  float volume;
};

// 一段已加载资产：源 PCM（解码后）+ 延迟重采样到流采样率的结果。
struct Segment {
  std::vector<float> srcPcm;
  int32_t srcRate = 0;
  int32_t markerMs = 0;
  std::vector<float> pcm;       // 流采样率下的 PCM
  int64_t markerFrames = 0;     // 段内拍点标记（帧，钳制在段长内）
  int32_t resampledRate = 0;    // pcm 对应的采样率（0 = 未重采样）
  bool loaded = false;
};

struct Renderer {
  // 槽表：槽数 = 创建时下传的容量（segments.size() 即容量，不另存一份）。
  std::vector<Segment> segments;
  AAudioStream* stream = nullptr;
  std::atomic<int64_t> framePos{0};   // 流会话累计已写帧（播放头，回调写）
  std::atomic<int64_t> head{0};       // 事件环写游标（控制线程写）
  std::atomic<int64_t> tail{0};       // 已消费游标（回调独占写）
  std::atomic<uint64_t> flushedSeq{0};  // flush 游标（控制线程只前移）
  uint64_t nextSeq = 1;               // 下一条事件序号（控制线程私有）
  RenderEvent ring[kRingCapacity];

  // 同步对锚（仅控制线程读写）。
  bool hasAnchor = false;
  bool playing = false;
  double anchorMediaMs = 0.0;
  double rate = 1.0;
  int64_t anchorFrame = 0;  // sync 时刻的播放头快照
  int32_t streamRate = 0;

  // 「流已被系统错误关闭」状态（错误回调置 1、成功开流清 0）：拔耳机/路由
  // 切换/设备异常时原生自行关流置空，Dart 侧靠此状态在**应活**时探测到即
  // 重开（生命周期自愈），不必等下一个播放/开声边沿。
  std::atomic<int32_t> streamLost{0};
};

// ---- AAudio 动态解析（minSdk < 26 可构建；运行时不可用则 start 报错）----

using FnCreateBuilder = aaudio_result_t (*)(AAudioStreamBuilder**);
using FnSetFormat = void (*)(AAudioStreamBuilder*, aaudio_format_t);
using FnSetChannelCount = void (*)(AAudioStreamBuilder*, int32_t);
using FnSetPerformanceMode = void (*)(AAudioStreamBuilder*,
                                      aaudio_performance_mode_t);
using FnSetDataCallback = void (*)(AAudioStreamBuilder*,
                                   AAudioStream_dataCallback, void*);
using FnSetErrorCallback = void (*)(AAudioStreamBuilder*,
                                    AAudioStream_errorCallback, void*);
using FnOpenStream = aaudio_result_t (*)(AAudioStreamBuilder*, AAudioStream**);
using FnDeleteBuilder = void (*)(AAudioStreamBuilder*);
using FnGetSampleRate = int32_t (*)(const AAudioStream*);
using FnRequestStart = aaudio_result_t (*)(AAudioStream*);
using FnRequestStop = aaudio_result_t (*)(AAudioStream*);
using FnClose = aaudio_result_t (*)(AAudioStream*);

struct AAudioApi {
  bool available = false;
  FnCreateBuilder createBuilder = nullptr;
  FnSetFormat setFormat = nullptr;
  FnSetChannelCount setChannelCount = nullptr;
  FnSetPerformanceMode setPerformanceMode = nullptr;
  FnSetDataCallback setDataCallback = nullptr;
  FnSetErrorCallback setErrorCallback = nullptr;
  FnOpenStream openStream = nullptr;
  FnDeleteBuilder deleteBuilder = nullptr;
  FnGetSampleRate getSampleRate = nullptr;
  FnRequestStart requestStart = nullptr;
  FnRequestStop requestStop = nullptr;
  FnClose close = nullptr;
};

const AAudioApi& AAudioApi_() {
  static const AAudioApi api = [] {
    void* handle = dlopen("libaaudio.so", RTLD_NOW);
    if (handle == nullptr) return AAudioApi{};
    AAudioApi a;
    auto sym = [&](void* p) {
      return p != nullptr ? p : (a.available = false, nullptr);
    };
    a.available = true;
    a.createBuilder =
        reinterpret_cast<FnCreateBuilder>(sym(dlsym(handle, "AAudio_createStreamBuilder")));
    a.setFormat =
        reinterpret_cast<FnSetFormat>(sym(dlsym(handle, "AAudioStreamBuilder_setFormat")));
    a.setChannelCount = reinterpret_cast<FnSetChannelCount>(
        sym(dlsym(handle, "AAudioStreamBuilder_setChannelCount")));
    a.setPerformanceMode = reinterpret_cast<FnSetPerformanceMode>(
        sym(dlsym(handle, "AAudioStreamBuilder_setPerformanceMode")));
    a.setDataCallback = reinterpret_cast<FnSetDataCallback>(
        sym(dlsym(handle, "AAudioStreamBuilder_setDataCallback")));
    a.setErrorCallback = reinterpret_cast<FnSetErrorCallback>(
        sym(dlsym(handle, "AAudioStreamBuilder_setErrorCallback")));
    a.openStream =
        reinterpret_cast<FnOpenStream>(sym(dlsym(handle, "AAudioStreamBuilder_openStream")));
    a.deleteBuilder = reinterpret_cast<FnDeleteBuilder>(
        sym(dlsym(handle, "AAudioStreamBuilder_delete")));
    a.getSampleRate =
        reinterpret_cast<FnGetSampleRate>(sym(dlsym(handle, "AAudioStream_getSampleRate")));
    a.requestStart =
        reinterpret_cast<FnRequestStart>(sym(dlsym(handle, "AAudioStream_requestStart")));
    a.requestStop =
        reinterpret_cast<FnRequestStop>(sym(dlsym(handle, "AAudioStream_requestStop")));
    a.close = reinterpret_cast<FnClose>(sym(dlsym(handle, "AAudioStream_close")));
    return a;
  }();
  return api;
}

// 线性插值重采样 srcRate → dstRate。
std::vector<float> ResampleLinear(const std::vector<float>& src, int32_t srcRate,
                                  int32_t dstRate) {
  if (src.empty() || srcRate <= 0 || dstRate <= 0 || srcRate == dstRate) {
    return src;
  }
  const int64_t dstFrames =
      static_cast<int64_t>(static_cast<double>(src.size()) * dstRate / srcRate);
  std::vector<float> dst(static_cast<size_t>(dstFrames > 0 ? dstFrames : 0));
  const double step = static_cast<double>(srcRate) / dstRate;
  for (int64_t i = 0; i < dstFrames; ++i) {
    const double pos = i * step;
    const int64_t i0 = static_cast<int64_t>(pos);
    const int64_t i1 = i0 + 1 < static_cast<int64_t>(src.size()) ? i0 + 1 : i0;
    const double frac = pos - i0;
    dst[static_cast<size_t>(i)] = static_cast<float>(
        src[static_cast<size_t>(i0)] * (1.0 - frac) + src[static_cast<size_t>(i1)] * frac);
  }
  return dst;
}

void EnsureResampled(Renderer* r, int32_t rate) {
  if (r->streamRate <= 0) return;
  for (Segment& s : r->segments) {
    if (!s.loaded || s.resampledRate == rate) continue;
    s.pcm = ResampleLinear(s.srcPcm, s.srcRate, rate);
    // 标记超出段长（脏数据）钳到段尾：退化为「段尾对齐拍点」，不回写过去。
    int64_t marker = static_cast<int64_t>(
        std::llround(static_cast<double>(s.markerMs) * rate / 1000.0));
    if (marker > static_cast<int64_t>(s.pcm.size())) {
      marker = static_cast<int64_t>(s.pcm.size());
    }
    s.markerFrames = marker;
    s.resampledRate = rate;
  }
}

aaudio_data_callback_result_t OnAudioData(AAudioStream*, void* userData,
                                          void* audioData, int32_t numFrames) {
  auto* r = static_cast<Renderer*>(userData);
  float* out = static_cast<float*>(audioData);
  memset(out, 0, sizeof(float) * static_cast<size_t>(numFrames));

  const int64_t pos = r->framePos.load(std::memory_order_relaxed);
  const int64_t head = r->head.load(std::memory_order_acquire);
  const uint64_t flushed = r->flushedSeq.load(std::memory_order_acquire);
  int64_t tail = r->tail.load(std::memory_order_relaxed);

  for (int64_t i = tail; i < head; ++i) {
    const RenderEvent& e = r->ring[static_cast<size_t>(i % kRingCapacity)];
    if (e.seq <= flushed) continue;  // 已 flush：跳过不渲染
    if (e.endFrame <= pos) continue;
    if (e.startFrame >= pos + numFrames) continue;
    const Segment& s = r->segments[e.segment];
    if (s.pcm.empty()) continue;
    const int64_t outBegin = e.startFrame > pos ? e.startFrame - pos : 0;
    const int64_t srcBegin = pos > e.startFrame ? pos - e.startFrame : 0;
    int64_t n = numFrames - outBegin;
    const int64_t remain = e.endFrame - e.startFrame - srcBegin;
    if (remain < n) n = remain;
    for (int64_t j = 0; j < n; ++j) {
      out[outBegin + j] += s.pcm[static_cast<size_t>(srcBegin + j)] * e.volume;
    }
  }

  // 软钳制：多事件叠加超满刻度限幅，防破音。
  for (int32_t j = 0; j < numFrames; ++j) {
    out[j] = std::max(-1.0f, std::min(1.0f, out[j]));
  }

  // 回调独占推进 tail：只回收队首已完整消费（播完或已 flush）的事件。
  while (tail < head) {
    const RenderEvent& front = r->ring[static_cast<size_t>(tail % kRingCapacity)];
    if (front.endFrame > pos + numFrames && front.seq > flushed) break;
    ++tail;
  }
  r->tail.store(tail, std::memory_order_release);
  r->framePos.store(pos + numFrames, std::memory_order_relaxed);
  return AAUDIO_CALLBACK_RESULT_CONTINUE;
}

// 流错误（拔耳机/路由切换/设备异常）：只置「已被系统错误关闭」状态——Dart
// 在应活时探测到即重开（beat_audio_stream_lost → 控制线程 CloseStream +
// beat_audio_start 新建流）。
void OnAudioError(AAudioStream* stream, void* userData, aaudio_result_t) {
  auto* r = static_cast<Renderer*>(userData);
  // 错误回调**只置状态、不关流**：本回调在 AAudio 自己的线程
  // 上执行，跨线程 close 会被 AAudio 判为非法（真机实测
  // `AAudioStream_close(s#n) failed. Close it from another thread` →
  // INVALID_STATE），旧流资源因此没能正常释放，其后连新建的流也起不来
  // （表现为设备切换后永久静默）。关流与重建一律留给控制线程（Dart 侧应活
  // 时探测到「流已失效」即调 beat_audio_recover_transport / beat_audio_start）。
  if (r == nullptr || r->stream != stream) return;
  r->streamLost.store(1, std::memory_order_release);
}

int32_t OpenStream(Renderer* r) {
  if (r->stream != nullptr) return AAUDIO_OK;
  const AAudioApi& aa = AAudioApi_();
  if (!aa.available) return AAUDIO_ERROR_UNAVAILABLE;
  AAudioStreamBuilder* builder = nullptr;
  aaudio_result_t result = aa.createBuilder(&builder);
  if (result != AAUDIO_OK) return result;
  aa.setFormat(builder, AAUDIO_FORMAT_PCM_FLOAT);
  aa.setChannelCount(builder, 1);
  aa.setPerformanceMode(builder, AAUDIO_PERFORMANCE_MODE_LOW_LATENCY);
  aa.setDataCallback(builder, OnAudioData, r);
  aa.setErrorCallback(builder, OnAudioError, r);
  result = aa.openStream(builder, &r->stream);
  aa.deleteBuilder(builder);
  if (result != AAUDIO_OK) {
    r->stream = nullptr;
    return result;
  }
  r->streamRate = aa.getSampleRate(r->stream);
  EnsureResampled(r, r->streamRate);
  return AAUDIO_OK;
}

// 关流（**只能由控制线程调用**：错误回调在 AAudio 线程上，跨线程 close 会被
// 拒）。停流 → 关流 → 置空；段资产与句柄保留。
void CloseStream(Renderer* r) {
  if (r->stream == nullptr) return;
  const AAudioApi& aa = AAudioApi_();
  // AAudio 符号要么全解析成功、要么 available 为假（见 AAudioApi_），
  // 故这里只判可用性。
  if (aa.available) {
    aa.requestStop(r->stream);
    // 关流失败（例如流早已被系统回收）不致命：置空后下一次 start 会新建。
    aa.close(r->stream);
  }
  r->stream = nullptr;
}

// 清空渲染状态：播放头、事件环与 flush 游标（重建流后帧位置从 0 重新起算，
// 旧事件相对旧播放头，必须一并丢弃）。
void ResetStreamState(Renderer* r) {
  r->framePos.store(0, std::memory_order_relaxed);
  r->head.store(0, std::memory_order_relaxed);
  r->tail.store(0, std::memory_order_relaxed);
  r->flushedSeq.store(0, std::memory_order_release);
  r->nextSeq = 1;
  r->hasAnchor = false;
  r->anchorFrame = 0;
}

}  // namespace

extern "C" {

__attribute__((visibility("default"))) void* beat_audio_create(
    int32_t capacity) {
  if (capacity <= 0) return nullptr;
  auto* r = new (std::nothrow) Renderer();
  if (r == nullptr) return nullptr;
  r->segments.resize(static_cast<size_t>(capacity));
  return r;
}

// 加载段资产（解码后的源 PCM；标记为段内拍点毫秒偏移）。重采样延迟到流
// 打开后按实际流采样率执行（start 时）。
__attribute__((visibility("default"))) int32_t beat_audio_load_segment(
    void* handle, int32_t segmentId, const float* pcm, int32_t frames,
    int32_t sampleRate, int32_t markerMs) {
  auto* r = static_cast<Renderer*>(handle);
  if (r == nullptr || segmentId < 0 ||
      segmentId >= static_cast<int32_t>(r->segments.size()) ||
      pcm == nullptr || frames <= 0 || sampleRate <= 0 || markerMs < 0) {
    return -1;
  }
  Segment& s = r->segments[static_cast<size_t>(segmentId)];
  s.srcPcm.assign(pcm, pcm + frames);
  s.srcRate = sampleRate;
  s.markerMs = markerMs;
  s.loaded = true;
  s.resampledRate = 0;
  s.pcm.clear();
  s.markerFrames = 0;
  if (r->streamRate > 0) EnsureResampled(r, r->streamRate);
  return 0;
}

// 下推同步对（媒介时钟锚）。锚换算只用 mediaTime/rate（墙钟时基一致性由
// monotonicMs 注入保证）。
__attribute__((visibility("default"))) int32_t beat_audio_sync(
    void* handle, double mediaTimeMs, double rate, int32_t playing) {
  auto* r = static_cast<Renderer*>(handle);
  if (r == nullptr) return -1;
  r->anchorMediaMs = mediaTimeMs;
  r->rate = rate > 0 ? rate : 1.0;
  r->playing = playing != 0;
  r->hasAnchor = true;
  r->anchorFrame = r->framePos.load(std::memory_order_relaxed);
  return 0;
}

// 排程一条指令：拍点媒介时间换算流内帧位置（含段标记前移）后入事件环。
__attribute__((visibility("default"))) int32_t beat_audio_enqueue(
    void* handle, double beatMediaTimeMs, int32_t segmentId, float volume) {
  auto* r = static_cast<Renderer*>(handle);
  if (r == nullptr || segmentId < 0 || segmentId >= static_cast<int32_t>(r->segments.size())) return -1;
  const Segment& s = r->segments[static_cast<size_t>(segmentId)];
  if (!r->hasAnchor || !r->playing || s.resampledRate <= 0 || s.pcm.empty()) {
    return 1;  // 无锚/暂停/段未就绪：丢弃（决策层纪律保证不在此补发）
  }
  const double deltaMs = beatMediaTimeMs - r->anchorMediaMs;
  // 倍速换算与播放头同向：媒介时刻差 ÷ rate = 墙钟毫秒 → 每墙钟
  // 秒推进采样率帧。2× 下拍声才落得在拍点上（取乘则方向与播放头相反）。
  int64_t start = r->anchorFrame +
                  static_cast<int64_t>(std::llround(
                      deltaMs / r->rate * static_cast<double>(r->streamRate) / 1000.0)) -
                  s.markerFrames;
  const int64_t pos = r->framePos.load(std::memory_order_relaxed);
  if (start < pos) start = pos;  // 已过拍点不回写过去
  const int64_t end = start + static_cast<int64_t>(s.pcm.size());

  const int64_t head = r->head.load(std::memory_order_relaxed);
  if (head - r->tail.load(std::memory_order_acquire) >= kRingCapacity) {
    return 1;  // 满：丢弃最新（错过的拍不补发；tail 归回调独占，不回挤）
  }
  RenderEvent& e = r->ring[static_cast<size_t>(head % kRingCapacity)];
  e.startFrame = start;
  e.endFrame = end;
  e.seq = r->nextSeq++;
  e.segment = segmentId;
  e.volume = volume;
  r->head.store(head + 1, std::memory_order_release);
  return 0;
}

// 丢弃全部未消费事件（暂停/seek/关声：错过的拍不补发）。只前移 flush 游
// 标（控制线程单写者），已入槽位由回调按 seq 跳过——不与回调竞争 tail。
__attribute__((visibility("default"))) int32_t beat_audio_flush(void* handle) {
  auto* r = static_cast<Renderer*>(handle);
  if (r == nullptr) return -1;
  const uint64_t last = r->nextSeq - 1;
  if (last > r->flushedSeq.load(std::memory_order_relaxed)) {
    r->flushedSeq.store(last, std::memory_order_release);
  }
  return 0;
}

// 开流（常驻低延迟流；段就绪后开流以便按实际流采样率重采样）。
// 已有流先尝试续跑（requestStart）；部分机型（实测 DNP-AN00）stop 后对同一
// 流 requestStart 返回 INVALID_STATE——此时关流重建再开，保证暂停/退页后
// 恢复发声。**错误回调只置状态、不关流**：跨线程 close 会被 AAudio 拒，
// 因此这里关掉的是错误回调留下的失效流对象，走新建这条正道。
//
// 这条内部重建**刻意不动** framePos/事件环/flushedSeq：它服务的是「暂停后
// 恢复」这类同一时间轴的延续（播放头连续、已排未播的拍仍要落在原位）。要
// 丢弃整条时间轴（设备切换后旧事件已无意义）走 beat_audio_recover_transport，
// 那条路才清 framePos 与事件环。播放头锚由 sync 重立。开流成功即清「已被
// 错误关闭」状态（供 Dart 侧探测重开的那一路收口）。
__attribute__((visibility("default"))) int32_t beat_audio_start(void* handle) {
  auto* r = static_cast<Renderer*>(handle);
  if (r == nullptr) return -1;
  const AAudioApi& aa = AAudioApi_();
  int32_t result;
  if (r->stream != nullptr) {
    if (!aa.available) return AAUDIO_ERROR_UNAVAILABLE;
    result = aa.requestStart(r->stream);
    if (result == AAUDIO_OK) {
      r->streamLost.store(0, std::memory_order_release);
      return AAUDIO_OK;
    }
    CloseStream(r);
  }
  result = OpenStream(r);
  if (result != AAUDIO_OK) return result;
  // 流对象已重建：错误回调遗留的「已被错误关闭」状态随之失效（本流是否真
  // 跑起来由 requestStart 的返回值决定，Dart 侧失败另有冷却重试记录）。
  r->streamLost.store(0, std::memory_order_release);
  return aa.requestStart(r->stream);
}

// 「流已被系统错误关闭」状态查询：1 = 错误回调关流置空后尚未成功重开、
// 0 = 正常、-1 = 句柄无效。Dart 在应活时探测到即重开（生命周期自愈）。
__attribute__((visibility("default"))) int32_t beat_audio_stream_lost(
    void* handle) {
  auto* r = static_cast<Renderer*>(handle);
  if (r == nullptr) return -1;
  return r->streamLost.load(std::memory_order_acquire);
}

// 停流（暂停/关声/退页）：流对象保留复用，回调停止即无输出不空耗。
__attribute__((visibility("default"))) int32_t beat_audio_stop(void* handle) {
  auto* r = static_cast<Renderer*>(handle);
  if (r == nullptr || r->stream == nullptr) return 0;
  const AAudioApi& aa = AAudioApi_();
  return aa.available ? aa.requestStop(r->stream) : AAUDIO_ERROR_UNAVAILABLE;
}

__attribute__((visibility("default"))) void beat_audio_destroy(void* handle) {
  auto* r = static_cast<Renderer*>(handle);
  if (r == nullptr) return;
  CloseStream(r);
  delete r;
}

// 重建原生输出流（恢复的最后手段）：停流 + 关掉当前流对象 + 清空
// 播放头/事件环，下一次 beat_audio_start 在**全新流对象**上开流。段资产与
// 句柄保留。**只能由控制线程调用**。
__attribute__((visibility("default"))) int32_t beat_audio_recover_transport(
    void* handle) {
  auto* r = static_cast<Renderer*>(handle);
  if (r == nullptr) return -1;
  CloseStream(r);
  ResetStreamState(r);
  // 「流已失效」状态一并清：重建后是否真跑起来由紧随其后的 start 决定，
  // 留着旧状态会让 Dart 把已经重建好的流又当失效（多绕一轮）。
  r->streamLost.store(0, std::memory_order_release);
  return 0;
}

// 与 Dart 媒介时钟同一单调时基（CLOCK_MONOTONIC，毫秒）：Dart 侧经此注入
// MediaClockEstimator 取时函数，同步对墙钟跨 ffi 无 epoch 偏差。
__attribute__((visibility("default"))) int64_t beat_audio_monotonic_ms() {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return static_cast<int64_t>(ts.tv_sec) * 1000 + ts.tv_nsec / 1000000;
}

}  // extern "C"
