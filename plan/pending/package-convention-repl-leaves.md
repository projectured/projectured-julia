# One leaf package per repository, and the compile workload lives there

> **Status (2026-08-12): IN PROGRESS.** `ProjecturedRepl`, `OmnetppRepl` and
> `InetRepl` all exist, and the `jp`/`jo`/`ji` aliases in `~/.bashrc` each load
> only their leaf — the core convention is built and used every day. The
> omnetpp-julia half of this plan is fully done, now in
> `omnetpp-julia/plan/done/package-convention-repl-leaves.md`. The inet-julia
> half is done except one step, `InetQueuingExample`'s `Test` dependency. Three
> items stay open here: the `ProjecturedTest` optional-slice decision (step 13),
> and `BlackBoxOptim`/`OmnetppDynamics` as weak instead of plain dependencies of
> `OmnetppPresentationExample` (steps 16a-16b). A later plan,
> [recorded-precompile-workload.md](../done/recorded-precompile-workload.md)
> (done), replaced the four-level `:none`/`:minimal`/`:demo`/`:full` workload
> scheme this plan specifies with a three-level `:none`/`:recorded`/`:live`
> scheme in all three leaves; the level tables and measurements below predate
> that change and are kept as the historical snapshot they were measured
> against. The "What should depend on what" tables also predate a further split
> of `ProjecturedBase`/`ProjecturedVisual` into the 28-package substrate
> `documentation/packages.md` now describes — check that document for the
> current package graph.

