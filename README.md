# dotfiles

A WSL2 / Rocky Linux 10 translation of [kunchenguid/dotfiles](https://github.com/kunchenguid/dotfiles),
the macOS setup from [this walkthrough](https://youtu.be/5N-okeDdIuI).
One repo, one command, and this machine ends up configured the same way every time.

The upstream repo is a Mac: nix-darwin, Homebrew, macOS system defaults.
None of those exist here, so the parts that do not translate were replaced
rather than dropped. [What changed and why](#what-changed-from-the-macos-version)
covers every difference.

## What you get

Running the switch builds:

- Nix user packages (ripgrep, fd, fzf, jq, lazygit, Neovim, herdr, Hack Nerd Font)
- Shell (zsh, aliases, starship prompt)
- Editor (Neovim config with the rose-pine moon theme)
- Terminal (WezTerm config with the rose-pine moon theme and dimmed unfocused
  windows, installed across the WSL/Windows boundary)
- Agent configs (Claude, Codex, opencode all share one AGENTS.md)
- Host settings for WSL itself (`/etc/wsl.conf`), applied only after you see the diff

## Prerequisites

- WSL2 with a systemd-enabled distro. Built and tested on Rocky Linux 10, x86_64.
- Windows 10 or 11 on the other side, for the terminal.
- Another distro or a non-Rocky WSL install works: nothing here is Rocky-specific
  beyond `system/wsl.conf`, but see [Make it yours](#make-it-yours).

## Fresh-machine setup

```sh
git clone <this repo> ~/github/<you>/dotfiles
cd dotfiles
```

Before you run it: review [Make it yours](#make-it-yours).
`bootstrap.sh` applies the config to your machine, so do this first.

```sh
./bootstrap.sh
```

`bootstrap.sh` does six things, in order:

1. Installs Determinate Nix, if it isn't already installed.
2. Symlinks this repo to `~/.dotfiles`.
   This has to happen before the first build, because `home.nix` points at
   config files through `~/.dotfiles`.
3. Checks the `user` configured in `flake.nix` against your actual Linux
   username, and offers to fix it for you if they differ.
4. Shows you a diff between `system/wsl.conf` and the live `/etc/wsl.conf`, and
   offers to install it with sudo. Nothing is written without your yes.
5. Runs the first `home-manager switch`, fetching `home-manager` itself from the
   release-26.05 branch. The config it applies is pinned by this repo's `flake.lock`.
6. Offers to make the Nix zsh your login shell (adding it to `/etc/shells` first,
   since `chsh` refuses shells that aren't listed).

Two steps stay manual, because they run on the Windows side:

```powershell
winget install wez.wezterm
powershell -ExecutionPolicy Bypass -File .\scripts\install-nerd-font.ps1
```

### Validate without applying

Once Nix is installed (step 1), you can check that the config builds without
touching your system - handy when you have edited something:

```sh
nix flake check                          # builds the whole home configuration
nix build .#checks.x86_64-linux.home     # same thing, explicitly
./tests/run.sh                           # static invariants
nix develop -c ./tests/run.sh            # plus lua + shellcheck
```

### Verify after applying

`tests/*.test.sh` check the repo. To check that the switch actually took
effect on this machine - packages resolving into the Nix store, symlinks
pointing back here, zsh loading its aliases, the Windows loader installed and
reading the right file - run:

```sh
./tests/verify.sh
```

It is read-only, reports every failure rather than stopping at the first, and
ends with the handful of visual checks no script can make for you.

## Daily use

Edit the config files in place, then apply:

```sh
./rebuild.sh
```

No sudo: this is a standalone Home Manager config and owns only your user
environment, unlike the video's `darwin-rebuild`, which writes system state.

## What changed from the macOS version

| macOS (upstream) | Here | Why |
| --- | --- | --- |
| `nix-darwin` + `darwinConfigurations."mac"` | standalone `homeConfigurations."wsl"` | There is no nix-darwin for a non-NixOS Linux host. Rocky is managed by dnf; Nix owns only this user. |
| `configuration.nix` (`system.defaults`, Homebrew) | `wsl.nix` + `system/wsl.conf` | No macOS defaults to set. The host-level WSL knobs live in root-owned `/etc/wsl.conf`, outside Home Manager's reach. |
| `sudo darwin-rebuild switch` | `home-manager switch` | User-level config needs no root. |
| `nixpkgs-26.05-darwin` | `nixos-26.05` | Linux branch of the same release. |
| Homebrew `casks` / `brews`, `cleanup = "zap"` | nothing | No Homebrew layer, so nothing to zap. Every package is declared in `home.nix`; anything nixpkgs lacks is packaged in `pkgs/`. |
| `herdr` from Homebrew | `pkgs/herdr.nix` | Not in nixpkgs. Pinned to upstream's official Linux x86_64 release binary by SRI hash. |
| `claude-code` Homebrew cask | not installed by Nix | See [Claude Code](#claude-code) below. |
| WezTerm cask + `~/.config/wezterm` symlink | `winget` + a generated Windows-side loader | See [How the WezTerm bridge works](#how-the-wezterm-bridge-works). |
| `macos_window_background_blur = 50` | `win32_system_backdrop = "Acrylic"` | The Windows equivalent. Both are guarded by a platform check in the same `wezterm.lua`. |
| Hack Nerd Font via `home.packages` | that, plus `scripts/install-nerd-font.ps1` | The Linux copy is invisible to a Windows terminal; it needs its own per-user install. |
| his `~/.pi/agent` layer (Pi themes, extensions, models.json, settings.json) | **not ported** | See [Not ported](#not-ported). |
| `chsh` not needed (zsh is the macOS default) | bootstrap step 6 | zsh is not the default shell on Rocky and is not in `/etc/shells` until Nix's copy is added. |

The Neovim config carries over untouched: it already checks for WSL and turns on
a transparent background there, so it was correct for this machine before the
translation started.

### If WezTerm says it cannot load the font

> Unable to load a font specified by your font=wezterm.font('Hack Nerd Font', ...)

Windows can see the family but not the Regular face. Re-run
`scripts/install-nerd-font.ps1` - it registers each face under its own name and
tells running apps - then restart WezTerm. `./tests/verify.sh` checks this
directly by asking Windows whether a Regular face resolves.

## Not ported

**Pi.** Upstream's `home/.pi/agent` layer - the rose-pine-moon Pi theme, the
`terminal-status-title` and `calm` local extensions, `models.json` and
`settings.json` - is not in this repo. Upstream describes it as "an additive
post-video layer" for an opt-in CLI it deliberately does not vendor, and the
walkthrough this repo follows does not cover it.

Nothing about it is macOS-specific, so it would port cleanly: copy
`home/.pi/` across and add the four `mkOutOfStoreSymlink` entries to
`home.nix`. It is left out because it was not asked for, not because it
does not work here. Note that his `settings.json` pins two third-party npm
packages that run with your full user permissions.

Everything else from upstream is present. The Neovim config, the herdr
config and `.claude/settings.json` are byte-identical to his; the package
list, shell aliases and starship settings match exactly.

## How the WezTerm bridge works

Every other config here is a `mkOutOfStoreSymlink` straight into this repo, so
editing the file in the repo *is* editing your live config.

WezTerm can't work that way. It runs as a Windows program, and Windows will not
follow a Linux symlink. A plain copy to the Windows side would work but would
break edit-in-place: every tweak would need a rebuild.

So `scripts/install-windows-wezterm.sh` renders
`home/.config/wezterm/windows-bootstrap.lua.in` into a small loader and copies
*that* to `C:\Users\<you>\.config\wezterm\wezterm.lua`. The loader does one
thing: read the real `wezterm.lua` back out of WSL over `\\wsl.localhost`.

```
home/.config/wezterm/wezterm.lua          <- the real file, edit here
        |
        +--> ~/.config/wezterm/           symlink (Linux side)
        |
        +--  \\wsl.localhost\rocky10\...  read at startup by
                    ^                     C:\Users\<you>\.config\wezterm\wezterm.lua
                    |                     (generated loader)
```

Edit the Lua in this repo, press Ctrl+Shift+R in WezTerm, done - no rebuild.
The loader runs `dofile` under `pcall`, so if WSL is unreachable you get a
minimal working terminal and an error in the log rather than a broken config.
The installer no-ops with a message, never an error, when Windows is
unreachable, so a switch inside a container or with interop off still succeeds.

`config.default_domain = "WSL:rocky10"` means new windows and tabs open straight
into this distro instead of PowerShell.

**Gotcha:** WezTerm checks `%USERPROFILE%\.wezterm.lua` *before*
`.config\wezterm\wezterm.lua`. If you have a stray one there it silently wins;
the installer warns you when it sees it.

## Make it yours

- **Username**: run `./bootstrap.sh` (it detects your username and offers to set
  it) OR change the single `user = "mindcriminal"` line in `flake.nix`.
  Everything else is threaded from that one variable.
- **Host label** `"wsl"`, in three places: `flake.nix`, `rebuild.sh`, and
  `bootstrap.sh`'s `HOST=`. All three have to match; `tests/config.test.sh`
  fails if they drift.
- **WSL distro name**, if yours isn't `rocky10`. Check with `wsl -l -q` on
  Windows, then update `WSL_DISTRO` in `home/.config/wezterm/wezterm.lua` and
  the `-Distro` default in `scripts/install-nerd-font.ps1`. The WezTerm
  *installer* detects it automatically; only these two need telling.
- **`system/wsl.conf`** hardcodes `default = mindcriminal` under `[user]`.
- **Font size** is 12pt on Windows and 15pt on macOS, in `wezterm.lua` - the
  same number does not render at the same size on both.

**Git identity:** like upstream, this config deliberately does not set your git
name or email. If you'd rather manage that declaratively, add to `home.nix`:

```nix
programs.git = {
  enable = true;
  settings.user = {
    name = "Your Name";
    email = "you@example.com";
  };
};
```

**Heads-up:**

- `home/AGENTS.md` is the upstream author's personal agent policy, kept as a
  starting point and installed for Claude, Codex, and opencode. It has a header
  saying so. Edit or delete it - you are not obliged to inherit his rules.
- The `cc` and `co` aliases are high-agency shortcuts:
  `claude --dangerously-skip-permissions` and `codex --full-auto`.
  They're convenient, but know what they do before you use them.
- `bootstrap.sh` runs `home-manager switch -b backup`, so any config file Home
  Manager wants to own that already exists is renamed to `<name>.backup` rather
  than lost. Expect `~/.claude/settings.json.backup` on a first run.

### Claude Code

Not installed by Nix, on purpose, even though nixpkgs has it.

Claude Code on Linux is a self-updating native install under
`~/.local/share/claude`, and it is usually ahead of the nixpkgs version. A Nix
copy would land earlier on `PATH`, pin an older build, and fight the updater.
The video installs it from a Homebrew cask, where that conflict doesn't arise.
Install or update it upstream's way and leave it out of `home.packages`.

## Repo tour

- `flake.nix` - the entry point. Wires up nixpkgs, home-manager, and the local
  overlay, and declares the `wsl` configuration.
- `home.nix` - user-level config: shell, packages, prompt, and the symlinks.
- `wsl.nix` - the WSL2 counterpart of upstream's `configuration.nix`. Explains
  what has no equivalent, and owns the Windows-side WezTerm activation.
- `overlay.nix` / `pkgs/` - packages nixpkgs doesn't carry. Upstream gets these
  from Homebrew.
- `system/wsl.conf` - intended contents of `/etc/wsl.conf`, applied by
  `bootstrap.sh` after showing you a diff.
- `scripts/` - the two Windows-boundary crossings: the WezTerm loader installer
  (run automatically on every switch) and the font installer (run by hand).
- `home/` - the actual config files that get symlinked into place.
- `tests/` - static invariants (`./tests/run.sh`) plus `verify.sh`, which
  checks the applied machine rather than the repo.

## Recovery

If a Nix garbage collection ever removes the zsh your login shell points at, you
are locked out of a normal shell. From Windows:

```powershell
wsl -d rocky10 --exec /bin/bash
```

Then `sudo chsh -s /bin/bash $USER`, or re-run `./rebuild.sh` to restore the
profile.

## Credit and license

Upstream: [kunchenguid/dotfiles](https://github.com/kunchenguid/dotfiles),
licensed MIT No Attribution. This translation keeps the same license; see
`LICENSE`.
