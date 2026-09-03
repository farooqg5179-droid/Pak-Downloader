# Pak Downloader

A Flutter starter app for downloading direct video URLs that the user is authorized to download.

## Important
This version intentionally does not bypass TikTok/Facebook protections or remove platform watermarks. A normal TikTok/Facebook page URL is not necessarily a direct video file URL.

## Main files
- `lib/main.dart` - app UI and download logic
- `pubspec.yaml` - Flutter dependencies

## Build
Run:
1. `flutter pub get`
2. `flutter run`
3. `flutter build apk --release`

The app stores downloads in its application documents directory.
