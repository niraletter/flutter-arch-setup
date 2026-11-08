# Flutter setup for Arch

Automated Flutter and Android SDK setup for Arch-based Linux, without Android Studio. Designed for testing on a physical device over USB.

## Features

- Installs Flutter (stable), the Android command-line tools, and required SDK packages
- Idempotent: safe to re-run, skips anything already installed
- `--dry-run` previews every action without changing the system
- Configures bash, zsh and fish, for whichever are present
- Applies Gradle memory limits suited to low-RAM machines

## Requirements

- Arch-based distribution with `pacman`
- Non-root user with `sudo`
- Internet connection

## Usage

```bash
git clone https://github.com/niraletter/flutter-arch-seutp.git
cd flutter-arch-setup
chmod +x flutter-setup.sh

./flutter-setup.sh --dry-run   # preview
./flutter-setup.sh             # apply
```

Reload your shell afterwards (the script prints the exact command) or open a new terminal.

| Option | Description |
|---|---|
| `-n`, `--dry-run` | Show planned actions; change nothing |
| `-y`, `--yes` | Skip pacman confirmation |
| `--udev` | Also install `android-udev` (if `adb` reports "no permissions") |
| `-h`, `--help` | Show usage |

Install locations can be overridden with `FLUTTER_DIR` and `SDK_DIR`. Package lists and versions are defined at the top of the script.

## What it changes

| Area | Change |
|---|---|
| Packages | `git curl unzip xz zip glu jdk17-openjdk` (missing ones only) |
| Java | JDK 17 set as system default |
| Flutter | `~/dev/flutter` (stable branch) |
| Android SDK | `~/Android/Sdk` (platform 36, platform-tools, build-tools) |
| Gradle | `~/.gradle/gradle.properties` (existing keys preserved) |
| Shell config | Marked block in `~/.bashrc` and `~/.zshrc`; `~/.config/fish/conf.d/flutter-android.fish` for fish |

Existing rc files are backed up once as `*.flutter-setup.bak`. Android Studio, the emulator and `android-tools` are intentionally not installed.

## Connect a device

Enable **Developer options → USB debugging** on the phone, connect it with a data cable, and accept the prompt. Then verify:

```bash
adb devices
flutter devices
```

## Uninstall

```bash
sed -i '/# >>> flutter-android setup >>>/,/# <<< flutter-android setup <<</d' ~/.bashrc ~/.zshrc
rm -f ~/.config/fish/conf.d/flutter-android.fish
rm -rf ~/dev/flutter ~/Android/Sdk
```

## Notes

The command-line tools download is pinned to a specific build and checked for integrity, but not against a checksum. Override it with `CMDLINE_URL` if the link changes.

## License

Add a `LICENSE` file of your choice.
