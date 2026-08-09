# One leaf package per repository, and the compile workload lives there

Applies to projectured-julia, omnetpp-julia and inet-julia. Supersedes the
layering decision in [precompile-workloads.md](precompile-workloads.md), which
put the workloads in the example packages; the measurement below shows why that
is not where they can survive.

## Why, measured

The first click on a demo catalog page in a real `jo` session costs 5.6 s. Of
that, `open_page!` is 1.2 s and the first paint is 4.3 s — and **3.5 s of the
paint is `recompile_time`**, not `compile_time`. That is Julia rebuilding code
that was already compiled into the package images and then thrown away.

The same click in a session that loads only what the demo needs costs 1.6 s,
with `recompile_time` of 0.03 s. Same document, same projection, same window.

What throws the compiled code away is method definitions arriving after it was
compiled. Loading `Omnetpp`, `OmnetppExample` and `OmnetppTest` on top of the
demo's own stack invalidates **15286 method instances from 497 method
definitions**. The worst offenders are not our code and not our types:

| instances killed | method added | comes with |
| ---: | --- | --- |
| 4371 | `(::Type{T})(::ChainedVectorIndex)` over `Int64(::Integer)` | SentinelArrays ← DataFrames ← OmnetppLegacy |
| 4111 | `thisind(::InlineString, ::Int)` over `thisind(::AbstractString, ::Int)` | InlineStrings ← DataFrames |
| 3872 | `convert(::Type{Symbol}, ::PtrString)` over `convert(::Type{Symbol}, ::Any)` | JSON |
| 2796 | `hash(::Token)` over `hash(::Any)` | Lerche ← OmnetppFormat |
| 2400 | `>(::Integer, ::OffsetInteger)` over `>(::Any, ::Any)` | GeometryBasics ← CairoMakie ← OmnetppLegacyPlot |
| 1226 | `getproperty(::RowIterator, ::Int)` over `getproperty(::Any, ::Int)` | Tables |
| 1028 | `setproperty!(::LazyRow, ::Int, ::Any)` over `setproperty!(::Any, ::Int, ::CellVector)` | StructArrays |

The last row is the shape of the whole problem: StructArrays adds a
three-argument `setproperty!` and thereby voids compiled code whose call site was
Projectured's own reactive `setproperty!(::Any, ::Int, ::CellVector{Cell,Cell})`.
The two have nothing to do with each other. **The signature collides, not the
types.** How many types a session holds is irrelevant.

### The property everything follows from

Compiled code is invalidated by methods that appear **after** it was compiled. A
package image is built with exactly that package's dependencies present. So:

- Code compiled into a **leaf** — a package nothing depends on, loaded last —
  sees the final method table. Nothing can void it.
- Code compiled into a **lower** package was built without the leaf's other
  dependencies, and dies when the session loads them.

A corollary that runs against instinct: **a heavy dependency does less damage the
lower it sits.** If DataFrames were a kernel dependency, every image above would
be built with its methods present and nothing would be invalidated. It hurts
because it arrives high, through `OmnetppLegacy`, after everything below was
compiled without it.

This convention resolves that tension: heavy dependencies stay high so lean
subsets remain possible, and the leaf's workload compiles the real code paths
after everything is loaded.

## The convention

### 1. Five kinds of package per stem

| kind | name | what it is |
| --- | --- | --- |
| main | `Stem` | the code |
| example | `StemExample` | documents, galleries, and the workload **bodies** |
| test | `StemTest` | the suite |
| repl | `StemRepl` | the leaf a person loads to work |
| build | `StemBuild` | the leaf PackageCompiler bakes into a binary |

Singular `Example`, matching the tree as it stands (`ProjecturedKernelExample`,
`OmnetppPresentationExample`).

`StemBuild` already exists in projectured-julia under another name:
`package/executable/main` is `ProjecturedExecutable`, the app package the binary
is compiled from, and `package/executable/builder` is `ProjecturedBuilder`, the
tool that drives PackageCompiler. **Keep both names.** The distinction they
encode is real — one is the artifact, the other is the tool — and `Builder` is
not a stem artifact at all. Read `StemBuild` as "the app package" wherever this
plan says it.

### 2. One dependency direction

```
Foo            -> Bar
FooExample     -> BarExample -> Foo
FooTest        -> BarTest    -> FooExample
FooRepl        -> FooTest                     (leaf)
FooBuild       -> FooExample                  (leaf)
```

**Nothing may depend on a `Repl` or a `Build` package.** That is the whole
mechanism; a dependency on a leaf makes it not a leaf.

### 3. A workload lives in a leaf

