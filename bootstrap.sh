#!/usr/bin/env bash
# Takes a fresh WSL2 Rocky Linux install from nothing to a built Home Manager
# config. Run this once. After it finishes, use ./rebuild.sh for every change.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOST=wsl                 # the flake host label; must match rebuild.sh
HM_REF="github:nix-community/home-manager/release-26.05"

ask() {  # ask "prompt" -> 0 on yes
  local reply
  read -r -p "    $1 [y/N] " reply
  [ "$reply" = "y" ] || [ "$reply" = "Y" ]
}

echo "==> Step 0: sanity checks"
if ! grep -qi microsoft /proc/version 2>/dev/null; then
  echo "    This repo is the WSL2 translation of a macOS setup, and it is not"
  echo "    running under WSL. Continuing anyway, but the Windows-side steps"
  echo "    (WezTerm, /etc/wsl.conf) will no-op."
fi
# shellcheck disable=SC1091  # /etc/os-release is a host file, not repo source
echo "    $(. /etc/os-release && echo "$PRETTY_NAME") on $(uname -m)"

echo "==> Step 1: Determinate Nix"
if command -v nix >/dev/null 2>&1; then
  echo "    nix already installed, skipping ($(nix --version))"
else
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
    | sh -s -- install --no-confirm
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

echo "==> Step 2: symlink this repo to ~/.dotfiles"
# home.nix resolves its mkOutOfStoreSymlink paths through ~/.dotfiles, so this
# has to exist before the first switch or the build will fail to find them.
ln -sfn "$DIR" ~/.dotfiles

