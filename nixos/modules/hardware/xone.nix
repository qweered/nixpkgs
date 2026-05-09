{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.xone;
in
{
  options.hardware.xone = {
    enable = lib.mkEnableOption "the xone driver for Xbox One and Xbox Series X|S accessories";
  };

  config = lib.mkIf cfg.enable {
    boot = {
      kernel.blacklistedModules = [
        "xpad"
        "mt76x2u"
      ];
      extraModulePackages = with config.boot.kernel.packages; [ xone ];
    };
    hardware.firmware = [ pkgs.xone-dongle-firmware ];
    hardware.xpad-noone.enable = lib.mkDefault true;
  };

  meta = {
    maintainers = with lib.maintainers; [ rhysmdnz ];
  };
}
