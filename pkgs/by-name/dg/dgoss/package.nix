{
  coreutils,
  gnused,
  goss,
  lib,
  which,
  writeResolvedShellApplication,
}:

writeResolvedShellApplication {
  pname = "dgoss";
  inherit (goss) version src;

  # Pin the bundled `goss` binary as the default for `$GOSS_PATH`. The
  # original line 2 is blank, so `2i` inserts above the blank and
  # leaves `set -e` on its original logical position.
  postPatch = ''
    sed -i '2i GOSS_PATH=''${GOSS_PATH:-${goss}/bin/goss}' extras/dgoss/dgoss
  '';

  installScripts."extras/dgoss/dgoss" = "bin/dgoss";

  # `$CONTAINER_RUNTIME` is the user's chosen container runtime (docker / podman)
  rusholveFlags = [
    "--skip"
    "$CONTAINER_RUNTIME"
  ];

  buildInputs = [
    coreutils
    gnused
    which
  ];

  meta = {
    homepage = "https://github.com/goss-org/goss/blob/v${goss.version}/extras/dgoss/README.md";
    changelog = "https://github.com/goss-org/goss/releases/tag/v${goss.version}";
    description = "Convenience wrapper around goss that aims to bring the simplicity of goss to docker containers";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
    maintainers = with lib.maintainers; [
      hyzual
      anthonyroussel
    ];
    mainProgram = "dgoss";
  };
}
