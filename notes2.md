# Getting `build_and_run.sh` to a Successful Coverage Run

This documents the steps taken on this machine to get `./build_and_run.sh` to run
end-to-end and produce `report/coverage.html`, starting from a clean checkout where
`bazel` wasn't even installed.

## 1. Install Bazel (via Bazelisk)

`bazel` was not on `PATH`. The repo pins an exact version in `.bazelversion`
(`7.4.1`), so Bazelisk (a launcher that auto-downloads the pinned version) was
installed to the user-local `~/.local/bin` (already on `PATH`, no `sudo` needed):

```sh
curl -sL -o ~/.local/bin/bazel \
  https://github.com/bazelbuild/bazelisk/releases/latest/download/bazelisk-linux-amd64
chmod +x ~/.local/bin/bazel
bazel version   # downloads/uses Bazel 7.4.1 per .bazelversion
```

## 2. Fix the `@cpptest` external repo (Parasoft C/C++test integration)

`bazel run @cpptest//:coverage ...` failed with:

```
ERROR: <builtin>: fetching _cpptest rule //:_main~cpptest_ext~cpptest: java.io.IOException:
No MODULE.bazel, REPO.bazel, or WORKSPACE file found in .../external/_main~cpptest_ext~cpptest
```

`bazel/cpptest_ext.bzl` (see `notes.md`) symlinks `$CPPTEST_HOME` into Bazel as the
`@cpptest` repo. Bazel 7+ requires every repo root to contain a boundary marker
(`MODULE.bazel`, `REPO.bazel`, or `WORKSPACE.bazel`) — the raw Parasoft install
directory has none.

This is actually documented by Parasoft itself, in
`$CPPTEST_HOME/integration/bazel/README.txt`:

> Move `WORKSPACE.bazel`, `BUILD.bazel`, and `MODULE.bazel` from
> `<INSTALL_DIR>/integration/bazel` to `<INSTALL_DIR>`.
> Be sure to **move** the files — without keeping a copy in
> `<INSTALL_DIR>/integration/bazel`.

The first pass at fixing this literally moved (copied) those three files into
`$CPPTEST_HOME` itself, which worked but mutates a shared, outside-the-repo
install directory — undesirable since other tooling/projects may rely on that
directory staying as Parasoft shipped it, and the fix wouldn't be visible in
`git`. There's also a real gotcha if you try to *copy* instead of *move*:
leaving `BUILD.bazel` in both places breaks the build, because a `BUILD.bazel`
file marks its directory as a Bazel package — with copies in both the install
root and `integration/bazel/`, `integration/bazel` becomes its own package,
which conflicts with a `load()` in the root `BUILD.bazel` that expects
`integration/bazel` to be a plain (non-package) subdirectory:

```
ERROR: Skipping '@cpptest//:target': error loading package '@@_main~cpptest_ext~cpptest//':
Label '...//:integration/bazel/cpptest-bazel-utils.bzl' is invalid because
'...//integration/bazel' is a subpackage
```

### Better fix: synthesize the layout inside `cpptest_ext.bzl` instead

Rather than touching `$CPPTEST_HOME` at all, `bazel/cpptest_ext.bzl`'s
repository rule now builds the `@cpptest` repo's file layout itself, entirely
inside Bazel's own external-repo cache (under `~/.cache/bazel/...`, not under
`/opt/parasoft`):

- Every top-level entry of `$CPPTEST_HOME` is symlinked into the repo
  individually (instead of one `ctx.symlink(path, ".")` for the whole tree),
  *except* `integration/`, which gets special handling.
- Every entry of `integration/bazel/` is symlinked into the repo's
  `integration/bazel/`, *except* `BUILD.bazel` — leaving that subdirectory
  bazel-package-free, just like Parasoft's README wants.
- `integration/bazel/{WORKSPACE.bazel,BUILD.bazel,MODULE.bazel}` are then
  symlinked up to the synthesized repo root, giving `@cpptest` its boundary
  marker and its actual build targets.

```python
def _cpptest_impl(ctx):
    install_dir = ctx.os.environ.get("CPPTEST_HOME", "/opt/parasoft/cpptest_ct-2025.2.0-linux.x86_64")
    root = ctx.path(install_dir)

    for entry in root.readdir():
        if entry.basename != "integration":
            ctx.symlink(entry, entry.basename)

    bazel_integration = root.get_child("integration", "bazel")
    for entry in bazel_integration.readdir():
        if entry.basename != "BUILD.bazel":
            ctx.symlink(entry, "integration/bazel/" + entry.basename)

    ctx.symlink(bazel_integration.get_child("WORKSPACE.bazel"), "WORKSPACE.bazel")
    ctx.symlink(bazel_integration.get_child("BUILD.bazel"), "BUILD.bazel")
    ctx.symlink(bazel_integration.get_child("MODULE.bazel"), "MODULE.bazel")
```

