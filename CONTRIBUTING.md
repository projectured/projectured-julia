# Contributing to ProjecturEd

Welcome. This document covers repo conventions, how to run the tests, code
style expectations, and how to submit a change.

---

## Prerequisites

- Julia 1.11+ (the `Project.toml` files use `[sources]` and `entryfile`)
- SDL2 and SDL_ttf (`apt install libsdl2-dev libsdl2-ttf-dev` on Debian/Ubuntu)
  — only for the SDL backend; the test suite runs without them
- Git

## Project structure

```
package/        → one folder per package triad (see below)
documentation/  → all documentation
plan/           → design notes and work-in-progress plans (internal)
asset/          → bundled fonts, screenshots, and UI icons
```

Every package under `package/<name>/` is a **triad** of up to three sibling
Julia packages in one grouping folder (which itself has no `Project.toml`):

```
package/kernel/
├── main/       → ProjecturedKernel        (the main package: the code)
├── test/       → ProjecturedKernelTest    (its test suite)
└── example/    → ProjecturedKernelExample (its examples)
```

Each subfolder holds its own `Project.toml` with its code directly beside it
(no `main/` level — the `entryfile` key names the entry module file). The
packages are linked by `[sources]` path dependencies. See
[documentation/architecture-rules.md](documentation/architecture-rules.md) for
the main/test/example DAGs and the rules that keep them parallel.

## Running the tests

```julia
julia --project=package/projectured/test
using ProjecturedTest
test_all()          # full suite

# Or the narrowest scope that covers your change (preferred):
test_kernel()       # one package's suite (also: test_substrate(), test_json(), …)
test_json()         # one domain
test_printer(json_example)  # one example
```

See [documentation/testing.md](documentation/testing.md) for the full list of per-layer
helpers and the walker utilities behind them.

## Running an example

```julia
julia --project=environment/all
using Projectured, ProjecturedExample
run_example()            # JSON example
run_example("widget")    # widget form example
write_example_image("json", "/tmp/snapshot.bmp")  # save screenshot
```

Press **Escape** to close the window.

## Code style

### 1-based indexing

All indexing is 1-based, consistent with Julia convention. Document children
are `[1]`, `[2]`, …; cursor boundaries are `{0}`, `{1}`, …

### Every field is a `Cell`

Domain struct fields are wrapped in `Cell`. The `@document` macro makes this
transparent at call sites — `doc.field` reads the cell value and
`doc.field = v` writes to it. Do not access raw cells with `getfield` unless
you are deliberately bypassing reactivity (which is rare and should be
commented).

### Projections must be bidirectional

Every `projection_print` method needs a matching `projection_read` method (or
an explicit decision that it is printer-only, documented in the struct's
docstring). The IO map is what makes inversion possible — return a `SimpleIoMap`
or a specialised `{Name}IoMap` that carries enough data for the reader.

### Module-per-domain, module-per-projection

Each domain and each projection lives in its own `module`. Only add
dependencies that are strictly needed — keep the dependency graph auditable.

### Tests for new code

Every new projection needs:
1. A printer test (verify the output structure for at least one input).
2. A reader test (verify selection translation for at least one event).
3. An example (so `run_example("my_domain")` works).

Use `@testset "Name" begin ... end` wrapped in a `function test_my_feature()`
function, following the existing pattern in `package/projectured/test/projection/`.

### No unrelated formatting changes

Keep diffs focused. Do not reformat lines you are not logically changing — it
makes review harder.

## Pull request process

1. Fork the repository and create a branch.
2. Make your changes. Follow the style guidelines above.
3. Run the narrowest test that covers the change (see
   [documentation/testing.md](documentation/testing.md)) and confirm it passes.
4. If you added a domain or projection, add a corresponding test file and
   register it in the test package of the lowest tier that can express it —
   `package/<domain>/test` when the fixture is that domain's document,
   `package/projectured/test` when it names several domains.
5. Update the relevant guide if the change affects documented behaviour —
   cross-cutting guides live in `documentation/`, per-package/per-domain
   reference guides in that package's `doc/` directory.
6. Open a pull request. The description should explain *what* changed and
   *why*; link to the relevant `plan/` document if one exists.

## Adding a new domain (quick checklist)

A full walkthrough is in [documentation/tutorial-new-domain.md](documentation/tutorial-new-domain.md).
The short version:

A domain is a package. [documentation/domains.md](documentation/domains.md) has
the full rules; the short version:

- [ ] `package/mydomain/main/Project.toml` — a fresh UUID, deps on
      `ProjecturedKernel`, the substrate packages it imports, plus any
      domain you embed.
- [ ] `package/mydomain/main/ProjecturedMyDomain.jl` — the root module: the
      submodule-binding loop, then the includes.
- [ ] `package/mydomain/main/MyDomain.jl` — define document types with
      `@document` (it injects the `selection::Reference` field automatically)
      and any domain-specific operations.
- [ ] `package/mydomain/main/MyDomainToSyntax.jl` — `print_document` and
      `read_intent` methods for each document type.
- [ ] Register the domain with the render-anything projection from that same
      file: `register_natural_syntax!(:mydomain, () -> …)` in an `__init__`.
- [ ] `package/mydomain/example/` — `make_my_domain_document_example()` and
      `make_my_domain_projection_example()`, in their own example package.
- [ ] Register the `Example` in `package/projectured/example/DomainExamples.jl`.
- [ ] `package/mydomain/test/` — printer and reader tests behind a
      `test_mydomain()` aggregator.
- [ ] Add all three to `Projectured`, `ProjecturedExample` and `ProjecturedTest`,
      and to the root `Project.toml`. Then run `Pkg.resolve()`.
- [ ] Add `package/mydomain/doc/mydomain.md` (per-domain guide, next to the code).

## Contact

levente.meszaros@gmail.com
