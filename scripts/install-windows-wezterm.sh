#!/usr/bin/env bash
# Install the Windows-side WezTerm loader.
#
# Home Manager symlinks every other config straight into the repo, but WezTerm
# is a Windows program and Windows cannot follow a Linux symlink. So we render
# home/.config/wezterm/windows-bootstrap.lua.in - a loader that reads the real
# config out of WSL over \\wsl.localhost - and copy that to the Windows side.
# Editing the .lua in this repo still takes effect on Ctrl+Shift+R, no rebuild.
#
# Run by home.activation.windowsWezterm in wsl.nix; also runnable by hand.
#   --dry-run                    report what would change, write nothing
#   --render <unc> <distro>      print the rendered loader on stdout
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TEMPLATE="$DIR/home/.config/wezterm/windows-bootstrap.lua.in"
SOURCE_CONFIG="$DIR/home/.config/wezterm/wezterm.lua"

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

note() { printf 'wezterm: %s\n' "$1"; }
skip() { printf 'wezterm: skipped - %s\n' "$1" >&2; exit 0; }

[ -f "$TEMPLATE" ] || skip "missing template $TEMPLATE"
[ -f "$SOURCE_CONFIG" ] || skip "missing config $SOURCE_CONFIG"

# substitute <string> <placeholder> <replacement> -- literal, on stdout.
#
# Not sed, and not ${var//placeholder/replacement} either. A UNC path is
# nothing but backslashes, and both of those process escapes in the
# replacement text:
#   * sed turns \\ into \ and reads \r in "\rocky10" as a carriage return;
#   * bash 5.2's pattern substitution collapses \\ into \ so it can support
#     & and \& in the replacement.
# Either one silently corrupts the path - the loader still looks plausible and
# WezTerm just quietly falls back to its defaults. Prefix/suffix removal plus
# plain concatenation is the only form that touches nothing, and consuming from
# the front means a replacement containing the placeholder cannot loop forever.
substitute() {
  local str=$1 placeholder=$2 replacement=$3 out=""
  while [ "${str#*"$placeholder"}" != "$str" ]; do
    out=$out${str%%"$placeholder"*}$replacement
    str=${str#*"$placeholder"}
  done
  printf '%s' "$out$str"
}

# render <unc-path> <distro> -- write the filled-in loader to stdout.
render() {
  local unc=$1 distro=$2 line
  while IFS= read -r line || [ -n "$line" ]; do
    line=$(substitute "$line" "@WSL_CONFIG_UNC@" "$unc")
    line=$(substitute "$line" "@WSL_DISTRO@" "$distro")
    printf '%s\n' "$line"
  done < "$TEMPLATE"
}

if [ "${1:-}" = "--render" ]; then
  [ "$#" -eq 3 ] || { printf 'usage: %s --render <unc-path> <distro>\n' "$0" >&2; exit 2; }
  render "$2" "$3"
  exit 0
fi

# --- 1. is Windows reachable from here at all? -------------------------------
command -v wslpath >/dev/null 2>&1 || skip "no wslpath; not running under WSL"

CMD_EXE=/mnt/c/Windows/System32/cmd.exe
[ -x "$CMD_EXE" ] || skip "cannot reach $CMD_EXE (is /mnt/c mounted, interop enabled?)"

# --- 2. where is the Windows home directory? ---------------------------------
# cmd.exe warns when the cwd is a UNC path, so ask it from a drive it likes.
WIN_USERPROFILE="$(cd /mnt/c && "$CMD_EXE" /d /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r\n')" || true
[ -n "${WIN_USERPROFILE:-}" ] || skip "could not read %USERPROFILE% from Windows"

WIN_HOME="$(wslpath -u "$WIN_USERPROFILE" 2>/dev/null)" || skip "could not translate $WIN_USERPROFILE"
[ -d "$WIN_HOME" ] || skip "$WIN_HOME is not a directory"

# --- 3. build the UNC path Windows will read the real config through ---------
# Resolve symlinks first: ~/.dotfiles is a symlink, and the \\wsl.localhost
# share is not a reliable place to expect Windows to follow one.
REAL_CONFIG="$(readlink -f "$SOURCE_CONFIG")"
WSL_CONFIG_UNC="$(wslpath -w "$REAL_CONFIG")" || skip "could not translate $REAL_CONFIG to a Windows path"

# \\wsl.localhost\<distro>\  ->  <distro>
WSL_DISTRO="$(wslpath -w / | sed -E 's#^\\\\[^\\]+\\([^\\]+)\\?.*$#\1#')"
[ -n "$WSL_DISTRO" ] || skip "could not determine the WSL distro name"

# --- 4. render the loader ----------------------------------------------------
RENDERED="$(mktemp)"
trap 'rm -f "$RENDERED"' EXIT
render "$WSL_CONFIG_UNC" "$WSL_DISTRO" > "$RENDERED"

TARGET_DIR="$WIN_HOME/.config/wezterm"
TARGET="$TARGET_DIR/wezterm.lua"

# %USERPROFILE%\.wezterm.lua wins over .config\wezterm\wezterm.lua in WezTerm's
# search order, so a stray one there would silently shadow everything we do.
STRAY="$WIN_HOME/.wezterm.lua"
if [ -e "$STRAY" ]; then
  note "WARNING: $STRAY exists and takes precedence over $TARGET."
  note "         Remove or rename it, or this config will not be used."
fi

if [ -f "$TARGET" ] && cmp -s "$RENDERED" "$TARGET"; then
  note "Windows config already up to date ($TARGET)"
  exit 0
fi

if [ "$DRY_RUN" = 1 ]; then
  note "would write $TARGET (distro=$WSL_DISTRO, source=$WSL_CONFIG_UNC)"
  exit 0
fi

# Never clobber a config we did not generate.
if [ -f "$TARGET" ] && ! grep -q 'GENERATED - do not edit on the Windows side' "$TARGET"; then
  BACKUP="$TARGET.backup-$(date +%Y%m%d%H%M%S)"
  cp "$TARGET" "$BACKUP"
  note "backed up your existing Windows config to $BACKUP"
fi

mkdir -p "$TARGET_DIR"
cp "$RENDERED" "$TARGET"
note "wrote $TARGET -> reads $WSL_CONFIG_UNC (domain WSL:$WSL_DISTRO)"
