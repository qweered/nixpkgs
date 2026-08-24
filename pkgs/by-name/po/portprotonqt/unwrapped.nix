{
  lib,
  callPackage,
  python3Packages,
  fetchFromGitHub,
  gettext,
  installShellFiles,
  meson,
  ninja,
  pkg-config,
  qt6,
  sdl3,
  vulkan-headers,
  vulkan-loader,
  bash,
  cabextract,
  coreutils,
  curl,
  desktop-file-utils,
  file,
  findutils,
  gawk,
  glib,
  gnugrep,
  gnused,
  gnutar,
  gzip,
  mesa-demos,
  p7zip,
  pciutils,
  perlPackages,
  procps,
  psmisc,
  unzip,
  util-linux,
  xdg-utils,
  xz,
  zstd,
  nix-update-script,
  portprotonqt-runtime ? callPackage ./runtime.nix { },
}:

let
  # Looked up on PATH by the bundled PortWINE scripts and by the GUI itself.
  # Optional tools are added by the wrapper instead, see ./package.nix.
  runtimeDeps = [
    bash
    cabextract # for the winetricks that functions_helper downloads
    coreutils
    curl
    desktop-file-utils
    file
    findutils
    gawk
    glib
    gnugrep
    gnused
    gnutar
    gzip
    mesa-demos
    p7zip
    pciutils
    perlPackages.ImageExifTool
    procps
    psmisc
    unzip
    util-linux
    xdg-utils
    xz
    zstd
  ];
in
python3Packages.buildPythonApplication (finalAttrs: {
  pname = "portprotonqt-unwrapped";
  version = "1.4.0";

  # Built with meson, not a python format.
  pyproject = false;

  src = fetchFromGitHub {
    owner = "Boria138";
    repo = "PortProtonQt";
    tag = "v${finalAttrs.version}";
    hash = "sha256-855fd+2zvAzFgq5fXLr3RAeyIw/TUzxhDJ1VjPnBB34=";
  };

  nativeBuildInputs = [
    gettext
    installShellFiles
    meson
    ninja
    pkg-config
    qt6.wrapQtAppsHook
  ];

  buildInputs = [
    # patchShebangs resolves the PortWINE scripts' interpreter from buildInputs.
    bash
    qt6.qtbase
    qt6.qtimageformats
    qt6.qtmultimedia
    qt6.qtsvg
    qt6.qtwayland
    sdl3
    vulkan-headers
    vulkan-loader
  ];

  dependencies = with python3Packages; [
    babel
    dbus-fast
    evdev
    libarchive-c
    orjson
    pefile
    pillow
    psutil
    pyside6
    qrcode
    rapidfuzz
    requests
    tqdm
    vdf
    websocket-client
  ];

  postPatch = ''
    # Reuse the translation layers Nix fetched instead of downloading them.
    install -Dm644 ${./seed-runtime.sh} \
      build-aux/share/portproton/scripts/seed_nix_runtime
    substituteInPlace build-aux/share/portproton/scripts/seed_nix_runtime \
      --subst-var-by runtime ${portprotonqt-runtime}
    substituteInPlace build-aux/share/portproton/scripts/start.sh \
      --replace-fail 'create_new_dir "''${PW_VULKAN_DIR}"' \
                     'create_new_dir "''${PW_VULKAN_DIR}" ; source "''${PORT_SCRIPTS_PATH}/seed_nix_runtime"'

    # Both lookups default to an FHS prefix that only exists inside the wrapper.
    substituteInPlace portprotonqt/localization.py \
      --replace-fail '"SHARUN_DIR", "/usr"' '"SHARUN_DIR", "@out@"'
    substituteInPlace portprotonqt/config/portproton.py \
      --replace-fail '("system package", Path("/usr"))' '("system package", Path("@out@"))'
    substituteInPlace portprotonqt/localization.py portprotonqt/config/portproton.py \
      --subst-var out
  '';

  mesonFlags = [
    (lib.mesonOption "python_purelibdir" "${placeholder "out"}/${python3Packages.python.sitePackages}")
    (lib.mesonOption "udev_rulesdir" "${placeholder "out"}/lib/udev/rules.d")
  ];

  # The meson setup hook leaves the build directory as the working directory.
  postInstall = ''
    pushd ..
    bash dev-scripts/generate-completions.sh
    installShellCompletion --cmd portprotonqt \
      --bash completions/portprotonqt \
      --fish completions/portprotonqt.fish \
      --zsh completions/_portprotonqt
    popd
  '';

  # wrapQtAppsHook skips python scripts, so pass its arguments along by hand.
  preFixup = ''
    makeWrapperArgs+=(
      "''${qtWrapperArgs[@]}"
      --prefix PATH : "${lib.makeBinPath runtimeDeps}"
      --suffix PATH : "$out/bin"
    )
  '';

  passthru = {
    runtime = portprotonqt-runtime;
    updateScript = nix-update-script { attrPath = "portprotonqt.unwrapped"; };
  };

  meta = {
    description = "Modern GUI for managing and launching games from PortProton and Steam";
    longDescription = ''
      PortProtonQt is a PySide6 rewrite of the PortProton (PortWINE) front-end.

      Proton builds, DXVK, VKD3D and the Steam Linux Runtime are not part of
      this package: PortProton downloads them into its data directory on first
      use.
    '';
    homepage = "https://github.com/Boria138/PortProtonQt";
    changelog = "https://github.com/Boria138/PortProtonQt/releases/tag/v${finalAttrs.version}";
    license = with lib.licenses; [
      gpl3Plus
      mit # icoextract and the bundled portproton scripts
      # ./runtime.nix seeds prebuilt dxvk and vkd3d-proton DLLs.
      zlib
      lgpl21Plus
    ];
    mainProgram = "portprotonqt";
    maintainers = with lib.maintainers; [ qweered ];
    platforms = [ "x86_64-linux" ];
  };
})
