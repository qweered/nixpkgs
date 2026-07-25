{
  lib,
  stdenv,
  runCommand,
  runCommandWith,
  runCommandCC,
  writeText,
  bintools,
  hello,
  debian-devscripts,
}:

let
  # writeCBin from trivial-builders won't let us choose
  # our own stdenv
  writeCBinWithStdenv =
    codePath: stdenv': env:
    runCommandWith
      {
        name = "test-bin";
        stdenv = stdenv';
        derivationArgs = {
          inherit codePath;
          preferLocalBuild = true;
          allowSubstitutes = false;
        }
        // env;
      }
      ''
        [ -n "$postConfigure" ] && eval "$postConfigure"
        [ -n "$preBuild" ] && eval "$preBuild"
        n=$out/bin/test-bin
        mkdir -p "$(dirname "$n")"
        cp "$codePath" .
        NIX_DEBUG=1 $CC -x ''${TEST_SOURCE_LANG:-c} "$(basename $codePath)" -O1 $TEST_EXTRA_FLAGS -o "$n"
      '';

  f1exampleWithStdEnv = writeCBinWithStdenv ./fortify1-example.c;
  f2exampleWithStdEnv = writeCBinWithStdenv ./fortify2-example.c;
  f3exampleWithStdEnv = writeCBinWithStdenv ./fortify3-example.c;

  flexArrF2ExampleWithStdEnv = writeCBinWithStdenv ./flex-arrays-fortify-example.c;

  # we don't really have a reliable property for testing for
  # libstdc++ we'll just have to check for the absence of libcxx
  checkGlibcxxassertionsWithStdEnv =
    expectDefined: stdenv': derivationArgs:
    brokenIf (stdenv.cc.libcxx != null) (
      writeCBinWithStdenv
        (writeText "main.cpp" ''
          #if${if expectDefined then "n" else ""}def _GLIBCXX_ASSERTIONS
          #error "Expected _GLIBCXX_ASSERTIONS to be ${if expectDefined then "" else "un"}defined"
          #endif
          int main() {}
        '')
        stdenv'
        (
          derivationArgs
          // {
            env = (derivationArgs.env or { }) // {
              TEST_SOURCE_LANG = derivationArgs.env.TEST_SOURCE_LANG or "c++";
            };
          }
        )
    );

  checkLibcxxHardeningWithStdEnv =
    expectValue: stdenv': env:
    brokenIf (stdenv.cc.libcxx == null) (
      writeCBinWithStdenv
        (writeText "main.cpp" (
          ''
            #include <limits>
            #ifndef _LIBCPP_HARDENING_MODE
            #error "Expected _LIBCPP_HARDENING_MODE to be defined"
            #endif
            #ifndef ${expectValue}
            #error "Expected ${expectValue} to be defined"
            #endif

            #if _LIBCPP_HARDENING_MODE != ${expectValue}
            #error "Expected _LIBCPP_HARDENING_MODE to equal ${expectValue}"
            #endif
          ''
          + ''
            int main() {}
          ''
        ))
        stdenv'
        (
          env
          // {
            env = (env.env or { }) // {
              TEST_SOURCE_LANG = env.env.TEST_SOURCE_LANG or "c++";
            };
          }
        )
    );

  # for when we need a slightly more complicated program
  helloWithStdEnv =
    stdenv': env:
    (hello.override { stdenv = stdenv'; }).overrideAttrs (
      {
        preBuild = ''
          export CFLAGS="$TEST_EXTRA_FLAGS"
        '';
        NIX_DEBUG = "1";
        postFixup = ''
          cp $out/bin/hello $out/bin/test-bin
        '';
      }
      // env
    );

  stdenvUnsupport =
    additionalUnsupported:
    stdenv.override {
      cc = stdenv.cc.override {
        cc = (
          lib.extendDerivation true rec {
            # this is ugly - have to cross-reference from
            # hardeningUnsupportedFlagsByTargetPlatform to hardeningUnsupportedFlags
            # because the finalAttrs mechanism that hardeningUnsupportedFlagsByTargetPlatform
            # implementations use to do this won't work with lib.extendDerivation.
            # but it's simplified by the fact that targetPlatform is already fixed
            # at this point.
            hardeningUnsupportedFlagsByTargetPlatform = _: hardeningUnsupportedFlags;
            hardeningUnsupportedFlags =
              (
                if stdenv.cc.cc ? hardeningUnsupportedFlagsByTargetPlatform then
                  stdenv.cc.cc.hardeningUnsupportedFlagsByTargetPlatform stdenv.targetPlatform
                else
                  (stdenv.cc.cc.hardeningUnsupportedFlags or [ ])
              )
              ++ additionalUnsupported;
          } stdenv.cc.cc
        );
      };
      allowedRequisites = null;
    };

  checkTestBin =
    testBin:
    {
      # can only test flags that are detectable by hardening-check
      ignoreBindNow ? true,
      ignoreFortify ? true,
      ignorePie ? true,
      ignoreRelRO ? true,
      ignoreStackProtector ? true,
      ignoreStackClashProtection ? true,
      expectFailure ? false,
    }:
    let
      stackClashStr = "Stack clash protection: yes";
      expectFailureClause = lib.optionalString expectFailure " && echo 'ERROR: Expected hardening-check to fail, but it passed!' >&2 && false";
    in
    runCommandCC "check-test-bin"
      {
        nativeBuildInputs = [ debian-devscripts ];
        buildInputs = [ testBin ];
        meta = {
          platforms =
            if ignoreStackClashProtection then
              lib.platforms.linux # ELF-reliant
            else
              [ "x86_64-linux" ]; # stackclashprotection test looks for x86-specific instructions
          # musl implementation of fortify undetectable by this means even if present,
          # static similarly
          broken = (stdenv.hostPlatform.isMusl || stdenv.hostPlatform.isStatic) && !ignoreFortify;
        };
      }
      (
        ''
          if ${lib.optionalString (!expectFailure) "!"} {
            hardening-check --nocfprotection --nobranchprotection \
              ${lib.optionalString ignoreBindNow "--nobindnow"} \
              ${lib.optionalString ignoreFortify "--nofortify"} \
              ${lib.optionalString ignorePie "--nopie"} \
              ${lib.optionalString ignoreRelRO "--norelro"} \
              ${lib.optionalString ignoreStackProtector "--nostackprotector"} \
              $(PATH=$HOST_PATH type -P test-bin) | tee $out
        ''
        + lib.optionalString (!ignoreStackClashProtection) ''
          # stack clash protection doesn't actually affect the exit code of
          # hardening-check (likely authors think false negatives too common)
          { grep -F '${stackClashStr}' $out || { echo "Didn't find '${stackClashStr}' in output" && false ;} ;}
        ''
        + ''
          } ; then
        ''
        + lib.optionalString expectFailure ''
          echo 'ERROR: Expected hardening-check to fail, but it passed!' >&2
        ''
        + ''
            exit 2
          fi
        ''
      );

  # `securitywarnings` and `nowerror` leave no trace in the produced binary,
  # so unlike the flags above they cannot be checked with hardening-check.
  # Observe whether the compiler accepts the program instead.
  ccDiagnosticTest =
    {
      code,
      extraFlags ? "",
      expectCompileFailure ? false,
      derivationArgs ? { },
    }:
    runCommandCC "cc-diagnostic-test"
      (
        {
          codePath = writeText "diagnostic-example.c" code;
          preferLocalBuild = true;
          allowSubstitutes = false;
        }
        // derivationArgs
      )
      ''
        cp "$codePath" test.c
        if NIX_DEBUG=1 $CC -c test.c -o test.o ${extraFlags}; then
          compiled=1
        else
          compiled=0
        fi
        if [ "$compiled" = ${if expectCompileFailure then "1" else "0"} ]; then
          echo "ERROR: expected the compile to ${
            if expectCompileFailure then "fail, but it succeeded" else "succeed, but it failed"
          }" >&2
          exit 1
        fi
        touch $out
      '';

  # A nested function makes GCC emit a trampoline on the stack, which is the
  # one common construct that asks the linker for an executable stack. Clang
  # has no nested functions, so this can only be exercised on GCC.
  trampolineExampleWithStdEnv = writeCBinWithStdenv (
    writeText "trampoline-example.c" ''
      int main(void) {
        int x = 0;
        int nested(void) { return x; }
        int (*p)(void) = nested;
        return p();
      }
    ''
  );

  # An executable stack shows up as the E permission on the GNU_STACK program
  # header rather than as a note, so this cannot reuse elfNoteTest.
  noExecStackTest =
    testBin:
    brokenIf stdenv.cc.isClang (
      overridePlatforms lib.platforms.linux (
        runCommand "noexecstack-test"
          {
            nativeBuildInputs = [ bintools ];
            buildInputs = [ testBin ];
          }
          ''
            touch $out
            header=$($READELF -lW "$(PATH=$HOST_PATH type -P test-bin)" | grep -E '\bGNU_STACK\b' || true)
            echo "GNU_STACK: $header" >&2
            if [ -z "$header" ]; then
              echo "ERROR: no GNU_STACK segment found" >&2
              exit 1
            fi
            if echo "$header" | grep -qE '\bRWE\b'; then
              echo "ERROR: stack is executable despite the noexecstack flag" >&2
              exit 1
            fi
          ''
      )
    );

  unusedVariableExample = ''
    int main(void) { int unused; return 0; }
  '';

  implicitDeclarationExample = ''
    int main(void) { return undeclared_function(); }
  '';

  formatSecurityExample = ''
    int printf(const char *, ...);
    void f(char *s) { printf(s); }
    int main(void) { return 0; }
  '';

  nameDrvAfterAttrName = builtins.mapAttrs (
    name: drv:
    drv.overrideAttrs (_: {
      name = "test-${name}";
    })
  );

  fortifyExecTest = fortifyExecTestFull true "012345 7" "0123456 7";

  # returning a specific exit code when aborting due to a fortify
  # check isn't mandated. so it's better to just ensure that a
  # nonzero exit code is returned when we go a single byte beyond
  # the buffer, with the example programs being designed to be
  # unlikely to genuinely segfault for such a small overflow.
  fortifyExecTestFull =
    expectProtection: saturatedArgs: oneTooFarArgs: testBin:
    runCommand "exec-test"
      {
        buildInputs = [
          testBin
        ];
        meta.broken = !(stdenv.buildPlatform.canExecute stdenv.hostPlatform);
      }
      ''
        (
          export PATH=$HOST_PATH
          echo "Saturated buffer:" # check program isn't completly broken
          test-bin ${saturatedArgs}
          echo "One byte too far:" # overflow byte being the null terminator?
          (
            ${if expectProtection then "!" else ""} test-bin ${oneTooFarArgs}
          ) || (
            echo 'Expected ${if expectProtection then "failure" else "success"}, but ${
              if expectProtection then "succeeded" else "failed"
            }!' && exit 1
          )
        )
        echo "Expected behaviour observed"
        touch $out
      '';

  brokenIf =
    cond: drv:
    if cond then
      drv.overrideAttrs (old: {
        meta = old.meta or { } // {
          broken = true;
        };
      })
    else
      drv;
  overridePlatforms =
    platforms: drv:
    drv.overrideAttrs (old: {
      meta = old.meta or { } // {
        inherit platforms;
      };
    });

  instructionPresenceTest =
    label: mnemonicPattern: testBin: expectFailure:
    runCommand "${label}-instr-test"
      {
        nativeBuildInputs = [
          bintools
        ];
        buildInputs = [
          testBin
        ];
      }
      ''
        touch $out
        if $OBJDUMP -d \
          -j .text \
          --no-addresses \
          --no-show-raw-insn \
          "$(PATH=$HOST_PATH type -P test-bin)" \
          | grep -E '${mnemonicPattern}' > /dev/null ; then
          echo "Found ${label} instructions" >&2
          ${lib.optionalString expectFailure "exit 1"}
        else
          echo "Did not find ${label} instructions" >&2
          ${lib.optionalString (!expectFailure) "exit 1"}
        fi
      '';

  pacRetTest =
    testBin: expectFailure:
    overridePlatforms [ "aarch64-linux" ] (
      instructionPresenceTest "pacret" "\\bpaciasp\\b" testBin expectFailure
    );

  elfNoteTest =
    label: pattern: testBin: expectFailure:
    runCommand "${label}-elf-note-test"
      {
        nativeBuildInputs = [
          bintools
        ];
        buildInputs = [
          testBin
        ];
      }
      ''
        touch $out
        if $READELF -n "$(PATH=$HOST_PATH type -P test-bin)" \
          | grep -E '${pattern}' > /dev/null ; then
          echo "Found ${label} note" >&2
          ${lib.optionalString expectFailure "exit 1"}
        else
          echo "Did not find ${label} note" >&2
          ${lib.optionalString (!expectFailure) "exit 1"}
        fi
      '';

  shadowStackTest =
    testBin: expectFailure:
    brokenIf stdenv.hostPlatform.isMusl (
      overridePlatforms [ "x86_64-linux" ] (elfNoteTest "shadowstack" "\\bSHSTK\\b" testBin expectFailure)
    );

