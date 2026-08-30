#!/usr/bin/env bash
# The WezTerm layer is the one place this repo crosses the WSL/Windows
# boundary, so it is the one place a macOS-shaped assumption does real damage.
#
# Coverage:
# - the shared wezterm.lua guards every platform-specific option;
# - the Windows loader template declares both placeholders, and rendering
#   leaves none behind;
# - the "generated" marker in the template is byte-identical to the one the
#   installer greps for before overwriting (the clobber guard);
# - the installer exits 0 with a message, never an error, when Windows is
#   unreachable - a switch must not fail because interop is off;
# - Lua syntax, when a Lua binary is available.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CONFIG="$ROOT/home/.config/wezterm/wezterm.lua"
TEMPLATE="$ROOT/home/.config/wezterm/windows-bootstrap.lua.in"
INSTALLER="$ROOT/scripts/install-windows-wezterm.sh"

# --- platform guards ----------------------------------------------------------

assert_contains "$(cat "$CONFIG")" "macos_window_background_blur" \
  "wezterm.lua dropped the macOS blur setting entirely; it should stay, guarded"
# macos_window_background_blur must sit inside the is_macos branch, never at
# top level where Windows would trip over it.
awk '/^if is_macos then/,/^end/' "$CONFIG" | grep -q "macos_window_background_blur" \
  || fail "macos_window_background_blur is not guarded by is_macos"
awk '/^if is_windows then/,/^end/' "$CONFIG" | grep -q "win32_system_backdrop" \
  || fail "win32_system_backdrop is not guarded by is_windows"
awk '/^if is_windows then/,/^end/' "$CONFIG" | grep -q "default_domain" \
  || fail "default_domain is not guarded by is_windows"
pass "wezterm.lua guards every platform-specific option"

# Acrylic only renders when the window is not fully opaque.
opacity=$(sed -nE 's/^config\.window_background_opacity = ([0-9.]+).*/\1/p' "$CONFIG")
[ -n "$opacity" ] || fail "wezterm.lua does not set window_background_opacity"
awk -v o="$opacity" 'BEGIN { exit !(o < 1.0) }' \
  || fail "win32_system_backdrop needs window_background_opacity < 1.0, got $opacity"
pass "window_background_opacity ($opacity) lets the Acrylic backdrop show"

# --- template placeholders ----------------------------------------------------

for placeholder in "@WSL_CONFIG_UNC@" "@WSL_DISTRO@"; do
  assert_contains "$(cat "$TEMPLATE")" "$placeholder" \
    "template is missing the $placeholder placeholder"
  assert_contains "$(cat "$INSTALLER")" "$placeholder" \
    "installer never substitutes $placeholder"
done
pass "both loader placeholders are declared and substituted"

# --- clobber guard coupling ---------------------------------------------------

MARKER="GENERATED - do not edit on the Windows side"
assert_contains "$(cat "$TEMPLATE")" "$MARKER" \
  "template lost the generated marker; the installer would back up its own output forever"
assert_contains "$(cat "$INSTALLER")" "grep -q '$MARKER'" \
  "installer's clobber guard does not match the template's marker verbatim"
pass "the generated marker matches between template and installer"

# --- rendering is literal ----------------------------------------------------

TMP_ROOT=$(dotfiles_test_tmproot wezterm)
RENDERED="$TMP_ROOT/wezterm.lua"

# Every segment here is an escape sequence that sed or bash pattern
# substitution would eat: a leading \\, then \r, \n, \t and \b. This exact
# corruption shipped once - the loader looked fine and pointed at nothing.
NASTY='\\\\wsl.localhost\\rocky10\\home\\me\\newline\\tab\\back.lua'

# Render through the real installer, not a reimplementation of it, or the test
# and the code can drift apart in exactly the way that caused the bug.
"$INSTALLER" --render "$NASTY" rocky10 > "$RENDERED" \
  || fail "installer --render failed"

got=$(sed -n 's/^local WSL_CONFIG = \[\[\(.*\)\]\]$/\1/p' "$RENDERED")
[ "$got" = "$NASTY" ] \
  || fail "the UNC path was corrupted in rendering: expected [$NASTY], got [$got]"
pass "the UNC path survives rendering byte-for-byte"

assert_not_contains "$(cat "$RENDERED")" "@WSL_" \
  "rendered loader still contains an unsubstituted placeholder"
assert_contains "$(cat "$RENDERED")" 'config.default_domain = "WSL:rocky10"' \
  "rendered fallback does not point at the WSL distro"
# A stray carriage return is what the sed bug produced; Lua would read it as
# part of the path.
if LC_ALL=C grep -q $'\r' "$RENDERED"; then
  fail "the rendered loader contains a carriage return"
fi
pass "rendering substitutes every placeholder and adds no control characters"

# --- installer degrades gracefully -------------------------------------------

# Stand in for "not running under WSL" with a PATH holding only the tools the
# installer needs before its wslpath check, and no wslpath. Emptying PATH
# outright would only prove that a script with no coreutils fails.
FAKE_BIN="$TMP_ROOT/bin"
mkdir -p "$FAKE_BIN"
# bash too: the installer's `#!/usr/bin/env bash` shebang resolves the
# interpreter itself through PATH.
for tool in bash dirname; do
  ln -s "$(command -v "$tool")" "$FAKE_BIN/$tool"
done
[ ! -e "$FAKE_BIN/wslpath" ] || fail "the fake PATH must not provide wslpath"

out=$(PATH="$FAKE_BIN" "$INSTALLER" 2>&1) && rc=0 || rc=$?
[ "${rc:-0}" -eq 0 ] || fail "installer exited $rc when Windows was unreachable; it must no-op"
assert_contains "$out" "skipped" "installer did not explain why it no-opped"
assert_contains "$out" "not running under WSL" "installer gave the wrong reason: $out"
pass "installer no-ops with a message when Windows is unreachable"

# --- the activation must be able to find wslpath ------------------------------

# Home Manager seals the activation PATH to Nix store tools. wslpath lives in
# /usr/bin, and without it the installer skips - correctly, but silently, so the
# Windows loader never gets installed and nothing says why. This regressed once.
WSL_NIX="$ROOT/wsl.nix"
# The $PATH below is a literal to match in wsl.nix, not a shell expansion.
# shellcheck disable=SC2016
grep -q 'PATH="\$PATH:/usr/bin" run' "$WSL_NIX" \
  || fail "wsl.nix must extend the activation PATH so the installer can find wslpath"
# Appended, never prepended: prepending would shadow the Nix coreutils the rest
# of the activation depends on.
# shellcheck disable=SC2016
grep -q 'PATH="/usr/bin:\$PATH" run' "$WSL_NIX" \
  && fail "wsl.nix prepends /usr/bin, which shadows the Nix tools; append instead"
pass "the activation extends PATH so the installer can find wslpath"

# --- lua syntax ---------------------------------------------------------------

if command -v luac >/dev/null 2>&1; then
  luac -p "$CONFIG" || fail "wezterm.lua is not valid Lua"
  luac -p "$RENDERED" || fail "the rendered Windows loader is not valid Lua"
  pass "both Lua files parse"
else
  printf 'ok - lua syntax check skipped (no luac; try: nix develop)\n'
fi
