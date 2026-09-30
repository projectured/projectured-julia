# Packages

> **Kind:** rule · **Status:** current · **Stands on:** [division-terminology.md](division-terminology.md), [system-anatomy.md](../design/system-anatomy.md)

What a package here is for, what it may depend on, and which one you load.

- [system-anatomy.md](../design/system-anatomy.md) — what the layers hold and how they stack.
- [domain-inventory.md](../design/domain-inventory.md) — the twenty-one domain packages, and what makes one.
- [division-terminology.md](division-terminology.md) — package, layer, slice, module, leaf.

This document is the shape those are arranged in.

## The five kinds

Every stem has up to five packages, and the suffix says which kind it is:

| kind | name | what it holds |
| --- | --- | --- |
| main | `Stem` | the code |
| example | `StemExample` | documents, galleries, and the workload **bodies** |
| test | `StemTest` | the suite |
| repl | `StemRepl` | the leaf a person loads to work |
| build | `StemBuild` | the leaf a binary is compiled from |

Here no build leaf is checked in. `ProjecturedBuilder` is the tool that drives
a build, and each build writes the package that PackageCompiler compiles, under
`build/app/<name>/`. That package is a leaf: nothing depends on it, and its
`@compile_workload` runs the workload of the binary. A tool is not a stem
artifact at all.

`Example`, `Test`, `Repl` and `Build` are the only reserved suffixes. A package
whose name merely begins with another's — `ProjecturedOdbc`, `ProjecturedTulip`
— is a **stem of its own**, not a kind of `Projectured`.

## One dependency direction

```
Foo         -> Bar, and every sub-stem of Foo
FooExample  -> Foo,  BarExample
FooTest     -> Foo,  BarTest, FooExample
FooRepl     -> ProjecturedTest and what a prompt needs          (leaf)
FooBuild    -> FooExample                                       (leaf)
```

