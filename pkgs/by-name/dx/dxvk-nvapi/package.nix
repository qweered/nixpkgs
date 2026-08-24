{
  lib,
  stdenvNoCC,
  callPackage,
  overrideCC,
  pkgsCross,
  enableReflexLayer ? stdenvNoCC.hostPlatform.isLinux,
}:

stdenvNoCC.mkDerivation (
  finalAttrs:
  let
    # Matching dxvk: the win32 thread model keeps libwinpthread out of the DLLs.
    useWin32ThreadModel =
      stdenv:
      overrideCC stdenv (
        stdenv.cc.override (old: {
          cc = old.cc.override {
            threadsCross = {
              model = "win32";
              package = null;
            };
          };
        })
      );

    nvapi32 = pkgsCross.mingw32.callPackage ./unwrapped.nix {
      stdenv = useWin32ThreadModel pkgsCross.mingw32.stdenv;
    };

    nvapi64 = pkgsCross.mingwW64.callPackage ./unwrapped.nix {
      stdenv = useWin32ThreadModel pkgsCross.mingwW64.stdenv;
    };

    reflexLayer = callPackage ./layer.nix { dxvk-nvapi-unwrapped = nvapi64; };
  in
  {
    pname = "dxvk-nvapi";
    inherit (nvapi64) version;

    strictDeps = true;
    __structuredAttrs = true;

    # Laid out the way wine front-ends install it: an x32/x64 pair of PE DLLs
    # to link into a prefix, next to nvapi's Vulkan implicit layer.
    buildCommand = ''
      mkdir -p "$out/bin"
      ln -s ${nvapi32}/bin "$out/bin/x32"
      ln -s ${nvapi64}/bin "$out/bin/x64"
    ''
    + lib.optionalString enableReflexLayer ''
      mkdir -p "$out/lib" "$out/share/vulkan"
      ln -s ${reflexLayer}/lib/* "$out/lib"
      ln -s ${reflexLayer}/share/vulkan/implicit_layer.d "$out/share/vulkan/implicit_layer.d"
    '';

    passthru = {
      inherit nvapi32 nvapi64 reflexLayer;
      inherit (nvapi64) updateScript;
    };

    meta = {
      inherit (nvapi64.meta)
        description
        homepage
        changelog
        license
        maintainers
        ;
      platforms = lib.platforms.windows ++ lib.platforms.linux;
    };
  }
)
