def _cpptest_impl(ctx):
    install_dir = ctx.os.environ.get("CPPTEST_HOME", "/opt/parasoft/cpptest_ct-2025.2.0-linux.x86_64")
    root = ctx.path(install_dir)

    # Mirror everything at the install root except "integration", which needs
    # special handling below.
    for entry in root.readdir():
        if entry.basename != "integration":
            ctx.symlink(entry, entry.basename)

    # Parasoft ships its Bazel integration (WORKSPACE.bazel/BUILD.bazel/MODULE.bazel)
    # under integration/bazel/ instead of at the install root. Their own setup
    # instructions (integration/bazel/README.txt) say to move those three files to
    # the install root, without leaving a copy of BUILD.bazel behind - a leftover
    # BUILD.bazel there makes integration/bazel its own Bazel package, which breaks
    # a load() in the promoted BUILD.bazel expecting integration/bazel to be a
    # plain subdirectory. Synthesize that layout here, inside the @cpptest repo
    # only, instead of mutating the real (shared) install directory.
    bazel_integration = root.get_child("integration", "bazel")
    for entry in bazel_integration.readdir():
        if entry.basename != "BUILD.bazel":
            ctx.symlink(entry, "integration/bazel/" + entry.basename)

    ctx.symlink(bazel_integration.get_child("WORKSPACE.bazel"), "WORKSPACE.bazel")
    ctx.symlink(bazel_integration.get_child("BUILD.bazel"), "BUILD.bazel")
    ctx.symlink(bazel_integration.get_child("MODULE.bazel"), "MODULE.bazel")

_cpptest = repository_rule(
    implementation = _cpptest_impl,
    environ = ["CPPTEST_HOME"],
    local = True,
)

def _ext_impl(mctx):
    _cpptest(name = "cpptest")

cpptest_ext = module_extension(implementation = _ext_impl, environ = ["CPPTEST_HOME"])
