#!/usr/bin/env bash
# flutter-setup.sh — Flutter + Android SDK (no Android Studio) for Arch-based distros.
# Idempotent: safe to re-run.   Preview first:  ./flutter-setup.sh --dry-run
set -Eeuo pipefail

# ── Settings (override via env, e.g. FLUTTER_DIR=~/sdk/flutter ./flutter-setup.sh) ──
FLUTTER_DIR="${FLUTTER_DIR:-$HOME/dev/flutter}"
SDK_DIR="${SDK_DIR:-$HOME/Android/Sdk}"
JDK_NAME="java-17-openjdk"
JDK_DIR="/usr/lib/jvm/$JDK_NAME"
CMDLINE_URL="${CMDLINE_URL:-https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip}"
PKGS=(git curl unzip xz zip glu jdk17-openjdk)
SDK_PKGS=("platform-tools" "platforms;android-36" "build-tools;35.0.0" "build-tools;28.0.3")
GRADLE_OPTS=("org.gradle.jvmargs=-Xmx2g" "org.gradle.daemon=true" "org.gradle.caching=true")
MARK_BEGIN="# >>> flutter-android setup >>>"
MARK_END="# <<< flutter-android setup <<<"
FISH_FILE="$HOME/.config/fish/conf.d/flutter-android.fish"

# ── Options ──
DRY=0; ASSUME_YES=0; UDEV=0
usage() {
  cat <<'EOF'
Usage: flutter-setup.sh [options]
  -n, --dry-run   Show what would happen; change nothing
  -y, --yes       Don't ask pacman for confirmation
      --udev      Also install android-udev (only if adb says "no permissions")
  -h, --help      Show this help
Env overrides: FLUTTER_DIR, SDK_DIR, CMDLINE_URL
EOF
}
for arg in "$@"; do
  case "$arg" in
    -n|--dry-run) DRY=1 ;;
    -y|--yes)     ASSUME_YES=1 ;;
    --udev)       UDEV=1 ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; usage >&2; exit 1 ;;
  esac
done

# ── Output helpers ──
if [[ -t 1 ]]; then
  B=$'\e[1m'; G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; D=$'\e[2m'; N=$'\e[0m'
else
  B=; G=; Y=; R=; D=; N=
fi
step() { printf '\n%s▸ %s%s\n' "$B" "$*" "$N"; }
ok()   { if (( ! DRY )); then printf '  %s✓%s %s\n' "$G" "$N" "$*"; fi; }
skip() { printf '  %s•%s %s%s%s\n' "$D" "$N" "$D" "$*" "$N"; }
warn() { printf '  %s!%s %s\n' "$Y" "$N" "$*"; }
dry()  { printf '  %s[dry-run]%s %s\n' "$Y" "$N" "$*"; }
die()  { printf '%s✗ %s%s\n' "$R" "$*" "$N" >&2; exit 1; }
tilde() { printf '%s' "${1/#$HOME/\~}"; }
run()  { if (( DRY )); then dry "$*"; else "$@"; fi; }

TMP=""
cleanup() { if [[ -n "$TMP" ]]; then rm -rf "$TMP"; fi; }
trap cleanup EXIT
trap 'printf "%s✗ Failed at line %s. Fix the error above and re-run (safe to repeat).%s\n" "$R" "$LINENO" "$N" >&2' ERR

# ── Steps ──
preflight() {
  step "Checking system"
  if (( EUID == 0 )); then die "Run as your normal user, not root."; fi
  command -v pacman >/dev/null || die "pacman not found: this script is for Arch-based distros."
  if [[ -n "${ANDROID_HOME:-}" && ! -d "$ANDROID_HOME" ]]; then
    warn "Stale ANDROID_HOME=$ANDROID_HOME in this session (fixed after you reload your shell)."
  fi
  if (( ! DRY )); then sudo -v; fi
  ok "Arch-based system, user $USER"
}

