{
  lib,
  callPackage,
  steam,
  enableGamemode ? true,
  gamemode,
  enableGamescope ? true,
  gamescope,
  enableMangohud ? true,
  mangohud,
  enablePrefixBackup ? true,
  squashfsTools,
  enableX11 ? true,
  setxkbmap,
  xrandr,
  extraPkgs ? pkgs: [ ], # extra packages to add to targetPkgs
  extraLibraries ? pkgs: [ ], # extra packages to add to multiPkgs
  extraProfile ? "", # string to append to shell profile
  extraEnv ? { }, # environment variables to include in shell profile
  portprotonqt-unwrapped ? callPackage ./unwrapped.nix { },
}:

let
  # Every one of these is probed with `command -v` or shutil.which and the
  # feature switches itself off when missing, so they are safe to drop. The
  # system tab's nmcli and pactl are not listed: the runtime env already pulls
  # them in through steam's multiPkgs and qtmultimedia's closure.
  optionalPackages =
    lib.optionals enableGamemode [ gamemode ]
    ++ lib.optionals enableGamescope [ gamescope ]
    ++ lib.optionals enableMangohud [ mangohud ]
    ++ lib.optionals enablePrefixBackup [ squashfsTools ] # legacy prefix backups
    ++ lib.optionals enableX11 [
      setxkbmap
      xrandr
    ];
in
# PortProtonQt drives the same PortWINE scripts as portproton, so it runs games
# through the Steam Linux Runtime and needs the FHS environment Steam does.
steam.buildRuntimeEnv {
  pname = "portprotonqt";
  inherit (portprotonqt-unwrapped) version meta;

  extraPkgs = pkgs: [ portprotonqt-unwrapped ] ++ optionalPackages ++ extraPkgs pkgs;
  inherit
    extraLibraries
    extraProfile
    extraEnv
    ;

  # The GUI reads the running session's variables back out of
  # /tmp/PortProton_$USER/var.log, which a private /tmp would hide from
  # shortcuts launched as separate processes.
  privateTmp = false;

  executableName = portprotonqt-unwrapped.meta.mainProgram;
  runScript = lib.getExe portprotonqt-unwrapped;

  extraInstallCommands = ''
    ln -s ${portprotonqt-unwrapped}/share $out/share

    # For services.udev.packages and systemd sysusers.
    mkdir -p $out/lib
    ln -s ${portprotonqt-unwrapped}/lib/udev $out/lib/udev
    ln -s ${portprotonqt-unwrapped}/lib/sysusers.d $out/lib/sysusers.d
  '';

  passthru = {
    unwrapped = portprotonqt-unwrapped;
    inherit (portprotonqt-unwrapped.passthru) updateScript;
  };
}
