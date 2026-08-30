#!/usr/bin/env bash
# bootstrap.sh step 6 puts firstmate on the machine and asks it to install its
# own agent tooling. The interesting part is the parse: firstmate prints one
# line per problem, and only some of those lines name a tool that may be passed
# to `fm-bootstrap.sh install`.
#
# Coverage:
# - the step is self-contained enough to run on its own, between its markers;
# - nothing missing is a clean no-op, not an error;
# - an absent firstmate is cloned over HTTPS to the documented default path;
# - an already-present firstmate is left completely alone;
# - `MISSING:` lines yield exactly the tool names, and `MISSING_MANUAL:` and
#   every other diagnostic line are excluded - checked against recorded real
#   fm-bootstrap.sh output, see tests/fixtures/README.md;
# - the install is gated behind one consent prompt, and declining installs
#   nothing;
# - this repo does not re-list the tools firstmate owns.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

FIXTURES="$ROOT/tests/fixtures"
CLEAN="$FIXTURES/fm-bootstrap-detect-clean.txt"
MISSING="$FIXTURES/fm-bootstrap-detect-missing.txt"

# --- the step, extracted ------------------------------------------------------

STEP=$(awk '/^# BEGIN firstmate step/,/^# END firstmate step/' "$ROOT/bootstrap.sh")
[ -n "$STEP" ] || fail "bootstrap.sh has no BEGIN/END firstmate step markers"
assert_contains "$STEP" "# END firstmate step" \
  "the firstmate step's END marker is missing; extraction would run to EOF"
pass "the firstmate step can be extracted from bootstrap.sh on its own"

# The step must ask firstmate what is missing in the read-only mode. Without the
# flag that same run performs firstmate's mutating startup sweeps.
assert_contains "$STEP" 'FM_BOOTSTRAP_DETECT_ONLY=1' \
  "the detect run must set FM_BOOTSTRAP_DETECT_ONLY=1, or it mutates firstmate's state"
assert_contains "$STEP" 'https://github.com/kunchenguid/firstmate' \
  "the clone source must be the public HTTPS URL, which works before any SSH key exists"
assert_not_contains "$STEP" "git@github.com" \
  "SSH clone would fail on a fresh machine that has no key on GitHub yet"
for mutation in "git pull" "git -C \"\$FIRSTMATE_DIR\"" "git reset" "git clean"; do
  assert_not_contains "$STEP" "$mutation" \
    "the step must never $mutation an existing firstmate checkout"
done
pass "the step detects read-only, clones over HTTPS, and never updates an existing clone"

# --- harness ------------------------------------------------------------------

# Runs the extracted step against a fake firstmate that replays a recorded
# report. Answers the consent prompt with $2 ("y" or "n").
#
# Sets, in the sandbox it creates:
#   $SANDBOX  - the fake $HOME
#   $OUT      - everything the step printed
#   $STATUS   - the step's exit status
#   $INSTALLED - one line per tool actually passed to `fm-bootstrap.sh install`
#   $CLONED   - the URL `git clone` was called with, if at all
run_step() {  # run_step <report-file|-> <answer> [preinstall|absent]
  local report=$1 answer=$2 mode=${3:-preinstall}
  SANDBOX=$(dotfiles_test_tmproot dotfiles-firstmate)
  local fmdir="$SANDBOX/github/mindcriminal/firstmate"
  local stubs="$SANDBOX/stubs"
  mkdir -p "$stubs"

  # The fake firstmate. It refuses a detect run that forgot the read-only flag,
  # so the test cannot pass by accident, and it records install arguments
  # verbatim rather than running anything.
  cat > "$SANDBOX/fm-bootstrap.sh" <<'FAKE'
#!/usr/bin/env bash
if [ "${1:-}" = install ]; then
  shift
  printf '%s\n' "$@" > "$FM_FAKE_INSTALL_LOG"
  exit 0
fi
if [ "${FM_BOOTSTRAP_DETECT_ONLY:-0}" != 1 ]; then
  echo "fake firstmate: detect run without FM_BOOTSTRAP_DETECT_ONLY=1" >&2
  exit 3
fi
cat "$FM_FAKE_REPORT"
FAKE
  chmod +x "$SANDBOX/fm-bootstrap.sh"

  if [ "$mode" = preinstall ]; then
    mkdir -p "$fmdir/bin"
    cp "$SANDBOX/fm-bootstrap.sh" "$fmdir/bin/fm-bootstrap.sh"
    # A file the step must not disturb, standing in for firstmate's private state.
    printf 'private\n' > "$fmdir/state-marker"
  else
    # `git clone` must be what creates it, so stub git and watch for the call.
    cat > "$stubs/git" <<STUB
#!/usr/bin/env bash
if [ "\$1" = clone ]; then
  printf '%s\n' "\$2" > "$SANDBOX/cloned"
  mkdir -p "\$3/bin"
  cp "$SANDBOX/fm-bootstrap.sh" "\$3/bin/fm-bootstrap.sh"
  exit 0
fi
exit 1
STUB
    chmod +x "$stubs/git"
  fi

  rm -f "$SANDBOX/installed" "$SANDBOX/cloned"
  OUT=$(
    HOME="$SANDBOX" PATH="$stubs:$PATH" \
    FM_FAKE_REPORT="$report" FM_FAKE_INSTALL_LOG="$SANDBOX/installed" \
    ASK_ANSWER="$answer" \
    bash -s 2>&1 <<PRELUDE
set -euo pipefail
# Stands in for bootstrap.sh's own ask(): the step may only reach outside this
# repo through it, and these tests need to drive both answers.
ask() { printf 'ASKED: %s\n' "\$1"; [ "\${ASK_ANSWER:-n}" = y ]; }
$STEP
PRELUDE
  )
  STATUS=$?
  INSTALLED=$(cat "$SANDBOX/installed" 2>/dev/null || true)
  CLONED=$(cat "$SANDBOX/cloned" 2>/dev/null || true)
}

