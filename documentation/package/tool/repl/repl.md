# REPL

> **Kind:** design · **Status:** current · **Stands on:** [package-rules.md](../../../rule/package-rules.md)

`ProjecturedREPL` is the leaf that a person loads to work: one `using` gives the editor, the examples, the SDL backend and the tests. This document says what it holds and how it gets its compiled code.

## How it works

`ProjecturedREPL` depends on `ProjecturedAll`, `ProjecturedExample`, `ProjecturedSDL` and `ProjecturedTest`. A loop over `names(module)` exports again every name that the four export, so no list of names needs care. `test_export_collisions()` checks that two of the four do not export one name with two bindings, which would make the name ambiguous. `Revise` is not a dependency: it must load before the packages that it tracks, so the session alias loads it first.

The leaf has no workload of its own. The session gets its compiled code from the images of the packages below it: each package compiles ahead of time with its `@compile_ahead`, as its preference `precompile_calls` says. [compile-ahead.md](../../../design/compile-ahead.md) holds the design, and [precompile.md](../precompile/precompile.md) says how a package compiles and how a recording is made.

## How it fits

The package is a name, four `using` lines and the loop that exports their names. Nothing depends on `ProjecturedREPL`. The session alias runs `julia --project=environment/all -i -e 'using Revise, ProjecturedREPL'`; the alias is outside this repository.

## Design decisions

- **No workload in the leaf.** Each package compiles its own code ahead of time, so a user of a release, who loads no leaf, gets the same compiled code as this session. The leaf gets a workload of its own only if a measurement shows that it needs one.

## Usage

```julia
using Revise, ProjecturedREPL         # what the session alias runs
```

- Test: `test_export_collisions()` in `test/projectured/ExportCollisionTest.jl`.
