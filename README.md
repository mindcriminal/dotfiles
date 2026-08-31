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
- Dictation settings for Handy, seeded across the same WSL/Windows boundary
  (see [How dictation is set up](#how-dictation-is-set-up))
- Agent tooling, by way of firstmate, which owns the list of tools rather than
  this repo (see [Agent tooling](#agent-tooling))
- Host settings for WSL itself (`/etc/wsl.conf`), applied only after you see the diff

## Prerequisites

- WSL2 with a systemd-enabled distro. Built and tested on Rocky Linux 10, x86_64.
- Windows 10 or 11 on the other side, for the terminal and for dictation.
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

`bootstrap.sh` does eight things, in order:

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
6. Clones [firstmate](https://github.com/kunchenguid/firstmate), then asks it
   which agent tools this machine is missing and lets it install them. This repo
   lists none of those tools by name: firstmate already owns that list and their
   minimum versions in its own `bin/fm-bootstrap.sh`, so a copy here would rot
   the first time it changes. Nothing is fetched without your yes, and an
   existing firstmate checkout is left exactly as it is - never pulled or reset.
7. Asks herdr to install its agent integrations, for each agent you actually
   have. These are generated hooks that herdr owns and overwrites on update, so
   this repo does not ship them; herdr writes its own, with paths correct for
   this machine.
8. Offers to make the Nix zsh your login shell (adding it to `/etc/shells` first,
   since `chsh` refuses shells that aren't listed).

Three steps stay manual, because they run on the Windows side:

```powershell
winget install wez.wezterm
powershell -ExecutionPolicy Bypass -File .\scripts\install-nerd-font.ps1
winget install cjpais.Handy
```

Launch Handy once so it can download its model, then quit it and run
`./rebuild.sh` to seed its settings - see
[How dictation is set up](#how-dictation-is-set-up).

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
| no dictation | Handy, installed Windows-side, settings seeded | Not a translation of anything upstream - an addition. See [How dictation is set up](#how-dictation-is-set-up). |
| `chsh` not needed (zsh is the macOS default) | bootstrap step 9 | zsh is not the default shell on Rocky and is not in `/etc/shells` until Nix's copy is added. |

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
config and the `.claude/settings.json` seed are byte-identical to his; the
package list, shell aliases and starship settings match exactly.

## How the WezTerm bridge works

Nearly every config here is a `mkOutOfStoreSymlink` straight into this repo, so
editing the file in the repo *is* editing your live config. (The other exception
is [Claude's settings file](#claudes-settings-file), for a different reason.)

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

## How dictation is set up

Dictation is [Handy](https://github.com/cjpais/Handy): hold a hotkey, talk, and
a local Whisper model types what you said into whatever has focus.

**It is a Windows app, and it has to be.** Handy needs a global hotkey and has
to type into the focused *Windows* window. A process inside the distro can do
neither, so there is no WSL-side install to prefer - this is the same boundary
the [WezTerm bridge](#how-the-wezterm-bridge-works) crosses, and it is handled
the same way: this repo does not automate the install, it tells you the command
and then checks that you ran it.

```powershell
winget install cjpais.Handy
```

winget pulls the Vulkan runtime it needs as a dependency. Launch Handy once and
let it download the Whisper `turbo` model (`ggml-large-v3-turbo.bin`, ~1.5GB).
That download is **not** in this repo and never will be: a gigabyte and a half
of weights does not belong in a dotfiles checkout, and Handy already knows how
to fetch and verify it. If you would rather not wait on the UI, the same file
is at `https://blob.handy.computer/ggml-large-v3-turbo.bin`
(sha256 `1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69`),
dropped into `%APPDATA%\com.pais.handy\models\`.

Then quit Handy and run `./rebuild.sh`. `scripts/seed-handy-settings.sh` seeds
three settings into `%APPDATA%\com.pais.handy\settings_store.json`:

| Setting | Value | Why |
| --- | --- | --- |
| `paste_method` | `direct` | The one that is not a preference. See below. |
| `selected_model` | `turbo` | Whisper large-v3-turbo, the model above. |
| `autostart_enabled` | `true` | Dictation is there after a reboot without being started by hand. |

### Why `paste_method` has to be `direct`

Handy's default pastes by putting the transcript on the Windows clipboard,
sending Ctrl+V, and restoring your previous clipboard on a timer. WezTerm
queues that paste through its own event loop and reads the clipboard *after*
the restore has already fired - so it pastes whatever you had copied before
instead of your words. That is upstream
[Handy issue #502](https://github.com/cjpais/Handy/issues/502).

Neither clipboard-based mitigation holds. A longer `paste_delay_after_ms` just
loses to any lag. The receipt-based `reliable_paste` path settled on a foreign
process that read the clipboard a millisecond after the chord and restored
early. `direct` types the characters and never touches the clipboard at all,
which removes the race rather than racing it - which is also why
`home/.config/wezterm/wezterm.lua` needs no change for any of this.

WezTerm is this machine's terminal, so at the default this is broken in the one
window it gets used in most. `./tests/verify.sh` checks the live value and
fails if it is anything else.

### How the seeding behaves

Same lesson as [Claude's settings file](#claudes-settings-file), for the same
reason: Handy rewrites `settings_store.json` itself, on every settings change
and again at shutdown, so Home Manager must not own it. The seeder is therefore
careful:

- it only writes a key that is still at **Handy's own default**. Anything else
  you set in Handy's UI is yours; it says so and moves on.
- it refuses to write while Handy is **running**, because Handy would serialize
  its in-memory settings over the file at exit and silently undo the change. It
  tells you to quit Handy and re-run.
- it backs the file up before its first write, and leaves a store it cannot
  parse strictly alone.
- it **no-ops with a message, never an error**, when Handy is not installed or
  Windows is unreachable. A machine with no Handy still builds, switches and
  tests clean.

`scripts/seed-handy-settings.sh --dry-run` reports what it would change.
`--apply <file>` prints the seeded JSON for a store on stdout and writes
nothing, which is how `tests/handy.test.sh` exercises the real merge rules
against a recorded Handy store.

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
  than lost.
- `~/.claude/settings.json` is the one config here that is **not** managed by
  Home Manager, and not a symlink. See
  [Claude's settings file](#claudes-settings-file).

### Claude Code

Not installed by Nix, on purpose, even though nixpkgs has it.

Claude Code on Linux is a self-updating native install under
`~/.local/share/claude`, and it is usually ahead of the nixpkgs version. A Nix
copy would land earlier on `PATH`, pin an older build, and fight the updater.
The video installs it from a Homebrew cask, where that conflict doesn't arise.
Install or update it upstream's way and leave it out of `home.packages`.

### Claude's settings file

`~/.claude/settings.json` is the single config in this repo that Home Manager
does not own, and the single one that is a real file rather than a symlink.

Claude Code rewrites that file itself every time you change a model, an effort
level or the theme. It does it atomically: it writes
`settings.json.tmp.<pid>.<hash>` in the directory of the **first** symlink hop
and then renames it into place. When Home Manager owns the path, that first hop
is the read-only, root-owned `/nix/store/...-home-manager-files` directory, so
every settings change dies with:

```
Failed to read raw settings from ~/.claude/settings.json:
Error: EACCES: permission denied, open '/nix/store/...-home-manager-files/.claude/settings.json.tmp....'
```

`mkOutOfStoreSymlink` does not rescue it, because the temp file lands beside the
first hop rather than beside the final target. So the entry is gone from
`home.nix` entirely.

`home/.claude/settings.json` stays in the repo as a **first-install seed**.
`scripts/seed-claude-settings.sh` copies it to `~/.claude/settings.json`, and
only when there is no regular file there already - if it finds the stale symlink
from an older generation it replaces that with the copy, and if it finds a real
file it leaves it alone, because by then the file is yours and Claude's. Editing
the repo copy therefore does *not* change your live settings on a machine that
is already set up; copy it across by hand if you want it to.

Both `bootstrap.sh` (step 6) and `rebuild.sh` run that script, always *after*
the switch. A bare `home-manager switch` does not - use `./rebuild.sh`, which is
what everything here assumes anyway.

**Upgrading a machine set up before this change.** Your `~/.claude/settings.json`
is still the symlink the old generation owned. Home Manager deletes a path it
owned in the previous generation but no longer declares, so the first
`./rebuild.sh` after this change removes that link - and then, in the same run,
the seed script puts a real file back in its place. You end up with a writable
copy of the repo seed, and Claude can save settings again.

If your live settings had drifted from the repo copy - most likely herdr's
`hooks` block, or anything you changed inside Claude - that drift lived only in
the symlink target, which is this repo's file, so it is still in the repo and
gets copied across with everything else. Any *later* rebuild is a no-op here:
the seed script sees a regular file and leaves it alone, and Home Manager
declines to delete a path that does not link into one of its generations. If you
want to be careful, `cp ~/.claude/settings.json ~/claude-settings.bak` first.

Expect the two to drift from then on. `herdr integration install claude`
(bootstrap step 8) writes its `hooks` block straight into the live file, and
Claude writes your own changes there too. That difference is normal, not damage.

### Agent tooling

The agent CLIs this machine uses (`treehouse`, `no-mistakes`, and a handful of
`*-axi` npm globals) are **not** declared here, and deliberately so. They
self-update, they register their own agent hooks, and
[firstmate](https://github.com/kunchenguid/firstmate) already owns both the list
of them and their minimum versions, in its `bin/fm-bootstrap.sh`. Listing them
here would mean two lists, and the second one rots the first time firstmate adds
a tool or raises a floor.

So bootstrap step 7 does the smallest thing that works: clone firstmate over
HTTPS (no SSH key exists yet on a fresh machine), ask it what is missing with

```sh
FM_BOOTSTRAP_DETECT_ONLY=1 <firstmate>/bin/fm-bootstrap.sh
```

and hand exactly those names back to `fm-bootstrap.sh install`. The detect-only
flag matters: without it that same command runs firstmate's mutating startup
sweeps, which a machine bootstrap has no business triggering. Tools that report
as `MISSING_MANUAL:` are printed for you and never installed, because that call
fails by design.

The clone destination defaults to `~/github/mindcriminal/firstmate` and is
overridable with `FIRSTMATE_DIR`; the source with `FIRSTMATE_URL`. An existing
checkout is never pulled, reset or cleaned - it holds machine-local private
state that this repo has no business touching, and a fresh clone starting empty
is the correct outcome on a new machine.

Five of those tools install with `npm install -g`, which is why `home.nix`
declares `~/.npmrc` with npm's global prefix. Without it npm's prefix is the
read-only Nix store copy of nodejs, every one of those installs fails, and the
`~/.npm-global/bin` entry that `home.nix` puts on `PATH` points at a directory
npm never uses.

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
- `scripts/` - the Windows-boundary crossings (the WezTerm loader installer,
  run automatically on every switch, and the font installer, run by hand), plus
  the two seeders - `seed-claude-settings.sh` and `seed-handy-settings.sh` -
  which both `bootstrap.sh` and `rebuild.sh` run after the switch.
- `home/` - the actual config files that get symlinked into place. The one
  exception is `home/.claude/settings.json`, which is copied once as a seed;
  see [Claude's settings file](#claudes-settings-file). Handy's settings are
  not a file here at all - the seeder writes three keys into the store Handy
  owns on the Windows side.
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