`@compile_workload` appears in `StemRepl` and `StemBuild` and nowhere else. A
lower package carries one only when someone genuinely loads it alone — a
slice-only test environment, CI. Anywhere else it costs build time for code the
full session invalidates and never uses. That is what the current workloads in
`ProjecturedDomainExample` and `ProjecturedVisualExample` are doing today.

### 4. Workload bodies are ordinary functions

The registry-driven bodies stay where they are, in the example packages, and gain
one public entry point each:

```julia
precompile_workload(level::Symbol)      # in StemExample
```

The macro in the leaf only calls it. This is what lets `StemRepl` and `StemBuild`
share one definition, and it keeps the bodies testable without a rebuild.

### 5. The alias loads exactly one leaf, and Revise first

```
jp: julia … -e 'using Revise, ProjecturedRepl'
jo: julia … -e 'using Revise, OmnetppRepl'
ji: julia … -e 'using Revise, InetRepl'
```

**Revise is not a dependency of `StemRepl`.** It must be loaded before the
packages it is to track; as a dependency its position in the load order is the
graph's business, and a package loaded before Revise is not tracked. Loading it
first in the alias costs 0.026 s of recompilation, measured — that is the price
of correct tracking and it is worth it.

Nothing may be loaded *after* the leaf. `using Revise, OmnetppRepl` is right;
adding `, OmnetppTest` at the end puts the invalidation back.

### 6. An external dependency is named deliberately

`DataFrames`, `Tables`, `Makie`, `JSON`, `Lerche` and anything else that adds
methods to `Base` functions belongs to one named package, chosen on purpose.
Never let one arrive in the middle of the stack as a side effect.

### 7. Do not overload a `Base` function on our own type

Where a new name would do, use a new name. `Base.:(:)(::Integer, ::ScopeEnd)` in
omnetpp-julia's `package/simulator/main/src/parameter/Pattern.jl:156` voids 3039
method instances in every session, whatever the packaging. Same call as
"mint vocabulary rather than overload".

## The parameterized workload

A REPL leaf re-precompiles whenever anything below it changes, which during a
working day is constantly. A demo in front of an audience wants the opposite: the
heaviest workload there is, so the first frame is instant. One package, one
setting.

### Levels

| level | what it compiles | for |
| --- | --- | --- |
| `:none` | nothing | editing low-level code all day |
| `:minimal` | one document per domain, printed and forced, headless | the REPL default |
| `:demo` | one catalog page opened end to end, plus the widgets a talk uses | showing the thing |
| `:full` | exactly what `StemBuild` compiles | a demo where speed is the point |

`:full` is not a separate list. It is the same function call `StemBuild` makes,
so "the same as the build" is literally the same code.

### How the level is chosen

Preferences, not an environment variable. A preference read with
`@load_preference` at module scope is part of the precompile cache key, so
changing it re-precompiles; an environment variable is not, so a stale image
would be reused and the setting would silently do nothing.

```julia
module ProjecturedRepl
using ProjecturedTest, PrecompileTools, Preferences

const WORKLOAD = Symbol(@load_preference("workload", "minimal"))

"""Set the workload level for the next session: :none, :minimal, :demo, :full."""
set_workload!(level::Symbol) =
    set_preferences!(@__MODULE__, "workload" => String(level); force = true)

@setup_workload begin
    @compile_workload begin
        ProjecturedExample.precompile_workload(WORKLOAD)
    end
end
end
```

`set_workload!(:full)` then restart; the next `using` pays the build once. Add
`LocalPreferences.toml` to `.gitignore` in each repository — the level is a
person's choice, not the project's.

## Repository by repository

### projectured-julia

- New `package/repl/` → `ProjecturedRepl`, depending on `ProjecturedTest` and
  `ProjecturedSdl`.
- `ProjecturedExample` gains `precompile_workload(level)`, which dispatches to
  the registry-driven bodies that exist today.
- The `@compile_workload` call sites move out of `ProjecturedDomainExample` and
  `ProjecturedVisualExample` into `ProjecturedRepl` and `ProjecturedExecutable`.
  The bodies do not move.
- `ProjecturedExecutable` gains the `:full` call.

### omnetpp-julia

- New `package/repl/` → `OmnetppRepl`, depending on `OmnetppTest` and
  `ProjecturedSdl`.
- `OmnetppExample` gains `precompile_workload(level)`. Its `:demo` level opens
  one catalog page through `demo_projection()` and forces the canvas — headless,
  because no window can be opened at precompile time.
- This is where the 13 pairs still owed by `OmnetppPresentationExample`
  ([precompile-workloads.md](precompile-workloads.md)) get their home.
