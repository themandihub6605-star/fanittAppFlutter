# Razorpay
-keepattributes *Annotation*
-dontwarn com.razorpay.**
-keep class com.razorpay.** {*;}
-optimizations !method/inlining/
-keepclasseswithmembers class * {
  public void onPayment*(...);
}

# Flutter local notifications (uses Gson for scheduled notifications)
-keep class com.dexterous.** { *; }
-keep class com.google.gson.** { *; }
-dontwarn com.google.gson.**

# Firebase / Play services
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# Google Play Services (Required for Firebase & Auth on Play Store)
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# Google Common dependencies
-keep class com.google.common.** { *; }
-dontwarn com.google.common.**

# Flutter deferred components reference Play Core classes that aren't bundled
-dontwarn com.google.android.play.core.**