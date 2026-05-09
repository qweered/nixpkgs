{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (lib) mkEnableOption mkIf;
  inherit (config.boot.kernel.packages) tt-kmd;

  cfg = config.hardware.tenstorrent;
in
{
  options.hardware.tenstorrent.enable = mkEnableOption "Tenstorrent driver & utilities";

  config = mkIf cfg.enable {
    boot = {
      kernel.extraModulePackages = [ tt-kmd ];
      kernel.modules = [ "tenstorrent" ];
    };

    services.udev.packages = [
      tt-kmd
    ];

    environment.systemPackages = with pkgs; [
      tt-smi
      tt-system-tools
    ];
  };

  meta.maintainers = with lib.maintainers; [ RossComputerGuy ];
}
