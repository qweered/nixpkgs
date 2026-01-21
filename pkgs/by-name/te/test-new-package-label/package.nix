{
  lib,
  stdenv,
}:
stdenv.mkDerivation {
  pname = "test-new-package-label";
  version = "0.0.1";

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    echo "#!/bin/sh" > $out/bin/test-new-package-label
    echo "echo hello" >> $out/bin/test-new-package-label
    chmod +x $out/bin/test-new-package-label
    runHook postInstall
  '';

  meta = {
    description = "Test package for CI label automation";
    license = lib.licenses.mit;
    maintainers = [ ];
    platforms = lib.platforms.all;
  };
}
