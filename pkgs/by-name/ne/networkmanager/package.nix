{
  lib,
  stdenv,
  fetchurl,
  replaceVars,
  gettext,
  pkg-config,
  dbus,
  gitUpdater,
  libuuid,
  polkit,
  gnutls,
  ppp,
  dhcpcd,
  iptables,
  nftables,
  python3,
  vala,
  libgcrypt,
  dnsmasq,
  bluez5,
  readline,
  libselinux,
  audit,
  gobject-introspection,
  perl,
  modemmanager,
  openresolv,
  libndp,
  newt,
  ethtool,
  gnused,
  iputils,
  kmod,
  jansson,
  elfutils,
  gtk-doc,
  libxslt,
  docbook_xsl,
  docbook_xml_dtd_412,
  docbook_xml_dtd_42,
  docbook_xml_dtd_43,
  curl,
  meson,
  mesonEmulatorHook,
  ninja,
  libnvme,
  libpsl,
  mobile-broadband-provider-info,
  runtimeShell,
  buildPackages,
  nixosTests,
  systemd,
  udev,
  udevCheckHook,
  clientOnly ? false,
  withSystemd ? lib.meta.availableOn stdenv.hostPlatform systemd,
  # NBFT (NVMe Boot Firmware Table) support, opt-in due to closure size
  # https://github.com/NixOS/nixpkgs/pull/446121#discussion_r2380598419
  withNbft ? false,
}:

let
  pythonForDocs = python3.pythonOnBuildForHost.withPackages (pkgs: with pkgs; [ pygobject3 ]);

  # Upstream does not provide a client-only build option. Keep the target and
  # install details with NetworkManager so source updates review them together.
  clientBuildPhase = ''
    runHook preBuild

    meson compile --jobs "$NIX_BUILD_CORES" nm nm-libnm-helper

    runHook postBuild
  '';

  clientInstallPhase = ''
    runHook preInstall

    mkdir -p "$out/lib" "$out/libexec"
    cp -a src/libnm-client-impl/libnm.so* "$out/lib/"
    cp src/nm-helpers/nm-libnm-helper "$out/libexec/"

    runHook postInstall
  '';
