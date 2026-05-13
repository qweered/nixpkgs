# shellcheck shell=bash
#
# Post-fixup hook: scan outputs for store-hash references to declared
# `buildInputs`. A declared input counts as used if any output of its
# derivation (any sibling found via `pkgsHostTarget`) appears in any of
# our outputs. Mirrors the default scanner of LordGrimmauld/nix-check-deps.
#
# Escape hatches:
#   dontCheckDeps        -- skip entirely.
#   allowedUnusedInputs  -- inputs whose absence may be silently ignored.
# Fixed-output derivations are skipped automatically.

if (( ${checkDepsHookInstalled:-0} > 0 )); then return 0; fi
declare -ig checkDepsHookInstalled=1
postFixupHooks+=(checkDeps)

checkDeps() {
    # FODs (fetchers/sources) declare no real buildInputs; skip silently.
    [[ -n ${outputHash-}    ]] && return 0
    [[ -n ${dontCheckDeps-} ]] && { echo "checkDeps: skipped (dontCheckDeps set)"; return 0; }

    echo "checkDeps: scanning outputs for declared buildInputs..."

    local storeDir=${NIX_STORE:-/nix/store}
    local -i hashAt=${#storeDir}+1   # offset to the 32-char hash
    local -i nameAt=hashAt+33        # offset past "<hash>-"

    # Sets _family to the "package family" for store path $1: the basename
    # with a trailing -<known-output> suffix stripped, so sibling outputs
    # of the same derivation share a key.
    _checkDepsFamily() {
        local n=${1:nameAt}
        case ${n##*-} in
            out|dev|lib|bin|doc|man|info|debug|static|dist|bash|py)
                _family=${n%-*} ;;
            *) _family=$n ;;
        esac
    }

    local -A familyToInput=()        # family -> declared store path
    local input _family
    # shellcheck disable=SC2206
    for input in ${buildInputs[@]-}; do
        [[ $input == "$storeDir"/* ]] || continue
        _checkDepsFamily "$input"
        familyToInput[$_family]=$input
    done
    local -i declared=${#familyToInput[@]}

    # shellcheck disable=SC2206
    for input in ${allowedUnusedInputs[@]-}; do
        [[ $input == "$storeDir"/* ]] || continue
        _checkDepsFamily "$input"
        unset "familyToInput[$_family]"
    done

    (( declared == 0 )) && { echo "checkDeps: no buildInputs to scan"; return 0; }
    (( ${#familyToInput[@]} == 0 )) && {
        echo "checkDeps: all $declared buildInput(s) allowlisted; nothing to scan"
        return 0
    }

    # Build hash -> family map. Includes declared hashes plus every sibling
    # output of the same family from pkgsHostTarget (e.g. gmp.out when only
    # gmp.dev was declared).
    local -A hashToFamily=()
    for _family in "${!familyToInput[@]}"; do
        hashToFamily[${familyToInput[$_family]:hashAt:32}]=$_family
    done
    # shellcheck disable=SC2206
    for input in ${pkgsHostTarget[@]-}; do
        [[ $input == "$storeDir"/* ]] || continue
        _checkDepsFamily "$input"
        [[ -n ${familyToInput[$_family]-} ]] || continue
        hashToFamily[${input:hashAt:32}]=$_family
    done

    local pattern
    pattern=$(IFS='|'; printf '%s' "${!hashToFamily[*]}")

    local -A seen=()
    local output prefix h
    for output in $(getAllOutputNames); do
        prefix=${!output}
        [[ -e $prefix ]] || continue
        while IFS= read -r h; do
            seen[${hashToFamily[$h]}]=1
        done < <(
            {
                # -a so binary files (.so, executables) are scanned -- the
                # RUNPATH and DT_NEEDED references we care about live in
                # binary ELF metadata, not just plain-text scripts.
                find "$prefix" -type f -print0 \
                    | xargs -0 -r -P "${NIX_BUILD_CORES:-1}" -n 64 grep -ahoE "$pattern" 2>/dev/null
                find "$prefix" -printf '%f\n%l\n' 2>/dev/null
            } | grep -aoE "$pattern" | sort -u
        )
    done

    local -a unused=()
    for _family in "${!familyToInput[@]}"; do
        [[ -z ${seen[$_family]-} ]] && unused+=("${familyToInput[$_family]}")
    done

    if (( ${#unused[@]} == 0 )); then
        echo "checkDeps: no unused deps found ($declared buildInput(s) scanned)"
    else
        echo "checkDeps: potentially unused deps: $(printf '%s\n' "${unused[@]}" | sort | paste -sd ' ' -)"
    fi
}
