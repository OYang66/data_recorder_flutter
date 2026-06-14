# SparkChain ASR uses JNI FindClass with exact nested class names.
# Keep the SDK package names and members stable in release/R8 builds.
-keep class com.iflytek.** { *; }
-keep class com.iflytek.sparkchain.** { *; }
-keep class com.iflytek.sparkchain.core.asr.ASR$* { *; }
-keepclasseswithmembers class * {
    native <methods>;
}

-keepattributes InnerClasses,EnclosingMethod,Signature,*Annotation*
-dontwarn com.iflytek.**