- A `Build` leaf if and when a binary is wanted.

### inet-julia

- New `package/repl/` → `InetRepl`, depending on `InetTest` and `ProjecturedSdl`.
- `InetExample` gains `precompile_workload(level)`.

## The domain split, in flight

Another agent is splitting `package/domain` in projectured-julia into a package
per domain. This plan must not collide with it:

- **Touch nothing under `package/domain/`** until that lands. The workload call
  site in `ProjecturedDomainExample` is the one file both pieces of work want;
  it moves last.
- `ProjecturedRepl` depends on `ProjecturedTest`, never on individual slices, so
  the leaf can be built while the split is in progress and needs no edit when it
  lands.
- The split's new packages follow rule 1: `ProjecturedJson`,
  `ProjecturedJsonExample`, `ProjecturedJsonTest`, and so on. No new
  `@compile_workload` in any of them — their bodies register with
  `ProjecturedExample.precompile_workload` instead.

## What should depend on what

Every package in the three repositories, checked against the rules. `→` is a
dependency. Standard library entries are left out.

### An important consequence of rule 3

Once the workload is in the leaf, **a heavy dependency no longer costs compile
time**, because the leaf is precompiled with it present. What it still costs is
load time, memory and disk. So the removals proposed below are about an honest
dependency graph and a session that starts quickly — not about the 3.5 s, which
the leaf fixes on its own.

### projectured-julia

| package | should depend on | external |
| --- | --- | --- |
| `ProjecturedKernel` | — | — |
| `ProjecturedBase` | Kernel | — |
| `ProjecturedVisual` | Base, Kernel | — |
| `ProjecturedDomain` | Base, Kernel, Visual | — |
| `Projectured` | Base, Domain, Kernel, Visual | — |
| `ProjecturedSdl` | Domain | SDL2_jll, SimpleDirectMediaLayer |
| `ProjecturedAdaptagrams` | Domain | Libdl |
| `ProjecturedOdbc` | Domain | DBInterface, ODBC, Tables |
| `ProjecturedTulip` | Domain | MathOptInterface, Tulip |
| `ProjecturedVideo` | Domain, Sdl | FFMPEG |
| `ProjecturedLlm` | Kernel | HTTP, JSON3 |
| `ProjecturedMcp` | Kernel | ModelContextProtocol |
| `ProjecturedWeb` | Domain | HTTP, JSON3 |
| `<Stem>Example` | `<Stem>`, the Examples below it | PrecompileTools where it holds a body |
| `<Stem>Test` | `<Stem>Example`, the Tests below it | — |
| `ProjecturedRepl` **(leaf)** | ProjecturedTest, ProjecturedSdl | PrecompileTools, Preferences |
| `ProjecturedExecutable` **(leaf)** | ProjecturedExample, Projectured, Llm, Sdl | PackageCompiler, FixedPointNumbers |
| `ProjecturedBuilder` (tool) | — | Pkg |

### omnetpp-julia

| package | should depend on | external |
| --- | --- | --- |
| `OmnetppUnits` | — | Unitful |
| `OmnetppSimulator` | Units, ProjecturedBase, ProjecturedKernel | DataStructures |
| `OmnetppFormat` | Units, ProjecturedBase, ProjecturedKernel | **Lerche** |
| `OmnetppDescription` | Format, Simulator, Units, ProjecturedKernel | — |
| `OmnetppDynamics` | Simulator, Units, ProjecturedBase, ProjecturedKernel | OrdinaryDiffEqCore, OrdinaryDiffEqTsit5, StaticArrays |
| `OmnetppPresentation` | Units, Simulator, Projectured, Adaptagrams, Base, Domain, Kernel, Visual | — |
| `OmnetppLegacy` | Format, Units, Projectured | **DataFrames** |
| `OmnetppLegacyPlot` | Legacy, Projectured, Sdl | **CairoMakie**, LaTeXStrings |
| `Omnetpp` | Description, Format, Legacy, Presentation, Simulator, Units | — |
| `<Stem>Example` | `<Stem>`, the Examples below it | BlackBoxOptim (presentation only) |
| `<Stem>Test` | `<Stem>Example`, the Tests below it | — |
| `OmnetppRepl` **(leaf)** | OmnetppTest, ProjecturedSdl | PrecompileTools, Preferences |

### inet-julia

