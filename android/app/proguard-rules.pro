# ── ML Kit (on-device OCR) — don't let R8 strip it in release builds ──
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.** { *; }

# google_mlkit_text_recognition references the optional Chinese/Devanagari/
# Japanese/Korean recognizers even though we only bundle Latin. Without these,
# R8 fails the release build with "Missing class ...TextRecognizerOptions".
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# Flutter deferred components (referenced by the engine, unused here).
-dontwarn com.google.android.play.core.**
