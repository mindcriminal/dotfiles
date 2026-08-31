#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ln -sfn "$DIR" ~/.dotfiles
# No sudo: this is a standalone Home Manager config and owns only this user's
# environment, unlike the video's darwin-rebuild which writes system state.
home-manager switch -b backup --flake ~/.dotfiles#wsl

# Handy's settings_store.json, on the Windows side, for the same reason: Handy
# rewrites it itself, so this repo seeds it rather than owning it. Nothing
# forces this one to run after the switch - Home Manager has never owned a path
# over there - but the two seeds belong together. Silent no-op when Handy is
# not installed or Windows is unreachable.
"$DIR/scripts/seed-handy-settings.sh"
