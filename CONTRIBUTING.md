# Contributing to ProjecturEd

Welcome. This document covers repository conventions, how to run the tests,
code style expectations, and how to submit a change.

---

## Prerequisites

- Julia 1.11 or later. The `Project.toml` files use `[sources]` path
  dependencies, which older versions of Pkg do not read.
- SDL2 and SDL_ttf (`apt install libsdl2-dev libsdl2-ttf-dev` on
  Debian/Ubuntu). They are needed only for the SDL backend. The test suite runs
  without them.
- Git.

## Sealed files

[SEALING.md](SEALING.md) lists the files that are sealed. A sealed file must
not change without explicit permission. Read it before you touch a file under
`source/kernel/`.

## Project structure

One dimension per level. What a file **is** decides its top folder, and the
**slice** it belongs to decides the folder under that.

```
source/         → the system, one folder per slice; kernel/ holds the layers
test/           → the suites, one folder per slice, plus suite/
example/        → documents, galleries and workload bodies, one folder per slice
package/        → one folder per package: a Project.toml and a src/<Name>.jl
environment/    → all/ — the resolved closure the whole suite runs in; no code
documentation/  → all documentation
plan/           → design notes and work-in-progress plans (internal)
asset/          → fonts, screenshots, the web client, the precompile recording
tool/           → scripts that are not part of the system
```

