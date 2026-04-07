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
