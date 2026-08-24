{
  lib,
  stdenv,
  fetchFromGitHub,
  meson,
  ninja,
  windows,
  gitUpdater,
}:

# The nvapi DLLs are PE libraries loaded by Wine, so this is only ever built
# through pkgsCross; see ./package.nix for the pair that ships together.
stdenv.mkDerivation (finalAttrs: {
  pname = "dxvk-nvapi-unwrapped";
  version = "0.9.2";

  src = fetchFromGitHub {
    owner = "jp7677";
    repo = "dxvk-nvapi";
    tag = "v${finalAttrs.version}";
    # NVAPI, Vulkan and DirectX headers, plus vkroots for the Reflex layer.
    fetchSubmodules = true;
    hash = "sha256-VXDh8xWKYYD7fLRJgsAzjGxeqH91coo6x3rQEzLF4HY=";
  };

  strictDeps = true;

  nativeBuildInputs = [
    meson
    ninja
  ];

  buildInputs = [ windows.pthreads ];

  mesonBuildType = "release";

  passthru.updateScript = gitUpdater { rev-prefix = "v"; };

  meta = {
    description = "Alternative NVAPI implementation on top of DXVK";
    homepage = "https://github.com/jp7677/dxvk-nvapi";
    changelog = "https://github.com/jp7677/dxvk-nvapi/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ qweered ];
    platforms = lib.platforms.windows;
  };
})
