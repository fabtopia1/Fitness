# R8 keep rules for the release build.
#
# Flutter, Firebase and Play Services ship their own consumer rules. These
# cover what is not covered for us — and every rule here exists because its
# absence produces a failure that appears ONLY in a shrunk release build.

# ---------------------------------------------------------------- Gson ------
# flutter_local_notifications persists scheduled notifications as Gson JSON and
# reads them back in the boot receiver. Gson resolves generic types through
# TypeToken, which needs the generic signature to survive shrinking; without
# `Signature`, TypeToken<HashMap<String,Object>> erases to a raw type and Gson
# throws when the device restarts. Symptom: every reminder silently disappears
# after a reboot, release builds only.
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes InnerClasses
-keepattributes EnclosingMethod

-keep class com.dexterous.** { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep class com.google.gson.reflect.TypeToken { *; }
# Gson serialises these plugin models by field name.
-keepclassmembers class com.dexterous.flutterlocalnotifications.models.** { <fields>; }
-dontwarn com.google.gson.**

# --------------------------------------------------------- Crashlytics ------
# Line numbers and source file names are what turn a release stack trace into a
# symbolicated one. `renamesourcefileattribute` keeps the mapping useful while
# discarding the original file names from the binary.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# ------------------------------------------------------------- Firebase -----
# Firestore's model layer and the Play Services task API are reached
# reflectively by the SDK's own serialisers.
-keepclassmembers class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# ------------------------------------------------------------ platform ------
# The Flutter embedding resolves plugin registrants by name.
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
