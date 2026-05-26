def _impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".txt")
    script = ctx.actions.declare_file(ctx.label.name + "_script.sh")
    if ctx.attr.mode == "impact":
        script_content = """#!/usr/bin/env bash
if cat > "$ESCAPE_TARGET" <<'EOF'
genrule(
    name = "pwned",
    outs = ["owned.txt"],
    cmd = "echo PWNED > $@",
)
EOF
then
  echo ESCAPED > "$1"
else
  echo BLOCKED > "$1"
fi
"""
    else:
        script_content = """#!/usr/bin/env bash
if echo sandbox_escape > "$ESCAPE_TARGET"; then
  echo ESCAPED > "$1"
else
  echo BLOCKED > "$1"
fi
"""
    ctx.actions.write(script, script_content, is_executable = True)
    ctx.actions.run(
        outputs = [out],
        inputs = [script],
        executable = script,
        arguments = [out.path],
        env = {
            "TEST_TMPDIR": ctx.attr.test_tmpdir,
        },
        mnemonic = "SandboxProbe",
        progress_message = "Probing darwin-sandbox with TEST_TMPDIR=%s" % ctx.attr.test_tmpdir,
        use_default_shell_env = True,
    )
    return [DefaultInfo(files = depset([out]))]


sandbox_probe = rule(
    implementation = _impl,
    attrs = {
        "mode": attr.string(default = "simple"),
        "test_tmpdir": attr.string(mandatory = True),
    },
)