Applies to projectured-julia, omnetpp-julia and inet-julia. Supersedes the
layering decision in
[precompile-workloads.md](../done/precompile-workloads.md) (done, moved to
`plan/done/`), which put the workloads in the example packages; the measurement
below shows why that is not where they can survive.

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
Foo            -> Bar,  and every sub-stem of Foo
FooExample     -> Foo,  BarExample
FooTest        -> Foo,  BarTest, FooExample
FooRepl        -> nothing but PrecompileTools and Preferences      (leaf)
FooBuild       -> FooExample                                       (leaf)
```

A stem's main package **aggregates its sub-stems**, so `Foo` is the one name a
consumer needs, and `FooTest` depends on `Foo` whole rather than on the pieces.

Which stems are *present* is not a package's business at all — see rule 2d.

**Nothing may depend on a `Repl` or a `Build` package.** That is the whole
mechanism; a dependency on a leaf makes it not a leaf.

### 2b. A package with a third-party dependency is a stem, not a sub-stem

Aggregation would otherwise pull an ODBC driver manager and a linear programming
solver into everything that says `using Projectured`. So the name prefix does not
decide: **a sub-stem is a layer of the stem and carries no third-party
dependency of its own. A package that has one is a stem in its own right, named
explicitly by whoever wants it.**

This is already how the tree is built; it has only been unstated. `Omnetpp`
aggregates Description, Format, Legacy, Presentation, Simulator and Units, and
deliberately not `OmnetppDynamics`, which owns a solver. `OmnetppLegacyPlot`,
`OmnetppLegacyResult` and `ProjecturedOdbc` are stems whose names begin with
another stem's name, and `Example`, `Test`, `Repl` and `Build` remain the only
reserved suffixes.

So:

- `Projectured` aggregates Kernel, Base, Visual, Domain — and, after the split,
  the domain packages. None of them has an external dependency.
- `ProjecturedSdl`, `ProjecturedAdaptagrams`, `ProjecturedOdbc`,
  `ProjecturedTulip`, `ProjecturedVideo`, `ProjecturedLlm`, `ProjecturedMcp`,
  `ProjecturedWeb` are stems. Each is named by the package or the leaf that
  wants it.
- `ProjecturedTest` therefore covers the umbrella's layers. **The suites of the
  separate stems reach the prompt through the leaf**, which is where "everything
  I want available" belongs:

That settles what `test_all()` covers: the **environment** decides which stems
and which suites are present, and the cost is load time rather than compile
time.

### 2c. Optional wiring goes in an extension, not in a dependency

The mechanism is `[weakdeps]` + `[extensions]`, and it is already in this tree:
`package/simulator/main/Project.toml` declares `BlackBoxOptim` and
`SQLite`/`DBInterface` as weak dependencies with an extension each. The
extension module loads by itself when both sides are present, in either order.

**Use it whenever a package needs another package only to wire something up.**
Two such force-loads exist today:

- `OmnetppPresentationExample` imports `OmnetppDynamics` at
  `src/OmnetppPresentationExample.jl:27` for one call —
  `register_doctype_module!(OmnetppDynamics)` at line 354. That is glue and
  nothing else, so it belongs in an extension. The demo then stops dragging a
  differential-equation solver in.
- `OmnetppPresentationTest` imports `OmnetppLegacy` only so the `.ned` and
  `.ini` doctypes are registered for the catalog walk. Same shape, if the
  coverage is not moved to `OmnetppLegacyTest` instead.

What an extension **cannot** do, so nobody expects it to:

- **It cannot re-export.** `using Projectured` will not hand out
  `ProjecturedOdbc`'s names because ODBC happens to be loaded. An extension adds
  methods; it does not merge namespaces. The reader still writes
  `using ProjecturedOdbc`.
- **It cannot pull.** It reacts to a package being loaded; it does not cause it.
- **It does not save disk or resolution.** A weak dependency is still resolved
  and installed. What it saves is the load, and the invalidation that comes with
  the load.

### 2d. Configuration is an environment, not a package

An "everything" package would be a second list beside the one the leaf holds,
and the two would drift. Julia already has a first-class unit for "the set of
packages present", and it is a `Project.toml`. Keep several per repository, all
checked in:

```
env/core    Projectured, ProjecturedSdl, the Repl leaf        — daily work
env/demo    + Adaptagrams, Llm                                — the catalog
env/full    + Odbc, Tulip, Video, Web, Mcp, every *Test       — everything
env/ci      = full, without Revise
```

The alias selects one:

```
jo:  julia --project=$OMNETPP/env/full  -e 'using Revise, OmnetppRepl'
jod: julia --project=$OMNETPP/env/demo  -e 'using Revise, OmnetppRepl'
```

One question — which heavy stems exist — asked once, and answered the same way
for the session, the workload and the binary. `PackageCompiler` takes a project
too, so a lean binary and a full binary differ by `--project`, not by a second
package.

The leaf therefore holds **no dependency list**. It declares each heavy stem as
a weak dependency with an extension that carries that stem's part of the
workload, so the extension exists only in an environment where the stem does.
`env/core` never compiles the ODBC or solver paths, because there is no
extension to compile.

One consequence to accept: a weak dependency is still resolved and installed. An
environment saves the load, not the download.

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

Measured on a scratch Startup package that pulls the whole `jo` session, with a
workload that opens one catalog page headlessly. "the click" is `open_page!`
plus the first paint.

| level | mechanism | build | the click |
| --- | --- | ---: | ---: |
| `:none` | nothing | 8.8 s | 5.98 s |
| `:minimal` | a workload over the atoms | — | — |
| `:demo` | `@compile_workload` over one catalog page | 17–22 s | **0.55 s** |
| `:full` | that, plus `@recompile_invalidations` | 107–116 s | **0.24 s** |

The split is real and it is the one this parameter exists for. A workload costs
about ten seconds of build and takes the click from 6 s to half a second.
`@recompile_invalidations` costs a further **ninety seconds** of build and takes
it to a fifth of a second. That is a demo-day setting, not a default.

What each one fixes is different, which is why `:full` is not redundant:

| | `open_page!` | first paint | of which recompile |
| --- | ---: | ---: | ---: |
| `:none` | 1.286 s | 4.695 s | 3.877 s |
| workload only | **0.038 s** | 0.510 s | 0.254 s |
| `@recompile_invalidations` only | 1.133 s | **0.674 s** | **0.000 s** |
| both | **0.038 s** | **0.201 s** | **0.000 s** |

`@recompile_invalidations` erases the invalidation damage and nothing else — the
paint's 3.9 s of recompilation goes to zero, while `open_page!` stays at 1.1 s
because that is code which was never compiled, not code that was voided. The
workload is the opposite: it compiles exactly the paths it runs, so `open_page!`
falls by a factor of 34, and it leaves a little recompilation behind. Together
they cover both halves.

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

  **Done, with the level argument later dropped.** `package/repl/ProjecturedRepl.jl`
  and `package/executable/main/ProjecturedExecutable.jl` both exist as
  described. `precompile_workload` lost its `level` parameter when
  [recorded-precompile-workload.md](../done/recorded-precompile-workload.md)
  landed — `ProjecturedExecutable.jl:135` now calls
  `ProjecturedExample.precompile_workload()` unconditionally whenever
  `APP_WORKLOAD` is not `:none`.

### omnetpp-julia

- New `package/repl/` → `OmnetppRepl`, depending on `OmnetppTest` and
  `ProjecturedSdl`.
- `OmnetppExample` gains `precompile_workload(level)`. Its `:demo` level opens
  one catalog page through `demo_projection()` and forces the canvas — headless,
  because no window can be opened at precompile time.
- This is where the 13 pairs still owed by `OmnetppPresentationExample`
  ([precompile-workloads.md](../done/precompile-workloads.md), done) get their
  home.
- A `Build` leaf if and when a binary is wanted.

  **Done, except the `Build` leaf.** `package/repl/src/OmnetppRepl.jl` exists,
  in `package/repl/src/`, not directly in `package/repl/`. The workload body
  landed on `OmnetppPresentationExample`, not `OmnetppExample` (see step 7); no
  `OmnetppBuild` package was created, and this plan does not say one is still
  wanted. Full detail in `omnetpp-julia/plan/done/package-convention-repl-leaves.md`.

### inet-julia

- New `package/repl/` → `InetRepl`, depending on `InetTest` and `ProjecturedSdl`.
- `InetExample` gains `precompile_workload(level)`.

  **Done**, as described — `package/repl/InetRepl.jl` and
  `InetExample.precompile_workload` both exist. See
  `inet-julia/plan/pending/package-convention-repl-leaves.md`.

## The domain split, in flight

**Landed.** The split described below is done —
[plan/done/split-domain-into-per-domain-packages.md](../done/split-domain-into-per-domain-packages.md) —
and `package/domain/main` now holds only the aggregator, `ProjecturedDomain`.
This section is kept as the record of how the two pieces of work were
sequenced.

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
| `Projectured` **(umbrella)** | Base, Domain, Kernel, Visual, and the domain packages after the split | — |
| `ProjecturedSdl` | Domain | SDL2_jll, SimpleDirectMediaLayer |
| `ProjecturedAdaptagrams` | Domain | Libdl |
| `ProjecturedOdbc` | Domain | DBInterface, ODBC, Tables |
| `ProjecturedTulip` | Domain | MathOptInterface, Tulip |
| `ProjecturedVideo` | Domain, Sdl | FFMPEG |
| `ProjecturedLlm` | Kernel | HTTP, JSON3 |
| `ProjecturedMcp` | Kernel | ModelContextProtocol |
| `ProjecturedWeb` | Domain | HTTP, JSON3 |
| `<Stem>Example` | `<Stem>`, the Examples below it | PrecompileTools where it holds a body |
| `<Stem>Test` | `<Stem>`, `<Stem>Example`, the Tests below it | — |
| `ProjecturedRepl` **(leaf)** | nothing; weakdeps on Sdl, Odbc, Tulip, Video, Llm, Mcp, Web, each with an extension carrying that stem's workload | PrecompileTools, Preferences |
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
| `Omnetpp` **(umbrella)** | Description, Format, Legacy, Presentation, Simulator, Units — not Dynamics, Plot or Result, which own dependencies | — |
| `<Stem>Example` | `<Stem>`, the Examples below it | BlackBoxOptim (presentation only) |
| `<Stem>Test` | `<Stem>`, `<Stem>Example`, the Tests below it | — |
| `OmnetppRepl` **(leaf)** | nothing; weakdeps on Dynamics, LegacyPlot, LegacyResult, each with an extension carrying that stem's workload | PrecompileTools, Preferences |

### inet-julia

| package | should depend on | external |
| --- | --- | --- |
| `InetPacket` | — | — |
| `InetCommon` | OmnetppSimulator, ProjecturedKernel | — |
| `InetLinkLayer` | Packet, OmnetppSimulator, ProjecturedKernel | — |
| `InetQueuing` | Common, Packet, OmnetppSimulator, ProjecturedKernel | — |
| `InetRunner` | Packet, Queuing, OmnetppDescription, OmnetppFormat, OmnetppSimulator, OmnetppUnits | — |
| `Inet` **(umbrella)** | Common, LinkLayer, Packet, Queuing, Runner, OmnetppSimulator, ProjecturedVisual | — |
| `<Stem>Example` | `<Stem>`, the Examples below it | — |
| `<Stem>Test` | `<Stem>`, `<Stem>Example`, the Tests below it | — |
| `InetRepl` **(leaf)** | nothing; weakdeps as needed | PrecompileTools, Preferences |

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

**Fixed, by inlining.** `SimulationTopologyToWidget.jl` no longer imports an
example package at all; `OmnetppPresentation` composes the topology projection
itself from `ProjecturedGraph`. See step 10.

### 2. The presentation test drags the legacy stack in

`OmnetppPresentationTest` imports `OmnetppLegacy` because the demo catalog has
legacy pages whose `.ned` and `.ini` doctypes are registered by
`OmnetppLegacy.__init__`, and the catalog walk needs them registered. The effect
is that `DataFrames` reaches every presentation test run, and through
`OmnetppTest` it reaches the REPL leaf.

Move the legacy pages' coverage into `OmnetppLegacyTest`, which owns that
dependency honestly, and let the presentation test skip a page whose doctype is
not registered — the catalog already survives an unresolved embed.

**Dropped, deliberately.** `Omnetpp` depends on `OmnetppLegacy` regardless, and
`OmnetppRepl` depends on `Omnetpp`, so a `jo` session pays for `DataFrames`
whatever `OmnetppPresentationTest` does. Moving the coverage would only have
saved a presentation-only test run, so `OmnetppPresentationTest` keeps the
import. See step 11.

### 3. `ProjecturedTest` aggregates the optional slices

It depends on `ProjecturedOdbc`, `ProjecturedTulip`, `ProjecturedVideo` and
`ProjecturedSdl`, so the `jp` REPL loads an ODBC driver manager, a linear
programming solver and FFMPEG. `Tulip` is where `MathOptInterface` comes from,
and `MathOptInterface` is one of the two sources of `JSON` — 3872 invalidated
instances in the earlier count.

This is defensible if `test_all()` must be callable from the prompt, and after
rule 3 it costs load time rather than compile time. Decide it deliberately
rather than by inheritance, and write the decision down.

**Still open — see step 13.** `ProjecturedTest` still names all four directly.

### 4. `InetQueuingExample` depends on `Test`

An example package should not need the test standard library. Move whatever uses
it into `InetQueuingTest`.

**Still open — see step 12.** `package/queuing/example/Project.toml` still
declares `Test`.

### DataFrames: the readers keep it, in a package nothing loads by default

It is not the plotting library. It is the **table type of the legacy result
reader**:

- `package/legacy/main/src/simulation/ResultReader.jl` — 30 references. Reads
  OMNeT++ `.sca` and `.vec` files into `DataFrame`s.
- `package/legacy/main/src/document/Simulation.jl` — 6 references.
  `simulation_plot(df::AbstractDataFrame)` builds a plot document from one.

Those results come from the **C++** OMNeT++. The Julia simulator has its own
result store, accumulators and charts, and nothing in the live path touches a
`DataFrame`. DataFrames is also the single largest source of invalidation:
SentinelArrays (4371 + 1332), InlineStrings (4111) and Tables (1226) arrive with
it, about 11000 of the 15286 instances.

**Decision: keep the readers as they are, and move them into a stem of their own
that nothing depends on by default.** Rewriting a working reader buys nothing
once it is not loaded.

```
OmnetppLegacyResult       -> OmnetppLegacy, OmnetppUnits   + DataFrames
OmnetppLegacyResultExample-> OmnetppLegacyResult, OmnetppLegacyExample
OmnetppLegacyResultTest   -> OmnetppLegacyResultExample
```

What moves: `ResultReader.jl` whole, the `simulation_plot(::AbstractDataFrame)`
method, and `attach_units!`. What stays in `OmnetppLegacy`:
`SimulationPlotDocument` and `PlotSeries`, which are documents and hold no table.
`OmnetppLegacyPlot` renders that document and never sees a `DataFrame`, so it is
untouched.

Two callers follow the reader out: `make_simulation_plot_document_example` in
`package/legacy/example/src/document/Simulation.jl:64`, and the `attach_units!`
cases in `package/legacy/test/src/simulation/QuantityTest.jl`.

**`Omnetpp`, `OmnetppExample`, `OmnetppTest` and `OmnetppRepl` must not depend on
it** — that is the whole point, and the layering test asserts it. The
consequence to accept knowingly: `using OmnetppLegacyResult` at the prompt loads
a package after the leaf, so that session pays a one-off recompilation. Reading
a C++ result file is a rare and deliberate act, and that is the right place for
the cost. `test_all()` will not run `OmnetppLegacyResultTest`; call it directly,
and have CI call both.

A note on names: `Plot` and `Result` are **stems**, not kinds. The five reserved
suffixes are the kinds — nothing, `Example`, `Test`, `Repl`, `Build` — so this
stem's own kinds are `OmnetppLegacyResultExample` and `OmnetppLegacyResultTest`.

**Done, with one simplification: no `OmnetppLegacyResultExample`.**
`package/legacy/result/` holds only `OmnetppLegacyResult` and
`OmnetppLegacyResultTest` (`src/`, `test/`) — the plot example that motivated a
separate example package is synthetic-only, so `OmnetppLegacyResultTest`
demonstrates the document and its projection directly. See step 14.

### CairoMakie: removed

Not relocated — removed. `OmnetppLegacyPlot` has three uses of it, and every one
has an answer in code we already own. GeometryBasics (2400 + 2049), StructArrays
(1028), MathTeXEngine and one of the two sources of `JSON` leave with it, and so
does `LaTeXStrings`.

1. **`SimulationPlotToGraphics`** today rasterizes the document with CairoMakie,
   decodes the PNG back to RGBA with `sdl_decode_image`, and embeds it as a
   `GraphicsImage`. Replace it with what its name says: a real projection from
   `SimulationPlotDocument` to a `GraphicsCanvas`, drawn with our own primitives.
   The presentation package already draws line, bar, scatter, histogram and
   colour-strip charts this way, each with a page in the demo catalog; a
   `PlotSeries` maps onto them. This also removes a raster round trip and turns a
   picture back into a projection the reader can select in.
2. **`save_simulation_plot`** becomes `write_image(doc, SimulationPlotToGraphics(),
   path)`. `ProjecturedSdl` already provides `write_image` and
   `OmnetppLegacyPlot` already depends on it.
3. **`save_formula_image`** renders a LaTeX formula to a PNG through
   MathTeXEngine. It has exactly **one** caller —
   `package/legacy/example/src/document/Mm1k.jl:479`, one formula in the M/M/1/K
   study. We have a math domain with its own projections; render it there and
   write the PNG the same way as 2. If that is more than the one picture is
   worth, drop the picture.

**Done — see step 15.** `package/legacy/plot/Project.toml` no longer names
`CairoMakie` or `LaTeXStrings`.

**`OmnetppBenchPlot` is already dead.** It depends on `Plots`, `CSV` and
`DataFrames`, and `Plots` is not installed in the root environment — the package
cannot resolve. Delete it or rebuild it on our own charts.

**Not done, and the premise turned out wrong — see step 16.**
`OmnetppBenchPlot` (`benchmark/plot/`) is not dead; it was never wired into the
root environment in the first place, its own `Project.toml` says to instantiate
it standalone, and it still depends on `Plots`, `CSV` and `DataFrames`
unchanged. "Cannot resolve" described that isolation, not a broken package, so
nothing was deleted or rebuilt.

**Lerche is genuinely needed** and should stay: it is the grammar engine behind
the NED and INI parsers in `OmnetppFormat`, two real grammars. It costs 2796
instances by defining `hash(::Lerche.Token)`. Keep it, and keep it named — it is
the reason `OmnetppFormat` is a slice of its own rather than part of the
simulator.

## The exceptions that remain

After the removals above, every third-party dependency left in the three
repositories is here. Each one needs a line in `documentation/packages.md`
saying which package owns it and why; the list below is that text in draft.

### Keep, and write down why

| dependency | owner | why it stays |
| --- | --- | --- |
| `Unitful` | `OmnetppUnits` | quantities carry their units through the whole simulator; this is a modelling decision, not a convenience |
| `DataStructures` | `OmnetppSimulator` | the event queue |
| `Lerche` | `OmnetppFormat` | the NED and INI grammars are real grammars |
| `SDL2_jll`, `SimpleDirectMediaLayer` | `ProjecturedSdl` | a window and a pointer have to come from somewhere |
| `Libdl` | `ProjecturedAdaptagrams` | loads the layout shim |
| `FFMPEG` | `ProjecturedVideo` | encodes a recording |
| `HTTP`, `JSON3` | `ProjecturedLlm`, `ProjecturedWeb` | a wire protocol we do not define |
| `ModelContextProtocol` | `ProjecturedMcp` | likewise |
| `OrdinaryDiffEqCore`, `OrdinaryDiffEqTsit5`, `StaticArrays` | `OmnetppDynamics` | the continuous half of hybrid dynamics is a solver, and writing one is not this project's business |
| `DBInterface`, `ODBC`, `Tables` | `ProjecturedOdbc` | a database driver |
| `MathOptInterface`, `Tulip` | `ProjecturedTulip` | a linear programming solver |
| `PackageCompiler`, `FixedPointNumbers` | `ProjecturedExecutable` | a leaf; nothing depends on it |
| `PrecompileTools` | the example packages that hold a workload body, and the leaves | the mechanism itself |
| `Preferences` | the leaves | the workload level |
| `SQLite`, `DBInterface` | `OmnetppSimulatorTest` | a test writes results to a database |
| `DataFrames` | `OmnetppLegacyResult` | the C++ result readers, in a package nothing loads by default |

`Unitful` is worth a second look, because it is an invalidator too:
`(:)(::Any, ::Quantity)` cost 3044 instances in the whole-session pass. It is
nonetheless in the right place — the lowest package that needs it — so
everything above is compiled with it present and nothing above is voided. That
is the general rule stated as an example: **an unavoidable invalidator belongs
as low as it can go.**

### Decide, rather than inherit

| dependency | the question |
| --- | --- |
| `ODBC`, `Tulip`, `FFMPEG` | **not yet settled — still open, see step 13.** `ProjecturedTest`'s `Project.toml` still names `ProjecturedOdbc`, `ProjecturedTulip`, `ProjecturedVideo` and `ProjecturedSdl` directly today, so `ProjecturedRepl` still loads all of them through `ProjecturedTest`; the deliberate-decision write-up in `packages.md` this row asks for has not been made |
| `OrdinaryDiffEq*` via `OmnetppPresentationExample` | the demo has hybrid-dynamics pages and `src/OmnetppPresentationExample.jl` imports `OmnetppDynamics` to register its doctype module (now at line 27 of that file, unchanged), so this one is real. Keep it, and know that the demo session carries a solver stack. Still a plain dependency, not a weak one — see step 16b |

### Remove

| dependency | where | what to do |
| --- | --- | --- |
| `BlackBoxOptim` | `OmnetppPresentationExample` `[deps]` | used only from `watch/adaptive.jl`, which runs in the watch environment where it is installed, and `OmnetppSimulator` reaches it through an extension. Nothing under `src/` imports it. Drop it from the package. **Still open — see step 16a**; still a plain `[deps]` entry today |
| `CairoMakie`, `LaTeXStrings` | `OmnetppLegacyPlot` | replaced by our own charts, above. **Done — see step 15**; neither name is in the `Project.toml` any more |
| `Plots`, `CSV`, `DataFrames` | `OmnetppBenchPlot` | the package cannot resolve — `Plots` is not installed. Delete it or rebuild it on our own charts. **Dropped — see step 16**; the package was already isolated in its own standalone environment and never reached the root, so it was left as is |

## Guards

- **A layering test**, next to `test_kernel_layering()`: no package depends on a
  `Repl` or a `Build` package; no `Example` is a dependency of a non-`Example`;
  no `Test` is a dependency of anything but a `Test` or a `Repl`.

  **Done**, as `test_package_graph()` in projectured-julia
  (`package/projectured/test/PackageGraphTest.jl`) and omnetpp-julia
  (`package/omnetpp/test/PackageGraph.jl`), and as the unnamed `@testset` in
  `package/inet/test/packagegraph.jl` for inet-julia.
- **A recompile check**: open a page in a `Repl`-shaped session and assert
  `@timed`'s `recompile_time` is near zero. That single number is what makes a
  misplaced dependency visible, and it is how this whole problem surfaced.

  **Not automated in any of the three repositories.** The number is measured by
  hand and recorded in each repository's "Result" section rather than asserted
  by a test.
- **An external-dependency list**, asserted rather than described: the set of
  non-standard-library dependencies per package is written down, and the test
  fails when a package acquires one that is not on its list. That is what stops
  a `DataFrames` from arriving in the middle of the stack again.

  **Done only in inet-julia** (`packagegraph.jl`'s `"a third-party dependency is
  one that was named"` testset). Still owed in projectured-julia and
  omnetpp-julia — both `test_package_graph()`s say so in their own comments.