in
nameDrvAfterAttrName (
  {
    # Even a binary whose objects ask for an executable stack must end up with
    # a non-executable one.
    noExecStackDefaultEnabled = noExecStackTest (trampolineExampleWithStdEnv stdenv { });

    # `nowerror` must cancel a blanket -Werror the build system sets itself.
    nowerrorDefaultEnabled = ccDiagnosticTest {
      code = unusedVariableExample;
      extraFlags = "-Wall -Werror";
    };

    # ...including the -Werror=<warning> form, which no appended flag can
    # cancel and which is therefore stripped from the command line instead.
    nowerrorStripsSpecificWerror = ccDiagnosticTest {
      code = unusedVariableExample;
      extraFlags = "-Wall -Werror=unused-variable";
    };

    # ...and '-w', which would otherwise stop the diagnostic being emitted at
    # all, leaving nothing for our -Werror= to escalate.
    nowerrorStripsW = ccDiagnosticTest {
      code = formatSecurityExample;
      extraFlags = "-w";
      expectCompileFailure = true;
    };

    # NIX_CFLAGS_COMPILE is appended after the hardening flags and is therefore
    # still able to ask for '-w'.
    nowerrorNixCflagsCanStillSuppress = ccDiagnosticTest {
      code = formatSecurityExample;
      derivationArgs.env.NIX_CFLAGS_COMPILE = "-w";
    };

    nowerrorExplicitDisabledKeepsW = ccDiagnosticTest {
      code = formatSecurityExample;
      extraFlags = "-w";
      derivationArgs.hardeningDisable = [ "nowerror" ];
    };

    nowerrorExplicitDisabled = ccDiagnosticTest {
      code = unusedVariableExample;
      extraFlags = "-Wall -Werror";
      expectCompileFailure = true;
      derivationArgs.hardeningDisable = [ "nowerror" ];
    };

    nowerrorExplicitDisabledKeepsSpecificWerror = ccDiagnosticTest {
      code = unusedVariableExample;
      extraFlags = "-Wall -Werror=unused-variable";
      expectCompileFailure = true;
      derivationArgs.hardeningDisable = [ "nowerror" ];
    };

    # ...but it must not weaken a -Werror= that names a specific diagnostic,
    # whether that comes from `format`, from `securitywarnings` or from the
    # package itself.
    nowerrorKeepsFormatSecurityFatal = ccDiagnosticTest {
      code = formatSecurityExample;
      expectCompileFailure = true;
    };

    securitywarningsImplicitIsFatal = ccDiagnosticTest {
      code = implicitDeclarationExample;
      extraFlags = "-std=gnu89";
      expectCompileFailure = true;
    };

    # The package's own flags must not be able to countermand a diagnostic we
    # make fatal, however they reach the command line.
    securitywarningsOutrankPackageFlags = ccDiagnosticTest {
      code = implicitDeclarationExample;
      extraFlags = "-std=gnu89 -Wno-error=implicit-function-declaration";
      expectCompileFailure = true;
    };

    # NIX_CFLAGS_COMPILE, which cc-wrapper appends after the hardening flags,
    # remains the supported way to opt out of an individual diagnostic without
    # disabling the whole flag.
    securitywarningsNixCflagsOverrideWins = ccDiagnosticTest {
      code = implicitDeclarationExample;
      extraFlags = "-std=gnu89";
      derivationArgs.env.NIX_CFLAGS_COMPILE = "-Wno-error=implicit-function-declaration";
    };

    securitywarningsExplicitDisabled = ccDiagnosticTest {
      code = implicitDeclarationExample;
      extraFlags = "-std=gnu89";
      derivationArgs.hardeningDisable = [ "securitywarnings" ];
    };

    bindNowExplicitEnabled = brokenIf stdenv.hostPlatform.isStatic (
      checkTestBin
        (f2exampleWithStdEnv stdenv {
          hardeningEnable = [ "bindnow" ];
        })
        {
          ignoreBindNow = false;
        }
    );

    fortifyExplicitEnabled = (
      checkTestBin
        (f2exampleWithStdEnv stdenv {
          hardeningEnable = [ "fortify" ];
        })
        {
          ignoreFortify = false;
        }
    );

    fortify1ExplicitEnabledExecTest = fortifyExecTest (
      f1exampleWithStdEnv stdenv {
        hardeningEnable = [ "fortify" ];
      }
    );

    # musl implementation is effectively FORTIFY_SOURCE=1-only,
    fortifyExplicitEnabledExecTest = brokenIf stdenv.hostPlatform.isMusl (
      fortifyExecTest (
        f2exampleWithStdEnv stdenv {
          hardeningEnable = [ "fortify" ];
        }
      )
    );

    fortify3ExplicitEnabled = brokenIf (!stdenv.cc.isGNU || lib.versionOlder stdenv.cc.version "12") (
      checkTestBin
        (f3exampleWithStdEnv stdenv {
          hardeningEnable = [ "fortify3" ];
        })
        {
          ignoreFortify = false;
        }
    );

    # musl implementation is effectively FORTIFY_SOURCE=1-only
    fortify3ExplicitEnabledExecTest =
      brokenIf (stdenv.hostPlatform.isMusl || !stdenv.cc.isGNU || lib.versionOlder stdenv.cc.version "12")
        (
          fortifyExecTest (
            f3exampleWithStdEnv stdenv {
              hardeningEnable = [ "fortify3" ];
            }
          )
        );

    sfa1explicitEnabled =
      checkTestBin
        (flexArrF2ExampleWithStdEnv stdenv {
          hardeningEnable = [
            "fortify"
            "strictflexarrays1"
          ];
          env = {
            TEST_EXTRA_FLAGS = "-DBUFFER_DEF_SIZE=7";
          };
        })
        {
          ignoreFortify = false;
        };

    # musl implementation is effectively FORTIFY_SOURCE=1-only
    sfa1explicitEnabledExecTest = brokenIf stdenv.hostPlatform.isMusl (
      fortifyExecTestFull true "012345" "0123456" (
        flexArrF2ExampleWithStdEnv stdenv {
          hardeningEnable = [
            "fortify"
            "strictflexarrays1"
          ];
          env = {
            TEST_EXTRA_FLAGS = "-DBUFFER_DEF_SIZE=7";
          };
        }
      )
    );

    sfa1explicitEnabledDoesntProtectDefLen1 =
      checkTestBin
        (flexArrF2ExampleWithStdEnv stdenv {
          hardeningEnable = [
            "fortify"
            "strictflexarrays1"
          ];
          env = {
            TEST_EXTRA_FLAGS = "-DBUFFER_DEF_SIZE=1";
          };
        })
        {
          ignoreFortify = false;
          expectFailure = true;
        };

    # musl implementation is effectively FORTIFY_SOURCE=1-only
    sfa1explicitEnabledDoesntProtectDefLen1ExecTest = brokenIf stdenv.hostPlatform.isMusl (
      fortifyExecTestFull false "''" "0" (
        flexArrF2ExampleWithStdEnv stdenv {
          hardeningEnable = [
            "fortify"
            "strictflexarrays1"
          ];
          env = {
            TEST_EXTRA_FLAGS = "-DBUFFER_DEF_SIZE=1";
          };
        }
      )
    );

    sfa3explicitEnabledProtectsDefLen1 =
      checkTestBin
        (flexArrF2ExampleWithStdEnv stdenv {
          hardeningEnable = [
            "fortify"
            "strictflexarrays3"
          ];
          env = {
            TEST_EXTRA_FLAGS = "-DBUFFER_DEF_SIZE=1";
          };
        })
        {
          ignoreFortify = false;
        };

    # musl implementation is effectively FORTIFY_SOURCE=1-only
    sfa3explicitEnabledProtectsDefLen1ExecTest = brokenIf stdenv.hostPlatform.isMusl (
      fortifyExecTestFull true "''" "0" (
        flexArrF2ExampleWithStdEnv stdenv {
          hardeningEnable = [
            "fortify"
            "strictflexarrays3"
          ];
          env = {
            TEST_EXTRA_FLAGS = "-DBUFFER_DEF_SIZE=1";
          };
        }
      )
    );

    sfa3explicitEnabledDoesntProtectCorrectFlex =
      checkTestBin
        (flexArrF2ExampleWithStdEnv stdenv {
          hardeningEnable = [
            "fortify"
            "strictflexarrays3"
          ];
          env = {
            TEST_EXTRA_FLAGS = "-DBUFFER_DEF_SIZE=";
          };
        })
        {
          ignoreFortify = false;
          expectFailure = true;
        };

    # musl implementation is effectively FORTIFY_SOURCE=1-only
    sfa3explicitEnabledDoesntProtectCorrectFlexExecTest = brokenIf stdenv.hostPlatform.isMusl (
      fortifyExecTestFull false "" "0" (
        flexArrF2ExampleWithStdEnv stdenv {
          hardeningEnable = [
            "fortify"
            "strictflexarrays3"
          ];
          env = {
            TEST_EXTRA_FLAGS = "-DBUFFER_DEF_SIZE=";
          };
        }
      )
    );

    pieAlwaysEnabled = brokenIf stdenv.hostPlatform.isStatic (
      checkTestBin (f2exampleWithStdEnv stdenv { }) {
        ignorePie = false;
      }
    );

    relROExplicitEnabled =
      checkTestBin
        (f2exampleWithStdEnv stdenv {
          hardeningEnable = [ "relro" ];
        })
        {
          ignoreRelRO = false;
        };

    stackProtectorExplicitEnabled = brokenIf stdenv.hostPlatform.isStatic (
      checkTestBin
        (f2exampleWithStdEnv stdenv {
          hardeningEnable = [ "stackprotector" ];
        })
        {
          ignoreStackProtector = false;
        }
    );

    # protection patterns generated by clang not detectable?
    stackClashProtectionExplicitEnabled = brokenIf stdenv.cc.isClang (
      checkTestBin
        (helloWithStdEnv stdenv {
          hardeningEnable = [ "stackclashprotection" ];
        })
        {
          ignoreStackClashProtection = false;
        }
    );

    pacRetExplicitEnabled = pacRetTest (helloWithStdEnv stdenv {
      hardeningEnable = [ "pacret" ];
    }) false;

    shadowStackExplicitEnabled = shadowStackTest (f1exampleWithStdEnv stdenv {
      hardeningEnable = [ "shadowstack" ];
    }) false;

    glibcxxassertionsExplicitEnabled = checkGlibcxxassertionsWithStdEnv true stdenv {
      hardeningEnable = [ "glibcxxassertions" ];
    };

    bindNowExplicitDisabled =
      checkTestBin
        (f2exampleWithStdEnv stdenv {
          hardeningDisable = [ "bindnow" ];
        })
        {
          ignoreBindNow = false;
          expectFailure = true;
        };

    fortifyExplicitDisabled =
      checkTestBin
        (f2exampleWithStdEnv stdenv {
          hardeningDisable = [ "fortify" ];
        })
        {
          ignoreFortify = false;
          expectFailure = true;
        };

    fortify3ExplicitDisabled =
      checkTestBin
        (f3exampleWithStdEnv stdenv {
          hardeningDisable = [ "fortify3" ];
        })
        {
          ignoreFortify = false;
          expectFailure = true;
        };

    fortifyExplicitDisabledDisablesFortify3 =
      checkTestBin
        (f3exampleWithStdEnv stdenv {
          hardeningEnable = [ "fortify3" ];
          hardeningDisable = [ "fortify" ];
        })
        {
          ignoreFortify = false;
          expectFailure = true;
        };

    fortify3ExplicitDisabledDoesntDisableFortify =
      checkTestBin
        (f2exampleWithStdEnv stdenv {
          hardeningEnable = [ "fortify" ];
          hardeningDisable = [ "fortify3" ];
        })
        {
          ignoreFortify = false;
        };

    # musl implementation is effectively FORTIFY_SOURCE=1-only
    sfa1explicitDisabled = brokenIf stdenv.hostPlatform.isMusl (
      checkTestBin
        (flexArrF2ExampleWithStdEnv stdenv {
          hardeningEnable = [ "fortify" ];
          hardeningDisable = [ "strictflexarrays1" ];
          env = {
            TEST_EXTRA_FLAGS = "-DBUFFER_DEF_SIZE=7";
          };
        })
        {
          ignoreFortify = false;
          expectFailure = true;
        }
    );

    sfa1explicitDisabledExecTest = fortifyExecTestFull false "012345" "0123456" (
      flexArrF2ExampleWithStdEnv stdenv {
        hardeningEnable = [ "fortify" ];
        hardeningDisable = [ "strictflexarrays1" ];
        env = {
          TEST_EXTRA_FLAGS = "-DBUFFER_DEF_SIZE=7";
        };
      }
    );

    # musl implementation is effectively FORTIFY_SOURCE=1-only
    sfa1explicitDisabledDisablesSfa3 = brokenIf stdenv.hostPlatform.isMusl (
      checkTestBin
        (flexArrF2ExampleWithStdEnv stdenv {
          hardeningEnable = [
            "fortify"
            "strictflexarrays3"
          ];
          hardeningDisable = [ "strictflexarrays1" ];
          env = {
            TEST_EXTRA_FLAGS = "-DBUFFER_DEF_SIZE=1";
          };
        })
        {
          ignoreFortify = false;
          expectFailure = true;
        }
    );

    # musl implementation is effectively FORTIFY_SOURCE=1-only
    sfa1explicitDisabledDisablesSfa3ExecTest = brokenIf stdenv.hostPlatform.isMusl (
      fortifyExecTestFull false "''" "0" (
        flexArrF2ExampleWithStdEnv stdenv {
          hardeningEnable = [
            "fortify"
            "strictflexarrays3"
          ];
          hardeningDisable = [ "strictflexarrays1" ];
          env = {
            TEST_EXTRA_FLAGS = "-DBUFFER_DEF_SIZE=1";
          };
        }
      )
    );

    sfa3explicitDisabledDoesntDisableSfa1 =
      checkTestBin
        (flexArrF2ExampleWithStdEnv stdenv {
          hardeningEnable = [
            "fortify"
            "strictflexarrays1"
          ];
          hardeningDisable = [ "strictflexarrays3" ];
          env = {
            TEST_EXTRA_FLAGS = "-DBUFFER_DEF_SIZE=7";
          };
        })
        {
          ignoreFortify = false;
        };

    # musl implementation is effectively FORTIFY_SOURCE=1-only
    sfa3explicitDisabledDoesntDisableSfa1ExecTest = brokenIf stdenv.hostPlatform.isMusl (
      fortifyExecTestFull true "012345" "0123456" (
        flexArrF2ExampleWithStdEnv stdenv {
          hardeningEnable = [
            "fortify"
            "strictflexarrays1"
          ];
          hardeningDisable = [ "strictflexarrays3" ];
          env = {
            TEST_EXTRA_FLAGS = "-DBUFFER_DEF_SIZE=7";
          };
        }
      )
    );

    # can't force-disable ("partial"?) relro
    relROExplicitDisabled = brokenIf true (
      checkTestBin
        (f2exampleWithStdEnv stdenv {
        })
        {
          ignoreRelRO = false;
          expectFailure = true;
        }
    );

    stackProtectorExplicitDisabled =
      checkTestBin
        (f2exampleWithStdEnv stdenv {
          hardeningDisable = [ "stackprotector" ];
        })
        {
          ignoreStackProtector = false;
          expectFailure = true;
        };

    stackClashProtectionExplicitDisabled =
      checkTestBin
        (helloWithStdEnv stdenv {
          hardeningDisable = [ "stackclashprotection" ];
        })
        {
          ignoreStackClashProtection = false;
          expectFailure = true;
        };

    pacRetExplicitDisabled = pacRetTest (helloWithStdEnv stdenv {
      hardeningDisable = [ "pacret" ];
    }) true;

    shadowStackExplicitDisabled = shadowStackTest (f1exampleWithStdEnv stdenv {
      hardeningDisable = [ "shadowstack" ];
    }) true;

    glibcxxassertionsExplicitDisabled = checkGlibcxxassertionsWithStdEnv false stdenv {
      hardeningDisable = [ "glibcxxassertions" ];
    };

    lchFastExplicitDisabled = checkLibcxxHardeningWithStdEnv "_LIBCPP_HARDENING_MODE_NONE" stdenv {
      hardeningDisable = [ "libcxxhardeningfast" ];
    };

    lchExtensiveExplicitEnabled =
      checkLibcxxHardeningWithStdEnv "_LIBCPP_HARDENING_MODE_EXTENSIVE" stdenv
        {
          hardeningEnable = [ "libcxxhardeningextensive" ];
        };

    lchExtensiveExplicitDisabledDoesntDisableLchFast =
      checkLibcxxHardeningWithStdEnv "_LIBCPP_HARDENING_MODE_FAST" stdenv
        {
          hardeningEnable = [ "libcxxhardeningfast" ];
          hardeningDisable = [ "libcxxhardeningextensive" ];
        };

    lchFastExplicitDisabledDisablesLchExtensive =
      checkLibcxxHardeningWithStdEnv "_LIBCPP_HARDENING_MODE_NONE" stdenv
        {
          hardeningEnable = [ "libcxxhardeningextensive" ];
          hardeningDisable = [ "libcxxhardeningfast" ];
        };

    lchFastExtensiveExplicitEnabledResultsInLchExtensive =
      checkLibcxxHardeningWithStdEnv "_LIBCPP_HARDENING_MODE_EXTENSIVE" stdenv
        {
          hardeningEnable = [
            "libcxxhardeningfast"
            "libcxxhardeningextensive"
          ];
        };

    lchFastExtensiveExplicitDisabledDisablesBoth =
      checkLibcxxHardeningWithStdEnv "_LIBCPP_HARDENING_MODE_NONE" stdenv
        {
          hardeningDisable = [
            "libcxxhardeningfast"
            "libcxxhardeningextensive"
          ];
        };

    # most flags can't be "unsupported" by compiler alone and
    # binutils doesn't have an accessible hardeningUnsupportedFlags
    # mechanism, so can only test a couple of flags through altered
    # stdenv trickery

    fortifyStdenvUnsupp =
      checkTestBin
        (f2exampleWithStdEnv
          (stdenvUnsupport [
            "fortify"
            "fortify3"
          ])
          {
            hardeningEnable = [ "fortify" ];
          }
        )
        {
          ignoreFortify = false;
          expectFailure = true;
        };

    fortify3StdenvUnsupp =
      checkTestBin
        (f3exampleWithStdEnv (stdenvUnsupport [ "fortify3" ]) {
          hardeningEnable = [ "fortify3" ];
        })
        {
          ignoreFortify = false;
          expectFailure = true;
        };

    fortifyStdenvUnsuppUnsupportsFortify3 =
      checkTestBin
        (f3exampleWithStdEnv (stdenvUnsupport [ "fortify" ]) {
          hardeningEnable = [ "fortify3" ];
        })
        {
          ignoreFortify = false;
          expectFailure = true;
        };

    fortify3StdenvUnsuppDoesntUnsuppFortify1 =
      checkTestBin
        (f1exampleWithStdEnv (stdenvUnsupport [ "fortify3" ]) {
          hardeningEnable = [ "fortify" ];
        })
        {
          ignoreFortify = false;
        };

    fortify3StdenvUnsuppDoesntUnsuppFortify1ExecTest = fortifyExecTest (
      f1exampleWithStdEnv (stdenvUnsupport [ "fortify3" ]) {
        hardeningEnable = [ "fortify" ];
      }
    );

    sfa1StdenvUnsupp =
      checkTestBin
        (flexArrF2ExampleWithStdEnv
          (stdenvUnsupport [
            "strictflexarrays1"
            "strictflexarrays3"
          ])
          {
            hardeningEnable = [
              "fortify"
              "strictflexarrays1"
            ];
            env = {
              TEST_EXTRA_FLAGS = "-DBUFFER_DEF_SIZE=7";
            };
          }
        )
        {
          ignoreFortify = false;
          expectFailure = true;
        };

    sfa3StdenvUnsupp =
      checkTestBin
        (flexArrF2ExampleWithStdEnv (stdenvUnsupport [ "strictflexarrays3" ]) {
          hardeningEnable = [
            "fortify"
            "strictflexarrays3"
          ];
          env = {
            TEST_EXTRA_FLAGS = "-DBUFFER_DEF_SIZE=1";
          };
        })
        {
          ignoreFortify = false;
          expectFailure = true;
        };

    sfa1StdenvUnsuppUnsupportsSfa3 =
      checkTestBin
        (flexArrF2ExampleWithStdEnv (stdenvUnsupport [ "strictflexarrays1" ]) {
          hardeningEnable = [
            "fortify"
            "strictflexarrays3"
          ];
          env = {
            TEST_EXTRA_FLAGS = "-DBUFFER_DEF_SIZE=1";
          };
        })
        {
          ignoreFortify = false;
          expectFailure = true;
        };

    sfa3StdenvUnsuppDoesntUnsuppSfa1 =
      checkTestBin
        (flexArrF2ExampleWithStdEnv (stdenvUnsupport [ "strictflexarrays3" ]) {
          hardeningEnable = [
            "fortify"
            "strictflexarrays1"
          ];
          env = {
            TEST_EXTRA_FLAGS = "-DBUFFER_DEF_SIZE=7";
          };
        })
        {
          ignoreFortify = false;
        };

    # musl implementation is effectively FORTIFY_SOURCE=1-only
    sfa3StdenvUnsuppDoesntUnsuppSfa1ExecTest = brokenIf stdenv.hostPlatform.isMusl (
      fortifyExecTestFull true "012345" "0123456" (
        flexArrF2ExampleWithStdEnv (stdenvUnsupport [ "strictflexarrays3" ]) {
          hardeningEnable = [
            "fortify"
            "strictflexarrays1"
          ];
          env = {
            TEST_EXTRA_FLAGS = "-DBUFFER_DEF_SIZE=7";
          };
        }
      )
    );

    stackProtectorStdenvUnsupp =
      checkTestBin
        (f2exampleWithStdEnv (stdenvUnsupport [ "stackprotector" ]) {
          hardeningEnable = [ "stackprotector" ];
        })
        {
          ignoreStackProtector = false;
          expectFailure = true;
        };

    stackClashProtectionStdenvUnsupp =
      checkTestBin
        (helloWithStdEnv (stdenvUnsupport [ "stackclashprotection" ]) {
          hardeningEnable = [ "stackclashprotection" ];
        })
        {
          ignoreStackClashProtection = false;
          expectFailure = true;
        };

    # NIX_HARDENING_ENABLE set in the shell overrides hardeningDisable
    # and hardeningEnable

    stackProtectorReenabledEnv =
      checkTestBin
        (f2exampleWithStdEnv stdenv {
          hardeningDisable = [ "stackprotector" ];
          postConfigure = ''
            export NIX_HARDENING_ENABLE="stackprotector"
          '';
        })
        {
          ignoreStackProtector = false;
        };

    stackProtectorReenabledFromAllEnv =
      checkTestBin
        (f2exampleWithStdEnv stdenv {
          hardeningDisable = [ "all" ];
          postConfigure = ''
            export NIX_HARDENING_ENABLE="stackprotector"
          '';
        })
        {
          ignoreStackProtector = false;
        };

    stackProtectorRedisabledEnv =
      checkTestBin
        (f2exampleWithStdEnv stdenv {
          hardeningEnable = [ "stackprotector" ];
          postConfigure = ''
            export NIX_HARDENING_ENABLE=""
          '';
        })
        {
          ignoreStackProtector = false;
          expectFailure = true;
        };

    glibcxxassertionsStdenvUnsupp =
      checkGlibcxxassertionsWithStdEnv false (stdenvUnsupport [ "glibcxxassertions" ])
        {
          hardeningEnable = [ "glibcxxassertions" ];
        };

    lchFastStdenvUnsupp =
      checkLibcxxHardeningWithStdEnv "_LIBCPP_HARDENING_MODE_NONE"
        (stdenvUnsupport [ "libcxxhardeningfast" ])
        {
          hardeningEnable = [ "libcxxhardeningfast" ];
        };

    lchFastStdenvUnsuppUnsupportsLchExtensive =
      checkLibcxxHardeningWithStdEnv "_LIBCPP_HARDENING_MODE_NONE"
        (stdenvUnsupport [ "libcxxhardeningfast" ])
        {
          hardeningEnable = [ "libcxxhardeningextensive" ];
        };

    lchExtensiveStdenvUnsuppDoesntUnsupportLchFast =
      checkLibcxxHardeningWithStdEnv "_LIBCPP_HARDENING_MODE_FAST"
        (stdenvUnsupport [ "libcxxhardeningextensive" ])
        {
          hardeningEnable = [
            "libcxxhardeningfast"
            "libcxxhardeningextensive"
          ];
        };

    fortify3EnabledEnvEnablesFortify1 =
      checkTestBin
        (f1exampleWithStdEnv stdenv {
          hardeningDisable = [
            "fortify"
            "fortify3"
          ];
          postConfigure = ''
            export NIX_HARDENING_ENABLE="fortify3"
          '';
        })
        {
          ignoreFortify = false;
        };

    fortify3EnabledEnvEnablesFortify1ExecTest = fortifyExecTest (
      f1exampleWithStdEnv stdenv {
        hardeningDisable = [
          "fortify"
          "fortify3"
        ];
        postConfigure = ''
          export NIX_HARDENING_ENABLE="fortify3"
        '';
      }
    );

    fortifyEnabledEnvDoesntEnableFortify3 =
      checkTestBin
        (f3exampleWithStdEnv stdenv {
          hardeningDisable = [
            "fortify"
            "fortify3"
          ];
          postConfigure = ''
            export NIX_HARDENING_ENABLE="fortify"
          '';
        })
        {
          ignoreFortify = false;
          expectFailure = true;
        };

    sfa3EnabledEnvEnablesSfa1 =
      checkTestBin
        (flexArrF2ExampleWithStdEnv stdenv {
          hardeningDisable = [
            "strictflexarrays1"
            "strictflexarrays3"
          ];
          postConfigure = ''
            export NIX_HARDENING_ENABLE="fortify strictflexarrays3"
          '';
          env = {
            TEST_EXTRA_FLAGS = "-DBUFFER_DEF_SIZE=7";
          };
        })
        {
          ignoreFortify = false;
        };

    sfa3EnabledEnvEnablesSfa1ExecTest = fortifyExecTestFull true "012345" "0123456" (
      f1exampleWithStdEnv stdenv {
        hardeningDisable = [
          "strictflexarrays1"
          "strictflexarrays3"
        ];
        postConfigure = ''
          export NIX_HARDENING_ENABLE="fortify strictflexarrays3"
        '';
        env = {
          TEST_EXTRA_FLAGS = "-DBUFFER_DEF_SIZE=7";
        };
      }
    );

    sfa1EnabledEnvDoesntEnableSfa3 =
      checkTestBin
        (flexArrF2ExampleWithStdEnv stdenv {
          hardeningDisable = [
            "strictflexarrays1"
            "strictflexarrays3"
          ];
          postConfigure = ''
            export NIX_HARDENING_ENABLE="fortify strictflexarrays1"
          '';
          env = {
            TEST_EXTRA_FLAGS = "-DBUFFER_DEF_SIZE=1";
          };
        })
        {
          ignoreFortify = false;
          expectFailure = true;
        };

    lchFastEnabledEnv = checkLibcxxHardeningWithStdEnv "_LIBCPP_HARDENING_MODE_FAST" stdenv {
      hardeningDisable = [
        "libcxxhardeningfast"
        "libcxxhardeningextensive"
      ];
      postConfigure = ''
        export NIX_HARDENING_ENABLE="libcxxhardeningfast"
      '';
    };

    lchExtensiveEnabledEnv = checkLibcxxHardeningWithStdEnv "_LIBCPP_HARDENING_MODE_EXTENSIVE" stdenv {
      hardeningDisable = [
        "libcxxhardeningfast"
        "libcxxhardeningextensive"
      ];
      postConfigure = ''
        export NIX_HARDENING_ENABLE="libcxxhardeningextensive"
      '';
    };

    lchFastExtensiveEnabledEnvResultsInLchExtensive =
      checkLibcxxHardeningWithStdEnv "_LIBCPP_HARDENING_MODE_EXTENSIVE" stdenv
        {
          hardeningDisable = [
            "libcxxhardeningfast"
            "libcxxhardeningextensive"
          ];
          postConfigure = ''
            export NIX_HARDENING_ENABLE="libcxxhardeningextensive libcxxhardeningfast"
          '';
        };

    # NIX_HARDENING_ENABLE can't enable an unsupported feature
    stackProtectorUnsupportedEnabledEnv =
      checkTestBin
        (f2exampleWithStdEnv (stdenvUnsupport [ "stackprotector" ]) {
          postConfigure = ''
            export NIX_HARDENING_ENABLE="stackprotector"
          '';
        })
        {
          ignoreStackProtector = false;
          expectFailure = true;
        };

    # current implementation prevents the command-line from disabling
    # fortify if cc-wrapper is enabling it.

    fortify1ExplicitEnabledCmdlineDisabled =
      checkTestBin
        (f1exampleWithStdEnv stdenv {
          hardeningEnable = [ "fortify" ];
          postConfigure = ''
            export TEST_EXTRA_FLAGS='-D_FORTIFY_SOURCE=0'
          '';
        })
        {
          ignoreFortify = false;
          expectFailure = false;
        };

    # current implementation doesn't force-disable fortify if
    # command-line enables it even if we use hardeningDisable.

    fortify1ExplicitDisabledCmdlineEnabled =
      checkTestBin
        (f1exampleWithStdEnv stdenv {
          hardeningDisable = [ "fortify" ];
          postConfigure = ''
            export TEST_EXTRA_FLAGS='-D_FORTIFY_SOURCE=1'
          '';
        })
        {
          ignoreFortify = false;
        };

    fortify1ExplicitDisabledCmdlineEnabledExecTest = fortifyExecTest (
      f1exampleWithStdEnv stdenv {
        hardeningDisable = [ "fortify" ];
        postConfigure = ''
          export TEST_EXTRA_FLAGS='-D_FORTIFY_SOURCE=1'
        '';
      }
    );

    fortify1ExplicitEnabledCmdlineDisabledNoWarn = f1exampleWithStdEnv stdenv {
      hardeningEnable = [ "fortify" ];
      postConfigure = ''
        export TEST_EXTRA_FLAGS='-D_FORTIFY_SOURCE=0 -Werror'
      '';
    };

  }
  // (
    let
      tb = f2exampleWithStdEnv stdenv {
        hardeningDisable = [ "all" ];
        hardeningEnable = [
          "fortify"
        ];
      };
    in
    {

      allExplicitDisabledBindNow = checkTestBin tb {
        ignoreBindNow = false;
        expectFailure = true;
      };

      allExplicitDisabledFortify = checkTestBin tb {
        ignoreFortify = false;
        expectFailure = true;
      };

      # can't force-disable ("partial"?) relro
      allExplicitDisabledRelRO = brokenIf true (
        checkTestBin tb {
          ignoreRelRO = false;
          expectFailure = true;
        }
      );

      allExplicitDisabledStackProtector = checkTestBin tb {
        ignoreStackProtector = false;
        expectFailure = true;
      };

      allExplicitDisabledStackClashProtection = checkTestBin tb {
        ignoreStackClashProtection = false;
        expectFailure = true;
      };

      allExplicitDisabledPacRet = pacRetTest (helloWithStdEnv stdenv {
        hardeningDisable = [ "all" ];
      }) true;

      allExplicitDisabledShadowStack = shadowStackTest (f1exampleWithStdEnv stdenv {
        hardeningDisable = [ "all" ];
      }) true;

      allExplicitDisabledGlibcxxAssertions = checkGlibcxxassertionsWithStdEnv false stdenv {
        hardeningDisable = [ "all" ];
      };

      allExplicitDisabledLibcxxHardening =
        checkLibcxxHardeningWithStdEnv "_LIBCPP_HARDENING_MODE_NONE" stdenv
          {
            hardeningDisable = [ "all" ];
          };
    }
  )
)
