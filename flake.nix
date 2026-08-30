{
  description = "dotfiles - WSL2 / Rocky Linux 10";

  inputs = {
    # Linux counterpart of the video's nixpkgs-26.05-darwin branch.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, home-manager }:
    let
      # The one username line to change if this isn't your machine.
      # bootstrap.sh offers to rewrite this for you if your Linux username differs.
      user = "mindcriminal";

      system = "x86_64-linux";

      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [ (import ./overlay.nix) ];
      };
    in
    {
      # There is no nix-darwin here. On WSL2 the host OS is Rocky Linux, managed
      # by dnf, and Nix is only a package manager on top of it - so the whole
      # config is a standalone Home Manager configuration. "wsl" is the host
      # label, the counterpart of the video's "mac".
      homeConfigurations."wsl" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = { inherit user; };
        modules = [
          ./home.nix
          ./wsl.nix
        ];
      };

      packages.${system} = {
        inherit (pkgs) herdr;
        default = self.homeConfigurations."wsl".activationPackage;
      };

      # `nix flake check` builds this, so a broken config fails before it is applied.
      checks.${system}.home = self.homeConfigurations."wsl".activationPackage;

      formatter.${system} = pkgs.nixpkgs-fmt;

      # `nix develop` gives ./tests/run.sh its optional linters: without lua the
      # Lua syntax checks skip rather than fail.
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [ lua shellcheck nixpkgs-fmt ];
      };
    };
}
