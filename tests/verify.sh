#!/usr/bin/env bash
# Post-switch verification: does the LIVE machine match what this repo declares?
#
# tests/*.test.sh check the repo and run before you apply anything. This checks
# the applied result, so it only makes sense after ./bootstrap.sh or
# ./rebuild.sh. It is read-only: it never changes a file, a package or a shell.
#
# Unlike the .test.sh files it does not stop at the first failure - you want the
# whole picture after a switch, not the first thing that broke.
#
#   ./tests/verify.sh
#
# Exit status is 0 only if every required check passed. Checks that depend on
# something you may legitimately not have done yet (Windows-side installs, the
# first nvim launch) report as SKIP and do not fail the run.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
PASS=0; FAIL=0; SKIP=0

section() { printf '\n\033[1m%s\033[0m\n' "$1"; }
ok()   { PASS=$((PASS+1)); printf '  \033[32mok\033[0m   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; return 0; }
skip() { SKIP=$((SKIP+1)); printf '  \033[33mskip\033[0m %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; return 0; }

# Resolve a path and report whether it lands inside this repo.
links_into_repo() {
  local link=$1 want=$2 real
  [ -L "$link" ] || { bad "$link is not a symlink" "expected a link into $ROOT"; return; }
  real=$(readlink -f "$link" 2>/dev/null)
  if [ "$real" = "$want" ]; then
    ok "$link -> ${want#"$ROOT"/}"
  else
    bad "$link points at $real" "expected $want"
  fi
}

# ---------------------------------------------------------------------------
section "1. Home Manager generation"

if ! command -v home-manager >/dev/null 2>&1; then
  bad "home-manager is not on PATH" "the switch never completed; run ./bootstrap.sh"
else
  ok "home-manager is on PATH ($(command -v home-manager))"
fi

HM_PROFILE="${XDG_STATE_HOME:-$HOME/.local/state}/nix/profiles/home-manager"
if [ -e "$HM_PROFILE" ]; then
  ok "a generation is active ($(readlink -f "$HM_PROFILE" | sed 's|.*/||'))"
else
  bad "no Home Manager generation exists" "nothing has been applied yet; run ./bootstrap.sh"
fi

# ---------------------------------------------------------------------------
section "2. Packages, and that they come from Nix"

for tool in rg fd fzf jq lazygit nvim herdr starship zsh; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    bad "$tool is not on PATH"
    continue
  fi
  path=$(readlink -f "$(command -v "$tool")")
  case "$path" in
    /nix/store/*) ok "$tool ($(command -v "$tool"))" ;;
    *) bad "$tool resolves to $path" "expected a /nix/store path; something else shadows it" ;;
  esac
done

# The version this repo pins, read from the derivation so the two cannot drift.
want_herdr=$(sed -nE 's/^[[:space:]]*version = "([^"]+)";.*/\1/p' "$ROOT/pkgs/herdr.nix" | head -1)
if command -v herdr >/dev/null 2>&1; then
  got_herdr=$(herdr --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  if [ "$got_herdr" = "$want_herdr" ]; then
    ok "herdr is the pinned $want_herdr"
  else
    bad "herdr reports ${got_herdr:-nothing}" "pkgs/herdr.nix pins $want_herdr"
  fi
fi

# Claude Code must NOT be the Nix copy - see AGENTS.md.
if command -v claude >/dev/null 2>&1; then
  case "$(readlink -f "$(command -v claude)")" in
    /nix/store/*) bad "claude resolves into /nix/store" "a Nix claude-code is shadowing the self-updating install" ;;
    *) ok "claude is the native install, not Nix ($(command -v claude))" ;;
  esac
else
  skip "claude is not on PATH" "expected if you have not installed it here"
fi

# herdr can only report an agent's state if that agent's integration hook is
# installed, which bootstrap step 8 does. Ask herdr instead of looking for files:
# it owns those paths and they differ per agent.
if command -v herdr >/dev/null 2>&1; then
  herdr_status=$(herdr integration status 2>/dev/null || true)
  for pair in claude:claude codex:codex opencode:opencode pi:pi gemini:antigravity-cli; do
    agent_cmd=${pair%%:*}
    herdr_target=${pair##*:}
    command -v "$agent_cmd" >/dev/null 2>&1 || continue
    case "$(printf '%s\n' "$herdr_status" | sed -n "s/^${herdr_target}: //p")" in
      "")               skip "herdr reports no integration for $agent_cmd" \
                             "this herdr version may not know that agent" ;;
      "not installed"*) bad  "herdr's $agent_cmd integration is not installed" \
                             "run ./bootstrap.sh; herdr cannot track $agent_cmd panes without it" ;;
      current*)         ok   "herdr's $agent_cmd integration is installed and current" ;;
      *)                skip "herdr's $agent_cmd integration is out of date" \
                             "re-run ./bootstrap.sh to refresh it" ;;
    esac
  done
fi

# ---------------------------------------------------------------------------
section "3. Edit-in-place symlinks, and the one file that must not be one"

links_into_repo "$HOME/.config/nvim"                "$ROOT/home/.config/nvim"
links_into_repo "$HOME/.config/wezterm"             "$ROOT/home/.config/wezterm"
links_into_repo "$HOME/.config/herdr"               "$ROOT/home/.config/herdr"
links_into_repo "$HOME/.claude/CLAUDE.md"           "$ROOT/home/AGENTS.md"
links_into_repo "$HOME/.codex/AGENTS.md"            "$ROOT/home/AGENTS.md"
links_into_repo "$HOME/.config/opencode/AGENTS.md"  "$ROOT/home/AGENTS.md"

# ~/.claude/settings.json is the exception: it must NOT be a link. Claude Code
# rewrites it in place, and it cannot write through a link into the Nix store -
# see the comment in home.nix. bootstrap step 6 copies the repo's seed there
# once, and the live file drifts from that seed on purpose.
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
if [ -L "$CLAUDE_SETTINGS" ]; then
  bad "$CLAUDE_SETTINGS is a symlink" \
      "Claude cannot write settings through it; re-run ./bootstrap.sh to replace it with a copy"
elif [ ! -f "$CLAUDE_SETTINGS" ]; then
  bad "$CLAUDE_SETTINGS does not exist" "run ./bootstrap.sh to seed it"
elif [ ! -w "$CLAUDE_SETTINGS" ]; then
  bad "$CLAUDE_SETTINGS is not writable" "Claude rewrites this file itself"
else
  ok "$CLAUDE_SETTINGS is a writable regular file, not managed by Home Manager"
fi

# The whole point of mkOutOfStoreSymlink: a file read through ~ is the repo file.
if [ -r "$HOME/.config/nvim/init.lua" ] \
  && cmp -s "$HOME/.config/nvim/init.lua" "$ROOT/home/.config/nvim/init.lua"; then
  ok "editing the repo edits the live config (init.lua is the same file)"
else
  bad "\$HOME/.config/nvim/init.lua is not the repo's file" "edit-in-place is broken"
fi

# ---------------------------------------------------------------------------
section "4. firstmate and the agent tooling it owns"

# bootstrap step 7 clones firstmate and asks it to install its own tooling. This
# repo never lists those tools, so the only honest check is to ask firstmate
# whether anything is still missing.
FIRSTMATE_DIR="${FIRSTMATE_DIR:-$HOME/github/mindcriminal/firstmate}"
FM_BOOTSTRAP="$FIRSTMATE_DIR/bin/fm-bootstrap.sh"

# npm's prefix has to be the directory that is on PATH, or `npm install -g`
# writes into the read-only Nix store and five of those tools never appear.
if command -v npm >/dev/null 2>&1; then
  npm_prefix=$(npm config get prefix 2>/dev/null | tr -d '\r')
  if [ "$npm_prefix" = "$HOME/.npm-global" ]; then
    ok "npm's global prefix is $npm_prefix"
  else
    bad "npm's global prefix is ${npm_prefix:-unreadable}" \
        "expected $HOME/.npm-global, the directory home.nix puts on PATH"
  fi
  case ":$PATH:" in
    *":$HOME/.npm-global/bin:"*) ok "\$HOME/.npm-global/bin is on PATH" ;;
    *) bad "\$HOME/.npm-global/bin is not on PATH" "npm globals would be installed but unreachable" ;;
  esac
else
  skip "npm is not on PATH" "cannot check the global prefix"
fi

if [ -L "$HOME/.npmrc" ]; then
  ok ".npmrc is managed by Home Manager"
elif [ -f "$HOME/.npmrc" ] && grep -q "^prefix=$HOME/.npm-global\$" "$HOME/.npmrc"; then
  # Right answer, wrong owner: this is the hand-written file home.nix now
  # declares. It only becomes a symlink on the next switch.
  skip ".npmrc is still the hand-written file" "run ./rebuild.sh to let Home Manager own it"
else
  bad ".npmrc does not set the npm prefix" "expected prefix=$HOME/.npm-global"
fi

if [ ! -x "$FM_BOOTSTRAP" ]; then
  bad "firstmate is not installed at $FIRSTMATE_DIR" \
      "run ./bootstrap.sh; without it this machine has no agent tooling"
else
  ok "firstmate is cloned ($FIRSTMATE_DIR)"

  # Read-only on both axes: DETECT_ONLY skips firstmate's mutating sweeps, and
  # NETWORK=skip keeps this check local and fast. Anything else would make a
  # verification script change the machine it is verifying.
  fm_report=$(FM_BOOTSTRAP_DETECT_ONLY=1 FM_BOOTSTRAP_NETWORK=skip "$FM_BOOTSTRAP" 2>&1) \
    || fm_report="__FAILED__"
  if [ "$fm_report" = "__FAILED__" ]; then
    skip "firstmate's detect run did not complete" "cannot tell what tooling is missing"
  else
    fm_missing=$(printf '%s\n' "$fm_report" | sed -nE 's/^MISSING: ([^[:space:]]+).*/\1/p')
    fm_manual=$(printf '%s\n' "$fm_report" | sed -n 's/^MISSING_MANUAL: //p')
    if [ -z "$fm_missing" ]; then
      ok "firstmate reports all of its agent tooling installed"
    else
      bad "firstmate reports missing tooling: $(printf '%s' "$fm_missing" | tr '\n' ' ')" \
          "re-run ./bootstrap.sh"
    fi
    if [ -n "$fm_manual" ]; then
      skip "firstmate wants tooling that has no unattended install" \
           "$(printf '%s' "$fm_manual" | tr '\n' ' ')"
    fi
  fi
fi

# ---------------------------------------------------------------------------
section "5. Shell"

login_shell=$(getent passwd "$(id -un)" | cut -d: -f7)
case "$login_shell" in
  *zsh) ok "login shell is zsh ($login_shell)" ;;
  *) skip "login shell is $login_shell" "bootstrap step 9 offers to change this" ;;
esac

if [ -L "$HOME/.zshrc" ] && [ -e "$HOME/.zshrc" ]; then
  ok ".zshrc is managed by Home Manager"
else
  bad ".zshrc is not a Home Manager symlink"
fi

if command -v zsh >/dev/null 2>&1; then
  # -i so the interactive rc actually runs, which is where aliases live.
  for alias_name in cc co m push; do
    if zsh -ic "alias $alias_name" >/dev/null 2>&1; then
      ok "alias '$alias_name' is defined in an interactive zsh"
    else
      bad "alias '$alias_name' is missing from an interactive zsh"
    fi
  done

  if zsh -ic 'command -v starship' >/dev/null 2>&1; then
    ok "starship is initialised in zsh"
  else
    bad "starship is not available in zsh"
  fi

  # The guard added in home.nix: a non-login zsh must still find nix.
  if zsh -ic 'command -v nix' >/dev/null 2>&1; then
    ok "nix is reachable from a non-login zsh"
  else
    bad "nix is not on PATH in zsh" "the profile guard in home.nix is not working"
  fi

  if zsh -ic '[ -n "$EDITOR" ] && [ "$EDITOR" = nvim ]' >/dev/null 2>&1; then
    ok "EDITOR is nvim"
  else
    bad "EDITOR is not nvim in zsh"
  fi
fi

# ---------------------------------------------------------------------------
section "6. Neovim"

if command -v nvim >/dev/null 2>&1; then
  # lazy.nvim prints plugin-install progress to stdout on first launch, which
  # would be captured along with the answer. Have Neovim write the value to a
  # file and read that instead, so the check is immune to plugin chatter.
  probe=$(mktemp)
  nvim --headless \
    "+lua vim.fn.writefile({vim.inspect(vim.g.mapleader), tostring(vim.o.relativenumber)}, '$probe')" \
    +qa >/dev/null 2>&1
  leader=$(sed -n 1p "$probe" 2>/dev/null)
  relnum=$(sed -n 2p "$probe" 2>/dev/null)
  rm -f "$probe"

  if [ "$leader" = '" "' ]; then
    ok "vim_config.lua is loaded (mapleader is space)"
  else
    bad "mapleader is ${leader:-unreadable}" "expected \" \"; the config did not load"
  fi

  # vim_config.lua deliberately turns relativenumber off, unlike upstream.
  if [ "$relnum" = "false" ]; then
    ok "options applied (relativenumber is off, as vim_config.lua sets it)"
  else
    bad "relativenumber is ${relnum:-unreadable}" "expected false; vim_config.lua turns it off"
  fi

  if [ -d "$HOME/.local/share/nvim/lazy/lazy.nvim" ]; then
    n=$(find "$HOME/.local/share/nvim/lazy" -maxdepth 1 -mindepth 1 -type d | wc -l)
    ok "lazy.nvim is bootstrapped ($n plugin dirs)"
  else
    skip "lazy.nvim has not bootstrapped yet" "launch nvim once, with network, to clone plugins"
  fi
fi

# ---------------------------------------------------------------------------
section "7. Font, Linux side"

if command -v fc-list >/dev/null 2>&1; then
  # Capture first, then match. Under `set -o pipefail`, `fc-list | grep -q`
  # reports failure even on a match: grep -q exits at the first hit, fc-list
  # takes SIGPIPE, and pipefail surfaces its 141 as the pipeline's status.
  installed_fonts=$(fc-list 2>/dev/null || true)
  case "$installed_fonts" in
    *"Hack Nerd Font"*) ok "Hack Nerd Font is visible to fontconfig" ;;
    *) bad "fontconfig cannot see Hack Nerd Font" "is nerd-fonts.hack in home.packages?" ;;
  esac
