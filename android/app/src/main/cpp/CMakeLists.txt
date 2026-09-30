cmake_minimum_required(VERSION 3.18)
project(beat_native LANGUAGES CXX)

add_library(beat_native SHARED beat_native.cpp)

# 与 Dart 实现逐位一致：禁用 FMA 收缩与任何快速数学重排。
target_compile_options(beat_native PRIVATE -O2 -ffp-contract=off)

# 节拍声原生排程渲染器（lib/player/beat_audio_native.dart 经 ffi 加载）：
# AAudio 常驻低延迟输出流。AAudio 符号经 dlopen
# 运行时解析（minSdk < 26 亦可构建；libaaudio 仅 API 26+ 存在，不链接）。
add_library(audio_native SHARED audio_native.cpp)
target_compile_options(audio_native PRIVATE -O2)