echo "==> Step 3: personalize the configured username"
REAL_USER="$(whoami)"
FLAKE_USER="$(sed -nE 's/^[[:space:]]*user = "([^"]+)";.*/\1/p' "$DIR/flake.nix" | head -n1)"
if [ -z "$FLAKE_USER" ]; then
  echo "    Could not find the single \"user = \" line in flake.nix."
  echo "    Edit flake.nix yourself before continuing."
  exit 1
elif [ "$FLAKE_USER" != "$REAL_USER" ]; then
  echo "    flake.nix is configured for user \"$FLAKE_USER\", but you are \"$REAL_USER\"."
  if ask "Rewrite flake.nix's \"user = \" line to \"$REAL_USER\"?"; then
    # GNU sed: -i takes no argument, unlike the BSD sed the macOS version uses.
    sed -i -E "s/^([[:space:]]*user = \")[^\"]+(\";.*)/\1${REAL_USER}\2/" "$DIR/flake.nix"
    echo "    Updated. Review the change with: git diff flake.nix"
  else
    echo "    Skipped. Edit the single \"user = \" line in flake.nix yourself first."
    exit 1
  fi
else
  echo "    flake.nix already matches \"$REAL_USER\", nothing to do."
fi

echo "==> Step 4: /etc/wsl.conf"
# The stand-in for the video's macOS system.defaults: root-owned host settings
# that Home Manager cannot reach. Shown as a diff, never applied silently.
if [ ! -e /proc/version ] || ! grep -qi microsoft /proc/version 2>/dev/null; then
  echo "    not running under WSL, skipping"
elif diff -q "$DIR/system/wsl.conf" /etc/wsl.conf >/dev/null 2>&1; then
  echo "    /etc/wsl.conf already matches system/wsl.conf"
else
  echo "    system/wsl.conf differs from the live /etc/wsl.conf:"
  diff -u /etc/wsl.conf "$DIR/system/wsl.conf" 2>/dev/null | sed 's/^/      /' || true
  if ask "Install system/wsl.conf to /etc/wsl.conf (sudo)?"; then
    sudo cp -n /etc/wsl.conf /etc/wsl.conf.backup 2>/dev/null || true
    sudo cp "$DIR/system/wsl.conf" /etc/wsl.conf
    echo "    Installed. Run 'wsl --shutdown' from Windows for it to take effect."
  else
    echo "    Skipped, leaving /etc/wsl.conf as it is."
  fi
fi

echo "==> Step 5: first home-manager switch (pinned to release-26.05)"
# home-manager doesn't exist yet on a fresh machine, so run it straight from
# the flake this once. After this, rebuild.sh works normally.
# -b backup renames any pre-existing file Home Manager wants to own to
# <name>.backup rather than failing the switch.
nix run "$HM_REF" -- switch -b backup --flake "$HOME/.dotfiles#$HOST"

echo "==> Step 6: herdr agent integrations"
# herdr shows which agent is live in which pane by way of a small hook it
# installs inside each agent's own config. Those hooks are generated files that
# herdr owns - the one it writes says so at the top, and updating herdr
# overwrites it - so this repo ships no copy of them. It asks herdr to write its
# own instead, which also keeps the absolute paths inside them right for
# whatever machine this is.
HERDR_BIN="$HOME/.nix-profile/bin/herdr"
if [ ! -x "$HERDR_BIN" ]; then
  echo "    herdr not found at $HERDR_BIN, skipping (did step 5 succeed?)"
else
  # command name -> herdr integration target, for the agents home.nix configures.
  # Only agents you actually have get one: installing an integration for an
  # absent agent builds a config tree for a tool that will never run.
  for pair in claude:claude codex:codex opencode:opencode pi:pi gemini:antigravity-cli; do
    agent_cmd=${pair%%:*}
    herdr_target=${pair##*:}
    if ! command -v "$agent_cmd" >/dev/null 2>&1; then
      echo "    $agent_cmd is not installed, skipping its integration"
    elif herdr_out=$("$HERDR_BIN" integration install "$herdr_target" 2>&1); then
      echo "    $agent_cmd: integration installed"
    else
      # Never fatal. herdr still works; it just cannot show that agent's state.
      echo "    $agent_cmd: herdr could not install its integration, continuing"
      printf '%s\n' "$herdr_out" | sed 's/^/      /'
    fi
  done
  # Claude reads its hook registration from ~/.claude/settings.json, which is
  # this repo's file through the symlink in home.nix. So the "hooks" block there
  # is herdr's output, not hand-written config: expect it to change when herdr
  # updates its integration, and let herdr be the one to rewrite it.
fi

echo "==> Step 7: make zsh the login shell"
ZSH_BIN="$HOME/.nix-profile/bin/zsh"
if [ ! -x "$ZSH_BIN" ]; then
  echo "    $ZSH_BIN not found, skipping (did step 5 succeed?)"
elif [ "$(getent passwd "$REAL_USER" | cut -d: -f7)" = "$ZSH_BIN" ]; then
  echo "    already your login shell"
else
  if ! grep -qxF "$ZSH_BIN" /etc/shells 2>/dev/null; then
    echo "    $ZSH_BIN is not in /etc/shells; chsh will refuse it until it is."
    if ask "Append it to /etc/shells (sudo)?"; then
      echo "$ZSH_BIN" | sudo tee -a /etc/shells >/dev/null
    fi
  fi
  if grep -qxF "$ZSH_BIN" /etc/shells 2>/dev/null && ask "Set $ZSH_BIN as your login shell?"; then
    sudo chsh -s "$ZSH_BIN" "$REAL_USER"
    # Worth stating plainly: a broken login shell is the one failure here that
    # can lock you out of the distro, and the way back in is not obvious.
    DISTRO="$(wslpath -w / 2>/dev/null | sed -E 's#^\\\\[^\\]+\\([^\\]+)\\?.*$#\1#')"
    printf '    Done. If Nix garbage collection ever removes that path, get back in from\n'
    printf '    Windows with:  wsl -d %s --exec /bin/bash\n' "${DISTRO:-<distro>}"
  else
    echo "    Skipped. Run 'zsh' by hand to try it; chsh later when you're happy."
  fi
fi

echo
echo "==> Done."
echo "    Remaining manual steps, both on the Windows side:"
echo "      1. Install WezTerm:  winget install wez.wezterm"
echo "      2. Install Hack Nerd Font: see scripts/install-nerd-font.ps1"
echo "    Then use ./rebuild.sh for every future change."
