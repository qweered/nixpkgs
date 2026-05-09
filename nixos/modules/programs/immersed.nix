{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.immersed;
in
{
  imports = [
    (lib.mkRenamedOptionModule
      [
        "programs"
        "immersed-vr"
      ]
      [
        "programs"
        "immersed"
      ]
    )
  ];

  options = {
    programs.immersed = {
      enable = lib.mkEnableOption "immersed";

      package = lib.mkPackageOption pkgs "immersed" { };
    };
  };

  config = lib.mkIf cfg.enable {
    boot = {
      kernel.modules = [
        "v4l2loopback"
        "snd-aloop"
      ];
      kernel.extraModulePackages = [ config.boot.kernel.packages.v4l2loopback ];
      modprobeConfig.extra = ''
        options v4l2loopback exclusive_caps=1 card_label="v4l2loopback Virtual Camera"
      '';
    };

    environment.systemPackages = [ cfg.package ];
  };

  meta.maintainers = pkgs.immersed.meta.maintainers;
}
