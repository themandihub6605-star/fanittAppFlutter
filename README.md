# Fanitt — Flutter app (creators, brands, agencies)

## 1. Create the native projects
```
cd fanitt
flutter create . --org com.fanitt --project-name fanitt --platforms android,ios
flutter pub get
```
Keep this `lib/` and `pubspec.yaml` (answer "no" if asked to overwrite them).

## 2. Firebase (Google sign-in) — same project as the backend's FIREBASE_PROJECT_ID
```
dart pub global activate flutterfire_cli
flutterfire configure
```
This replaces the placeholder `lib/firebase_options.dart`.
- Firebase Console → Authentication → Sign-in method → enable Google
- Android: add debug + release SHA-1 and SHA-256 to the Android app in Firebase
- iOS: add `REVERSED_CLIENT_ID` as a URL scheme (see `platform_setup/ios_Info.plist_additions.xml`)

## 3. Push notifications
- Firebase Console → Project settings → Cloud Messaging → upload your **APNs auth key** (.p8) for iOS
- Xcode → Runner → Signing & Capabilities → add **Push Notifications** and **Background Modes → Remote notifications**
- Backend: `FIREBASE_PROJECT_ID`, `FIREBASE_CLIENT_EMAIL`, `FIREBASE_PRIVATE_KEY` must be set (already used for Google sign-in)

## 4. Platform settings
- `platform_setup/ios_Info.plist_additions.xml` → `ios/Runner/Info.plist`
- `platform_setup/android_AndroidManifest_additions.xml` → `android/app/src/main/AndroidManifest.xml`
- `platform_setup/android_proguard-rules.pro` → `android/app/proguard-rules.pro`
- `platform_setup/android_build_gradle_additions.txt` → `android/app/build.gradle(.kts)`
- `ios/Podfile`: `platform :ios, '13.0'`

## 5. Run
```
flutter run \
  --dart-define=API_BASE_URL=https://<your-api-domain>/api \
  --dart-define=RAZORPAY_KEY_ID=rzp_live_xxxxxxxx
```
Android emulator → local backend: `http://10.0.2.2:5000/api`. iOS simulator: `http://localhost:5000/api`.

## 6. Release builds
```
flutter build appbundle --dart-define=API_BASE_URL=... --dart-define=RAZORPAY_KEY_ID=...
flutter build ipa       --dart-define=API_BASE_URL=... --dart-define=RAZORPAY_KEY_ID=...
```

## 7. Backend
Copy everything in `backend/` over the same paths in `fanitt-backend`, then restart the server.

## Password reset links (optional deep link)
The reset email links to `https://fanitt.com/reset-password?token=…`. In the app, users tap
**Forgot password → I have the reset link** and paste it. To open the app straight from the email,
set up Android App Links / iOS Universal Links for `fanitt.com/reset-password` — the app already
handles the `/reset-password?token=` route.