| package | should depend on | external |
| --- | --- | --- |
| `InetPacket` | — | — |
| `InetCommon` | OmnetppSimulator, ProjecturedKernel | — |
| `InetLinkLayer` | Packet, OmnetppSimulator, ProjecturedKernel | — |
| `InetQueuing` | Common, Packet, OmnetppSimulator, ProjecturedKernel | — |
| `InetRunner` | Packet, Queuing, OmnetppDescription, OmnetppFormat, OmnetppSimulator, OmnetppUnits | — |
| `Inet` | Common, LinkLayer, Packet, Queuing, OmnetppSimulator, ProjecturedVisual | — |
| `<Stem>Example` | `<Stem>`, the Examples below it | — |
| `<Stem>Test` | `<Stem>Example`, the Tests below it | — |
| `InetRepl` **(leaf)** | InetTest, ProjecturedSdl | PrecompileTools, Preferences |

### The domains, after the split

Each domain the split produces gets the same three packages and **no external
dependency at all**, which is what `ProjecturedDomain` has today:

```
ProjecturedJson        -> ProjecturedVisual (and Base, Kernel)
ProjecturedJsonExample -> ProjecturedJson, ProjecturedVisualExample
ProjecturedJsonTest    -> ProjecturedJsonExample, ProjecturedVisualTest
```

If a domain ever needs an external package — a real SQL grammar, say — it stops
being a plain domain and becomes an optional slice like `ProjecturedOdbc`, named
in the table above rather than folded into the aggregate.

`ProjecturedDomain` survives as the aggregator over the domain packages, and
keeps depending on nothing external.

## Four things that need fixing, and one that looks wrong

### 1. A main package depends on an example package

`OmnetppPresentation` imports **one** function from `ProjecturedDomainExample`:

```
package/presentation/main/src/module/SimulationTopologyToWidget.jl:38
    import ProjecturedDomainExample: make_graph_projection_example
```

This breaks rule 2 in the worst direction — every session that loads the
presentation package loads example code. Move `make_graph_projection_example`
down into `ProjecturedDomain` (it is a projection factory, not an example) or
inline the projection at the call site. One function either way.

### 2. The presentation test drags the legacy stack in

`OmnetppPresentationTest` imports `OmnetppLegacy` because the demo catalog has
legacy pages whose `.ned` and `.ini` doctypes are registered by
`OmnetppLegacy.__init__`, and the catalog walk needs them registered. The effect
is that `DataFrames` reaches every presentation test run, and through
`OmnetppTest` it reaches the REPL leaf.

Move the legacy pages' coverage into `OmnetppLegacyTest`, which owns that
dependency honestly, and let the presentation test skip a page whose doctype is
not registered — the catalog already survives an unresolved embed.

### 3. `ProjecturedTest` aggregates the optional slices

It depends on `ProjecturedOdbc`, `ProjecturedTulip`, `ProjecturedVideo` and
`ProjecturedSdl`, so the `jp` REPL loads an ODBC driver manager, a linear
programming solver and FFMPEG. `Tulip` is where `MathOptInterface` comes from,
and `MathOptInterface` is one of the two sources of `JSON` — 3872 invalidated
instances in the earlier count.

This is defensible if `test_all()` must be callable from the prompt, and after
rule 3 it costs load time rather than compile time. Decide it deliberately
rather than by inheritance, and write the decision down.

### 4. `InetQueuingExample` depends on `Test`

An example package should not need the test standard library. Move whatever uses
it into `InetQueuingTest`.

### The one that looks wrong: DataFrames

You are right that it should not be needed, though not quite for the reason you
gave — it is not the plotting library. It is the **table type of the legacy
result reader**:

- `package/legacy/main/src/simulation/ResultReader.jl` — 30 references. Reads
  OMNeT++ `.sca` and `.vec` files into `DataFrame`s.
- `package/legacy/main/src/document/Simulation.jl` — 6 references.
  `simulation_plot(df::AbstractDataFrame)` builds a plot document from one.

That is one file's worth of table handling, for results produced by the **C++**
OMNeT++. The Julia simulator has its own result store, accumulators and charts;
nothing in the live path touches a `DataFrame`. What the reader actually needs
is columns by name, `eachrow` and filtering — which a column table of our own
supplies, and which the result store already is.

DataFrames is also the single largest source of invalidation: SentinelArrays
(4371 + 1332), InlineStrings (4111) and Tables (1226) all arrive with it, about
11000 of the 15286 instances.

**CairoMakie deserves the same question, and there your reason does hold.**
`OmnetppLegacyPlot` uses it to render a `SimulationPlotDocument` to a PNG
headlessly. We render line, bar, scatter, histogram and colour-strip charts
ourselves — they have pages in the demo catalog. If our own charts can write a
PNG, CairoMakie goes, and GeometryBasics (2400 + 2049), StructArrays (1028) and
the other source of `JSON` go with it.

