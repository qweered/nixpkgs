{
  lib,
  fetchzip,
  runCommand,
}:

# PortProton downloads its Vulkan translation layers into the user's data
# directory on first launch. These are upstream's own prebuilt PE DLLs rather
# than the nixpkgs builds: `dxvk` does not ship the bundled dxvk-nvapi DLLs
# PortProton links into prefixes, and `vkd3d-proton` builds native .so
# libraries instead of DLLs. Names must match the versions declared in
# `build-aux/share/portproton/scripts/var`.
let
  bundle =
    name: hash:
    fetchzip {
      name = "portprotonqt-${name}";
      url = "https://github.com/Castro-Fidel/vulkan/releases/download/${name}/${name}.tar.xz";
      inherit hash;
    };

  bundles = {
    "dxvk-2.7.1-509" = "sha256-q3JyIol2qLD1CNzfdunkZtItXfTyiJFl2P9ksa/GA4Q=";
    "dxvk-2.6.2" = "sha256-t++/f+7Rnrf6BUhQRV9SujPIBNDlj2rXzGvTKxQJI+E=";
    "dxvk-sarek-1.11.0" = "sha256-KHqV1NCx65pXOl0jpthmFZBPWW/1ygwN5fX9DpT55aw=";
    "vkd3d-proton-1.1-5122" = "sha256-Qm3gEWaH7JAADUQcdeMrCCEfZGXKq8CUhi+wrKA/2s0=";
    "vkd3d-proton-2.14.1" = "sha256-YFjM+yA9z5enBp1hWwjF6+6rb0nfn1icWkr58ACbBdM=";
    "vkd3d-proton-sarek-2.6.0" = "sha256-91X3uznyrSLrrB0UcbsoX3Ur+JjjHUqh347TewwB+N0=";
  };
in
runCommand "portprotonqt-runtime"
  {
    passthru.bundleNames = lib.attrNames bundles;

    meta = {
      description = "Prebuilt Vulkan translation layers seeded into PortProtonQt's data directory";
      license = with lib.licenses; [
        zlib # dxvk
        lgpl21Plus # vkd3d-proton
      ];
      sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
      maintainers = with lib.maintainers; [ qweered ];
      platforms = [ "x86_64-linux" ];
    };
  }
  (
    ''
      mkdir -p "$out/VULKAN"
    ''
    + lib.concatLines (
      lib.mapAttrsToList (name: hash: ''
        ln -s ${bundle name hash} "$out/VULKAN/${name}"
      '') bundles
    )
  )