**Nothing may depend on a `Repl` or a `Build` package.** That is not a matter of
taste; it is the whole mechanism, and [the next section](#why-the-leaf-matters)
says why. `test_package_graph()` asserts it, along with two more:

- an example package is a dependency only of a leaf, an example or a test;
- a `@compile_workload` lives only in a leaf.

### A package with a third-party dependency is a stem, not a sub-stem

`Projectured` aggregates its layers — Kernel, Base, Visual and the twenty-one
domain packages, none of which has a third-party dependency. It deliberately does not
aggregate `ProjecturedSdl`, `ProjecturedOdbc`, `ProjecturedTulip`,
`ProjecturedVideo`, `ProjecturedAnthropic`, `ProjecturedOllama`, `ProjecturedMcp`,
`ProjecturedWeb`, `ProjecturedDataFrames` or
`ProjecturedAdaptagrams`, each of which owns one.

The rule: a sub-stem is a layer and carries no third-party dependency of its
own; a package that has one is a stem in its own right, named explicitly by
whoever wants it. Without it, `using Projectured` would drag an ODBC driver
manager and a linear-programming solver into every session.

## Why the leaf matters

A package image is built with exactly that package's dependencies present. So
compiled code survives only in a package that nothing depends on and nothing
loads after — the leaf the alias loads. Everything below it has its compiled
code **invalidated** when the session finishes loading, because a method added
later can void a call site that was already compiled, and a session ends up
loading a great many packages that add methods to `Base` functions.

Measured, a first paint of a JSON document in a fresh session:

| | first paint |
| --- | ---: |
| with no workload anywhere | 8.36 s |
| with a workload in the leaf | **0.66 s** |

That is why `@compile_workload` is asserted to live only in a leaf, and why the
body it calls — `ProjecturedExample.precompile_workload(level)` — is an ordinary
function rather than code inside the macro. Both leaves call the same one.

## The session

```bash
jp   # julia --project=environment/all -i -e 'using Revise, ProjecturedRepl'
```

`ProjecturedRepl` re-exports what it names, so one `using` gives the session you
expect: `run_example`, `test_all`, `SdlBackend`, every document and projection
constructor. Revise stays in the alias and out of the package's dependencies: it
must be loaded before the packages it tracks, and as a dependency its position
in the load order is the resolver's business. **Nothing may be loaded after the
leaf.**

How much the build compiles is a Preference, so changing it rebuilds:

```julia
julia> get_workload()          # what this session was built with
julia> set_workload!(:recorded)  # then restart
```

| level | what the build does |
| --- | --- |
| `:none` | nothing; for a day spent editing the kernel |
| `:recorded` | replays `asset/precompile/PrecompileStatements.jl` — the default |
| `:live` | runs `ProjecturedExample.precompile_workload()` |

`:recorded` replays a list that a person recorded by driving the editor, rather
than a workload somebody wrote. That is why it is the only level that compiles
the **reader**: a workload prints atoms, and an atom is never read. Measured on
the json example, the first click costs 475 ms at `:recorded` and 2600 ms at
`:live`, of which the read half is 221 ms against 1494 ms.

Record again with `record_precompile_statements()` when the list falls behind
the code. It goes stale gracefully: a statement that names nothing is skipped.
The build says how many were skipped, warning past a tenth of them.
Recording needs a display: the driver opens a real window.

**Set `workload = :none` before you record, and put it back after.** A trace
reports what actually had to be COMPILED, and a `:recorded` build already holds
the old list in its image — so those methods never compile, never reach the
trace, and never reach the new list. Recording on top of `:recorded` therefore
yields the *residue*: measured on 2026-09-10, 6963 statements sharing 174 entries
with the 12760 it would have replaced. It looks like a recording and it is a
downgrade, and each repeat shrinks the list again.

The same run at `:none` gave 12342 statements. Of the 7485 the old list held and
it dropped, 7033 — 94 % — no longer resolved at all, so the old list was more
than half dead. 452 still resolved: a recording replaces, it does not merge, and
that is the price of a generated file that stays reproducible from its driver.

```julia
julia> set_workload!(:none)        # then restart
julia> record_precompile_statements()
julia> set_workload!(:recorded)    # then restart; the next build replays the new list
```

**Check a new list before you keep it.** Compare it with the one in git: a
comparable SIZE says the recording was made against a bare build, and the
fraction of the dropped entries that no longer resolve says whether the old list
was stale or the new run missed coverage.

Each level caches its own image, so switching back to one you have built is
instant. `~/.julia/compiled/*/ProjecturedRepl/` grows accordingly
(13 MB at `:none`, 149 MB at `:live`, 217 MB at `:recorded`). `Pkg.gc()` clears
what you no longer use.

A binary makes its own choice: the `workload` keyword of `build_executable`
is the expression that the generated package runs in its `@compile_workload`.
The `projectured` binary runs `warm_application()`, which opens the application
once without a window.

## What depends on what

Every dependency below is **direct**: the package imports a module of it. Julia
needs each direct dependency in `[deps]`, and
`ProjecturedTest.test_package_graph()` asserts that a package declares exactly
the packages its own source names — no more and no less.

The kernel depends on nothing. A row names it only where it is the one
dependency.

### The twenty-nine packages of the substrate

| package | depends on | third-party |
| --- | --- | --- |
| `ProjecturedCollection` | Kernel | — |
| `ProjecturedSerialization` | Kernel | Serialization |
| `ProjecturedPrimitive` | Kernel | — |
| `ProjecturedDomain` | Kernel | — |
| `ProjecturedStyle` | Kernel | — |
| `ProjecturedComponent` | Kernel | — |
| `ProjecturedProjection` | Collection, Primitive | — |
| `ProjecturedDragging` | Collection, Projection | — |
| `ProjecturedFocus` | Collection | — |
| `ProjecturedVersioning` | Collection, Domain, Primitive | — |
| `ProjecturedPlot` | Style | — |
| `ProjecturedGraphics` | Collection, Projection, Style | — |
| `ProjecturedScreen` | Collection, Graphics, Primitive, Projection | — |
| `ProjecturedLayout` | Collection, Focus, Graphics, Projection | — |
| `ProjecturedText` | Collection, Domain, Graphics, Primitive, Projection, Style | — |
| `ProjecturedWidget` | Collection, Domain, Focus, Graphics, Layout, Primitive, Projection, Screen, Serialization, Style, Text | — |
| `ProjecturedReflection` | Collection, Widget | — |
| `ProjecturedClipboard` | Collection, Domain, Primitive, Projection, Serialization, Text | — |
| `ProjecturedPane` | Clipboard, Collection, Domain, Dragging, Focus, Layout, Primitive, Projection, Serialization, Widget | — |
| `ProjecturedTooltip` | Screen | — |
| `ProjecturedNatural` | Collection, Domain, Layout, Primitive, Projection, Style, Text, Widget | — |
| `ProjecturedSyntax` | Collection, Domain, Natural, Primitive, Projection, Style, Text | — |
| `ProjecturedInspector` | Domain, Natural, Projection, Screen, Serialization, Style, Text | — |
| `ProjecturedGestureHelp` | Collection, Graphics, Projection, Screen, Style, Syntax, Text | — |
| `ProjecturedGestureLog` | Collection, Domain, Graphics, Natural, Projection, Serialization, Style, Syntax, Text | — |
| `ProjecturedFileFormat` | Collection, Domain, Layout, Natural, Primitive, Projection, Serialization, Style, Syntax, Text, Widget | — |
| `ProjecturedFault` | Collection, Domain, Graphics, Natural, Projection, Serialization, Style, Syntax, Text, Widget | — |
| `ProjecturedConsole` | Style, Text | — |
| `ProjecturedPdf` | Graphics, Style | — |

### The twenty-one domains

Each domain depends on the kernel, on the substrate packages it uses, and on
the domains it embeds. [domain-inventory.md](../design/domain-inventory.md) has the table.

### The packages that own a third-party dependency

| package | depends on | third-party |
| --- | --- | --- |
| `ProjecturedAnthropic` | Kernel | HTTP, JSON3 |
| `ProjecturedOllama` | Kernel | HTTP, JSON3 |
| `ProjecturedOpenRouter` | Kernel | HTTP, JSON3 |
| `ProjecturedMcp` | Kernel | ModelContextProtocol |
| `ProjecturedTulip` | Layout | MathOptInterface, Tulip |
| `ProjecturedVideo` | Graphics, Kernel, Screen, Sdl | FFMPEG |
| `ProjecturedAdaptagrams` | Graph | Libdl |
| `ProjecturedSdl` | Collection, Graphics, Kernel, Screen, Style | SDL2_jll, SimpleDirectMediaLayer |
| `ProjecturedWeb` | Collection, Graphics, Kernel, Screen, Style | Base64, HTTP, JSON3 |
| `ProjecturedOdbc` | Collection, Database, DbCatalog, Kernel, Projection, Sql, Syntax, Text | DBInterface, ODBC, Tables |
| `ProjecturedDataFrames` | Collection, Kernel, Layout, Natural, Pane, Primitive, Projection, Screen, Sdl, Style, Widget | DataFrames |

### The aggregate and the leaves

| package | depends on |
| --- | --- |
| `Projectured` (umbrella) | Kernel, the 29 substrate packages, the 21 domains |
| `ProjecturedSubstrateExample` | the 29 substrate packages, KernelExample |
| `ProjecturedSubstrateTest` | the 29 substrate packages, KernelTest, SubstrateExample |
| `<Stem>Example` | `<Stem>`, the Examples below it |
| `<Stem>Test` | `<Stem>`, `<Stem>Example`, the Tests below it |
| `ProjecturedRepl` **(leaf)** | Projectured, Example, Test, Sdl |
| `build/app/<name>` **(leaf, written by a build)** | the packages the build names |
| `ProjecturedBuilder` (tool) | — |

### Why each third-party dependency is there

- **SDL2_jll**, **SimpleDirectMediaLayer** — a window and a pointer have to come
  from somewhere.
- **Libdl** — loads the Adaptagrams layout shim.
- **DBInterface**, **ODBC**, **Tables** — a database driver.
- **MathOptInterface**, **Tulip** — a linear-programming solver.
- **FFMPEG** — encodes a recording.
- **HTTP**, **JSON3**, **ModelContextProtocol** — wire protocols this project
  does not define.
- **DataFrames** — the native tables that `ProjecturedDataFrames` views and
  edits.
- **PackageCompiler**, **FixedPointNumbers** — building the binary. A leaf;
  nothing depends on it.
- **PrecompileTools**, **Preferences** — the workload mechanism itself.

**No domain package has a third-party dependency, and none should acquire one.**
A domain that needs one — a real SQL grammar, say — stops being a domain and
becomes an optional stem like `ProjecturedOdbc`, named in the table above.

## Adding a package

1. Decide whether it is a **sub-stem** (a layer, no third-party dependency) or a
   **stem of its own** (it has one). Only the first may be aggregated. For a new
   domain, [domain-inventory.md](../design/domain-inventory.md) has the rest.
2. Give it the kinds it needs, with the reserved suffixes.
3. Name every third-party dependency in the table above, with its reason.
4. Do not depend on a leaf, and do not put a `@compile_workload` outside one.
5. Run `test_package_graph()` — it asserts 2 and 4, and it fails loudly.