**`OmnetppBenchPlot` is already dead.** It depends on `Plots`, `CSV` and
`DataFrames`, and `Plots` is not installed in the root environment — the package
cannot resolve. Delete it or rebuild it on our own charts.

**Lerche is genuinely needed** and should stay: it is the grammar engine behind
the NED and INI parsers in `OmnetppFormat`, two real grammars. It costs 2796
instances by defining `hash(::Lerche.Token)`. Keep it, and keep it named — it is
the reason `OmnetppFormat` is a slice of its own rather than part of the
simulator.

## Guards

- **A layering test**, next to `test_kernel_layering()`: no package depends on a
  `Repl` or a `Build` package; no `Example` is a dependency of a non-`Example`;
  no `Test` is a dependency of anything but a `Test` or a `Repl`.
- **A recompile check**: open a page in a `Repl`-shaped session and assert
  `@timed`'s `recompile_time` is near zero. That single number is what makes a
  misplaced dependency visible, and it is how this whole problem surfaced.
- **An external-dependency list**, asserted rather than described: the set of
  non-standard-library dependencies per package is written down, and the test
  fails when a package acquires one that is not on its list. That is what stops
  a `DataFrames` from arriving in the middle of the stack again.

## Documentation

The architecture is only useful if it is written down where a reader looks
first. After the convention is applied, each repository gets a package document
and the existing guides point at it.

- `documentation/packages.md` in each of the three repositories: the five kinds,
  the dependency direction, the full table of what depends on what, the external
  dependency of each package and why it has one, and which package is the leaf
  the alias loads.
- [documentation/architecture.md](../../documentation/architecture.md) in
  projectured-julia gains the leaf and workload rules next to the existing
  layer and slice vocabulary, and links to `packages.md`. The division
  vocabulary in [terminology.md](../../documentation/terminology.md) gains
  `leaf` as a term, since the whole convention turns on it.
- Each repository's `CLAUDE.md` gains one line: where a new package goes, and
  that a `@compile_workload` belongs only in a leaf.
- The document and the layering test are written together and say the same
  thing. The test is the authority; the document explains it.

## Steps

- [ ] 1. This plan, and companion plans in omnetpp-julia and inet-julia.
- [ ] 2. `precompile_workload(level)` in `ProjecturedExample`, wrapping the
      bodies that exist. No call-site moves yet.
- [ ] 3. `ProjecturedRepl`, with the Preferences-driven level and `set_workload!`.
- [ ] 4. `ProjecturedExecutable` calls `precompile_workload(:full)`.
- [ ] 5. Move the call sites out of `ProjecturedDomainExample` and
      `ProjecturedVisualExample`. **After the domain split lands.**
- [ ] 6. The layering test, the recompile check and the external-dependency
      list.
- [ ] 7. omnetpp-julia: `OmnetppExample.precompile_workload`, `OmnetppRepl`.
- [ ] 8. inet-julia: `InetExample.precompile_workload`, `InetRepl`.
- [ ] 9. The three aliases.
- [ ] 10. `make_graph_projection_example` moves down, so `OmnetppPresentation`
      stops depending on an example package.
- [ ] 11. The legacy pages' coverage moves to `OmnetppLegacyTest`, so
      `OmnetppPresentationTest` stops needing `OmnetppLegacy`.
- [ ] 12. `InetQueuingExample` stops depending on `Test`.
- [ ] 13. Decide `ProjecturedTest`'s optional slices deliberately, and write the
      decision into `documentation/packages.md`.
- [ ] 14. Replace `DataFrames` in the legacy result reader with a column table
      of our own, or state why it stays.
- [ ] 15. Replace `CairoMakie` in `OmnetppLegacyPlot` with our own charts
      rendered to PNG, or state why it stays.
- [ ] 16. Delete or rebuild `OmnetppBenchPlot` — `Plots` does not resolve.
- [ ] 17. `documentation/packages.md` in each repository, and the pointers from
      `architecture.md`, `terminology.md` and `CLAUDE.md`.
- [ ] 18. Re-measure the first click in each repository, at each level.

## Risks

- **The leaf re-precompiles on every change below it.** That is why `:minimal` is
  the default and `:none` exists.
- **The SDL path cannot be precompiled.** No window opens during precompilation,
  so a workload covers the projection and the forced canvas, not the blitting.
  The measurements say the projection is where the seconds are.
- **Revise undoes the workload for what it revises.** Expected, and the point of
  Revise.
- **`:full` in the REPL is slow to build.** It is a deliberate setting for a
  deliberate occasion.

## Result

To be filled in at step 10.
