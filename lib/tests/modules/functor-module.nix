{
  config = { };

  __functor =
    _:
    { lib, ... }:
    let
      inherit (lib) mkOption;
    in
    {
      options.result = mkOption { };
      config.result = "called";
    };
}
