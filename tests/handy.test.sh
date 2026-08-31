#!/usr/bin/env bash
# Handy is the second Windows-side app this repo depends on, and the second
# config file an application rewrites out from under Home Manager. Both of
# those have already cost this repo a bug, so both are pinned down here.
#
# Coverage:
# - the seed table declares all three keys, with Handy's real Windows defaults;
# - the comment explaining why paste_method is "direct" survives, because that
#   value looks like an arbitrary preference and is not one;
# - seeding a real Handy store sets paste_method and touches nothing else;
# - a value you chose yourself is never overwritten;
# - an absent or empty store still produces all three keys;
# - a store that is not valid JSON is refused, not rewritten;
# - the seeder exits 0 with a message, never an error, when Windows is
#   unreachable - a switch on a machine without Handy must not fail;
# - bootstrap.sh and rebuild.sh both run it, after the switch, and bootstrap
#   tells you how to install Handy;
# - tests/verify.sh reports Handy's absence instead of passing silently;
# - home.nix does not manage the settings file.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SEEDER="$ROOT/scripts/seed-handy-settings.sh"
FIXTURE="$ROOT/tests/fixtures/handy-settings-store.json"

[ -x "$SEEDER" ] || fail "scripts/seed-handy-settings.sh is missing or not executable"

command -v jq >/dev/null 2>&1 || fail "these tests need jq, which home.nix installs"

# --- the seed table -----------------------------------------------------------

# Handy 0.9.6, src-tauri/src/settings.rs: PasteMethod::default() is CtrlV
# everywhere but Linux, default_autostart_enabled() is false, and
# get_default_settings() leaves selected_model empty. If Handy ever changes one
# of these, the seeder would start treating a stale default as "your choice"
# and quietly stop applying - so the defaults are asserted, not just used.
for entry in 'paste_method|"ctrl_v"|"direct"' \
             'selected_model|""|"turbo"' \
             'autostart_enabled|false|true'; do
  assert_contains "$(cat "$SEEDER")" "$entry" \
    "the seed table no longer declares $entry"
done
pass "all three settings are declared with Handy's Windows defaults"

# The one setting here that is not a preference. Losing this comment is how it
# gets tidied back to the default by someone who reads it as one.
for phrase in "WezTerm" "clipboard" "#502"; do
  assert_contains "$(cat "$SEEDER")" "$phrase" \
    "the seeder no longer explains the $phrase half of why paste_method is direct"
done
pass "the seeder still explains why paste_method must be \"direct\""

# --- seeding a real store -----------------------------------------------------

[ -r "$FIXTURE" ] || fail "tests/fixtures/handy-settings-store.json is missing"

# Seed through the real script, not a reimplementation of the merge rules, so
# the test and the code cannot drift apart.
seeded=$("$SEEDER" --apply "$FIXTURE" 2>/dev/null) || fail "--apply failed on the recorded store"

[ "$(jq -r '.settings.paste_method' <<<"$seeded")" = "direct" ] \
  || fail "seeding a default store did not set paste_method to direct"
pass "seeding Handy's own store sets paste_method to \"direct\""

# Everything the seeder does not declare has to survive untouched - the store
# is 174 lines of nested objects and arrays, and the rest of it is Handy's.
before=$(jq -S 'del(.settings.paste_method, .settings.selected_model, .settings.autostart_enabled)' "$FIXTURE")
after=$(jq -S 'del(.settings.paste_method, .settings.selected_model, .settings.autostart_enabled)' <<<"$seeded")
[ "$before" = "$after" ] || fail "seeding changed keys outside the three it declares"
pass "every other key in the store survives seeding byte-for-byte"

# --- your own choices are yours -----------------------------------------------

TMP_ROOT=$(dotfiles_test_tmproot handy)

MINE="$TMP_ROOT/mine.json"
cat > "$MINE" <<'JSON'
{"settings":{"paste_method":"shift_insert","selected_model":"parakeet-tdt-0.6b-v3","autostart_enabled":false}}
JSON
mine_seeded=$("$SEEDER" --apply "$MINE" 2>/dev/null) || fail "--apply failed on a customised store"
[ "$(jq -r '.settings.paste_method' <<<"$mine_seeded")" = "shift_insert" ] \
  || fail "the seeder overwrote a paste_method the user chose"
[ "$(jq -r '.settings.selected_model' <<<"$mine_seeded")" = "parakeet-tdt-0.6b-v3" ] \
  || fail "the seeder overwrote a selected_model the user chose"
