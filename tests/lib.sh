#!/usr/bin/env bash
# tests/lib.sh - shared primitives for dotfiles behavior tests.
#
# Source this from a test file:
#   # shellcheck source=tests/lib.sh
#   . "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
#
# ROOT is exported as the repository root (this file lives in tests/).

if [ -n "${DOTFILES_TEST_LIB_SOURCED:-}" ]; then
  return 0
fi
DOTFILES_TEST_LIB_SOURCED=1

# shellcheck disable=SC2034
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'ok - %s\n' "$1"
}

# --- self-cleaning temp root -------------------------------------------------

# dotfiles_test_tmproot is called as TMP_ROOT=$(dotfiles_test_tmproot ...), so
# its body runs in a command-substitution subshell. That breaks the two obvious
# implementations, in opposite directions:
#
#   * registering the EXIT trap inside the helper registers it in the subshell,
#     which fires it the moment the substitution ends and deletes the directory
#     before the caller ever sees it;
#   * recording the directory in a shell array records it in the subshell, so
#     the parent's array stays empty and nothing is ever cleaned up.
#
# So the trap is registered once here, in the sourcing shell, and the list of
# directories lives in a file, which is the one channel that crosses a subshell
# boundary. $$ is identical in a subshell and cannot guard the trap; $BASHPID
# is not, so it can.

DOTFILES_TEST_MAIN_BASHPID=$BASHPID
DOTFILES_TEST_REGISTRY=$(mktemp "${TMPDIR:-/tmp}/dotfiles-test-registry.XXXXXX")

dotfiles_test_cleanup() {
  local d
  [ "$BASHPID" = "$DOTFILES_TEST_MAIN_BASHPID" ] || return 0
  [ -f "$DOTFILES_TEST_REGISTRY" ] || return 0
  while IFS= read -r d; do
    [ -n "$d" ] && rm -rf "$d"
  done < "$DOTFILES_TEST_REGISTRY"
  rm -f "$DOTFILES_TEST_REGISTRY"
}

dotfiles_test_tmproot() {
  local prefix=${1:-dotfiles-test} root
  root=$(mktemp -d "${TMPDIR:-/tmp}/${prefix}.XXXXXX")
  printf '%s\n' "$root" >> "$DOTFILES_TEST_REGISTRY"
  printf '%s\n' "$root"
}

# --- assertions ---------------------------------------------------------------

assert_contains() {
  local haystack=$1 needle=$2 message=$3
  case "$haystack" in
    *"$needle"*) : ;;
    *) fail "$message" ;;
  esac
}

assert_not_contains() {
  local haystack=$1 needle=$2 message=$3
  case "$haystack" in
    *"$needle"*) fail "$message" ;;
    *) : ;;
  esac
}

# --- deterministic git fixtures ------------------------------------------------

dotfiles_git_init_commit() {
  local dir=$1
  mkdir -p "$dir"
  git -C "$dir" init -q
  printf '# %s\n' "$(basename "$dir")" > "$dir/README.md"
  git -C "$dir" add README.md
  git -C "$dir" -c user.name=dotfiles-test -c user.email=dotfiles-test@example.invalid \
    commit -qm "fixture"
}

# Registered here, in the shell that sources this file, rather than lazily
# inside the helper - see the $BASHPID note above.
trap dotfiles_test_cleanup EXIT
