# herdr - "agent multiplexer that lives in your terminal" (https://herdr.dev).
#
# Not in nixpkgs, and the upstream Homebrew formula is the macOS path. Upstream
# publishes an official Linux x86_64 release binary, so this pins that exact
# artifact by hash instead of pulling in Homebrew-on-Linux.
#
# The binary is static-pie linked (verify with `file`), so it needs no
# autoPatchelfHook and no runtime library closure - just install it.
#
# To update: bump `version`, then run
#   nix hash convert --hash-algo sha256 --to sri \
#     "$(nix-prefetch-url https://github.com/herdrdev/herdr/releases/download/vVERSION/herdr-linux-x86_64)"
{ lib
, stdenvNoCC
, fetchurl
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "herdr";
  version = "0.8.2";

  src = fetchurl {
    url = "https://github.com/herdrdev/herdr/releases/download/v${finalAttrs.version}/herdr-linux-x86_64";
    hash = "sha256-l2FQoU1JDJSyQ+ouGn6y37Z/EuNrGC25CTb2co5q7PQ=";
  };

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/herdr"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    "$out/bin/herdr" --version
    runHook postInstallCheck
  '';

  meta = {
    description = "Agent multiplexer that lives in your terminal";
    homepage = "https://herdr.dev";
    license = lib.licenses.asl20;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "herdr";
  };
})
