# Flutter Android Setup for Arch Linux

An automated, lightweight setup for Flutter Android development on Arch Linux.

The installer provides:

- A version-pinned Flutter stable SDK
- The Dart SDK bundled with Flutter
- Android command-line tools and platform-tools
- One Android SDK platform and matching build tools
- Java 17, Android udev rules, and required Arch packages

Android Studio, emulators, system images, FVM, and mise are intentionally excluded. The intended workflow uses a physical Android device with USB debugging enabled.

## Requirements

- Arch Linux
- A user account with `sudo` access
- Internet access
- An Android device and USB data cable

Run the installer as a normal user. Do not run it with `sudo`; it invokes `sudo` only when installing system packages.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/niraletter/flutter-arch-setup/main/setup-flutter-arch.sh \
  -o setup-flutter-arch.sh
chmod +x setup-flutter-arch.sh
./setup-flutter-arch.sh
```

The default setup installs:

```text
Flutter 3.47.9
Android API 36
Android Build Tools 36.0.0
SDK location: ~/Android/Sdk
Flutter location: ~/.local/share/flutter/3.47.9
```

Android SDK licenses are accepted automatically. `pacman` and `sudo` may still prompt for confirmation.

## Options

```bash
./setup-flutter-arch.sh --dry-run
./setup-flutter-arch.sh --flutter-version 3.47.9
./setup-flutter-arch.sh --android-api 36
./setup-flutter-arch.sh --sdk "$HOME/Android/Sdk"
```

Environment variables can also override defaults:

```bash
FLUTTER_VERSION=3.47.9 \
ANDROID_API=36 \
BUILD_TOOLS_VERSION=36.0.0 \
./setup-flutter-arch.sh
```

## Verify a physical device

On the phone, enable **Developer options** and **USB debugging**, connect it over USB, and approve the computer authorization prompt.

Open a new shell, then run:

```bash
adb devices
flutter doctor
flutter devices
```

The device should appear with the state `device`. No emulator is required.