## Documentation

The architecture is only useful if it is written down where a reader looks
first. After the convention is applied, each repository gets a package document
and the existing guides point at it.

- `documentation/packages.md` in each of the three repositories: the five kinds,
  the dependency direction, the full table of what depends on what, the external
  dependency of each package and why it has one, the environments and what each
  is for, and which package is the leaf the alias loads.
- [documentation/architecture.md](../../documentation/design/system-anatomy.md) in
  projectured-julia gains the leaf and workload rules next to the existing
  layer and slice vocabulary, and links to `packages.md`. The division
  vocabulary in [terminology.md](../../documentation/rule/division-terminology.md) gains
  `leaf` as a term, since the whole convention turns on it.
- Each repository's `CLAUDE.md` gains one line: where a new package goes, and
  that a `@compile_workload` belongs only in a leaf.
- The document and the layering test are written together and say the same
  thing. The test is the authority; the document explains it.

## Steps

**No longer held.** The domain package split landed on projectured-julia `main`
(see [plan/done/split-domain-into-per-domain-packages.md](../done/split-domain-into-per-domain-packages.md))
and steps 0-9, 14, 15, 17 and 18 below are done. See the status banner at the
top for what is still open.

- [x] 0. The split lands. Re-read the dependency tables against the packages it
      produced, then start.