else
  skip "fc-list not available" "cannot check the Linux font cache"
fi

# ---------------------------------------------------------------------------
section "8. Windows side"

if ! command -v wslpath >/dev/null 2>&1 || [ ! -x /mnt/c/Windows/System32/cmd.exe ]; then
  skip "Windows is not reachable from here" "nothing below can be checked"
else
  PWSH=/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe
  WIN_HOME=$(wslpath -u "$(cd /mnt/c && /mnt/c/Windows/System32/cmd.exe /d /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r\n')" 2>/dev/null)
  LOADER="$WIN_HOME/.config/wezterm/wezterm.lua"

  if [ -f "$LOADER" ]; then
    ok "the Windows loader is installed ($LOADER)"

    if grep -q 'GENERATED - do not edit on the Windows side' "$LOADER"; then
      ok "the loader is the one this repo generated"
    else
      bad "$LOADER is not our generated loader" "something else owns the Windows config"
    fi

    # The UNC path baked into the loader must resolve back to the repo's file.
    unc=$(sed -nE 's/^local WSL_CONFIG = \[\[(.*)\]\]$/\1/p' "$LOADER" | head -1)
    if [ -n "$unc" ]; then
      back=$(wslpath -u "$unc" 2>/dev/null)
      if [ -f "$back" ] && cmp -s "$back" "$ROOT/home/.config/wezterm/wezterm.lua"; then
        ok "the loader reads this repo's wezterm.lua back over \\\\wsl.localhost"
      else
        bad "the loader's path does not resolve to the repo config" "it points at $unc"
      fi
    else
      bad "could not read the WSL_CONFIG path out of the loader"
    fi
  else
    skip "the Windows loader is not installed" "run ./rebuild.sh with interop enabled"
  fi

  if [ -e "$WIN_HOME/.wezterm.lua" ]; then
    bad "$WIN_HOME/.wezterm.lua exists" "WezTerm reads it FIRST and will ignore the managed config"
  else
    ok "no stray %USERPROFILE%\\.wezterm.lua shadowing the config"
  fi

  # Files on disk are NOT enough, and checking only for them hid a real bug:
  # each face must be registered under its own HKCU value name. When they all
  # claim one name the last write wins, the family collapses to a single style,
  # and WezTerm reports it cannot find a Regular face. Ask Windows what it can
  # actually resolve, which is the only thing WezTerm cares about.
  if ls "$WIN_HOME/AppData/Local/Microsoft/Windows/Fonts/"HackNerdFont*.ttf >/dev/null 2>&1; then
    font_probe=$(cd /mnt/c && "$PWSH" -NoProfile -Command "
      Add-Type -AssemblyName System.Drawing
      \$f = (New-Object System.Drawing.Text.InstalledFontCollection).Families |
            Where-Object { \$_.Name -eq 'Hack Nerd Font' }
      if (-not \$f) { 'MISSING' }
      elseif (\$f.IsStyleAvailable([System.Drawing.FontStyle]::Regular)) { 'OK' }
      else { 'NOREGULAR' }" 2>/dev/null | tr -d '\r\n')
    case "$font_probe" in
      OK) ok "Windows resolves Hack Nerd Font with a Regular face" ;;
      NOREGULAR) bad "Hack Nerd Font has no Regular face on Windows" \
                     "the per-face registry entries collided; re-run scripts/install-nerd-font.ps1" ;;
      MISSING) bad "the font files are installed but Windows cannot see the family" \
                   "re-run scripts/install-nerd-font.ps1, then sign out and back in" ;;
      *) skip "could not ask Windows about installed fonts" ;;
    esac
  else
    skip "Hack Nerd Font is not installed on Windows" "run scripts/install-nerd-font.ps1 from PowerShell"
  fi

  if ls /mnt/c/Program\ Files/WezTerm/wezterm-gui.exe >/dev/null 2>&1 \
    || ls "$WIN_HOME/AppData/Local/Programs/WezTerm/wezterm-gui.exe" >/dev/null 2>&1; then
    ok "WezTerm is installed on Windows"
  else
    skip "WezTerm is not installed on Windows" "winget install wez.wezterm"
  fi
