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

## Guards

- **A layering test**, next to `test_kernel_layering()`: no package depends on a
  `Repl` or a `Build` package; no `Example` is a dependency of a non-`Example`;
  no `Test` is a dependency of anything but a `Test` or a `Repl`.
- **A recompile check**: open a page in a `Repl`-shaped session and assert
  `@timed`'s `recompile_time` is near zero. That single number is what makes a
  misplaced dependency visible, and it is how this whole problem surfaced.

## Steps

- [ ] 1. This plan, and companion plans in omnetpp-julia and inet-julia.
- [ ] 2. `precompile_workload(level)` in `ProjecturedExample`, wrapping the
      bodies that exist. No call-site moves yet.
- [ ] 3. `ProjecturedRepl`, with the Preferences-driven level and `set_workload!`.
- [ ] 4. `ProjecturedExecutable` calls `precompile_workload(:full)`.
- [ ] 5. Move the call sites out of `ProjecturedDomainExample` and
      `ProjecturedVisualExample`. **After the domain split lands.**
- [ ] 6. The layering test and the recompile check.
- [ ] 7. omnetpp-julia: `OmnetppExample.precompile_workload`, `OmnetppRepl`.
- [ ] 8. inet-julia: `InetExample.precompile_workload`, `InetRepl`.
- [ ] 9. The three aliases.
- [ ] 10. Re-measure the first click in each repository, at each level.

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