- [x] 1. This plan, and companion plans in omnetpp-julia and inet-julia.
- [x] 2. `precompile_workload(level)` in `ProjecturedExample`, wrapping the
      bodies that exist. No call-site moves yet.
- [x] 3. `ProjecturedRepl`, with the Preferences-driven level and
      `set_workload!`. **The environments and the per-stem extensions are not
      done**: `ProjecturedTest` still aggregates Odbc, Tulip and Video, so
      `env/core` cannot be leaner than `env/full` until step 13 is decided. The
      leaf reproduces today's `jp` session and is precompiled last, which is
      what the measurement needed.
- [x] 4. The binary chooses its level. `precompile_warmup` already warms the
      *configured* domains, which is what a single-domain binary wants, so an
      unconditional catalog sweep would be wrong. `BuildSpec(…; workload =
      :full)` renders `APP_WORKLOAD`, which defaults to `:none`.
- [x] 5. The call site moved out of the example package. The split had already
      consolidated the two into one, so there was one site to move.
- [x] 6. Three assertions in `test_package_graph`: nothing depends on a leaf,
      an example package is a dependency only of a leaf or an example or a test,
      and a compile workload lives only in a leaf. 318 pass. The
      external-dependency list is still owed.
- [x] 7. omnetpp-julia: `OmnetppRepl` exists (`package/repl/src/OmnetppRepl.jl`).
      The workload body ended up in
      `OmnetppPresentationExample.precompile_workload`, not `OmnetppExample`,
      because `OmnetppExample` never grew one. Full detail in the companion
      plan, now `omnetpp-julia/plan/done/package-convention-repl-leaves.md`.