fi

# ---------------------------------------------------------------------------
section "9. /etc/wsl.conf"

if [ ! -f /etc/wsl.conf ]; then
  skip "/etc/wsl.conf does not exist"
elif diff -q "$ROOT/system/wsl.conf" /etc/wsl.conf >/dev/null 2>&1; then
  ok "/etc/wsl.conf matches system/wsl.conf"
else
  skip "/etc/wsl.conf differs from system/wsl.conf" "run ./bootstrap.sh to review the diff"
fi

# ---------------------------------------------------------------------------
printf '\n\033[1mSummary\033[0m\n'
printf '  %d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"

if [ "$FAIL" -eq 0 ]; then
  cat <<'MSG'

Everything checkable from a script is in order. Four things still need eyes,
because no script can see them:

  1. Open WezTerm on Windows. It should land in a WSL shell, not PowerShell.
  2. The prompt should show a purple chevron and your git branch, and glyphs
     should be glyphs, not boxes. Boxes mean the Windows font install.
  3. The window should be translucent, and dim when you focus another window.
  4. Open nvim. Colours should be rose-pine moon; press space then wait for the
     which-key popup; <leader>f should open a file picker.

Then prove edit-in-place: change font_size in
home/.config/wezterm/wezterm.lua, press Ctrl+Shift+R in WezTerm, and watch it
change with no rebuild.
MSG
  exit 0
fi

printf '\n%d check(s) failed. Re-run ./rebuild.sh, then this script again.\n' "$FAIL"
exit 1
