#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ln -sfn "$DIR" ~/.dotfiles
# No sudo: this is a standalone Home Manager config and owns only this user's
# environment, unlike the video's darwin-rebuild which writes system state.
exec home-manager switch -b backup --flake ~/.dotfiles#wsl
