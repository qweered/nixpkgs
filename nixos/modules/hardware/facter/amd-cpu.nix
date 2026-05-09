{ lib, config, ... }:
let
  facterLib = import ./lib.nix lib;

  inherit (config.hardware.facter) report;
  isBaremetal = config.hardware.facter.detected.virtualisation.none.enable;
  hasAmdCpu = facterLib.hasAmdCpu report;

  kver = config.boot.kernel.packages.kernel.version;
in
lib.mkIf (config.hardware.facter.enable && isBaremetal && hasAmdCpu) {
  boot.kernel = lib.mkMerge [
    (lib.mkIf ((lib.versionAtLeast kver "5.17") && (lib.versionOlder kver "6.1")) {
      params = [ "initcall_blacklist=acpi_cpufreq_init" ];
      modules = [ "amd-pstate" ];
    })
    (lib.mkIf ((lib.versionAtLeast kver "6.1") && (lib.versionOlder kver "6.3")) {
      params = [ "amd_pstate=passive" ];
    })
    (lib.mkIf (lib.versionAtLeast kver "6.3") {
      params = [ "amd_pstate=active" ];
    })
  ];
}
