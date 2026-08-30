#!/usr/bin/env bash
# Run every *.test.sh in this directory. Each file prints TAP-ish "ok -" lines
# and exits non-zero on the first failure.
#
#   ./tests/run.sh              # skips the checks that need lua/shellcheck
#   nix develop -c ./tests/run.sh   # runs all of them
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
failed=0

for t in "$DIR"/*.test.sh; do
  printf '\n# %s\n' "$(basename "$t")"
  if ! "$t"; then
    failed=$((failed + 1))
  fi
done

printf '\n'
if [ "$failed" -ne 0 ]; then
  printf '%d test file(s) failed\n' "$failed" >&2
  exit 1
fi
printf 'all test files passed\n'
