# Android

[Documentation index](README.md) · [Русский](../ANDROID.md)

ATLAS uses native Godot rendering with armeabi-v7a, arm64-v8a, x86 and x86_64 libraries. Minimum Android is 7.0 / API 24 with OpenGL ES 3.0; the current template targets API 36. This release is an installable signed APK, not a Google Play AAB.

Install `Atlas-Android.apk` from Releases. Install updates over the previous app; uninstalling deletes private saves, preferences and the multiplayer identity. Portrait and landscape layouts, safe-area insets, scrolling menus, touch selection, dragging, pinch zoom and Back navigation are supported. Solo play saves and pauses when backgrounded; online pause requests are best effort and server disconnect timeouts still apply.

## Build and signing

First run the full build to obtain the pinned editor or place the Godot 4.7.2 Windows editor in `tools`. Configure Android SDK and JDK, then:

```powershell
$env:ATLAS_ANDROID_SDK = 'C:/path/to/Android/Sdk'
$env:ATLAS_JAVA_SDK = 'C:/path/to/jdk'
python tools/build_android.py
```

The helper downloads the release template when missing, exports, signs, checks the APK signature and verifies native libraries. It also accepts `ANDROID_HOME`/`JAVA_HOME`, detects the SDK through `android info` if available, and can use Android Studio JBR on Windows. It configures only the two Android SDK paths in the user's Godot editor settings. The prebuilt template controls min/target SDK; changing those requires a Gradle export.

A first build generates a signing key and config in `%USERPROFILE%/.atlas/signing`: `android-release.jks` and `android-release.json`. **Back up both privately.** Future install-over updates need the same key and an increasing Android version code. Forks should use their own signing key and package ID. Never commit signing credentials.

Version name is `0.1.0`. Android version code is `11` so this APK can update the earlier local builds with codes `9` and `10`, despite the public version-number reset.

## Validation limits

Release signature and library checks pass; mobile UI and network scenarios run in native desktop Godot. No physical Android device was available for this release, and the local emulator could not boot without a hypervisor driver. GPU compatibility, software keyboard, system gestures and lifecycle behavior still need a real-device test.
