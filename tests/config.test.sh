#!/usr/bin/env bash
# Static invariants of the WSL2 config that are easy to break by hand and
# expensive to notice later.
#
# Coverage:
# - host label agrees across flake.nix, rebuild.sh and bootstrap.sh (the
#   "three places have to match" trap the README warns about);
# - the username in flake.nix is threaded, not duplicated per file;
# - every mkOutOfStoreSymlink source in home.nix actually exists in the repo;
# - npm's global prefix is declared, and agrees with the PATH entries;
# - Claude's settings.json is left unmanaged and seeded by a copy instead;
# - no macOS-only leftovers survived the translation;
# - the herdr pin is a real SRI hash against the official Linux artifact.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# --- host label consistency ---------------------------------------------------

# The label is referenced several times in flake.nix (definition, packages,
# checks); what matters is that they are all the same label.
flake_hosts=$(grep -oE 'homeConfigurations\."[^"]+"' "$ROOT/flake.nix" \
  | sed -E 's/.*"([^"]+)"/\1/' | sort -u)
[ "$(printf '%s\n' "$flake_hosts" | wc -l)" -eq 1 ] \
  || fail "flake.nix references more than one host label: $(tr '\n' ' ' <<<"$flake_hosts")"
HOST=$flake_hosts

grep -q "#${HOST}\$" "$ROOT/rebuild.sh" \
  || fail "rebuild.sh does not target the flake host label \"$HOST\""
grep -qE "^HOST=${HOST}([[:space:]]|#|$)" "$ROOT/bootstrap.sh" \
  || fail "bootstrap.sh HOST does not match the flake host label \"$HOST\""
pass "host label \"$HOST\" agrees across flake.nix, rebuild.sh and bootstrap.sh"

# --- username is declared once ------------------------------------------------

user_lines=$(grep -cE '^[[:space:]]*user = "[^"]+";' "$ROOT/flake.nix")
[ "$user_lines" -eq 1 ] || fail "flake.nix should declare \"user\" exactly once, found $user_lines"

USER_NAME=$(sed -nE 's/^[[:space:]]*user = "([^"]+)";.*/\1/p' "$ROOT/flake.nix" | head -n1)
[ -n "$USER_NAME" ] || fail "could not read the user from flake.nix"

# home.nix must derive the home directory from that variable, never hardcode it.
# The ${user} here is a Nix interpolation in home.nix, not a shell one.
# shellcheck disable=SC2016
grep -q 'home.homeDirectory = "/home/''${user}"' "$ROOT/home.nix" \
  || fail "home.nix should derive homeDirectory from the threaded \$user"
assert_not_contains "$(cat "$ROOT/home.nix")" "/home/$USER_NAME" \
  "home.nix hardcodes /home/$USER_NAME instead of using \$user"
pass "username \"$USER_NAME\" is declared once and threaded through"

# --- npm's global prefix ------------------------------------------------------

# home.sessionPath and the zsh PATH both put ~/.npm-global/bin on PATH, and
# firstmate installs several tools with `npm install -g`. If npm's prefix is not
# declared to match, those installs write into the read-only Nix store copy of
# nodejs and fail. It used to be a hand-written ~/.npmrc, owned by nothing.
grep -q 'home.file.".npmrc"' "$ROOT/home.nix" \
  || fail "home.nix does not declare ~/.npmrc; npm's global prefix would be unmanaged"
# shellcheck disable=SC2016  # ${config...} is a Nix interpolation, not a shell one
grep -q 'prefix=''${config.home.homeDirectory}/.npm-global' "$ROOT/home.nix" \
  || fail "the npm prefix must be derived from config.home.homeDirectory"
# shellcheck disable=SC2016  # $HOME here is literal text inside home.sessionPath
grep -q '"\$HOME/.npm-global/bin"' "$ROOT/home.nix" \
  || fail "home.sessionPath no longer matches the declared npm prefix"
pass "npm's global prefix is declared and agrees with the ~/.npm-global/bin on PATH"

# --- every symlink source exists ----------------------------------------------

missing=0
while IFS= read -r target; do
  rel=${target#\$\{dotfiles\}/}
  if [ ! -e "$ROOT/$rel" ]; then
    printf 'not ok - home.nix links a missing path: %s\n' "$rel" >&2
    missing=1
  fi
done < <(grep -oE 'mkOutOfStoreSymlink "\$\{dotfiles\}/[^"]+"' "$ROOT/home.nix" \
         | sed -E 's/.*mkOutOfStoreSymlink "(.*)"/\1/')
[ "$missing" -eq 0 ] || exit 1
pass "every mkOutOfStoreSymlink source in home.nix exists in the repo"

# --- ~/.claude/settings.json is Claude's, not Home Manager's -------------------

# Claude Code rewrites this file itself, by writing a temp file next to the
# *first* symlink hop and renaming it into place. Any home.file entry for the
# path makes that first hop a read-only /nix/store directory, so every settings
# change Claude makes fails with EACCES - mkOutOfStoreSymlink included. The repo
# copy is a first-install seed that bootstrap.sh copies, and nothing more.
grep -q 'home.file.".claude/settings.json"' "$ROOT/home.nix" \
  && fail "home.nix must not manage .claude/settings.json; Claude cannot write through the store symlink"
[ -r "$ROOT/home/.claude/settings.json" ] \
  || fail "home/.claude/settings.json is missing; bootstrap.sh has no seed to copy"
# shellcheck disable=SC2016  # this is bootstrap.sh's literal source text, not an expansion
grep -q 'cp "$CLAUDE_SEED" "$CLAUDE_LIVE"' "$ROOT/bootstrap.sh" \
  || fail "bootstrap.sh no longer copies the Claude settings seed into place"
pass "Claude's settings.json is seeded by a copy, not managed by Home Manager"

# --- the translation is complete ----------------------------------------------

for leftover in darwinConfigurations nix-darwin homebrew system.defaults /Users/; do
  for f in "$ROOT/flake.nix" "$ROOT/home.nix" "$ROOT/wsl.nix"; do
    # Comments explain what these were on macOS; only real code should be clean.
    if sed -E 's/#.*//' "$f" | grep -q -- "$leftover"; then
      fail "$(basename "$f") still contains macOS-only setting: $leftover"
    fi
  done
done
pass "no macOS-only settings survive outside explanatory comments"

# --- herdr pin ----------------------------------------------------------------

grep -q 'herdr-linux-x86_64' "$ROOT/pkgs/herdr.nix" \
  || fail "pkgs/herdr.nix should pin the official Linux x86_64 release artifact"
grep -qE 'hash = "sha256-[A-Za-z0-9+/]{43}=";' "$ROOT/pkgs/herdr.nix" \
  || fail "pkgs/herdr.nix should pin a full SRI sha256 hash"
grep -q 'platforms = \[ "x86_64-linux" \]' "$ROOT/pkgs/herdr.nix" \
  || fail "pkgs/herdr.nix should declare its platform"
pass "herdr is pinned to the official Linux artifact by SRI hash"
