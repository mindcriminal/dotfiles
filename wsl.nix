{ config, lib, ... }:

# The WSL2 counterpart of the video's configuration.nix.
#
# On macOS that file holds system-level state: `system.defaults` (dark mode,
# dock, Finder, trackpad) and the Homebrew package list, applied by nix-darwin
# as root. Neither has an equivalent here:
#
#   * There is no nix-darwin for a non-NixOS Linux host. Rocky Linux itself is
#     managed by dnf, and Nix only owns this user's environment.
#   * The system-level WSL knobs live in /etc/wsl.conf, which is root-owned and
#     outside Home Manager's reach. This repo tracks the intended contents in
#     system/wsl.conf, and bootstrap.sh installs it with sudo after showing you
#     the diff.
#   * There is no Homebrew layer, so no `cleanup = "zap"` either. Every package
#     is declared in home.nix, and anything nixpkgs lacks is packaged in pkgs/.
#
# What is left that is genuinely WSL-specific is the Windows boundary: the
# terminal emulator runs on the Windows side of that boundary.

let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
  installer = "${dotfiles}/scripts/install-windows-wezterm.sh";
in
{
  # WezTerm is a Windows program, so it cannot be symlinked into place like
  # every other config here. This renders a small loader onto the Windows side
  # that reads the real wezterm.lua back out of WSL, which preserves
  # edit-in-place: change the .lua in this repo, press Ctrl+Shift+R, done.
  #
  # The script no-ops with a message (never an error) when Windows is not
  # reachable - interop disabled, /mnt/c not mounted, running in CI - so a
  # switch never fails just because the Windows side is unavailable.
  home.activation.windowsWezterm = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    verboseEcho "Installing the Windows-side WezTerm loader"
    if [ -x "${installer}" ]; then
      # Home Manager seals the activation PATH to Nix store tools only. wslpath
      # is a WSL system binary in /usr/bin, so without this the installer's
      # first guard concludes it is not running under WSL and skips - silently,
      # because skipping is the correct behaviour off-WSL. Appended, not
      # prepended, so the Nix coreutils/sed/grep still win.
      PATH="$PATH:/usr/bin" run "${installer}"
    else
      echo "wezterm: skipped - ${installer} not found (is ~/.dotfiles linked?)" >&2
    fi
  '';
}