- [x] 8. inet-julia: `InetExample.precompile_workload` and `InetRepl` both
      exist, matching this line as written. See
      `inet-julia/plan/pending/package-convention-repl-leaves.md`.
- [x] 9. The three aliases. `~/.bashrc` has `jp`/`jo`/`ji`, each
      `julia --project=<repo> ... -e "using Revise, <Stem>Repl"` — nothing loads
      after the leaf.
- [x] 10. Done, but differently than described: `OmnetppPresentation` composes
      the topology projection itself, in
      `package/presentation/main/src/module/SimulationTopologyToWidget.jl`,
      rather than moving the factory function into a domain package.
      `OmnetppPresentation`'s `Project.toml` names no `Example` package.
- [ ] 11. The legacy pages' coverage moves to `OmnetppLegacyTest`, so
      `OmnetppPresentationTest` stops needing `OmnetppLegacy`. **Dropped — the
      premise was wrong.** `Omnetpp` depends on `OmnetppLegacy` and `OmnetppRepl`
      depends on `Omnetpp`, so a `jo` session loads legacy whatever the
      presentation test does; moving the coverage would only have saved a
      presentation-only test run. `OmnetppPresentationTest` still imports
      `OmnetppLegacy` directly today, with the reasoning recorded next to the
      import.
