# Project Notes

## Bazel Configuration

### Hardcoded Path: `cpptest` Install Location

Both `MODULE.bazel` and `WORKSPACE.bazel` currently hardcode the Parasoft cpptest installation path:

```
/opt/parasoft/cpptest_ct-2025.2.0-linux.x86_64
```

This path appears as:
- `local_path_override` in `MODULE.bazel`
- `local_repository` in `WORKSPACE.bazel` (see note below — this entry is dead code)

#### Externalizing the Path (Options)

Neither `local_path_override` nor `local_repository` natively support environment variable interpolation. Two approaches to externalize:

**Option A — Custom repository rule + module extension (recommended)**

Uses `CPPTEST_HOME`, the env var already established in `build_and_run.sh`.

Create `bazel/cpptest_ext.bzl`:
```python
def _cpptest_impl(ctx):
    path = ctx.os.environ.get("CPPTEST_HOME", "/opt/parasoft/cpptest_ct-2025.2.0-linux.x86_64")
    ctx.symlink(path, ".")

_cpptest = repository_rule(
    implementation = _cpptest_impl,
    environ = ["CPPTEST_HOME"],
    local = True,
)

def _ext_impl(mctx):
    _cpptest(name = "cpptest")

cpptest_ext = module_extension(implementation = _ext_impl, environ = ["CPPTEST_HOME"])
```

Update `MODULE.bazel` — replace `bazel_dep(cpptest)` + `local_path_override` with:
```python
cpptest_ext = use_extension("//bazel:cpptest_ext.bzl", "cpptest_ext")
use_repo(cpptest_ext, "cpptest")
```

Users set `export CPPTEST_HOME=/your/path` in their shell. Bazel picks it up automatically via the declared `environ` attribute.

**Option B — Per-user `.bazelrc` file (simpler, no `.bzl` changes)**

Add to `.bazelrc`:
```
try-import %workspace%/user.bazelrc
```

Each user creates a gitignored `user.bazelrc`:
```
build --override_module=cpptest=/opt/parasoft/cpptest_ct-2025.2.0-linux.x86_64
```

This replaces `local_path_override` in `MODULE.bazel`. WORKSPACE.bazel would still need a custom rule or remain hardcoded.

---

### `local_repository(name = "cpptest", ...)` in WORKSPACE.bazel is Dead Code

This entry is **never used** and can be safely deleted.

**Why:** This project uses bzlmod (`MODULE.bazel` is present; Bazel 7+ enables it by default). When bzlmod is active, `MODULE.bazel` definitions take precedence over `WORKSPACE.bazel` for any module declared there. The `cpptest` repository is already resolved by `local_path_override` in `MODULE.bazel`, so the `local_repository` entry in `WORKSPACE.bazel` is silently shadowed.

It is a legacy artifact from before bzlmod was adopted — the entry was added when cpptest was first integrated via the old WORKSPACE-only approach, then MODULE.bazel was added later without removing this now-redundant line.

**Important:** Only the `local_repository(name = "cpptest", ...)` line is dead code. The rest of `WORKSPACE.bazel` is still active and loads other dependencies (`rules_foreign_cc`, etc.) not yet fully migrated to MODULE.bazel. **Do not delete `WORKSPACE.bazel`.**
