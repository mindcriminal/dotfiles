#!/usr/bin/env bash
# Seed the three Handy settings this machine depends on, on the Windows side.
#
# Handy (https://github.com/cjpais/Handy) is the push-to-talk dictation app.
# It runs as a Windows program - it needs a global hotkey and has to type into
# whatever Windows app has focus, and a WSL process can do neither - so its
# config lives at %APPDATA%\com.pais.handy\settings_store.json, across the same
# boundary scripts/install-windows-wezterm.sh crosses.
#
# Home Manager must not own that file, for the same reason it does not own
# ~/.claude/settings.json: Handy rewrites it itself, on every settings change
# and again at shutdown, from its own in-memory copy. So this is a seed, never
# a symlink, and it is careful about three things:
#
#   * it only ever writes a key that is still at Handy's Windows default. A
#     value you chose is yours; the script reports it and moves on.
#   * it refuses to write at all while Handy is running, because Handy would
#     serialize its in-memory settings over the file at shutdown and silently
#     undo the edit.
#   * it no-ops with a message - never an error - when Handy is not installed
#     or Windows is unreachable, so a switch on a machine without Handy, or in
#     a container with interop off, still succeeds.
#
# Handy's settings struct carries a container-level #[serde(default)], so a
# store holding only some keys loads fine and every absent key falls back to
# its default (src-tauri/src/settings.rs, "a partial store can never fail the
# whole load"). That is what makes a three-key seed safe on a fresh install.
#
# Run by bootstrap.sh and by rebuild.sh, after the switch - the same place
# seed-claude-settings.sh runs. That script *has* to run after the switch
# because activation deletes the symlink an older generation owned; this one
# has no such constraint, since Home Manager has never owned a path on the
# Windows side. It runs there for consistency, and so that both seeds are in
# one place.
#
#   scripts/seed-handy-settings.sh
#   scripts/seed-handy-settings.sh --dry-run     report what would change, write nothing
#   scripts/seed-handy-settings.sh --apply FILE  print the seeded JSON on stdout
#
# --apply exists so tests/handy.test.sh can exercise the real merge rules
# against fixture stores instead of reimplementing them and drifting.
set -euo pipefail

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

note() { printf '    %s\n' "$1"; }
skip() { printf '    skipped - %s\n' "$1"; exit 0; }

# --- the settings, and why each one is here ----------------------------------
#
# One line per key: <key>|<Handy's Windows default>|<what we want>, both values
# written as JSON. The default column is what makes "never clobber your choice"
# possible: a live value that is neither the default nor ours was set by you.
# All three defaults are Handy 0.9.6's, read out of src-tauri/src/settings.rs
# (PasteMethod::default() is CtrlV off Linux, default_autostart_enabled() is
# false, and get_default_settings() leaves selected_model empty).
#
# paste_method = "direct" is the one that is not a preference. Handy's default
# pastes by putting the transcript on the Windows clipboard, sending Ctrl+V,
# and restoring the previous clipboard on a timer. WezTerm queues that paste
# through its own event loop and reads the clipboard *after* the restore has
# already fired, so it pastes whatever you had copied before instead of your
# words (upstream Handy issue #502). Neither clipboard-based mitigation holds:
# a longer paste_delay_after_ms loses to any lag, and the receipt-based
# reliable_paste path settled on a foreign process that read the clipboard a
# millisecond after the chord and restored early. "direct" types the characters
# and never touches the clipboard, which removes the race rather than racing
# it. WezTerm is this machine's terminal, so without this dictation is broken
# in the one window it is used in most. Do not tidy this back to the default.
#
# selected_model = "turbo" is the Whisper large-v3-turbo model. The seed only
# preselects it; Handy downloads the ~1.5GB weights itself on first run.
# autostart_enabled = true so dictation is there after a reboot without being
# started by hand.
SEEDS='
paste_method|"ctrl_v"|"direct"
selected_model|""|"turbo"
autostart_enabled|false|true
'

# seed_settings <json> -- set UPDATED to the seeded store and CHANGES to a
# space-prefixed list of the keys it moved. Explanations go to stderr, so
# --apply's stdout stays parseable JSON.
seed_settings() {
  UPDATED=$1
  CHANGES=""
  local key def want present current
  while IFS='|' read -r key def want; do
    [ -n "$key" ] || continue

    # `.settings[$k]` on an absent key is null, which is indistinguishable from
    # a stored null, so ask `has` explicitly.
    present="$(printf '%s' "$UPDATED" | jq --arg k "$key" '(.settings // {}) | has($k)')"
    current="$(printf '%s' "$UPDATED" | jq -c --arg k "$key" '.settings[$k]')"

    if [ "$present" = "true" ] && [ "$current" != "$def" ] && [ "$current" != "$want" ]; then
      note "$key is $current, which is neither Handy's default nor ours - leaving your choice alone" >&2
      continue
    fi
    if [ "$present" = "true" ] && [ "$current" = "$want" ]; then
      continue
    fi

    UPDATED="$(printf '%s' "$UPDATED" | jq --arg k "$key" --argjson v "$want" \
      '.settings = ((.settings // {}) | .[$k] = $v)')"
    CHANGES="$CHANGES $key=$want"
  done <<< "$SEEDS"
}

JQ_MISSING="jq is not on PATH; cannot edit the settings JSON safely"