install_packages() {
  step "System packages"
  local missing=() p flags=(--needed)
  for p in "${PKGS[@]}"; do pacman -Qq "$p" &>/dev/null || missing+=("$p"); done
  if (( UDEV )); then pacman -Qq android-udev &>/dev/null || missing+=(android-udev); fi
  if (( ${#missing[@]} == 0 )); then skip "all present"; return 0; fi
  if (( ASSUME_YES )); then flags+=(--noconfirm); fi
  run sudo pacman -S "${flags[@]}" "${missing[@]}"
  ok "Installed: ${missing[*]}"
}

set_java() {
  step "Java 17"
  if ! command -v archlinux-java >/dev/null; then warn "archlinux-java not found; skipping"; return 0; fi
  if [[ "$(archlinux-java get 2>/dev/null || true)" == "$JDK_NAME" ]]; then skip "already default"; return 0; fi
  run sudo archlinux-java set "$JDK_NAME"
  ok "Default JDK: $JDK_NAME"
}

install_flutter() {
  step "Flutter SDK"
  if [[ -x "$FLUTTER_DIR/bin/flutter" ]]; then skip "found at $(tilde "$FLUTTER_DIR")"; return 0; fi
  if [[ -d "$FLUTTER_DIR" && -n "$(ls -A "$FLUTTER_DIR" 2>/dev/null)" ]]; then
    die "$FLUTTER_DIR exists but isn't a Flutter SDK. Move it or set FLUTTER_DIR."
  fi
  run mkdir -p "$(dirname "$FLUTTER_DIR")"
  run git clone --branch stable https://github.com/flutter/flutter.git "$FLUTTER_DIR"
  ok "Flutter (stable) → $(tilde "$FLUTTER_DIR")"
}

install_cmdline_tools() {
  step "Android command-line tools"
  if [[ -x "$SDK_DIR/cmdline-tools/latest/bin/sdkmanager" ]]; then skip "already installed"; return 0; fi
  if (( DRY )); then
    dry "download $CMDLINE_URL"
    dry "extract → $SDK_DIR/cmdline-tools/latest"
    return 0
  fi
  TMP="$(mktemp -d)"
  curl -fL --progress-bar -o "$TMP/tools.zip" "$CMDLINE_URL"
  unzip -tq "$TMP/tools.zip" >/dev/null   # integrity check before extracting
  unzip -q "$TMP/tools.zip" -d "$TMP"
  mkdir -p "$SDK_DIR/cmdline-tools"
  rm -rf "$SDK_DIR/cmdline-tools/latest"
  mv "$TMP/cmdline-tools" "$SDK_DIR/cmdline-tools/latest"
  ok "cmdline-tools → $(tilde "$SDK_DIR")/cmdline-tools/latest"
}

install_sdk_packages() {
  step "Android SDK packages"
  local sdkm="$SDK_DIR/cmdline-tools/latest/bin/sdkmanager" missing=() p rel
  for p in "${SDK_PKGS[@]}"; do
    rel="$(tr ';' '/' <<<"$p")"
    [[ -d "$SDK_DIR/$rel" ]] || missing+=("$p")
  done
  if (( ${#missing[@]} == 0 )); then skip "all present"; return 0; fi
  if (( DRY )); then dry "sdkmanager --sdk_root=$SDK_DIR $(printf '%q ' "${missing[@]}")"; return 0; fi
  yes | "$sdkm" --sdk_root="$SDK_DIR" --licenses >/dev/null 2>&1 || true
  yes | "$sdkm" --sdk_root="$SDK_DIR" "${missing[@]}" || true
  for p in "${missing[@]}"; do
    rel="$(tr ';' '/' <<<"$p")"
    [[ -d "$SDK_DIR/$rel" ]] || die "SDK package failed to install: $p"
  done
  ok "Installed: ${missing[*]}"
}

tune_gradle() {
  step "Gradle memory limits"
  local f="$HOME/.gradle/gradle.properties" line key added=()
  run mkdir -p "$HOME/.gradle"
  for line in "${GRADLE_OPTS[@]}"; do
    key="${line%%=*}"
    if [[ -f "$f" ]] && grep -q "^${key}=" "$f"; then continue; fi
    if (( DRY )); then dry "append '$line' → $(tilde "$f")"; else printf '%s\n' "$line" >> "$f"; fi
    added+=("$key")
  done
  if (( ${#added[@]} == 0 )); then skip "already set (existing values kept)"; else ok "Set: ${added[*]##*.}"; fi
}

# ── Shell config (bash / zsh / fish) ──
posix_block() {
  cat <<EOF
$MARK_BEGIN
export ANDROID_HOME="$SDK_DIR"
export PATH="$FLUTTER_DIR/bin:\$ANDROID_HOME/cmdline-tools/latest/bin:\$ANDROID_HOME/platform-tools:\$PATH"
$MARK_END
EOF
}

fish_block() {
  cat <<EOF
$MARK_BEGIN
set -gx ANDROID_HOME "$SDK_DIR"
fish_add_path -g "$FLUTTER_DIR/bin" "$SDK_DIR/cmdline-tools/latest/bin" "$SDK_DIR/platform-tools"
$MARK_END
EOF
}

write_block() {   # write_block <file> <block-function>
  local file="$1" want have=""
  want="$("$2")"
  if [[ -f "$file" ]]; then have="$(sed -n "\|$MARK_BEGIN|,\|$MARK_END|p" "$file")"; fi
  if [[ "$have" == "$want" ]]; then skip "$(tilde "$file") up to date"; return 0; fi
  if (( DRY )); then dry "write env block → $(tilde "$file")"; return 0; fi
  mkdir -p "$(dirname "$file")"
  if [[ -f "$file" ]]; then
    [[ -e "$file.flutter-setup.bak" ]] || cp "$file" "$file.flutter-setup.bak"
    sed -i "\|$MARK_BEGIN|,\|$MARK_END|d" "$file"
  fi
  local lead=""
  if [[ -s "$file" ]]; then lead=$'\n'; fi
  printf '%s%s\n' "$lead" "$want" >> "$file"
  ok "$(tilde "$file")"
}

CONFIGURED=()
configure_shells() {
  step "Shell environment"
  if [[ -f "$HOME/.bashrc" ]] || command -v bash >/dev/null; then
    write_block "$HOME/.bashrc" posix_block; CONFIGURED+=(bash)
  fi
  if command -v zsh >/dev/null || [[ -f "$HOME/.zshrc" ]]; then
    write_block "$HOME/.zshrc" posix_block; CONFIGURED+=(zsh)
  fi
  if command -v fish >/dev/null || [[ -d "$HOME/.config/fish" ]]; then
    write_block "$FISH_FILE" fish_block; CONFIGURED+=(fish)
  fi
  # A script can't change your open terminal, but it can behave like a reloaded one:
  export ANDROID_HOME="$SDK_DIR"
  export PATH="$FLUTTER_DIR/bin:$SDK_DIR/cmdline-tools/latest/bin:$SDK_DIR/platform-tools:$PATH"
}

reload_cmd() {
  local cur; cur="$(basename "${SHELL:-bash}")"
  if [[ " ${CONFIGURED[*]} " != *" $cur "* ]]; then cur="${CONFIGURED[0]}"; fi
  case "$cur" in
    zsh)  echo "source ~/.zshrc" ;;
    fish) echo "source ~/.config/fish/conf.d/flutter-android.fish" ;;
    *)    echo "source ~/.bashrc" ;;
  esac
}

configure_flutter() {
  step "Flutter config"
  local fl="$FLUTTER_DIR/bin/flutter"
  run "$fl" config --no-analytics
  run "$fl" config --android-sdk "$SDK_DIR" --jdk-dir "$JDK_DIR"
  run "$fl" config --no-enable-linux-desktop --no-enable-web
  ok "SDK, JDK 17, Android-only"
}

verify() {
  step "Verifying"
  if (( DRY )); then dry "flutter doctor"; return 0; fi
  "$FLUTTER_DIR/bin/flutter" doctor || true
}

summary() {
  printf '\n'
  if (( DRY )); then
    printf '%sDry run complete.%s Nothing changed. Run without --dry-run to apply.\n' "$B" "$N"
    return 0
  fi
  printf '%s✓ All set.%s Next:\n' "$G$B" "$N"
  printf '  1. Reload:  %s   (or open a new terminal)\n' "$(reload_cmd)"
  printf '  2. Phone:   Settings → About phone → tap Build number ×7 → Developer options → USB debugging\n'
  printf '  3. Check:   adb devices && flutter devices\n'
  printf '  4. Try:     flutter create hello_app && cd hello_app && flutter run\n'
  if pacman -Qq android-tools &>/dev/null; then
    warn "android-tools also ships adb; doctor may flag duplicates → sudo pacman -Rns android-tools"
  fi
}

main() {
  local tag=""; if (( DRY )); then tag="(dry run)"; fi
  printf '%sFlutter + Android setup%s%s\n' "$B" "$N" "${tag:+ $tag}"
  preflight
  install_packages
  set_java
  install_flutter
  install_cmdline_tools
  install_sdk_packages
  tune_gradle
  configure_shells
  configure_flutter
  verify
  summary
}
main
