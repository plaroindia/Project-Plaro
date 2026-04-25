# Flutter specific
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Video Player - ExoPlayer
-keep class com.google.android.exoplayer2.** { *; }
-keep interface com.google.android.exoplayer2.** { *; }
-keep class com.google.android.exoplayer2.ext.** { *; }
-keep class com.google.android.exoplayer2.extractor.** { *; }
-keep class com.google.android.exoplayer2.source.** { *; }
-keep class com.google.android.exoplayer2.upstream.** { *; }
-keep class com.google.android.exoplayer2.util.** { *; }
-dontwarn com.google.android.exoplayer2.**

# Flutter Video Player Plugin
-keep class io.flutter.plugins.videoplayer.** { *; }
-keep interface io.flutter.plugins.videoplayer.** { *; }
-dontwarn io.flutter.plugins.videoplayer.**

# Keep video player surface views
-keep class * extends android.view.TextureView {
    <init>(...);
}
-keep class * extends android.view.SurfaceView {
    <init>(...);
}
-keepclassmembers class * extends android.view.TextureView {
    <init>(...);
}
-keepclassmembers class * extends android.view.SurfaceView {
    <init>(...);
}

# Prevent stripping of native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep video codec classes - Media3
-keep class androidx.media3.** { *; }
-keep interface androidx.media3.** { *; }
-dontwarn androidx.media3.**

# Cached Network Image
-keep class com.github.bumptech.glide.** { *; }
-keep class cached_network_image.** { *; }
-dontwarn com.github.bumptech.glide.**

# Supabase
-keep class io.supabase.** { *; }
-dontwarn io.supabase.**

# Video rendering and codecs
-keep class android.media.** { *; }
-keep class android.hardware.** { *; }
-dontwarn android.media.**

# Preserve annotations
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes Exceptions

# Keep generic signature of Dart objects
-keepattributes InnerClasses
-keepattributes EnclosingMethod