Verified by running `bazel clean --expunge` (to force a fresh `@cpptest` fetch)
and re-running the full pipeline (build, test, coverage) — everything passed
exactly as before, with `$CPPTEST_HOME` confirmed to have zero new files at its
root afterward. This fix is entirely in `bazel/cpptest_ext.bzl`, which is
git-tracked, so it travels with the repo and needs no manual setup step in
`/opt/parasoft` at all — on any machine, for any `CPPTEST_HOME`.

### Note: `CPPTEST_HOME` controls the version

`bazel/cpptest_ext.bzl` reads `CPPTEST_HOME` from the environment and builds
`@cpptest` from it (falling back to a hardcoded `2025.2.0` path only if the var
is unset). `build_and_run.sh` also puts `$CPPTEST_HOME/bin` on `PATH`. So
switching Parasoft versions — e.g. from `2025.2.0` to `2026.1.0` — is just:

```sh
export CPPTEST_HOME=/opt/parasoft/cpptest_ct-2026.1.0-linux.x86_64/
```

No edits to `MODULE.bazel`, `WORKSPACE.bazel`, or `cpptest_ext.bzl` are needed —
both the Bazel repo and the CLI tools key off this one variable, and (with the
fix above) no per-install setup is needed in `$CPPTEST_HOME` either.

## 3. Install missing system header (`libacl1-dev`)

The instrumented compile of `iceoryx_platform` failed:

```
[cpptestcc] fatal error: sys/acl.h: No such file or directory
```

Only the runtime lib (`libacl1`) was installed, not the dev package:

```sh
sudo apt install libacl1-dev
```

## 4. Run the actual pipeline

With the above fixed, the original `build_and_run.sh` steps work:

```sh
export PATH=$CPPTEST_HOME/bin:$PATH

# Instrument + build the target under coverage
bazel run @cpptest//:coverage \
  --@cpptest//:target=//iceoryx_hoofs/test:hoofs_moduletests_vector \
  --@cpptest//:psrc_file=//:cpptestcc-bazel-psrc

# Execute the instrumented test binary (writes cpptest_results.clog + gtest XML)
bazel-out/k8-fastbuild/bin/iceoryx_hoofs/test/hoofs_moduletests_vector.elf --gtest_output=xml
```

Result: **108/108 tests passed** (`vector_test` suite).

## 5. Coverage report generation — license-limited metrics

`cpptestcov compute` initially produced no `.coverage` output:

```
ERROR: Invalid license
The following coverage metrics are not licensed: SC,BC,SCC,MCDC,FC,CC.
Upgrade your license to include all coverage metrics or limit enabled metrics to:
* Line Coverage (LC)
* Decision Coverage (DC)
```

The installed license only covers Line Coverage (LC) and Decision Coverage (DC).
Fix: explicitly request only those metrics:

```sh
cpptestcov compute -map .cpptest -clog cpptest_results.clog -out .coverage -coverage "LC,DC"
cpptestcov index .coverage
cpptestcov report html -code -out report/coverage.html .coverage
```

(`cpptestcov index` printed harmless `WARNING: line 0 not found in ...` for a few
files — header-only/templated code where some instrumentation markers don't map to
a real source line — output still generated successfully.)

## Result

- `report/coverage.html` generated successfully (Line + Decision coverage for
  `iceoryx_platform`, `iceoryx_hoofs`, and `hoofs_moduletests_vector`).
- All 108 `vector_test` cases passed.

## Summary of fixes

| Fix | Location | Committed to repo? | Reason |
|---|---|---|---|
| Install Bazelisk as `bazel` | `~/.local/bin/bazel` | No (machine-local) | Bazel wasn't installed at all |
| Synthesize `@cpptest` repo layout (root `WORKSPACE.bazel`/`BUILD.bazel`/`MODULE.bazel`, `integration/bazel/` without its `BUILD.bazel`) | `bazel/cpptest_ext.bzl` | **Yes** | Gives `@cpptest` a repo boundary marker without mutating `$CPPTEST_HOME`; works for any Parasoft install pointed to by `CPPTEST_HOME` |
| Install `libacl1-dev` | system package | No (machine-local) | `sys/acl.h` needed by `iceoryx_platform` |
| Pass `-coverage "LC,DC"` | `build_and_run.sh` invocation | No (just how it's invoked) | Local Parasoft license only covers Line/Decision coverage |

Only the Bazel/`libacl1-dev` install and the `-coverage` flag are machine-local
setup now — the `@cpptest` repo fix lives in `bazel/cpptest_ext.bzl` and needs
no manual repeating on other machines or other Parasoft installs.
