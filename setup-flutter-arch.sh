#!/usr/bin/env bash
set -Eeuo pipefail

# Lightweight Flutter Android setup for Arch Linux.
# Installs a version-pinned Flutter SDK and Android command-line tooling.
# It does not install Android Studio, an emulator, system images, FVM, or mise.

FLUTTER_VERSION="${FLUTTER_VERSION:-3.47.9}"
ANDROID_API="${ANDROID_API:-36}"
BUILD_TOOLS_VERSION="${BUILD_TOOLS_VERSION:-36.0.0}"
ANDROID_SDK="${ANDROID_SDK:-$HOME/Android/Sdk}"
FLUTTER_ROOT="${FLUTTER_ROOT:-$HOME/.local/share/flutter/$FLUTTER_VERSION}"
FLUTTER_BIN="${FLUTTER_BIN:-$HOME/.local/bin}"
CMDLINE_TOOLS_URL="${CMDLINE_TOOLS_URL:-https://dl.google.com/android/repository/commandlinetools-linux-14742923_latest.zip}"
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: setup-flutter-arch.sh [options]

Options:
  --flutter-version VERSION  Flutter stable version to install (default: 3.47.9)
  --android-api API           Android API platform (default: 36)
  --sdk PATH                  Android SDK location (default: ~/Android/Sdk)
  --dry-run                   Print actions without changing the system
  -h, --help                  Show this help

Environment overrides:
  FLUTTER_VERSION, ANDROID_API, BUILD_TOOLS_VERSION, ANDROID_SDK,
  FLUTTER_ROOT, FLUTTER_BIN, CMDLINE_TOOLS_URL
EOF
}

