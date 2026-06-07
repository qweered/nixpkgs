# Deterministic profile-guided optimization for GCC

On native x86 Linux, nixpkgs builds GCC with profile-guided optimization (PGO)
**by default**, via gcc's `profiledbootstrap`. This document explains how that
is wired, why it is believed to be reproducible, and -- most importantly -- how
to *verify* that belief.

## How PGO is controlled

There is a single internal knob, `enablePgo`, on the gcc derivation
(`pkgs/development/compilers/gcc/default.nix`). It is **not** a public/stable
API. Left at its `null` default it resolves by platform:

```nix
doPgo =
  if enablePgo != null then
    enablePgo
  else
    # native, non-cross x86 Linux only
    !stdenv.hostPlatform.isDarwin && stdenv.hostPlatform.isx86 && hostIsTarget && buildIsHost;
```

So:

| target                              | PGO?                |
| ----------------------------------- | ------------------- |
| native x86_64 / i686 Linux          | **yes** (default)   |
| Darwin, aarch64, other non-x86      | no                  |
| any cross compiler (`host≠target`)  | no                  |
| stdenv-bootstrap `xgcc` (stage 1)   | no (`enablePgo = false`) |
| `gccWithoutTargetLibc` (libc seed)  | no (`enablePgo = false`) |
| final stdenv compiler (stage 3)     | **yes** -- this is `stdenv.cc`/`pkgs.gcc` |

The two historical booleans `reproducibleBuild` and `profiledCompiler` have been
removed in favour of this single platform-defaulted knob.

### Why the bootstrap stages opt out

`pkgs.gcc` / `stdenv.cc.cc` is the compiler emitted by the *final* stdenv
bootstrap stage (stage 3), reused as the package set's compiler. The earlier
stages (notably stage 1, `xgcc`) are transient and are deliberately built
*without* gcc's internal bootstrap (the externalised-bootstrap design,
NixOS/nixpkgs#209870). They force `enablePgo = false` so only the final,
user-facing compiler pays for -- and benefits from -- the profiled bootstrap.

## How it is hardened for reproducibility

`profiledbootstrap` is a multi-stage build: an instrumented compiler
(`-fprofile-generate`) recompiles gcc's own (fixed, tarball-identical) source to
record `.gcda` edge/value counters, then the final compiler is built with
`-fprofile-use`. The training corpus is therefore already fixed.

On top of that, the gcc derivation sets `pgoBootCFlags = "-fno-profile-values"`
when PGO is on; `common/builder.nix` appends it to `BOOT_CFLAGS`. This keeps only
the (machine-independent) edge counters and drops gcc's value-profiling
histograms, the most plausible carrier of machine-dependent state, while
retaining PGO's main benefit (hot/cold path layout).

## The reproducibility question (read this before trusting it)

From NixOS/nixpkgs#112928:

- `profiledbootstrap` is **already reproducible on a single machine** -- building
  it twice on the same host (even `make -j1`) is byte-identical.
- It was **not reproducible across machines**, and the root cause was never
  found. `-j1` did not fix it, so it is not a build-ordering effect.

A local experiment for this work also ruled out the obvious culprit: compiling
indirect-call code with `-fprofile-generate` and running it twice under ASLR
produced identical `.gcda` *with and without* `-fno-profile-values`. So the
hardening flag is a low-cost belt, not a proven fix, and **cross-machine
determinism remains unverified**.

### `nix-build --check` is not sufficient

`--check` rebuilds on the *same* machine, where PGO gcc already reproduces. It
proves nothing about the cross-machine property. You must build on two
differently configured machines.

## Verifying cross-machine determinism (the real test)

Pick two hosts differing as much as practical (CPU microarch, core count, kernel,
RAM). On **each**:

```sh
out=$(nix-build . -A gcc.cc --no-out-link)   # the default, PGO compiler
nix-store --dump "$out" | sha256sum
```

- Matching hashes → reproducible across those two machines. 🎉
- Differing hashes → locate where with `diffoscope` (copy one closure across
  first, e.g. `nix copy --to ssh://other "$out"`):

```sh
nix shell nixpkgs#diffoscope -c diffoscope \
  --exclude-directory-metadata=recursive \
  /nix/store/<hashA>-gcc-<ver> /nix/store/<hashB>-gcc-<ver>
```

`cc1`, `cc1plus`, `lto1` are the binaries to watch. If they still diverge, the
next suspects are gcc's pointer-seeded internal hash-table ordering (classic gcc
reproducibility bug, usually addressed with a fixed `-frandom-seed`) and the
`stagetrain` counter-merge path.

The same-machine sanity check is still worth running first:

```sh
nix-build . -A gcc.cc --check     # expected PASS; necessary but not sufficient
```

## Trade-offs and risks

- **Build cost**: every C/C++ compiler in the package set (and the stdenv
  compiler) now pays for a profiled bootstrap -- historically a 7–12% slower gcc
  build, and the *final stdenv stage* now runs gcc's internal bootstrap again.
- **Runtime benefit**: PGO made compiled-by-gcc workloads ~7–12% faster in the
  2021 measurements.
- **Variant risk**: native non-C frontends (`gccgo`, `gnat`/Ada, `gfortran`) now
  default to PGO too. If any fails to profiled-bootstrap, set `enablePgo = false`
  on that specific derivation.
- `fastStdenv` is now just an alias for `gccStdenv` (the default compiler is
  already the optimized one), kept for backwards compatibility.

## Status / open work

- [x] PGO is the default for native x86-linux gcc, including `stdenv.cc`.
- [x] Bootstrap stages, cross, non-x86, and Darwin stay deterministic/non-PGO.
- [x] Whole tree evaluates; `stdenv` instantiates.
- [ ] Full build of `stdenv` / `gcc.cc` validated end-to-end (long; not done in
      the change itself).
- [ ] Cross-machine determinism demonstrated with diffoscope on two hosts.
- [ ] If still divergent: bisect remaining entropy; consider a fixed
      `-frandom-seed` across the profiled stages.
