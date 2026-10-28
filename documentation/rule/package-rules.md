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
`build/app/<name>/`. That package is a leaf: nothing depends on it. A tool is not
a stem artifact at all.

`Example`, `Test`, `Repl` and `Build` are the only reserved suffixes. A package
whose name merely begins with another's — `ProjecturedODBC`, `ProjecturedTulip`
— is a **stem of its own**, not a kind of `Projectured`.

## One dependency direction

```
Foo         -> Bar, and every sub-stem of Foo
FooExample  -> Foo,  BarExample
FooTest     -> Foo,  BarTest, FooExample
FooRepl     -> ProjecturedTest and what a prompt needs          (leaf)
FooBuild    -> FooExample                                       (leaf)
```

**Nothing may depend on a `Repl` or a `Build` package.** A leaf is what a person
or a binary loads last, and nothing builds on it. `test_package_graph()` asserts
it, along with these:

- an example package is a dependency only of a leaf, an example or a test;
- a package compiles ahead of time only with the one `@compile_ahead` at the end
  of its entry file, and it depends on `ProjecturedPrecompile` (see
  [the next section](#how-a-package-compiles-ahead));
- a package whose slice has natural rows runs
  `run_natural_rows_workload(<Domain>Module)` in the workload of its
  `@compile_ahead`;
- a package whose slice has a file of a workload runs
  `run_file_workload(<Domain>Module.<Type>)` in that workload too.

### A package with a third-party dependency is a stem, not a sub-stem

`ProjecturedAll` aggregates the kernel, the platform, the console and PDF
backends and the eighteen domain packages, none of which has a third-party
dependency. It deliberately does not aggregate `ProjecturedSDL`, `ProjecturedODBC`, `ProjecturedTulip`,
`ProjecturedVideo`, `ProjecturedAnthropic`, `ProjecturedOllama`, `ProjecturedACP`, `ProjecturedMCP`,
`ProjecturedWeb`, `ProjecturedDataFrames`, `ProjecturedLanguageServer` or
`ProjecturedAdaptagrams`, each of which owns one. The umbrella `Projectured`
depends on `ProjecturedPlatform` and `AutoIntegration`, and re-exports only the
names of `ProjecturedPlatform.EssentialsModule`. AutoIntegration loads each
other installed package whose triggers are all loaded and whose state is
`"auto"`; [autointegration.md](../package/autointegration/autointegration.md)
says how.

The rule: a sub-stem is a layer and carries no third-party dependency of its
own; a package that has one is a stem in its own right, named explicitly by
whoever wants it. Without it, `using ProjecturedAll` would drag an ODBC driver
manager and a linear-programming solver into every session.

`ProjecturedIntegrations` (its code is in `source/integrations/`) carries no
third-party dependency of its own either —
each one is a `[weakdeps]` entry behind a package extension — but it still
installs every third-party package that the six integrations own, because
`add` installs the `[deps]` of each one. A user who wants all of them names
this package; a user who does not stays with the ones installed by name. See
[autointegration.md](../package/autointegration/autointegration.md).

## How a package compiles ahead

Julia compiles a function at its first call, and a new process forgets what the
last one compiled. So each package compiles its code ahead of time, into its
image, with the one mechanism of
[compile-ahead.md](../design/compile-ahead.md): the call `@compile_ahead` of
`ProjecturedPrecompile` at the end of its entry file.

```julia
using ProjecturedPrecompile: @compile_ahead
@compile_ahead begin
    run_natural_rows_workload(JsonModule)
    run_file_workload(JsonModule.JsonFile)
end
```

The workload drives the package as a person does. The preference
`precompile_calls` of the package chooses what its build compiles: `"none"`,
`"recorded"`, the calls of the files in its folder `precompile/`, which is the
default, or `"live"`, a run of the workload. The preference `precompile_failure`
chooses what a failure does. [precompile.md](../package/tool/precompile/precompile.md)
says how the package works and how a recording is made.

A package with no workload of its own writes `@compile_ahead` alone. It still
compiles the calls that an application records for it, because a recording
gives each call to the lowest package that sees each type that the call names.

### A package that a user loads compiles its own first window

A user of the released packages loads no leaf of ours: a session writes `using
Projectured, DataFrames, SimpleDirectMediaLayer`, and its first window must not
wait for the compiler. So each package that such a session loads and whose code
the first window runs has the first window in its workload:
`ProjecturedPlatform`, `ProjecturedDataFrames` and `ProjecturedSDL`. Each calls
`run_display_workload` of the platform, which runs the first window of
`display_in_editor`, with a backend that has no device or with an offscreen SDL
window, and gives it the gestures of a first look.

Every first window builds the natural table of the display, with the rows of
each domain that the session has loaded, also when it shows no document of that
domain. A slice has natural rows when it calls a `register_natural_…!`
function or defines a method of `make_graphics_projection` for a type. So the
workload of a package whose slice has natural rows calls
`run_natural_rows_workload(<Domain>Module)`.

`run_natural_rows_workload` runs the `__init__` of the module, where the domain
registers its rows, and builds the table as the display does. The workload runs
while the package precompiles, before that `__init__`, so without the call it
would build no row of the domain. A package that only depends on such a domain,
as `ProjecturedFSM` depends on `ProjecturedGraph`, needs no workload of its own.

That code survives only where no package loaded later can invalidate it. Three
rules keep it valid with any packages that a session loads after it:

1. **A value of unknown type gets its type before a call that other packages
   extend.** A value from a cell is `Any`. Give it its concrete type with an
   assertion (`::Int`, `::String`, `::NamedTuple`) before it reaches `Int`,
   `length`, `merge`, `sort!` or the like, and assert the result of a call that
   gives up during inference. Do not annotate the argument of such a helper with
   a narrow abstract type: `size::Integer` makes Julia infer the body for
   `Integer`, where `Int(size)` meets every constructor that a package adds. Ask
   `hasfield(typeof(x), name)` of a struct, not `hasproperty`, which DataFrames
   extends.
2. **A call of a protocol that packages loaded later extend goes through
   `invokelatest`.** No argument type can keep such a call valid. The editor loop
   calls the backend protocol so, and so do the window check and the choice of a
   backend.
3. **An integration loads the packages below it before the package that it
   joins**, as a session does: `ProjecturedDataFrames` loads the platform, then
   DataFrames. Its build then meets the platform code that the joined package
   invalidates, and its workload compiles that code into its image.

Measured on the session of the README, the first frame of a data frame of
100 000 rows (Julia 1.13.1, one thread, the window offscreen):

| | first frame |
| --- | ---: |
| with no workload in a package | 48.3 s |
| with a workload in each package, and the three rules | **0.75 s** |

### A package compiles the gestures of its home

After the first window, a person clicks a menu, a tool of the toolbar, a file and
the assistant. Each gesture runs code that the first window did not run. So the
workload of each package runs the gestures whose code it holds, the gestures of
its home:

| Package | The gestures of its home |
| --- | --- |
| `ProjecturedPlatform` | the application window (`run_window_workload`): each item of each menu but File › Exit, each tool of the toolbar, a text file and a `.pred` file opened and edited, the Explorer and its context menu, a new tab named in the name buffer, F1, the command palette, and an assistant turn with a tool call |
| `ProjecturedSDL` | the same list on an `SdlBackend`, with each input in the event queue of SDL (`run_sdl_window_workload`) |
| a package whose slice has a file of a workload | the gestures of a file of its format (`run_file_workload`): open it from the Files pane, click in it, type, save, undo, and the name buffer |
| `ProjecturedExample` | each example, opened in a window and sent one event of each kind (`run_example_workload`) |

A slice has a file of a workload when it defines a method of
`make_workload_file`. A domain with a file format gives a file of that format; a
domain with no file format gives a `.pred` file that holds one of its documents.

A gesture runs through the real loop of the editor. The workload finds each
target in what the window drew, gives the inputs to the backend as a device gives
them, and waits until the window is quiet. The body of a workload lets a fault
through: it throws an error that names each step whose target the window did not
draw and each fault that a barrier of the editor caught. A test of the package
calls the body in a normal process (`test_window_workload`, `test_sdl_workload`,
`test_file_workloads`). In a build, the preference `precompile_failure` of the
package says what the error does.

To build a package quickly while you change it, set its preference in
`LocalPreferences.toml`:

```toml
[ProjecturedPlatform]
precompile_calls = "none"
```

## The session

```bash
jp   # julia --project=environment/all -i -e 'using Revise, ProjecturedREPL'
```

`ProjecturedREPL` re-exports what it names, so one `using` gives the session you
expect: `run_example`, `test_all`, `SdlBackend`, every document and projection
constructor. Revise stays in the alias and out of the package's dependencies: it
must be loaded before the packages it tracks, and as a dependency its position
in the load order is the resolver's business.

`ProjecturedREPL` has no workload of its own. The session gets its compiled code
from the images of the packages below it, as their preference
`precompile_calls` says. Record the calls of a package again when its code moves:

```julia
julia> using ProjecturedPrecompile
julia> record_package_calls!("ProjecturedJSON")   # one package
julia> record_repository_calls!()                 # each package of the repository
```

## What depends on what

Every dependency below is **direct**: the package imports a module of it. Julia
needs each direct dependency in `[deps]`, and
`ProjecturedTest.test_package_graph()` asserts that a package declares exactly
the packages its own source names — no more and no less.

The kernel depends on one package, Preferences, which reads its compile-time
switches. A row names the kernel only where it is the one dependency.

### The slices of the platform

One package, `ProjecturedPlatform`, holds every slice below. A slice names
the other slices it depends on the same way a package would; the layering
guard of the platform checks every edge below against the code.

| slice | depends on | third-party |
| --- | --- | --- |
| `collection` | Kernel | — |
| `serialization` | Kernel | Serialization |
| `primitive` | Kernel | — |
| `domain` | Kernel | — |
| `style` | Serialization | — |
| `component` | Kernel | — |
| `projection` | Collection, Primitive | — |
| `dragging` | Collection, Projection | — |
| `focus` | Collection | — |
| `versioning` | Collection, Domain, Primitive | — |
| `plot` | Style | — |
| `graphics` | Collection, Projection, Style | — |
| `screen` | Collection, Graphics, Primitive, Projection | — |
| `layout` | Collection, Focus, Graphics, Projection | — |
| `text` | Collection, Domain, Graphics, Layout, Primitive, Projection, Style | — |
| `widget` | Collection, Domain, Focus, Graphics, Layout, Primitive, Projection, Screen, Serialization, Style, Text | — |
| `reflection` | Collection, Widget | — |
| `clipboard` | Collection, Domain, Primitive, Projection, Serialization, Text | — |
| `pane` | Clipboard, Collection, Domain, Dragging, Focus, Layout, Primitive, Projection, Screen, Serialization, Style, Widget | — |
| `tooltip` | Screen | — |
| `natural` | Collection, Domain, Layout, Primitive, Projection, Style, Text, Widget | — |
| `syntax` | Collection, Domain, Natural, Primitive, Projection, Style, Text | — |
| `inspector` | Domain, Natural, Projection, Screen, Serialization, Style, Text | — |
| `gesturehelp` | Collection, Graphics, Projection, Screen, Style, Syntax, Text | — |
| `gesturelog` | Collection, Domain, Graphics, Natural, Projection, Serialization, Style, Syntax, Text | — |
| `mcplog` | Collection, Domain, Layout, Natural, Primitive, Projection, Serialization, Shell, Style, Widget | — |
| `terminal` | Domain, Layout, Natural, Primitive, Projection, Style, Widget | — |
| `task` | Collection, Domain, Focus, Graphics, Layout, Natural, Pane, Primitive, Projection, Style, Widget | — |
| `fileformat` | Collection, Domain, Layout, Natural, Primitive, Projection, Serialization, Style, Syntax, Text, Widget | — |
| `fault` | Collection, Domain, Graphics, Natural, Projection, Serialization, Style, Syntax, Text, Widget | — |
| `display` | Natural, Screen, Style, Widget | — |
| `essentials` | Display, Natural, Style | — |

This is not every slice of the platform: `gesturetracking`, `dragtracking`,
`filesystem`, `undo`, `log`, `statistics`, `shell`, `help`, `conversation`,
`assistant`, `appearance`, `settings`, `settingsmanaging` and `application` are
the rest, and `PLATFORM_SLICE_EDGES` in
[PlatformSuite.jl](../../test/platform/PlatformSuite.jl) has every one of the
forty-eight. `ProjecturedConsole` and `ProjecturedPDF` are backend packages,
not slices of the platform, even though neither carries a third-party
dependency.

### The eighteen domains

Each domain depends on the kernel, on the platform, and on the domains it
embeds. [domain-inventory.md](../design/domain-inventory.md) has the table.

### The packages that own a third-party dependency

| package | depends on | third-party |
| --- | --- | --- |
| `ProjecturedAnthropic` | Kernel | HTTP, JSON3 |
| `ProjecturedOllama` | Kernel | HTTP, JSON3 |
| `ProjecturedACP` | Kernel | JSON3 |
| `ProjecturedLanguageServer` | Domain, Editor, FileFormat, Graphics, Projection, Serialization, Style, Text, Undo, Widget | JSON3 |
| `ProjecturedOpenRouter` | Kernel | HTTP, JSON3 |
| `ProjecturedMCP` | Kernel, McpLog | ModelContextProtocol |
| `ProjecturedTulip` | Layout | MathOptInterface, Tulip |
| `ProjecturedVideo` | Graphics, Kernel, Screen, Sdl | FFMPEG |
| `ProjecturedAdaptagrams` | Graph | Libdl |
| `ProjecturedSDL` | Collection, Graphics, Kernel, Screen, Style | SDL2_jll, SimpleDirectMediaLayer |
| `ProjecturedWeb` | Collection, Graphics, Kernel, Screen, Style | Base64, HTTP, JSON3 |
| `ProjecturedODBC` | Collection, Database, DbCatalog, Kernel, Projection, Sql, Syntax, Text | DBInterface, ODBC, Tables |
| `ProjecturedDataFrames` | Collection, Kernel, Layout, Primitive, Projection, Style, Widget | DataFrames |

### The aggregate and the leaves

| package | depends on |
| --- | --- |
| `Projectured` (umbrella) | the platform, AutoIntegration |
| `AutoIntegration` | — (its own repository, `projectured/AutoIntegration.jl`; the TOML standard library alone) |
| `ProjecturedIntegrations` | the umbrella, the six packages that own a third-party dependency |
| `ProjecturedAll` (released) | Kernel, the platform, Console, PDF, the 18 domains |
| `ProjecturedPlatformExample` | the platform, KernelExample |
| `ProjecturedPlatformTest` | the platform, KernelTest, PlatformExample |
| `<Stem>Example` | `<Stem>`, the Examples below it |
| `<Stem>Test` | `<Stem>`, `<Stem>Example`, the Tests below it |
| `ProjecturedREPL` **(leaf)** | ProjecturedAll, Example, Test, Sdl |
| `build/app/<name>` **(leaf, written by a build)** | the packages the build names |
| `ProjecturedBuilder` (tool) | — |
| `ProjecturedPrecompile` (tool, released) | — (PrecompileTools, Preferences, TOML); each package that compiles ahead depends on it |

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
- **PrecompileTools**, **Preferences** — the mechanism that compiles ahead,
  through `ProjecturedPrecompile`, which no domain names directly.

**No domain package has a third-party dependency, and none should acquire one.**
A domain that needs one — a real SQL grammar, say — stops being a domain and
becomes an optional stem like `ProjecturedODBC`, named in the table above.

## Adding a package

1. Decide whether it is a **sub-stem** (a layer, no third-party dependency) or a
   **stem of its own** (it has one). Only the first may be aggregated. For a new
   domain, [domain-inventory.md](../design/domain-inventory.md) has the rest.
2. Give it the kinds it needs, with the reserved suffixes.
3. Name every third-party dependency in the table above, with its reason.
4. Do not depend on a leaf. End the entry file with one `@compile_ahead`, with
   the workload of the home of the package, by the rules of
   [the section above](#how-a-package-compiles-ahead).
5. Run `test_package_graph()` — it asserts 2 and 4, and it fails loudly.
