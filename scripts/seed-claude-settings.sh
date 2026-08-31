#!/usr/bin/env bash
# Seed ~/.claude/settings.json from this repo, once, by copying.
#
# This is the one config here that Home Manager must not own. Claude Code
# rewrites the file itself whenever you change a model, an effort level or the
# theme, and it does so by writing settings.json.tmp.<pid>.<hash> next to the
# *first* symlink hop before renaming it into place. While home.nix managed the
# path that first hop was the root-owned, read-only /nix/store copy, so every
# such write died with EACCES. mkOutOfStoreSymlink does not help: the temp file
# lands beside the first hop, never beside the out-of-store target.
#
# So the repo's copy is a first-install seed and nothing more. After it lands,
# the live file is Claude's: it collects your settings and herdr's hooks block,
# and it is expected to drift from the seed. Never clobber a real file here.
#
# Run by bootstrap.sh and by rebuild.sh, always AFTER the switch. That ordering
# matters on a machine set up before this file existed: Home Manager deletes the
# symlink it owned in the previous generation as part of activation, so running
# this first would find the stale link, replace it, and watch the switch delete
# the copy again. A bare `home-manager switch` skips this script entirely -
# use ./rebuild.sh, which is what the README tells you to use anyway.
#
#   scripts/seed-claude-settings.sh
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SEED="$DIR/home/.claude/settings.json"
LIVE="$HOME/.claude/settings.json"

if [ -f "$LIVE" ] && [ ! -L "$LIVE" ]; then
  echo "    $LIVE already exists and is yours to keep, leaving it alone"
  exit 0
fi

if [ ! -r "$SEED" ]; then
  echo "    $SEED is missing, skipping"
  exit 0
fi

# A symlink here is the leftover from when home.nix managed this path, on a
# machine that has not switched since. It points into the store (or at the
# repo), and Claude cannot write through it.
if [ -L "$LIVE" ]; then
  echo "    replacing the stale symlink left by an older generation"
  rm -f "$LIVE"
fi

mkdir -p "$(dirname "$LIVE")"
cp "$SEED" "$LIVE"
chmod u+w "$LIVE"
echo "    seeded from home/.claude/settings.json (yours to edit from now on)"
