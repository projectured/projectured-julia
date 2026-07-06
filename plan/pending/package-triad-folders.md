# Package triad folders

Co-locate each runtime package's test and example packages **inside its own
directory**: `package/<name>/{src, test, example}` instead of the sibling
`package/<name>`, `package/<name>-test`, `package/<name>-example` folders the
splits created. The test/example packages stay **full, separate packages**
(same names, UUIDs, deps, module files) — this is pure path plumbing; a Julia
package is defined by its `Project.toml`, not by where its directory sits.

## Target layout

```
package/kernel/       ProjecturedKernel          (src/, doc/)
  test/               ProjecturedKernelTest      (Project.toml, src/, test/runtests.jl)
  example/            ProjecturedKernelExample   (Project.toml, src/)
package/base/         ProjecturedBase
  test/               ProjecturedBaseTest
package/visual/       ProjecturedVisual
  test/               ProjecturedVisualTest
  example/            ProjecturedVisualExample
package/domain/       ProjecturedDomain
  test/               ProjecturedDomainTest
  example/            ProjecturedDomainExample
package/projectured/  Projectured (umbrella)
  test/               ProjecturedTest            (moves from package/test)
  example/            ProjecturedExample         (moves from package/example)
```

The umbrella triad moves too — `package/test` → `package/projectured/test`,
`package/example` → `package/projectured/example` — so the rule holds for
every package that has tests or examples. Opt-in packages
(sdl/web/odbc/tulip/video/llm/mcp/adaptagrams) have neither yet; when they
grow one, it goes in `package/<name>/test` from the start.
`package/extras-example` stays (it is the *extras'* example package, above
the umbrella).

## Directory moves

| from | to |
| --- | --- |
| package/kernel-test | package/kernel/test |
| package/kernel-example | package/kernel/example |
| package/base-test | package/base/test |
| package/visual-test | package/visual/test |
| package/visual-example | package/visual/example |
| package/domain-test | package/domain/test |
| package/domain-example | package/domain/example |
| package/test | package/projectured/test |
| package/example | package/projectured/example |

## What must change (all mechanical)

1. **`[sources]` paths** in every Project.toml that names a moved package or
   is itself moved (nesting shortens sibling paths: a test package's runtime
   dep becomes `path = ".."`, its example sibling `"../example"`, a lower
   tier `"../../kernel/test"`). Affected: root `Project.toml`, the seven
   moved test/example packages, `package/projectured/test`,
   `package/projectured/example`, `package/extras-example` (if it gains
   sources; today its deps resolve through the root env — nothing to do).
2. **Root `Manifest.toml`** `path = "package/…"` entries for the nine moved
   packages.
3. **Repo-root escapes** in moved sources gain one `..`:
   `Examples.jl` (screenshot harness ×3, now under `projectured/example/src`),
   `Gallery.jl` (screenshot image dir), `visual/example/src/document/Text.jl`
   (asset image load).
4. **`.gitignore`**: `package/*-test/Manifest.toml` /
   `package/*-example/Manifest.toml` → `package/*/test/Manifest.toml` /
   `package/*/example/Manifest.toml`.
5. **Docs**: CLAUDE.md, documentation/testing.md, architecture-rules.md,
   architecture.md, debugging.md — path mentions of `package/<x>-test` /
   `package/<x>-example` / `package/test` / `package/example`. Historical
   plan/done files stay as written (they describe the state at their time).

## The `test/` reserved-name corner

`Pkg.test("ProjecturedKernel")` looks for `test/runtests.jl` under the
package root and, if `test/Project.toml` exists, uses it as the test
environment. After the move, `package/kernel/test/Project.toml` **is** the
ProjecturedKernelTest package project. Two cases:

- **No `package/kernel/test/runtests.jl` (top level)**: `Pkg.test` on the
  runtime package errors with "no test file" — same as today (the runtime
  packages dropped their `[targets]` in the test split). Nothing breaks.
- **Optionally add one** (`using ProjecturedKernelTest; test_kernel()`): if
  an experiment shows Pkg accepts a *named package project* as the test env,
  `Pkg.test("ProjecturedKernel")` starts working again for free. Decided by
  the experiment in Phase 0; if Pkg misbehaves, skip the shim — the
  function-library entry points and `Pkg.test("ProjecturedKernelTest")` (its
  own nested `test/runtests.jl`) already cover both workflows.

Note the harmless oddity either way: each test package keeps its own
one-line `test/runtests.jl`, which now sits at `package/<x>/test/test/runtests.jl`.

## Phases

- [ ] **Phase 0 — experiment.** In a scratch env, point `Pkg.test` at a
  nested-layout kernel and see whether a named test/Project.toml works as
  the test env. Record the outcome here; add the top-level runtests shims
  only if it behaves.
- [ ] **Phase 1 — move + rewire.** `git mv` the nine directories; rewrite
  `[sources]`, the root Manifest, the repo-root escapes, and `.gitignore`.
  Verify offline: `test_kernel()`, `test_base()`, `test_visual()`,
  `test_domain()` from their (new) per-package envs; the three example
  packages load; umbrella + executable sources parse.
- [ ] **Phase 2 — docs.** Update the path mentions (CLAUDE.md, testing.md,
  architecture-rules.md, architecture.md, debugging.md); move this plan to
  plan/done/.

## Risks

- **Pkg.test env semantics** — contained by the Phase 0 experiment; the
  fallback (no shim) is exactly today's behavior.
- **Registration (future)**: a registered ProjecturedKernel tarball would
  include the nested test/example trees, and test edits would churn its
  tree-hash. Irrelevant for the path-`[sources]` monorepo; revisit if
  registration ever lands.
- **Path-glob tooling**: anything enumerating `package/*/Project.toml` must
  not treat nested projects as top-level packages (nothing in-repo does
  today; the layering guards scope to `src/`).
- **Stale per-package Manifests**: the moved test/example envs carry
  generated (ignored) Manifests whose relative paths break after the move —
  they must be deleted so the first run regenerates them.

## Out of scope

Registering packages; adding tests/examples to opt-in packages; renaming the
`-test`/`-example` module names (ProjecturedKernelTest etc. stay — only the
directories move).