- [ ] 12. `InetQueuingExample` stops depending on `Test`. Still open:
      `package/queuing/example/Project.toml` still declares `Test`, and
      `TutorialTest.jl` still lives inside the example package. Tracked as its
      own open step in inet-julia's companion plan.
- [ ] 13. Decide `ProjecturedTest`'s optional slices deliberately, and write the
      decision into `documentation/packages.md`. Still open: `ProjecturedTest`
      still declares `ProjecturedOdbc`, `ProjecturedTulip`, `ProjecturedVideo`
      and `ProjecturedSdl` directly, and `documentation/packages.md` gives a
      reason for each dependency but does not name this choice as a decision.
- [x] 14. `OmnetppLegacyResult` and `OmnetppLegacyResultTest` exist
      (`package/legacy/result/`), hold the readers and `DataFrames`, and nothing
      in `Omnetpp`, `OmnetppExample`, `OmnetppTest` or `OmnetppRepl` depends on
      the package.
- [x] 15. Done. `package/legacy/plot/Project.toml` no longer names `CairoMakie`
      or `LaTeXStrings` — only a doc comment in `OmnetppLegacyPlot.jl` still
      mentions CairoMakie, as history.
- [ ] 16. Delete or rebuild `OmnetppBenchPlot` — `Plots` does not resolve.
      **Dropped — the premise was wrong.** `OmnetppBenchPlot` (`benchmark/plot/`)
      was never in the root environment; its own `Project.toml` says to
      instantiate it standalone, and it still depends on `Plots`, `CSV` and
      `DataFrames` unchanged. It costs no session anything, so nothing moved.
