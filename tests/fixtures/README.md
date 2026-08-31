# Recorded fixtures

These are verbatim captures of real `bin/fm-bootstrap.sh` output, not
hand-written samples. `tests/firstmate.test.sh` replays them so bootstrap's
step 7 can be proven against firstmate's real line format without a fresh
machine and without a network install.

Both were recorded with firstmate's own read-only detect mode:

    FM_BOOTSTRAP_DETECT_ONLY=1 <firstmate>/bin/fm-bootstrap.sh

- `fm-bootstrap-detect-clean.txt` - a machine with everything installed. Not
  empty: firstmate still prints an unrelated `NOTICE:` line, which is exactly
  the kind of non-tool diagnostic the parse has to ignore.
- `fm-bootstrap-detect-missing.txt` - the same command with the tool
  directories taken off `PATH` and a `cursor` crew harness configured, so the
  run reports every `MISSING:` tool plus a `MISSING_MANUAL:` line.

To re-record, run the command above and paste its output in whole. Do not edit
these files by hand: their value is that firstmate wrote them.

## handy-settings-store.json

A verbatim `%APPDATA%\com.pais.handy\settings_store.json` as Handy 0.9.6 wrote
it on this machine, captured before `paste_method` was changed to `direct`.
`tests/handy.test.sh` seeds it to prove the merge handles Handy's real shape -
174 lines of nested objects and arrays - and touches nothing but the keys it
declares. It holds no secrets: every `post_process_api_keys` entry is empty.

Same rule as the others: re-record it, never edit it by hand.
