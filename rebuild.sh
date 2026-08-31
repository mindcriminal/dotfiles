#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ln -sfn "$DIR" ~/.dotfiles
# No sudo: this is a standalone Home Manager config and owns only this user's
# environment, unlike the video's darwin-rebuild which writes system state.
home-manager switch -b backup --flake ~/.dotfiles#wsl

# After the switch, never before it. ~/.claude/settings.json is deliberately not
# managed by home.nix (Claude rewrites it itself and cannot write through a link
# into the store), and activation deletes the symlink a pre-change generation
# owned - so on the first rebuild after that change this is what puts a real
# file back. It never overwrites one that is already there.
"$DIR/scripts/seed-claude-settings.sh"

# Handy's settings_store.json, on the Windows side, for the same reason: Handy
# rewrites it itself, so this repo seeds it rather than owning it. Nothing
# forces this one to run after the switch - Home Manager has never owned a path
# over there - but the two seeds belong together. Silent no-op when Handy is
# not installed or Windows is unreachable.
"$DIR/scripts/seed-handy-settings.sh"