- [ ] 16a. `BlackBoxOptim` out of `OmnetppPresentationExample`'s `[deps]` —
      only `watch/adaptive.jl` uses it, and that runs in the watch environment.
      Still open: `package/presentation/example/Project.toml` still lists
      `BlackBoxOptim` as a plain dependency.
- [ ] 16b. `OmnetppDynamics` becomes a weak dependency of
      `OmnetppPresentationExample`, with an extension holding the one
      `register_doctype_module!` call. The demo stops loading a solver. Still
      open: `OmnetppDynamics` is still a plain `[deps]` entry, and
      `src/OmnetppPresentationExample.jl` still does `import OmnetppDynamics`
      and the call directly.
- [x] 17. `documentation/packages.md` exists in all three repositories, and
      `architecture.md` and `CLAUDE.md` point at it in each. `terminology.md`
      only exists in projectured-julia, where it gained `leaf` as a term.
- [x] 18. Re-measured in all three repositories — see each repository's
      "Result" section and its companion plan.
      [recorded-precompile-workload.md](../done/recorded-precompile-workload.md)
      (done) re-measured again after replacing the four levels here with
      `:none`/`:recorded`/`:live`.

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

### What landed in projectured-julia

Branch `package-convention`, worktree `projectured-julia-packages`.

**The split had silently disabled the whole build-time workload.**
`package/projectured/example/Precompile.jl` was orphaned: nothing included it,
`PrecompileTools` was no longer a dependency, and the three names it exports did
not exist. `ProjecturedExample` precompiled in 10.6 s because the workload was
not running. Restoring the include takes it to 102 s, which is the compilation
being bought back. Everything `precompile-workloads.md` implemented had stopped
applying.