log() {
  printf '\n==> %s\n' "$*"
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

run() {
  if (( DRY_RUN )); then
    printf '+'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

while (($#)); do
  case "$1" in
    --flutter-version)
      (($# >= 2)) || die "--flutter-version needs a value"
      FLUTTER_VERSION="$2"
      FLUTTER_ROOT="$HOME/.local/share/flutter/$FLUTTER_VERSION"
      shift 2
      ;;
    --android-api)
      (($# >= 2)) || die "--android-api needs a value"
      ANDROID_API="$2"
      shift 2
      ;;
    --sdk)
      (($# >= 2)) || die "--sdk needs a value"
      ANDROID_SDK="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

[[ $EUID -ne 0 ]] || die "Run this script as a normal user, not with sudo."
[[ $FLUTTER_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
  die "Flutter version must look like 3.47.9."
[[ $ANDROID_API =~ ^[0-9]+$ ]] || die "Android API must be numeric."
[[ $BUILD_TOOLS_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
  die "Build-tools version must look like 36.0.0."

command -v pacman >/dev/null || die "This script requires Arch Linux (pacman was not found)."

log "Installing Arch prerequisites"
run sudo pacman -Syu --needed \
  android-tools \
  android-udev \
  curl \
  git \
  jdk17-openjdk \
  unzip \
  xz \
  zip

log "Preparing directories"
run mkdir -p "$FLUTTER_BIN" "$HOME/.local/share/flutter" "$ANDROID_SDK/cmdline-tools"

if [[ ! -x "$FLUTTER_ROOT/bin/flutter" ]]; then
  log "Downloading Flutter $FLUTTER_VERSION"
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "${tmp_dir:-}"' EXIT
  flutter_archive="$tmp_dir/flutter.tar.xz"
  run curl --fail --location --retry 3 \
    --output "$flutter_archive" \
    "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
  run mkdir -p "$tmp_dir/extracted"
  run tar -xf "$flutter_archive" -C "$tmp_dir/extracted"
  run rm -rf "$FLUTTER_ROOT"
  run mv "$tmp_dir/extracted/flutter" "$FLUTTER_ROOT"
else
  log "Flutter $FLUTTER_VERSION is already installed"
fi

run ln -sfn "$FLUTTER_ROOT/bin/flutter" "$FLUTTER_BIN/flutter"
run ln -sfn "$FLUTTER_ROOT/bin/dart" "$FLUTTER_BIN/dart"

cmdline_tools="$ANDROID_SDK/cmdline-tools/latest/bin/sdkmanager"
if [[ ! -x "$cmdline_tools" ]]; then
  log "Installing Android command-line tools"
  tmp_dir="${tmp_dir:-$(mktemp -d)}"
  trap 'rm -rf "${tmp_dir:-}"' EXIT
  cmdline_archive="$tmp_dir/android-cmdline-tools.zip"
  run curl --fail --location --retry 3 \
    --output "$cmdline_archive" "$CMDLINE_TOOLS_URL"
  run rm -rf "$tmp_dir/cmdline-tools" "$ANDROID_SDK/cmdline-tools/latest"
  run unzip -q "$cmdline_archive" -d "$tmp_dir"
  run mv "$tmp_dir/cmdline-tools" "$ANDROID_SDK/cmdline-tools/latest"
else
  log "Android command-line tools are already installed"
fi

export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk}"
export ANDROID_HOME="$ANDROID_SDK"
export ANDROID_SDK_ROOT="$ANDROID_SDK"
export PATH="$FLUTTER_BIN:$FLUTTER_ROOT/bin:$ANDROID_SDK/cmdline-tools/latest/bin:$ANDROID_SDK/platform-tools:$PATH"

if (( ! DRY_RUN )); then
  log "Accepting Android SDK licenses"
  yes | "$cmdline_tools" --sdk_root="$ANDROID_SDK" --licenses >/dev/null
fi

log "Installing Android SDK packages"
run "$cmdline_tools" --sdk_root="$ANDROID_SDK" \
  "platform-tools" \
  "platforms;android-$ANDROID_API" \
  "build-tools;$BUILD_TOOLS_VERSION"

profile_file="$HOME/.profile"
fish_env_dir="$HOME/.config/fish/conf.d"
fish_env_file="$fish_env_dir/flutter-android.fish"
zshrc_file="$HOME/.zshrc"

log "Writing shell environment configuration"
if (( ! DRY_RUN )); then
  if command -v fish >/dev/null 2>&1; then
    mkdir -p "$fish_env_dir"
    cat > "$fish_env_file" <<EOF
set -gx JAVA_HOME '$JAVA_HOME'
set -gx ANDROID_HOME '$ANDROID_SDK'
set -gx ANDROID_SDK_ROOT '$ANDROID_SDK'
fish_add_path '$FLUTTER_BIN' '$ANDROID_SDK/cmdline-tools/latest/bin' '$ANDROID_SDK/platform-tools'
EOF
  else
    log "Fish is not installed; skipping Fish configuration"
  fi

  touch "$profile_file"
  marker="# Flutter Android toolchain"
  if ! grep -Fqx "$marker" "$profile_file"; then
    cat >> "$profile_file" <<EOF

$marker
export JAVA_HOME='$JAVA_HOME'
export ANDROID_HOME='$ANDROID_SDK'
export ANDROID_SDK_ROOT='$ANDROID_SDK'
export PATH='$FLUTTER_BIN:$ANDROID_SDK/cmdline-tools/latest/bin:$ANDROID_SDK/platform-tools:\$PATH'
EOF
  fi

  if command -v zsh >/dev/null 2>&1; then
    touch "$zshrc_file"
    if ! grep -Fqx "$marker" "$zshrc_file"; then
      cat >> "$zshrc_file" <<EOF

 $marker
 export JAVA_HOME='$JAVA_HOME'
 export ANDROID_HOME='$ANDROID_SDK'
 export ANDROID_SDK_ROOT='$ANDROID_SDK'
 export PATH='$FLUTTER_BIN:$ANDROID_SDK/cmdline-tools/latest/bin:$ANDROID_SDK/platform-tools:\$PATH'
EOF
    fi
  else
    log "Zsh is not installed; skipping Zsh configuration"
  fi
fi

log "Verifying installation"
if (( DRY_RUN )); then
  printf 'Dry run complete. No changes were made.\n'
else
  "$FLUTTER_BIN/flutter" config --android-sdk "$ANDROID_SDK" >/dev/null
  "$FLUTTER_BIN/flutter" --version
  "$FLUTTER_BIN/flutter" doctor -v
  printf '\nConnect an Android phone with USB debugging enabled, then run:\n'
  printf '  adb devices\n'
  printf '  flutter devices\n'
fi
