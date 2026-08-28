# R8 keep rules for the release build.
#
# Flutter, Firebase and Play Services ship their own consumer rules; these
# cover the two cases that are not covered for us.

# flutter_local_notifications reflects over its receivers and over the
# GSON-serialised scheduled-notification payload it persists across reboots.
-keep class com.dexterous.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken

# Crashlytics needs line numbers and source files to symbolicate a stack trace;
# without these a release crash report names no method.
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception
