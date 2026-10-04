# Phase 0: Setup - Execution Plan

## 1. Goal
Setup dev environment and devices.
- Install Xcode, Android Studio, and platform-tools (adb).
- Enable Developer options and USB debugging on the Android phone.
- Accept RSA prompt for adb.
- Check Mac macOS version and Apple Developer account status.

## 2. Steps
1. **[Manual]** User installs Xcode from Mac App Store.
2. **[Manual]** User installs Android Studio from developer.android.com.
3. **[Manual]** User installs Android platform-tools (`brew install android-platform-tools` or via SDK manager).
4. **[Manual]** User enables Developer Options on phone (tap Build number 7 times).
5. **[Manual]** User enables USB debugging.
6. **[Manual]** User plugs phone into Mac via USB cable.
7. **[Manual]** User accepts the RSA fingerprint prompt on phone.
8. **[Validation]** Run `adb devices` to verify the phone is listed as `device`.
9. **[Manual]** Note macOS version (`sw_vers`).
10. **[Manual]** Check Apple ID (Free vs Paid developer program) on developer.apple.com.

## 3. Success Criteria
- `adb devices` successfully lists the phone.
- Dev tools are installed.