in
stdenv.mkDerivation (finalAttrs: {
  pname = if clientOnly then "libnm" else "networkmanager";
  version = "1.56.0";

  src = fetchurl {
    url = "https://gitlab.freedesktop.org/NetworkManager/NetworkManager/-/releases/${finalAttrs.version}/downloads/NetworkManager-${finalAttrs.version}.tar.xz";
    hash = "sha256-WaMtOFzB564m5DeYxvEtB/9hmKvQQewGILOgjPwCHMw=";
  };

  outputs =
    if clientOnly then
      [ "out" ]
    else
      [
        "out"
        "dev"
        "devdoc"
        "man"
        "doc"
      ];

  # Right now we hardcode quite a few paths at build time. Probably we should
  # patch networkmanager to allow passing these path in config file. This will
  # remove unneeded build-time dependencies.
  mesonFlags = [
    # System paths
    "--sysconfdir=/etc"
    "--localstatedir=/var"
    (lib.mesonOption "systemdsystemunitdir" (
      if withSystemd then "${placeholder "out"}/etc/systemd/system" else "no"
    ))
    # to enable link-local connections
    "-Dudev_dir=${placeholder "out"}/lib/udev"
    "-Ddbus_conf_dir=${placeholder "out"}/share/dbus-1/system.d"
    "-Dkernel_firmware_dir=/run/current-system/firmware"

    # Platform
    "-Dmodprobe=${kmod}/bin/modprobe"
    (lib.mesonOption "session_tracking" (if withSystemd then "systemd" else "no"))
    (lib.mesonBool "systemd_journal" withSystemd)
    "-Dlibaudit=yes-disabled-by-default"
    "-Dpolkit_agent_helper_1=/run/wrappers/bin/polkit-agent-helper-1"

    # Features
    # Allow using iwd when configured to do so
    "-Diwd=true"
    "-Dpppd=${ppp}/bin/pppd"
    "-Diptables=${iptables}/bin/iptables"
    "-Dnft=${nftables}/bin/nft"
    "-Dmodem_manager=true"
    "-Dnmtui=true"
    "-Ddnsmasq=${dnsmasq}/bin/dnsmasq"
    "-Dqt=false"
    (lib.mesonBool "nbft" withNbft)

    # Handlers
    "-Dresolvconf=${openresolv}/bin/resolvconf"

    # DHCP clients
    "-Ddhcpcd=${dhcpcd}/bin/dhcpcd"

    # Miscellaneous
    # almost cross-compiles, however fails with
    # ** (process:9234): WARNING **: Failed to load shared library '/nix/store/...-networkmanager-aarch64-unknown-linux-gnu-1.38.2/lib/libnm.so.0' referenced by the typelib: /nix/store/...-networkmanager-aarch64-unknown-linux-gnu-1.38.2/lib/libnm.so.0: cannot open shared object file: No such file or directory
    "-Ddocs=${lib.boolToString (stdenv.buildPlatform == stdenv.hostPlatform)}"
    "-Dman=${lib.boolToString (stdenv.buildPlatform == stdenv.hostPlatform)}"
    "-Dtests=no"
    "-Dcrypto=gnutls"
    "-Dmobile_broadband_provider_info_database=${mobile-broadband-provider-info}/share/mobile-broadband-provider-info/serviceproviders.xml"
  ]
  ++ lib.optionals clientOnly [
    "-Ddocs=false"
    "-Dintrospection=false"
    "-Dman=false"
    "-Dtests=no"
    "-Dvapi=false"
  ];

  patches = [
    (replaceVars ./fix-paths.patch {
      inherit
        iputils
        ethtool
        gnused
        ;
      inherit runtimeShell;
    })

    # Meson does not support using different directories during build and
    # for installation like Autotools did with flags passed to make install.
    ./fix-install-paths.patch
  ];

  buildInputs = [
    (if withSystemd then systemd else udev)
    libselinux
    audit
    libpsl
    libuuid
    polkit
    ppp
    libndp
    curl
    mobile-broadband-provider-info
    bluez5
    dnsmasq
    modemmanager
    readline
    newt
    jansson
    dbus # used to get directory paths with pkg-config during configuration
  ]
  ++ lib.optionals clientOnly [
    gnutls
    libgcrypt
  ]
  ++ lib.optionals withNbft [
    libnvme
  ];

  propagatedBuildInputs = lib.optionals (!clientOnly) [
    gnutls
    libgcrypt
  ];

  nativeBuildInputs = [
    meson
    ninja
    gettext
    pkg-config
    vala
    gobject-introspection
    perl
    elfutils # used to find jansson soname
    # Docs
    gtk-doc
    libxslt
    docbook_xsl
    docbook_xml_dtd_412
    docbook_xml_dtd_42
    docbook_xml_dtd_43
    pythonForDocs
    udevCheckHook
  ]
  ++ lib.optionals (!stdenv.buildPlatform.canExecute stdenv.hostPlatform) [
    mesonEmulatorHook
  ];

  doCheck = false; # requires /sys, the net

  postPatch = ''
    patchShebangs ./tools
    patchShebangs libnm/generate-setting-docs.py

    # TODO: submit upstream
    substituteInPlace meson.build \
      --replace "'vala', req" "'vala', native: false, req"
  ''
  + lib.optionalString withSystemd ''
    substituteInPlace data/NetworkManager.service.in \
      --replace-fail /usr/bin/busctl ${systemd}/bin/busctl
  '';

  preBuild = lib.optionalString (!clientOnly) ''
    # Our gobject-introspection patches make the shared library paths absolute
    # in the GIR files. When building docs, the library is not yet installed,
    # though, so we need to replace the absolute path with a local one during build.
    # We are using a symlink that will be overridden during installation.
    mkdir -p ${placeholder "out"}/lib
    ln -s $PWD/src/libnm-client-impl/libnm.so.0 ${placeholder "out"}/lib/libnm.so.0
  '';

  buildPhase = if clientOnly then clientBuildPhase else null;

  installPhase = if clientOnly then clientInstallPhase else null;

  postFixup = lib.optionalString (!clientOnly && stdenv.buildPlatform != stdenv.hostPlatform) ''
    cp -r ${buildPackages.networkmanager.devdoc} $devdoc
    cp -r ${buildPackages.networkmanager.man} $man
  '';

  doInstallCheck = !clientOnly;

  passthru = lib.optionalAttrs (!clientOnly) {
    updateScript = gitUpdater {
      odd-unstable = true;
      url = "https://gitlab.freedesktop.org/NetworkManager/NetworkManager.git";
    };
    tests = {
      inherit (nixosTests.networking) networkmanager;
    };
  };

  meta = {
    homepage = "https://networkmanager.dev";
    description =
      if clientOnly then
        "Client library for NetworkManager"
      else
        "Network configuration and management tool";
    license = if clientOnly then lib.licenses.lgpl21Plus else lib.licenses.gpl2Plus;
    changelog = "https://gitlab.freedesktop.org/NetworkManager/NetworkManager/-/raw/${finalAttrs.version}/NEWS";
    maintainers = with lib.maintainers; [
      obadz
    ];
    teams = [ lib.teams.freedesktop ];
    platforms = lib.platforms.linux;
    badPlatforms = [
      # Mandatory shared libraries.
      lib.systems.inspect.platformPatterns.isStatic
    ];
    identifiers.cpeParts = lib.meta.cpeFullVersionWithVendor "gnome" finalAttrs.version;
  };
})
