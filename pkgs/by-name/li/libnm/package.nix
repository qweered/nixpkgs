{ callPackage }:

callPackage ../../ne/networkmanager/package.nix {
  clientOnly = true;
  withSystemd = false;
}
