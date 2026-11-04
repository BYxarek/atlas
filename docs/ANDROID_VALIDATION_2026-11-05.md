# Android emulator validation — 2026-11-05

Device: Android Studio AVD `Medium_Phone_API_37.0`, API 37, 1080×2400, WHPX, SwiftShader.
Installed the signed release APK using Android CLI. This is the requested emulator substitute for a phone check.
All server interactions used isolated local data and `adb reverse`; production was untouched.

| Scenario | Result | Evidence |
| --- | --- | --- |
| Install, launch, start a new campaign | Passed | `build/android/emulator-game.png` |
| Select a country, confirm attack, resolve battle | Passed | `build/android/emulator-country.png`, `emulator-report.png` |
| Battle report strength, modifiers, scrolling | Passed | `build/android/emulator-report.png` |
| Portrait to landscape | Passed after rotation animation | `build/android/emulator-landscape-stable.png` |
| Home, return to application | Passed: solo campaign paused | `build/android/emulator-resume.png` |
| Persist campaign across APK update | Passed: Continue and saved campaign retained | `build/android/emulator-updated.png` |
| Type server address | Passed with focused field and ADB text input | `build/android/emulator-connected.png` |
| Connect, create PHP room, add bot, ready, start | Passed | `build/android/emulator-online-game.png` |
| Interrupt connection | Passed: timeout returns to menu with explanation | `build/android/emulator-timeout.png` |
| Restore connection and return to same room | Passed: saved room and bot retained, readiness required | `build/android/emulator-returned.png` |
| Long mobile dialogs | Found overflow; replaced with responsive in-scene modal; verified width and Back cancellation in automated tests and timeout modal in APK | `build/android/emulator-timeout.png` |
| Software keyboard | Not validated successfully: focused native helper exists and ADB text works, but IME did not appear despite the emulator setting | `build/android/emulator-ime.png` |

Reproduction commands included `android run --apks=... --device=emulator-5554`, `android layout`,
`android screen capture`, `adb shell input tap`, `adb shell input swipe`, `adb shell input text`,
`adb shell input keyevent 3`, `adb shell settings put system user_rotation 1` and `adb reverse`.
Screenshot coordinates were selected from inspected screenshots. Screenshots are generated under `build/android`.

Remaining engine/environment observations:

- SwiftShader reports `Fragment shader active uniforms exceed GL_MAX_FRAGMENT_UNIFORM_VECTORS (261)` for
  `SceneShaderGLES3`; the 2D map and controls rendered. This is not a clean graphics compatibility pass.
- The engine logged `Can't play finished Tween` during long sessions. The toast now drops its tween reference
  in its final callback to prevent later attempts to resume a completed notification animation.
- Desktop headless audio assertions pass, but engine shutdown reports 8 leaked ObjectDB instances and 4 resources.
- Wi-Fi-to-cellular switching and a second physical device were not exercised. The network test interrupts the
  local transport tunnel; it does not emulate radio handover, a provider's TLS, or real hosting performance.
