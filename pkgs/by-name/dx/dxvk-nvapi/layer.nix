{
  lib,
  stdenv,
  meson,
  ninja,
  vulkan-headers,
  dxvk-nvapi-unwrapped,
}:

# NVIDIA Reflex is driven from the host Vulkan loader rather than from inside
# the prefix, so this half is a native implicit layer rather than a DLL.
stdenv.mkDerivation {
  pname = "dxvk-nvapi-vkreflex-layer";
  inherit (dxvk-nvapi-unwrapped) version src;

  # layer/meson.build reads ../version.h.in and ../external, so the whole tree
  # has to be unpacked even though only the subdirectory is configured.
  sourceRoot = "${dxvk-nvapi-unwrapped.src.name}/layer";

  strictDeps = true;

  nativeBuildInputs = [
    meson
    ninja
  ];

  buildInputs = [ vulkan-headers ];

  mesonBuildType = "release";

  meta = {
    description = "Vulkan implicit layer providing NVIDIA Reflex support for dxvk-nvapi";
    inherit (dxvk-nvapi-unwrapped.meta)
      homepage
      changelog
      license
      maintainers
      ;
    platforms = lib.platforms.linux;
  };
}
