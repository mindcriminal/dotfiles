# Packages this repo adds on top of nixpkgs.
#
# On macOS the video gets herdr from Homebrew. There is no Homebrew layer here,
# so anything nixpkgs does not carry is packaged in pkgs/ and injected through
# this overlay instead.
final: prev: {
  herdr = final.callPackage ./pkgs/herdr.nix { };
}
