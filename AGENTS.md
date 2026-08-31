# Project notes for agents

This repo is a WSL2 / Rocky Linux 10 translation of the macOS setup in
[kunchenguid/dotfiles](https://github.com/kunchenguid/dotfiles)
(video: https://youtu.be/5N-okeDdIuI). When changing something, check what the
upstream repo does first, then decide whether the difference here is deliberate.

Deliberate decisions - do NOT silently revert them:

- **No nix-darwin, no NixOS module.** Rocky Linux is managed by dnf and Nix only
  owns this user's environment, so this is a *standalone* Home Manager flake.
  Do not restructure it into a NixOS configuration; this machine's system layer
  is not Nix-managed.
- **`claude-code` is deliberately not in `home.packages`,** even though nixpkgs
  has it. Claude Code here is the native self-updating install under
  `~/.local/share/claude`, which is usually ahead of the nixpkgs version. A Nix
  copy would come first on PATH, pin an older build, and fight the updater.
  The video gets it from a Homebrew cask, where that conflict does not arise.
- **`herdr` is pinned to an upstream release binary** in `pkgs/herdr.nix`, not
  built from source. It is a Homebrew formula upstream with no nixpkgs package.
  The artifact is static-pie linked, so it deliberately has no
  `autoPatchelfHook` and no runtime closure. Verify with `file` before assuming
  otherwise.
- **WezTerm's config is copied to the Windows side, not symlinked.** Windows
  cannot follow a Linux symlink. `scripts/install-windows-wezterm.sh` renders a
  loader that reads the real config back over `\\wsl.localhost`, which is what
  keeps edit-in-place working. Do not "simplify" it into a symlink or a plain
  copy of the whole config.
- **The Windows-side installer must never fail a switch.** It exits 0 with a
  message whenever Windows is unreachable (interop off, no `/mnt/c`, CI).
  `tests/wezterm.test.sh` enforces this.
- **`tests/lib.sh` diverges from upstream on purpose.** Upstream registers its
  cleanup trap and records temp dirs inside a command-substitution subshell,
  which both deletes directories early and leaks them. The `$BASHPID` guard and
  the registry file fix that; see the comment in the file.
- **`scripts/install-nerd-font.ps1` names each HKCU registry value per *face*,
  not per family.** Every face reports the same family name, so naming values
  after it makes each write overwrite the last: the family collapses to
  whichever style was written last and WezTerm reports no Regular face. The
  script now refuses to let two files claim one name. `tests/verify.sh` asks
  Windows whether a Regular face resolves, because files-on-disk passes even
  when this is broken.
- **The agent tools are firstmate's list, not this repo's.** `bootstrap.sh`
  step 7 clones firstmate and asks `bin/fm-bootstrap.sh` what is missing, then
  installs exactly what it names. Do not add `treehouse`, `no-mistakes` or the
  `*-axi` npm globals to `home.packages` or to any list here: firstmate owns
  both the roster and the version floors, and a second copy rots. The detect run
  must keep `FM_BOOTSTRAP_DETECT_ONLY=1`, or it performs firstmate's mutating
  startup sweeps. See the README's "Agent tooling" section for the rest.
- **`~/.claude/settings.json` is deliberately unmanaged.** Claude Code rewrites
  it itself, writing `settings.json.tmp.<pid>.<hash>` beside the *first* symlink
  hop before renaming it into place. Any `home.file` entry makes that first hop
  the read-only `/nix/store` copy, so every settings change fails with EACCES -
  `mkOutOfStoreSymlink` does not help, because the temp file never reaches the
  out-of-store target. `home/.claude/settings.json` is a first-install seed that
  `bootstrap.sh` step 6 *copies*, never over an existing regular file. The live
  file is expected to drift from the seed (herdr writes its hooks block there).
  Do not re-add it to `home.nix`; `tests/config.test.sh` fails if you do.
- **`home.nix` declares `~/.npmrc`.** Five of those tools are `npm install -g`,
  and without a declared prefix npm writes into the read-only Nix store. This
  replaced a hand-written file that nothing owned.
- **Upstream's `home/.pi/agent` layer is not ported.** Not a macOS
  incompatibility - it is upstream's own additive post-video layer for an
  opt-in CLI, and it was out of scope here. It would port cleanly if wanted.
  Do not treat its absence as an oversight to "fix" without asking.

## Conventions

- The host label is `wsl` and appears in three files that must agree:
  `flake.nix`, `rebuild.sh`, `bootstrap.sh`. `tests/config.test.sh` checks this.
- The username is declared once, in `flake.nix`, and threaded everywhere else.
- Run `./tests/run.sh` after changes; `nix develop -c ./tests/run.sh` also runs
  the Lua and shell linters.
- `nix build .#checks.x86_64-linux.home` proves the config still evaluates and
  builds without applying anything.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this
project. Do not repeat what the codebase already shows; point to the
authoritative file or command instead. Prefer rewriting or pruning existing
entries over appending new ones.
