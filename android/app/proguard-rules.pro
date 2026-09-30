# 节拍识别：flutter_onnxruntime 打包
# com.microsoft.onnxruntime:onnxruntime-android。其 JNI 层（Java_ai_onnxruntime_*）
# 经字符串名 FindClass/GetMethodID 解析类与方法；R8 混淆会改名/剥离这些符号
# （如 OnnxTensorLike -> a、OrtSession$Result -> zd），使 OrtSession.run 在
# convertToTensorInfo -> GetMethodID -> JniAbort 处 SIGSEGV（真机实测根因）。
# onnxruntime AAR 不带 consumer 规则，keep 规则在此预置。将来 release 开启
# minify 必须真机回归节拍分析。
-keep class ai.onnxruntime.** { *; }
-keepnames class ai.onnxruntime.** { *; }
-keep class ai.onnxruntime.**$Result { *; }
-dontwarn ai.onnxruntime.**
