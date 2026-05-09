{ lib, pkgs, ... }:
{
  name = "drbd-driver";
  meta.maintainers = with pkgs.lib.maintainers; [ birkb ];

  nodes = {
    machine =
      { config, pkgs, ... }:
      {
        boot = {
          kernel.modules = [ "drbd" ];
          extraModulePackages = with config.boot.kernel.packages; [ drbd ];
          kernel.packages = pkgs.linuxPackages;
        };
      };
  };

  testScript = ''
    machine.start();
    machine.succeed("modinfo drbd | grep --extended-regexp '^version:\s+${pkgs.linuxPackages.drbd.version}$'")
  '';
}