**First paint in a fresh session**, through `NaturalToGraphics`, with the
workload now in the leaf:

| level | json | workbench |
| --- | ---: | ---: |
| `:none` | 8.360 s | 11.398 s |
| `:minimal` | **0.657 s** | **1.629 s** |
| `:demo` | 0.651 s | 1.638 s |

`recompile_time` is 0.000 s at every level once the workload is in the leaf and
nowhere else — there is no lower image holding compiled code for something to
void. Before the move, `:none` showed 1.15 s (json) and 2.71 s (workbench) of
recompilation, which is the same damage the demo click showed at larger scale.

`:demo` costs 42 s of build against `:minimal`'s 24 s and buys nothing on these
two paints — it compiles the parser and stub-walk halves, which a first paint
does not exercise. That is the level doing its job: `:minimal` for a working
day, more only when the extra path is the one being shown.

**The demo click did not move, and could not have.** Measured on the `jo`
session after this landed: `open_page!` 1.271 s, first paint 4.404 s — the same
5.7 s as before. A `jo` session never loads `ProjecturedRepl`, so no workload
runs in it. The leaf has to be the *last package the session loads*, and for
`jo` that is an omnetpp package. This is structural, not an oversight: the
omnetpp-julia half is required for the click, and the inet-julia half for `ji`.

What did move is a `jp` session, which is what `ProjecturedRepl` is for: first
paint 8.360 s to 0.657 s.

The scratch probe already measured what the omnetpp leaf is worth, since it was
one in all but name: the click at 0.55 s with a workload, 0.24 s with
`@recompile_invalidations` as well, against 5.98 s with neither.

**Still owed here**: the environments, the per-stem extensions, and the
`ProjecturedTest` decision they wait on (step 13).

### The two mechanisms, measured

The table under "Levels" is the answer: the click falls from **5.98 s to 0.24 s**,
and the two mechanisms fix different halves. Build cost is what separates a
default from a demo setting: ~10 s for the workload, ~96 s more for
`@recompile_invalidations`.

### A workload inside an extension works

A probe package declared `Preferences` weak with an extension holding a
`@compile_workload` over `weigh(Box{T})`. In a fresh session with both loaded:

| call | compile time |
| --- | ---: |
| `weigh(Box{Int64})` — named by the extension's workload | **0.0000 s** |
| `weigh(Box{Bool})` — not named | 0.0224 s |

So the extension image carries the compiled code, and a heavy stem's workload can
live in an extension of the Startup package: present when the stem is, absent
when it is not. That is what makes `:demo` in `env/core` cheap.

### A catalog workload runs during precompilation

`demo_catalog()`, `open_page!` and a forced canvas all ran inside
`@compile_workload` with no failure. A dependency's `__init__` **does** run while
a dependent package is precompiled, so the marker and doctype registries are
populated; only the package's own `__init__` is skipped, and a Startup package
has none. The concern recorded in
[precompile-workloads.md](../done/precompile-workloads.md) does not apply at
this level.

### What this probe did not test

It named the whole session in the Startup package's `[deps]` rather than letting
an environment compose it. The mechanism is the same either way — the leaf is
last — but the environment shape is still unmeasured.
