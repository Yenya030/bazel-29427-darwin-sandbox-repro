# Bazel issue 29427 `darwin-sandbox` profile injection repro

This repro compares a normal `darwin-sandbox` action against an injected one.
Both actions try to write the same file outside the sandbox. The control target
should be blocked; the injected target should succeed and leave the generated
`sandbox.sb` containing an injected `(regex ".*")` rule.

`run-impact.sh` extends that into a clearer integrity story by overwriting a
sibling workspace's `BUILD.bazel` and then proving a later ordinary Bazel build
in that victim workspace changes behavior.

This folder is standalone apart from the Bazel client itself. It does not
depend on the surrounding checkout. The scripts will use:

- `BAZEL=/absolute/path/to/bazel` if set;
- otherwise `bazelisk` or `bazel` from `PATH`.

The checked-in `.bazelversion` pins Bazelisk to Bazel `9.1.0`, which is a
version known to reproduce this issue.

## Requirements

- macOS host with `sandbox-exec` available
- Bazel or Bazelisk

## Files

- `workspace/`
  - minimal Bazel workspace with two custom rules:
    - `//:control` uses a normal `TEST_TMPDIR`
    - `//:escape` uses `TEST_TMPDIR=") (regex ".*`
- `run.sh`
  - runs both targets with a controlled `ESCAPE_TARGET`
  - writes that target under `$HOME/.bazel-29427-repro/outside/` by default so
    cloning this repo under `/tmp` does not accidentally make the control case
    writable through macOS's normal temporary-directory allowances
  - preserves sandbox directories with `--sandbox_debug`
  - checks the output marker and the outside file
- `run-impact.sh`
  - resets a victim workspace under `$HOME/.bazel-29427-repro/victim-workspace/`
    to a safe baseline
  - shows `//:pwned` does not exist there initially
  - reruns the control and injected targets against the victim `BUILD.bazel`
  - proves the later victim build succeeds only after the injected overwrite

## Usage

```bash
./run.sh
```

If Bazel is not in `PATH`:

```bash
BAZEL=/absolute/path/to/bazel ./run.sh
```

Expected result:

- `control.txt` contains `BLOCKED`
- `escape.txt` contains `ESCAPED`
- `$HOME/.bazel-29427-repro/outside/outside.txt` exists and contains `sandbox_escape`
- printed `sandbox.sb` path contains an injected `(regex ".*")` line

On a fixed Bazel binary, the injected target should also be blocked. In that
case `escape.txt` contains `BLOCKED`, `runtime/outside.txt` is absent, and the
preserved `sandbox.sb` treats the payload as escaped string data rather than a
new sandbox policy expression.

Impact-chain repro:

```bash
./run-impact.sh
```

Expected result:

- the control action leaves victim `BUILD.bazel` unchanged
- the injected action rewrites victim `BUILD.bazel`
- the later ordinary victim build prints `PWNED`

On a fixed Bazel binary, the injected action should be blocked, the victim
`BUILD.bazel` should remain `exports_files(["safe.txt"])`, and the later
ordinary `//:pwned` build should fail because the target was never injected.