# autostart_enabled false IS Handy's default, so this one is still ours to set:
# "left alone" means "not at the default", not "present in the file".
[ "$(jq -r '.settings.autostart_enabled' <<<"$mine_seeded")" = "true" ] \
  || fail "the seeder skipped a key that was still at Handy's default"
pass "a setting you chose is left alone; one still at its default is seeded"

# --- an empty store -----------------------------------------------------------

# Handy's AppSettings carries a container-level #[serde(default)], so a store
# holding only these three keys loads and every absent key falls back. That is
# what makes seeding a not-yet-run Handy safe.
EMPTY="$TMP_ROOT/empty.json"
printf '{}\n' > "$EMPTY"
empty_seeded=$("$SEEDER" --apply "$EMPTY" 2>/dev/null) || fail "--apply failed on an empty store"
[ "$(jq -r '[.settings.paste_method, .settings.selected_model, .settings.autostart_enabled] | join(",")' <<<"$empty_seeded")" \
  = "direct,turbo,true" ] || fail "seeding an empty store did not produce all three settings"
pass "an empty store is seeded with all three settings"

# --- garbage is never rewritten -----------------------------------------------

BROKEN="$TMP_ROOT/broken.json"
printf 'not json at all\n' > "$BROKEN"
if broken_out=$("$SEEDER" --apply "$BROKEN" 2>/dev/null); then
  fail "--apply accepted a store that is not valid JSON: $broken_out"
fi
pass "a store that is not valid JSON is refused rather than rewritten"

# --- degrades gracefully when Windows is unreachable --------------------------

# Same shape as the WezTerm installer's test: a PATH with only the tools the
# seeder needs before its wslpath check, and no wslpath. A switch on a machine
# with interop off, or in a container, must not fail because of this script.
FAKE_BIN="$TMP_ROOT/bin"
mkdir -p "$FAKE_BIN"
# bash too: the `#!/usr/bin/env bash` shebang resolves the interpreter itself
# through PATH.
for tool in bash dirname; do
  ln -s "$(command -v "$tool")" "$FAKE_BIN/$tool"
done
[ ! -e "$FAKE_BIN/wslpath" ] || fail "the fake PATH must not provide wslpath"

out=$(PATH="$FAKE_BIN" "$SEEDER" 2>&1) && rc=0 || rc=$?
[ "${rc:-0}" -eq 0 ] || fail "the seeder exited $rc with Windows unreachable; it must no-op"
assert_contains "$out" "skipped" "the seeder did not explain why it no-opped"
assert_contains "$out" "not running under WSL" "the seeder gave the wrong reason: $out"
pass "the seeder no-ops with a message when Windows is unreachable"

# --- wired into both entry points ---------------------------------------------

REL=scripts/seed-handy-settings.sh
for caller in bootstrap.sh rebuild.sh; do
  grep -q "$REL" "$ROOT/$caller" \
    || fail "$caller does not run $REL; a fresh machine would get Handy's defaults"
done
# Run after the switch, next to seed-claude-settings.sh. Nothing forces this
# one to come after - Home Manager has never owned a path on the Windows side -
# but keeping the two seeds together is the point.
switch_line=$(grep -n 'home-manager switch' "$ROOT/rebuild.sh" | tail -n1 | cut -d: -f1)
seed_line=$(grep -n "$REL" "$ROOT/rebuild.sh" | tail -n1 | cut -d: -f1)
[ "$seed_line" -gt "$switch_line" ] \
  || fail "rebuild.sh should run $REL after the switch, with the other seed"
pass "both bootstrap.sh and rebuild.sh run the seeder after the switch"

# --- installing Handy is a documented manual step ------------------------------

# The convention for a Windows-side app in this repo is not to automate the
# install: bootstrap prints the winget line, and verify.sh hands it back.
WINGET="winget install cjpais.Handy"
assert_contains "$(cat "$ROOT/bootstrap.sh")" "$WINGET" \
  "bootstrap.sh never tells you to install Handy"
assert_contains "$(cat "$ROOT/tests/verify.sh")" "$WINGET" \
  "verify.sh does not hand back the command to install Handy"
assert_contains "$(cat "$ROOT/README.md")" "$WINGET" \
  "the README does not list Handy as a Windows prerequisite"
pass "installing Handy is documented as a manual winget step in all three places"

# --- Home Manager must not own the settings file -------------------------------

# Exactly the ~/.claude/settings.json lesson: Handy rewrites this file itself,
# on every settings change and again at shutdown.
grep -q 'com.pais.handy' "$ROOT/home.nix" \
  && fail "home.nix must not manage Handy's settings; Handy rewrites the file itself"
pass "home.nix leaves Handy's settings_store.json alone"