if [ "${1:-}" = "--apply" ]; then
  [ "$#" -eq 2 ] || { printf 'usage: %s --apply <settings-file>\n' "$0" >&2; exit 2; }
  command -v jq >/dev/null 2>&1 || { printf '%s\n' "$JQ_MISSING" >&2; exit 2; }
  # A failed command substitution does not fail the command it feeds, so parse
  # in its own step - otherwise unparseable input would come out as an empty
  # store seeded with three keys, which is the clobber, not the guard.
  PARSED="$(jq '.' "$2")" || { printf '%s is not valid JSON\n' "$2" >&2; exit 2; }
  seed_settings "$PARSED"
  printf '%s\n' "$UPDATED"
  exit 0
fi

# --- is Windows reachable from here at all? ----------------------------------
command -v wslpath >/dev/null 2>&1 || skip "no wslpath; not running under WSL"

CMD_EXE=/mnt/c/Windows/System32/cmd.exe
[ -x "$CMD_EXE" ] || skip "cannot reach $CMD_EXE (is /mnt/c mounted, interop enabled?)"

command -v jq >/dev/null 2>&1 || skip "$JQ_MISSING"

# --- where does Handy keep its settings? -------------------------------------
# Ask Windows for %APPDATA% rather than assembling
# <home>/AppData/Roaming by hand: it is the variable Handy itself resolves, it
# survives a redirected or roamed profile, and it never needs the Windows
# username spelled out anywhere in this repo. cmd.exe warns when the cwd is a
# UNC path, so ask it from a drive it likes - the same dance the WezTerm
# installer does.
WIN_APPDATA="$(cd /mnt/c && "$CMD_EXE" /d /c 'echo %APPDATA%' 2>/dev/null | tr -d '\r\n')" || true
[ -n "${WIN_APPDATA:-}" ] || skip "could not read %APPDATA% from Windows"

APPDATA="$(wslpath -u "$WIN_APPDATA" 2>/dev/null)" || skip "could not translate $WIN_APPDATA"
[ -d "$APPDATA" ] || skip "$APPDATA is not a directory"

HANDY_DIR="$APPDATA/com.pais.handy"
SETTINGS="$HANDY_DIR/settings_store.json"

# Handy's data directory only exists once it has been installed and run at
# least once. Absent means "no Handy on this machine", which is a perfectly
# fine state for this repo to be in - bootstrap.sh prints the winget command
# and tests/verify.sh reports it as a skip.
[ -d "$HANDY_DIR" ] || skip "Handy is not installed (no $HANDY_DIR); winget install cjpais.Handy"

# --- read the live settings --------------------------------------------------
# A store that is missing, empty, or not valid JSON is treated differently:
# missing/empty we may create, but garbage we leave strictly alone. Overwriting
# a file we cannot parse is exactly the clobber this script exists to avoid.
if [ -s "$SETTINGS" ]; then
  if ! LIVE="$(jq '.' "$SETTINGS" 2>/dev/null)"; then
    skip "$SETTINGS is not valid JSON; leaving it untouched"
  fi
else
  LIVE='{"settings":{}}'
fi

# --- work out what would change ----------------------------------------------
seed_settings "$LIVE"

if [ -z "$CHANGES" ]; then
  note "Handy's settings already match this repo, leaving them alone"
  exit 0
fi

if [ "$DRY_RUN" = 1 ]; then
  note "would set$CHANGES in $SETTINGS"
  exit 0
fi

# --- do not fight a running Handy --------------------------------------------
# Handy holds its settings in memory and serializes them back over this file
# when it exits. Writing underneath it looks like it worked and is undone the
# next time you quit, so refuse instead of producing a change that evaporates.
# Checked here rather than at the top so that the common case - nothing to do,
# Handy running happily - never has to spawn a Windows process at all.
#
# Capture the output and match it afterwards rather than piping into `grep -q`:
# under `set -o pipefail` grep exits at the first hit, tasklist.exe takes
# SIGPIPE, and its 141 becomes the pipeline's status - so a running Handy would
# read as "not running", which is the wrong way round to be wrong.
TASKLIST=/mnt/c/Windows/System32/tasklist.exe
RUNNING=""
if [ -x "$TASKLIST" ]; then
  RUNNING="$(cd /mnt/c && "$TASKLIST" /FI "IMAGENAME eq handy.exe" /NH 2>/dev/null || true)"
fi
case "$RUNNING" in *[Hh]andy.exe*)
  note "Handy is running, and would write its own settings back over ours at exit."
  note "Quit Handy from the tray icon and re-run: scripts/seed-handy-settings.sh"
  note "(wanted to set$CHANGES)"
  exit 0
  ;;
esac

# --- write -------------------------------------------------------------------
# Never in place: a crash mid-write would leave Handy with a truncated store.
# The temp file goes in the same directory so the rename is atomic, and on
# /mnt/c that means it never crosses a filesystem either.
BACKUP="$SETTINGS.backup-$(date +%Y%m%d%H%M%S)"
[ -f "$SETTINGS" ] && cp "$SETTINGS" "$BACKUP"

TMP="$(mktemp "$HANDY_DIR/settings_store.json.seed.XXXXXX")"
trap 'rm -f "$TMP"' EXIT
printf '%s\n' "$UPDATED" > "$TMP"
mv "$TMP" "$SETTINGS"
trap - EXIT

note "set$CHANGES in $SETTINGS"
[ -f "$BACKUP" ] && note "previous settings kept at $BACKUP"
exit 0
