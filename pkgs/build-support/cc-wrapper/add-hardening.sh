declare -a hardeningCFlagsAfter=()
declare -a hardeningCFlagsBefore=()

declare -A hardeningEnableMap=()

# Intentionally word-split in case 'NIX_HARDENING_ENABLE' is defined in Nix. The
# array expansion also prevents undefined variables from causing trouble with
# `set -u`.
for flag in ${NIX_HARDENING_ENABLE_@suffixSalt@-}; do
  hardeningEnableMap["$flag"]=1
done


# fortify3 implies fortify enablement - make explicit before
# we filter unsupported flags because unsupporting fortify3
# doesn't mean we should unsupport fortify too
if [[ -n "${hardeningEnableMap[fortify3]-}" ]]; then
  hardeningEnableMap["fortify"]=1
fi

# strictflexarrays3 implies strictflexarrays1 enablement - make explicit before
# we filter unsupported flags because unsupporting strictflexarrays3
# doesn't mean we should unsupport strictflexarrays1 too
if [[ -n "${hardeningEnableMap[strictflexarrays3]-}" ]]; then
  hardeningEnableMap["strictflexarrays1"]=1
fi

# libcxxhardeningextensive implies libcxxhardeningfast enablement - make explicit before
# we filter unsupported flags because unsupporting libcxxhardeningextensive
# doesn't mean we should unsupport libcxxhardeningfast too
if [[ -n "${hardeningEnableMap[libcxxhardeningextensive]-}" ]]; then
  hardeningEnableMap["libcxxhardeningfast"]=1
fi


# Remove unsupported flags.
for flag in @hardening_unsupported_flags@; do
  unset -v "hardeningEnableMap[$flag]"
  # fortify being unsupported implies fortify3 is unsupported
  if [[ "$flag" = 'fortify' ]] ; then
    unset -v "hardeningEnableMap['fortify3']"
  fi
  # strictflexarrays1 being unsupported implies strictflexarrays3 is unsupported
  if [[ "$flag" = 'strictflexarrays1' ]] ; then
    unset -v "hardeningEnableMap['strictflexarrays3']"
  fi
  # libcxxhardeningfast being unsupported implies libcxxhardeningextensive is unsupported
  if [[ "$flag" = 'libcxxhardeningfast' ]] ; then
    unset -v "hardeningEnableMap['libcxxhardeningextensive']"
  fi
done


# now make fortify and fortify3 mutually exclusive
if [[ -n "${hardeningEnableMap[fortify3]-}" ]]; then
  unset -v "hardeningEnableMap['fortify']"
fi

# now make strictflexarrays1 and strictflexarrays3 mutually exclusive
if [[ -n "${hardeningEnableMap[strictflexarrays3]-}" ]]; then
  unset -v "hardeningEnableMap['strictflexarrays1']"
fi

# now make libcxxhardeningfast and libcxxhardeningextensive mutually exclusive
if [[ -n "${hardeningEnableMap[libcxxhardeningextensive]-}" ]]; then
  unset -v "hardeningEnableMap['libcxxhardeningfast']"
fi


if (( "${NIX_DEBUG:-0}" >= 1 )); then
  declare -a allHardeningFlags=(fortify fortify3 shadowstack stackprotector stackclashprotection nostrictaliasing pacret strictflexarrays1 strictflexarrays3 pic strictoverflow libcxxhardeningfast libcxxhardeningextensive glibcxxassertions format securitywarnings nowerror nodeletenullpointerchecks trivialautovarinit zerocallusedregs)
  declare -A hardeningDisableMap=()

  # Determine which flags were effectively disabled so we can report below.
  for flag in "${allHardeningFlags[@]}"; do
    if [[ -z "${hardeningEnableMap[$flag]-}" ]]; then
      hardeningDisableMap["$flag"]=1
    fi
  done

  printf 'HARDENING: disabled flags:' >&2
  (( "${#hardeningDisableMap[@]}" )) && printf ' %q' "${!hardeningDisableMap[@]}" >&2
  echo >&2

  if (( "${#hardeningEnableMap[@]}" )); then
    echo 'HARDENING: Is active (not completely disabled with "all" flag)' >&2;
  fi
fi

