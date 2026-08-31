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

echo "==> Step 6: seed ~/.claude/settings.json"
# A first-install seed, copied - not symlinked - and never over a real file.
# The script says why at length; rebuild.sh calls the same one after every
# switch, because activation deletes the symlink an older generation owned.
"$DIR/scripts/seed-claude-settings.sh"

echo "==> Step 7: firstmate, and the agent tooling it owns"
# BEGIN firstmate step - tests/firstmate.test.sh extracts this block by these
# two markers and runs it on its own, so keep it self-contained: `ask`, $HOME
# and the shell options are the only things it may take from the rest of this
# file.
#
# This repo deliberately does NOT list the agent tools themselves. firstmate
# already owns that list, and their minimum versions, in bin/fm-bootstrap.sh;
# a second copy here would rot the first time firstmate adds a tool or raises a
# floor. So dotfiles' whole job is to get firstmate onto the machine, and
# firstmate's job is to install its own tooling. tests/firstmate.test.sh keeps
# this file honest by failing if it ever names one of them.
FIRSTMATE_URL="${FIRSTMATE_URL:-https://github.com/kunchenguid/firstmate}"
FIRSTMATE_DIR="${FIRSTMATE_DIR:-$HOME/github/mindcriminal/firstmate}"
# HTTPS, not SSH, on purpose: a fresh machine has no key on GitHub yet.
FM_BOOTSTRAP="$FIRSTMATE_DIR/bin/fm-bootstrap.sh"
fm_consented=0   # the clone prompt also covers the install, so only ever ask once
fm_usable=1

if [ -d "$FIRSTMATE_DIR" ]; then
  # Never pull, reset or clean it. It carries machine-local, captain-private
  # state (data/, state/, config/, projects/, .env) that this repo must not touch.
  echo "    firstmate already present at $FIRSTMATE_DIR, leaving it alone"
elif ! command -v git >/dev/null 2>&1; then
  echo "    git is not on PATH, skipping (did step 5 succeed?)"
  fm_usable=0
else
  echo "    firstmate is not on this machine yet. It is the thing that knows"
  echo "    which agent tools this machine needs, and installs them itself."
  echo "      clone $FIRSTMATE_URL"
  echo "         -> $FIRSTMATE_DIR"
  if ask "Clone it, then install whatever agent tooling it reports missing?"; then
    fm_consented=1
    if git clone "$FIRSTMATE_URL" "$FIRSTMATE_DIR"; then
      echo "    cloned"
    else
      echo "    clone failed, skipping the rest of this step"
      fm_usable=0
    fi
  else
    echo "    Skipped. Without firstmate this machine gets none of its agent tooling."
    fm_usable=0
  fi
fi

if [ "$fm_usable" = 1 ] && [ ! -x "$FM_BOOTSTRAP" ]; then
  echo "    $FM_BOOTSTRAP is missing or not executable, skipping"
  fm_usable=0
fi

if [ "$fm_usable" = 1 ]; then
  # FM_BOOTSTRAP_DETECT_ONLY=1 is required, not a nicety: without it this run
  # performs firstmate's mutating startup sweeps (fleet sync, secondmate
  # liveness, backlog reconciliation), which a machine bootstrap has no
  # business triggering.
  if ! fm_report=$(FM_BOOTSTRAP_DETECT_ONLY=1 "$FM_BOOTSTRAP" 2>&1); then
    echo "    firstmate's detect run failed, skipping its tooling install:"
    printf '%s\n' "$fm_report" | sed 's/^/      /'
  else
    # It prints one line per problem. Only "MISSING: <tool> (install: <cmd>)"
    # names a tool this step may install. "MISSING_MANUAL: " needs a human, and
    # passing it to `install` fails by design; every other line (NEEDS_GH_AUTH,
    # TANGLE:, FLEET_SYNC:, ...) is a diagnostic, not a tool.
    fm_missing=$(printf '%s\n' "$fm_report" | sed -nE 's/^MISSING: ([^[:space:]]+).*/\1/p')
    fm_manual=$(printf '%s\n' "$fm_report" | sed -n 's/^MISSING_MANUAL: //p')

    if [ -n "$fm_manual" ]; then
      echo "    These have no unattended install; do them by hand:"
      printf '%s\n' "$fm_manual" | sed 's/^/      /'
    fi

    if [ -z "$fm_missing" ]; then
      echo "    all of firstmate's agent tooling is already installed"
    else
      echo "    firstmate reports these missing:"
      printf '%s\n' "$fm_missing" | sed 's/^/      /'
      echo "    Installing them fetches from the network, and two of them pipe a"
      echo "    remote install script straight into a shell."
      if [ "$fm_consented" = 1 ] || ask "Let firstmate install them?"; then
        # Unquoted on purpose: one argument per tool name.
        # shellcheck disable=SC2086
        if "$FM_BOOTSTRAP" install $fm_missing; then
          echo "    installed"
        else
          # Never fatal: the rest of this machine is still worth finishing.
          echo "    firstmate could not install everything; re-run ./bootstrap.sh once fixed"
        fi
      else
        echo "    Skipped."
      fi
    fi
  fi
fi
# END firstmate step

echo "==> Step 8: herdr agent integrations"
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
  # Claude reads its hook registration from ~/.claude/settings.json. That file
  # is not managed by home.nix and is not this repo's file: step 6 only seeds it
  # once, and `herdr integration install claude` writes its "hooks" block
  # straight into the live copy. So the repo's home/.claude/settings.json is
  # expected to drift from what is actually on the machine - do not treat the
  # difference as damage, and let herdr be the one to rewrite those hooks.
fi

echo "==> Step 9: make zsh the login shell"
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
