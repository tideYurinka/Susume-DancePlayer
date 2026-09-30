import 'package:dance_learning_app/core/document_beat_grid.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';

/// 由文档 `beat` 段构造真实网格（拍序列 + 平移量 + 倍频 + 可选逐段档），
/// 供测试按同一口径装配 [DocumentBeatGrid]。
DocumentBeatGrid documentGridOf(
  BeatGrid doc, {
  Map<int, double> segmentDensities = const {},
  List<({int startMs, int endMs})> segments = const [],
}) => DocumentBeatGrid(
  beats: doc.beats,
  shift: doc.shift,
  density: doc.density,
  segmentDensities: segmentDensities,
  segments: segments,
);
