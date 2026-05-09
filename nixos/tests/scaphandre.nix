{
  name = "scaphandre";

  nodes.scaphandre =
    { pkgs, ... }:
    {
      boot.kernel.modules = [ "intel_rapl_common" ];

      environment.systemPackages = [ pkgs.scaphandre ];
    };

  testScript = ''
    scaphandre.start()
    scaphandre.wait_until_succeeds(
        "scaphandre stdout -t 4",
    )
  '';
}