for flag in "${!hardeningEnableMap[@]}"; do
  case $flag in
    fortify | fortify3)
      # Use -U_FORTIFY_SOURCE to avoid warnings on toolchains that explicitly
      # set -D_FORTIFY_SOURCE=0 (like 'clang -fsanitize=address').
      hardeningCFlagsBefore+=('-O2' '-U_FORTIFY_SOURCE')
      # Unset any _FORTIFY_SOURCE values the command-line may have set before
      # enforcing our own value, avoiding (potentially fatal) redefinition
      # warnings
      hardeningCFlagsAfter+=('-U_FORTIFY_SOURCE')
      case $flag in
        fortify)
          if (( "${NIX_DEBUG:-0}" >= 1 )); then echo HARDENING: enabling fortify >&2; fi
          hardeningCFlagsAfter+=('-D_FORTIFY_SOURCE=2')
        ;;
        fortify3)
          if (( "${NIX_DEBUG:-0}" >= 1 )); then echo HARDENING: enabling fortify3 >&2; fi
          hardeningCFlagsAfter+=('-D_FORTIFY_SOURCE=3')
        ;;
        *)
          # Ignore unsupported.
          ;;
      esac
      ;;
    shadowstack)
      if (( "${NIX_DEBUG:-0}" >= 1 )); then echo HARDENING: enabling shadowstack >&2; fi
      hardeningCFlagsBefore+=('-fcf-protection=return')
      ;;
    strictflexarrays1)
      if (( "${NIX_DEBUG:-0}" >= 1 )); then echo HARDENING: enabling strictflexarrays1 >&2; fi
      hardeningCFlagsBefore+=('-fstrict-flex-arrays=1')
      ;;
    strictflexarrays3)
      if (( "${NIX_DEBUG:-0}" >= 1 )); then echo HARDENING: enabling strictflexarrays3 >&2; fi
      hardeningCFlagsBefore+=('-fstrict-flex-arrays=3')
      ;;
    pacret)
      if (( "${NIX_DEBUG:-0}" >= 1 )); then echo HARDENING: enabling pacret >&2; fi
      hardeningCFlagsBefore+=('-mbranch-protection=pac-ret')
      ;;
    glibcxxassertions)
      if (( "${NIX_DEBUG:-0}" >= 1 )); then echo HARDENING: enabling glibcxxassertions >&2; fi
      hardeningCFlagsBefore+=('-D_GLIBCXX_ASSERTIONS')
      ;;
    libcxxhardeningfast)
      if (( "${NIX_DEBUG:-0}" >= 1 )); then echo HARDENING: enabling libcxxhardeningfast >&2; fi
      hardeningCFlagsBefore+=('-D_LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_FAST')
      ;;
    libcxxhardeningextensive)
      if (( "${NIX_DEBUG:-0}" >= 1 )); then echo HARDENING: enabling libcxxhardeningextensive >&2; fi
      hardeningCFlagsBefore+=('-D_LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_EXTENSIVE')
      ;;
    stackprotector)
      if (( "${NIX_DEBUG:-0}" >= 1 )); then echo HARDENING: enabling stackprotector >&2; fi
      hardeningCFlagsBefore+=('-fstack-protector-strong' '--param' 'ssp-buffer-size=4')
      ;;
    stackclashprotection)
      if (( "${NIX_DEBUG:-0}" >= 1 )); then echo HARDENING: enabling stackclashprotection >&2; fi
      hardeningCFlagsBefore+=('-fstack-clash-protection')
      ;;
    nodeletenullpointerchecks)
      if (( "${NIX_DEBUG:-0}" >= 1 )); then echo HARDENING: enabling nodeletenullpointerchecks >&2; fi
      # Stops the optimiser from deleting a null check on the grounds that an
      # earlier dereference already made a null pointer undefined behaviour.
      # Such deletions silently turn a defensive check into an exploitable
      # null dereference. This only ever keeps code the compiler would
      # otherwise remove, so it cannot change the meaning of a correct program.
      hardeningCFlagsBefore+=('-fno-delete-null-pointer-checks')
      ;;
    nostrictaliasing)
      if (( "${NIX_DEBUG:-0}" >= 1 )); then echo HARDENING: enabling nostrictaliasing >&2; fi
      hardeningCFlagsBefore+=('-fno-strict-aliasing')
      ;;
    pic)
      if (( "${NIX_DEBUG:-0}" >= 1 )); then echo HARDENING: enabling pic >&2; fi
      hardeningCFlagsBefore+=('-fPIC')
      ;;
    strictoverflow)
      if (( "${NIX_DEBUG:-0}" >= 1 )); then echo HARDENING: enabling strictoverflow >&2; fi
      if (( @isClang@ )); then
        # In Clang, -fno-strict-overflow only serves to set -fwrapv and is
        # reported as an unused CLI argument if -fwrapv or -fno-wrapv is set
        # explicitly, so we side step that by doing the conversion here.
        #
        # See: https://github.com/llvm/llvm-project/blob/llvmorg-16.0.6/clang/lib/Driver/ToolChains/Clang.cpp#L6315
        #
        hardeningCFlagsBefore+=('-fwrapv')
      else
        hardeningCFlagsBefore+=('-fno-strict-overflow')
      fi
      ;;
    trivialautovarinit)
      if (( "${NIX_DEBUG:-0}" >= 1 )); then echo HARDENING: enabling trivialautovarinit >&2; fi
      hardeningCFlagsBefore+=('-ftrivial-auto-var-init=pattern')
      ;;
    format)
      if (( "${NIX_DEBUG:-0}" >= 1 )); then echo HARDENING: enabling format >&2; fi
      hardeningCFlagsBefore+=('-Wformat' '-Wformat-security' '-Werror=format-security')
      ;;
    securitywarnings)
      if (( "${NIX_DEBUG:-0}" >= 1 )); then echo HARDENING: enabling securitywarnings >&2; fi
      # Diagnostics recommended by the OpenSSF Compiler Options Hardening Guide
      # for C and C++. These go in the 'before' array so that a package can
      # still silence any of them with its own '-Wno-...'.
      #
      # The guide also lists '-Wformat=2', which is deliberately omitted: the
      # 'format' flag already supplies '-Wformat -Wformat-security', and all
      # '-Wformat=2' adds on top is '-Wformat-nonliteral', which fires on the
      # ordinary varargs logging wrapper. The dangerous case -- a non-literal
      # format with no arguments, the '%n' vector -- is '-Wformat-security',
      # which 'format' already makes fatal.
      hardeningCFlagsBefore+=('-Wall' '-Wextra' '-Wimplicit-fallthrough')
      # '-Wtrampolines' and '-Wbidi-chars' are GCC-only. Every other compiler
      # driven by this wrapper -- clang, arocc -- would emit an
      # "unknown warning option" diagnostic for each of them on *every*
      # compile, so gate on isGNU rather than merely excluding clang.
      if (( @isGNU@ )); then
        hardeningCFlagsBefore+=('-Wtrampolines' '-Wbidi-chars=any')
      fi
      # Constraint violations that C23, GCC 14+ and Clang 16+ already reject by
      # default. Requesting them explicitly holds the older compilers still
      # present in nixpkgs to the same standard.
      #
      # These go in the 'after' array, and name the individual diagnostics
      # rather than the '-Werror=implicit' group, so that they outrank any
      # '-Wno-error=' the package's own build system passes: equally specific
      # '-W' options are resolved by position, and a group option always loses
      # to a more specific one. A package can still opt out through
      # 'env.NIX_CFLAGS_COMPILE', which cc-wrapper.sh appends after these.
      #
      # They are C-only, and GCC prints an unsuppressable "'-Werror=' argument
      # ... is not valid for C++" note once per compile if they reach cc1plus,
      # so skip them for GCC when we know we are compiling C++. Note that this
      # must not be gated on isCxx alone: cc-wrapper.sh force-sets isCxx=1 for
      # every clang invocation regardless of source language, so doing so would
      # drop these flags from all clang compiles, C included.
      if ! (( @isGNU@ )) || [[ "${isCxx-0}" != 1 ]]; then
        hardeningCFlagsAfter+=('-Werror=implicit-function-declaration' '-Werror=implicit-int' '-Werror=int-conversion' '-Werror=incompatible-pointer-types')
      fi
      ;;
    nowerror)
      if (( "${NIX_DEBUG:-0}" >= 1 )); then echo HARDENING: enabling nowerror >&2; fi
      # Appended *after* the package's own flags, which is the only position
      # from which it can cancel a '-Werror' the build system set itself.
      # Warning-specific '-Werror=' options -- the ones above, and any the
      # package sets -- are more specific and survive this regardless of
      # position, on both GCC and Clang.
      hardeningCFlagsAfter+=('-Wno-error')
      ;;
    zerocallusedregs)
      if (( "${NIX_DEBUG:-0}" >= 1 )); then echo HARDENING: enabling zerocallusedregs >&2; fi
      hardeningCFlagsBefore+=('-fzero-call-used-regs=used-gpr')
      ;;
    *)
      # Ignore unsupported. Checked in Nix that at least *some*
      # tool supports each flag.
      ;;
  esac
done
