{
  lib,
  stdenv,
  wrapCCWith,
  overrideCC,
  zig,
  version,
  src,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "arocc";
  inherit version src;

  nativeBuildInputs = [ zig ];

  passthru = {
    inherit zig;
    isArocc = true;
    # Aro implements a subset of the GCC/Clang warning options, so the
    # OpenSSF diagnostics set is not safely applicable here yet.
    hardeningUnsupportedFlags = [
      "securitywarnings"
      "nowerror"
      "nodeletenullpointerchecks"
    ];
    wrapped = wrapCCWith { cc = finalAttrs.finalPackage; };
    stdenv = overrideCC stdenv finalAttrs.passthru.wrapped;
  };

  meta = {
    description = "C compiler written in Zig";
    homepage = "http://aro.vexu.eu/";
    license = with lib.licenses; [
      mit
      unicode-30
    ];
    maintainers = with lib.maintainers; [ RossComputerGuy ];
    mainProgram = "arocc";
  };
})