**A package and its code do not share a directory.**
`package/ProjecturedJson/` holds a name and an include list; the code it
includes is `source/json/`, its suite is `test/json/` and its documents are
`example/json/`. The [README](README.md#repository-layout) has the same table
with a link on every row.

A stem has up to five packages, and the suffix says which kind each one is:

| kind | name | what it holds |
| --- | --- | --- |
| main | `Stem` | the code |
| example | `StemExample` | documents, galleries and workload bodies |
| test | `StemTest` | the suite |
| repl | `StemRepl` | the leaf a person loads to work |
| build | `StemBuild` | the leaf a binary is compiled from |

The JSON domain has the first three: `ProjecturedJson`,
`ProjecturedJsonExample` and `ProjecturedJsonTest`. The two leaves of the
repository are `ProjecturedRepl` and `ProjecturedBench`. A build writes one
more leaf for each binary, under `build/app/`. Nothing may depend on a leaf.

The packages are linked by `[sources]` path dependencies. Read
[documentation/rule/package-rules.md](documentation/rule/package-rules.md) for
what each kind may depend on, why a `@compile_workload` belongs only in a leaf,
and which package a third-party dependency makes a stem of its own. The terms
package, layer, slice, module and leaf are defined in
[documentation/rule/division-terminology.md](documentation/rule/division-terminology.md).

## Running the tests

There is no `Project.toml` at the root. The whole suite runs in
`environment/all`:

```julia
julia --project=environment/all
using ProjecturedTest
test_all()          # the full suite, about 47 minutes

# Or the narrowest scope that covers your change (preferred):
test_kernel()               # one package's suite (also: test_substrate(), …)
test_json()                 # one domain
test_printer(json_example)  # one example
```

A per-package suite also runs in its own test package, which depends only on
the packages below it. Use that when SDL, ODBC or Tulip are not installed:

```julia
julia --project=package/ProjecturedKernelTest
using ProjecturedKernelTest
test_kernel()
```

See [documentation/guide/testing-guide.md](documentation/guide/testing-guide.md)
for the full list of per-package helpers and the walker utilities behind them.

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

Read [documentation/rule/naming-rules.md](documentation/rule/naming-rules.md)
before you write a name. It is a rule, not a suggestion: every function name
starts with a verb, a predicate is `is_…` or `has_…`, a function that mutates
ends with `!`, and no name carries an ad-hoc abbreviation.

### 1-based indexing

All indexing is 1-based, consistent with Julia convention. Document children
are `[1]`, `[2]`, …; cursor boundaries are `{0}`, `{1}`, …

### Every field is a `Cell`

Domain struct fields are wrapped in `Cell`. The `@document` macro makes this
transparent at call sites — `doc.field` reads the cell value and
`doc.field = v` writes to it. Do not access raw cells with `getfield` unless
you deliberately bypass reactivity, which is rare and needs a comment.

### Projections must be bidirectional

Every `print_document` method needs a matching `read_intent` method, or the
forward and backward mappers `map_reference_forward` and
`map_reference_backward` that the default reader uses. A printer-only
projection is a decision, and the docstring of the struct must say so. The IO
map is what makes the inversion possible: return a `SimpleIoMap` or a
specialised `{Name}IoMap` that carries enough data for the reader.

### One module per slice

Each slice and each projection lives in its own `module`. Add only the
dependencies that the source names. `test_package_graph()` asserts that a
package declares exactly the packages its own source names — no more and no
less.

### Tests for new code

Every new projection needs:

1. A printer test that checks the output structure for at least one input.
2. A reader test that checks selection translation for at least one event.
3. An example, so that `run_example("mydomain")` works.

Use `@testset "Name" begin … end` wrapped in a `function test_my_feature()`
function, and follow the pattern in `test/projectured/projection/`.

### No unrelated formatting changes

Keep diffs focused. Do not reformat lines that you do not change. It makes
review harder.

## Pull request process

1. Fork the repository and create a branch.
2. Make your changes. Follow the style guidelines above.
3. Run the narrowest test that covers the change. See
   [documentation/guide/testing-guide.md](documentation/guide/testing-guide.md).
   Confirm that it passes.
4. If you added a domain or a projection, add a test file under `test/<slice>/`
   and register it in the test package of the lowest tier that can express it.
   `Projectured<Name>Test` takes a fixture that is that domain's document;
   `ProjecturedTest` takes one that names several domains.
5. Update the guide that the change makes wrong. Cross-cutting guides live in
   [documentation/](documentation/); the per-slice reference guides live in
   [documentation/package/](documentation/package/).
6. Open a pull request. The description explains *what* changed and *why*, and
   links to the `plan/` document if one exists.

## Adding a new domain (quick checklist)

A full walkthrough is in
[documentation/guide/new-domain-guide.md](documentation/guide/new-domain-guide.md).
A domain is a package;
[documentation/design/domain-inventory.md](documentation/design/domain-inventory.md)
has the full rules. The short version:

- [ ] `package/ProjecturedMyDomain/Project.toml` — a fresh UUID, then `[deps]`
      and `[sources]` for `ProjecturedKernel`, the substrate packages it
      imports, and any domain it embeds.
- [ ] `package/ProjecturedMyDomain/src/ProjecturedMyDomain.jl` — the root
      module: the `using` list, the submodule-binding loop, then the includes.
      Every include names a file under `source/mydomain/`.
- [ ] `source/mydomain/MyDomain.jl` — the document types, declared with
      `@document`, which appends a `selection::Union{Nothing, Reference}` field
      to every one of them. Add the operations of the domain here.
- [ ] `source/mydomain/MyDomainToSyntax.jl` — `print_document`, and the
      mappers or the `read_intent` methods, for each document type.
- [ ] Register the domain with the render-anything projection from that same
      file: `register_natural_syntax!(:mydomain, () -> …)` in an `__init__`.
- [ ] `package/ProjecturedMyDomainExample/` with its code in
      `example/mydomain/` — `make_mydomain_document_example()` and
      `make_mydomain_projection_example()`.
- [ ] Register the `Example` in `example/projectured/DomainExamples.jl`, and
      add it to the `examples` vector in
      `example/projectured/ProjecturedExamples.jl`.
- [ ] `package/ProjecturedMyDomainTest/` with its code in `test/mydomain/` —
      printer and reader tests behind a `test_mydomain()` aggregator.
- [ ] Add the three packages to `Projectured`, `ProjecturedExample` and
      `ProjecturedTest`, and to `environment/all/Project.toml`. Then run
      `Pkg.resolve()`. `Pkg.instantiate()` does not resolve again, and the
      error it gives names the wrong cause.
- [ ] Add `documentation/package/mydomain/mydomain.md`, the per-slice guide.

## Contact

levente.meszaros@gmail.com
