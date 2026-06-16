# Contributing to ProjecturEd

Welcome. This document covers repo conventions, how to run the tests, code
style expectations, and how to submit a change.

---

## Prerequisites

- Julia 1.10+
- SDL2 and SDL_ttf (`apt install libsdl2-dev libsdl2-ttf-dev` on Debian/Ubuntu)
- Git

## Project structure

```
program/    → core Projectured package (Julia module)
example/    → ProjecturedExample package (examples + REPL helpers)
test/       → ProjecturedTest package (test suite)
guide/      → all documentation
plan/       → design notes and work-in-progress plans (internal)
font/       → bundled font assets
image/      → screenshots and UI icons
```

Each of `program/`, `example/`, and `test/` is its own Julia project with its
own `Project.toml`. They are linked by path dependencies.

## Running the tests

```julia
julia --project=test
using ProjecturedTest
test_all()          # full suite (~30 s)

# Or individual layers:
test_printers()
test_readers()
test_text_navigations()
test_repls()
test_mcp_tools()
```

See [guide/testing.md](guide/testing.md) for the full list of per-layer
helpers and the walker utilities behind them.

## Running an example

```julia
julia --project=.
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
function, following the existing pattern in `test/src/projection/`.

### No unrelated formatting changes

Keep diffs focused. Do not reformat lines you are not logically changing — it
makes review harder.

## Pull request process

1. Fork the repository and create a branch.
2. Make your changes. Follow the style guidelines above.
3. Run the test suite (`test_all()`) and confirm it passes.
4. If you added a domain or projection, add a corresponding test file and
   register it in `test/src/ProjecturedTest.jl`.
5. Update the relevant guide in `guide/document/` or `guide/` if the change
   affects documented behaviour.
6. Open a pull request. The description should explain *what* changed and
   *why*; link to the relevant `plan/` document if one exists.

## Adding a new domain (quick checklist)

A full walkthrough is in [guide/tutorial-new-domain.md](guide/tutorial-new-domain.md).
The short version:

- [ ] `program/src/document/MyDomain.jl` — define document types with `@document`,
      `selection::Reference`, and any domain-specific operations.
- [ ] Include in `program/src/Projectured.jl` and add `using` + `export` lines.
- [ ] `program/src/projection/primitive/MyDomainToSyntax.jl` — `projection_print`
      methods for each document type.
- [ ] `projection_read` methods for each printer.
- [ ] `example/src/document/MyDomain.jl` — `make_my_domain_document_example()`.
- [ ] `example/src/projection/MyDomain.jl` — `make_my_domain_projection_example()`.
- [ ] Register in `example/src/Examples.jl` and `example/src/ProjecturedExample.jl`.
- [ ] `test/src/projection/MyDomainTest.jl` — printer + reader tests.
- [ ] Register in `test/src/ProjecturedTest.jl`.
- [ ] Update `guide/document/my-domain.md`.

## Contact

levente.meszaros@gmail.com
