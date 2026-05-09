{
  config,
  lib,
  ...
}:

let
  cfg = config.hardware.sheep_net;
in
{
  options.hardware.sheep_net = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enables sheep_net udev rules, ensures 'sheep_net' group exists, and adds
        sheep-net to boot.kernel.modules and boot.extraModulePackages
      '';
    };
  };
  config = lib.mkIf cfg.enable {
    services.udev.extraRules = ''
      KERNEL=="sheep_net", GROUP="sheep_net"
    '';
    boot.kernel.modules = [
      "sheep_net"
    ];
    boot.extraModulePackages = [
      config.boot.kernel.packages.sheep-net
    ];
    users.groups.sheep_net = { };
  };
  meta.maintainers = with lib.maintainers; [ matthewcroughan ];
}
