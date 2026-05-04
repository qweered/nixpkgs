{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "rusholve";
  version = "0.1.0";

  src = ./source;
  cargoLock.lockFile = ./source/Cargo.lock;

  doCheck = false;

  meta = {
    description = "Rust port of resholve: shell-script command-reference resolver/rewriter for Nix";
    homepage = "https://github.com/qweered/rusholve";
    license = lib.licenses.mit;
    mainProgram = "rusholve";
    platforms = lib.platforms.unix;
  };
}
