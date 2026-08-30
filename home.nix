{ config, pkgs, lib, user, ... }:

let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
in

{
  home.username = user;
  home.homeDirectory = "/home/${user}";  # /Users/${user} on macOS
  home.stateVersion = "24.11";

  home.packages = with pkgs; [
    # cli i use constantly
    ripgrep   # fast search
    fd        # fast find
    fzf       # fuzzy finder
    jq        # json on the command line
    lazygit
    neovim
    # agent multiplexer - Homebrew formula upstream, packaged in pkgs/herdr.nix here
    herdr
    # the font everything renders in.
    # WSL side only: the Windows terminal needs its own copy, see
    # scripts/install-nerd-font.ps1
    nerd-fonts.hack
    nodejs_22
    gh
  ];
  # The standalone counterpart of darwin-rebuild existing after the first
  # switch: this puts the `home-manager` command on PATH for rebuild.sh.
  programs.home-manager.enable = true;

  fonts.fontconfig.enable = true;
  home.sessionVariables.EDITOR = "nvim";

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;      # ghost text from history
    syntaxHighlighting.enable = true;  # commands turn green when valid
    initContent = ''
      # Ensure Home Manager user packages take precedence over system/WSL packages
      export PATH="$HOME/.npm-global/bin:$HOME/.nix-profile/bin:/etc/profiles/per-user/$USER/bin:$PATH"

      bindkey '^f' autosuggest-accept

      # Determinate Nix drops its profile script in /etc/profile.d, which zsh
      # does not read on Rocky. Without this a non-login zsh has no `nix`.
      if [ -z "''${__NIX_PROFILE_SOURCED:-}" ] && ! command -v nix >/dev/null 2>&1; then
        if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
          . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
          export __NIX_PROFILE_SOURCED=1
        fi
      fi

    # Ensure emacs mode is active for standard readline shortcuts (Ctrl+A, Ctrl+E, Ctrl+R)
    bindkey -e

    # Bind Ctrl+R to incremental pattern search backwards
    bindkey '^R' history-incremental-pattern-search-backward
    
    # Keep the Ctrl+F autosuggest accept from the video
    bindkey '^F' autosuggest-accept
  '';

    shellAliases = {
      ".." = "cd ..";
      add = "git add .";
      push = "git push";
      pull = "git pull";
      m = "git switch main";
      # High-agency shortcuts, exactly as in the video. Know what they do.
      cc = "claude --dangerously-skip-permissions";
      co = "codex --full-auto";
    };
  };

  # Also carried over from .bashrc. sessionPath lands in hm-session-vars.sh,
  # which both zsh and bash source, so these survive a shell switch.
  home.sessionPath = [
    "$HOME/.npm-global/bin"
    "$HOME/.local/bin"
    "$HOME/.local/share/pi-node/node-v22.23.2-linux-x64/bin"
  ];

  # npm's global prefix, which nothing used to own: this was a hand-written
  # ~/.npmrc. Both PATH entries above point at ~/.npm-global/bin, and firstmate
  # installs several of its tools with `npm install -g`. Without this, npm's
  # prefix is the read-only Nix store copy of nodejs, so those installs fail and
  # the bin directory on PATH stays empty.
  home.file.".npmrc".text = ''
    prefix=${config.home.homeDirectory}/.npm-global
  '';

  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      format = "$directory$git_branch$git_status$cmd_duration$line_break$character";
      character = {
        success_symbol = "[❯](purple)";
        error_symbol = "[❯](red)";
      };
      cmd_duration.format = "[$duration]($style) ";
    };
  };

  # Edit-in-place: the real file stays in my repo, ~/.config just points at it.
  home.file.".config/wezterm".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/wezterm";
  home.file.".config/nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/nvim";
  home.file.".config/herdr".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/herdr";
  home.file.".claude/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.claude/settings.json";

  home.file.".claude/CLAUDE.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".codex/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".config/opencode/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".pi/agent/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".gemini/GEMINI.md".source = 
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
}