# --- nothing missing ----------------------------------------------------------

run_step "$CLEAN" n preinstall
[ "$STATUS" -eq 0 ] || fail "a machine with nothing missing must not fail the step (exit $STATUS)"
assert_contains "$OUT" "already present" "an existing firstmate should be reported as present"
assert_contains "$OUT" "already installed" "nothing missing should say so"
assert_not_contains "$OUT" "ASKED:" "nothing to do must not prompt for consent"
[ -z "$INSTALLED" ] || fail "nothing was missing, but install ran with: $INSTALLED"
[ -f "$SANDBOX/github/mindcriminal/firstmate/state-marker" ] \
  || fail "the step disturbed the existing firstmate checkout"
pass "nothing missing is a clean, silent, promptless no-op"

# The NOTICE line in that fixture is the point: a non-tool diagnostic must not
# be mistaken for something to install.
assert_contains "$(cat "$CLEAN")" "NOTICE:" \
  "the clean fixture no longer carries a non-tool diagnostic line to ignore"

# --- some tools missing -------------------------------------------------------

run_step "$MISSING" y preinstall
[ "$STATUS" -eq 0 ] || fail "installing missing tools failed (exit $STATUS)"

# Exactly the MISSING: names, in order, and nothing else. Derived from the
# fixture rather than typed out, so the two cannot drift.
want=$(sed -nE 's/^MISSING: ([^[:space:]]+).*/\1/p' "$MISSING")
[ "$INSTALLED" = "$want" ] \
  || fail "install got:$(printf '\n  %s' "$INSTALLED")$(printf '\nwanted:')$(printf '\n  %s' "$want")"
pass "the parse passes exactly the MISSING: tool names to firstmate ($(echo "$want" | wc -l) of them)"

# The three exclusions, stated against the real fixture.
assert_contains "$(cat "$MISSING")" "MISSING_MANUAL: cursor-agent" \
  "the fixture no longer contains a MISSING_MANUAL: line to exclude"
assert_not_contains "$INSTALLED" "cursor-agent" \
  "MISSING_MANUAL: tools must never reach install; that call fails by design"
assert_not_contains "$INSTALLED" "MISSING" \
  "a whole report line leaked into the install arguments instead of a tool name"
assert_not_contains "$INSTALLED" "npm" \
  "the install COMMAND leaked into the arguments; only the tool name is wanted"
assert_contains "$OUT" "cursor-agent" \
  "MISSING_MANUAL: tools must still be printed for a human to handle"
pass "MISSING_MANUAL: is reported to the human and kept out of the install"

# --- consent ------------------------------------------------------------------

run_step "$MISSING" n preinstall
[ "$STATUS" -eq 0 ] || fail "declining the install must not fail the step (exit $STATUS)"
assert_contains "$OUT" "ASKED:" "the install must be gated behind a consent prompt"
[ -z "$INSTALLED" ] || fail "consent was declined, but install ran with: $INSTALLED"
# What is about to be installed has to be on screen before the question.
asked_line=$(printf '%s\n' "$OUT" | grep -n 'ASKED:' | head -1 | cut -d: -f1)
tool_line=$(printf '%s\n' "$OUT" | grep -n 'treehouse' | head -1 | cut -d: -f1)
[ -n "$tool_line" ] && [ "$tool_line" -lt "$asked_line" ] \
  || fail "the consent prompt must come after the list of what would be installed"
pass "the install is gated behind one prompt that first shows what it would install"

# --- firstmate absent ---------------------------------------------------------

run_step "$MISSING" y absent
[ "$STATUS" -eq 0 ] || fail "the fresh-machine path failed (exit $STATUS)"
[ "$CLONED" = "https://github.com/kunchenguid/firstmate" ] \
  || fail "cloned from \"${CLONED:-nothing}\", expected the public HTTPS URL"
[ "$INSTALLED" = "$want" ] \
  || fail "after cloning, install got \"$INSTALLED\", expected the same tool list"
[ "$(printf '%s\n' "$OUT" | grep -c 'ASKED:')" -eq 1 ] \
  || fail "cloning and installing must be covered by ONE consent prompt"
pass "an absent firstmate is cloned and its tooling installed, behind one prompt"

run_step "$MISSING" n absent
[ "$STATUS" -eq 0 ] || fail "declining the clone must not fail the step (exit $STATUS)"
[ -z "$CLONED" ] || fail "consent was declined, but the clone ran"
[ ! -d "$SANDBOX/github/mindcriminal/firstmate" ] \
  || fail "consent was declined, but firstmate was created anyway"
pass "declining leaves the machine untouched and the run alive"

# --- firstmate owns the tool list, not this repo -------------------------------

# The whole design: firstmate's bin/fm-bootstrap.sh owns which tools exist and
# what versions they must be. A copy here would rot the first time it changes.
for tool in treehouse no-mistakes gh-axi chrome-devtools-axi lavish-axi tasks-axi quota-axi; do
  assert_not_contains "$STEP" "$tool" \
    "bootstrap.sh names \"$tool\"; that list belongs to firstmate, not this repo"
done
pass "bootstrap.sh names none of the tools firstmate owns"
