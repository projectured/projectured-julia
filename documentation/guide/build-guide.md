# Build a binary

> **Kind:** procedure · **Status:** current · **Stands on:** [package-rules.md](../rule/package-rules.md)

A build makes a native binary of this repository: a directory that holds an
executable, a system image, the shared libraries and the files that the program
reads while it runs. A person who gets that directory needs no Julia and no
checkout.

This guide says how to start a build, what the options do, how a distribution is
tested, and how to add a binary of your own. For the other compiler, `juliac
--trim`, read [static-compilation-guide.md](static-compilation-guide.md). That
one is an experiment; the builder here is the path that ships.

## Warnings

- **A build uses much memory.** The compile of the system image reached 14 GB.
  Run one build at a time, and run no large model beside it.
- **A build takes minutes.** About 8 minutes for a build on top of the image of
  this Julia, and about 25 minutes for a distribution.

## Run the application without a build

```bash
bin/projectured                       # the window, from this checkout
bin/projectured a.json --window=workbench
bin/projectured --help
```

`bin/projectured` runs the same program that a build compiles: the build
function writes the package of the binary, and asked to compile nothing it
stops there. The script then starts `julia_main` of that package. A change is
tried in the time that Julia needs to compile it, and not in the minutes that a
build costs.

## Start a build

```bash
bin/build_projectured --help
bin/build_projectured
```

The bundle goes to `build/projectured/`, and the executable is
`build/projectured/bin/projectured`. The script is
`source/builder/build_binary.jl` under a name of its own; that front end reads
the command line and calls a build function, and every decision about a build is
in the function.

Without the script:

```bash
julia --project=environment/build source/builder/build_binary.jl --help
julia --project=environment/build source/builder/build_binary.jl projectured
```

The options of the front end:

| Option | What it does |
| --- | --- |
| `--distribution` | build for other machines, test the copy, and write an archive |
| `--backends=<list>` | the backends in the binary (default: `sdl,web`). The first one is its default |
| `--no-workload` | compile no start of the application ahead of time |
| `--no-incremental` | compile a fresh system image, not one on top of the image of this Julia |
| `--filter-stdlibs` | hold only the standard libraries that the program uses. Needs `--no-incremental` |
| `--name=<name>` | the name of the executable and of its directory under `build/` |
| `--output=<dir>` | where the bundle goes |
| `--optimization=N`, `--debug-info=N`, `--strip-metadata` | how the image is compiled |
| `--cpu-target=<target>` | the processors the binary runs on (default: this machine) |
| `--log=<file>` | write the output of the compiler to a file |
| `--log-level=<level>` | the level the binary logs from |
| `--no-compile` | write the package of the binary under `build/app/`, and compile nothing |

`--no-compile` is the fast way to see what a build would make. It writes the
package in a second and compiles nothing.

The same builds start from a Julia session:

```julia
using ProjecturedBuilder                      # julia --project=environment/build
build_projectured_executable()
build_projectured_executable(; compile = false, backends = (:sdl,))
build_projectured_distribution()
```

## What a build makes

1. **A package for the binary**, under `build/app/<name>/`. It names the
   packages that go in, and its module holds the body of `julia_main`, the
   workload, the `--help` text and the build record. A build that would write
   the same package again leaves it alone, so the compiler cache holds.
2. **The bundle**, under `build/<name>/`: `bin/`, `lib/`, `libexec/` and
   `share/`. PackageCompiler writes it, and the build adds the files that the
   program reads while it runs.

Every binary answers four flags that the builder writes itself: `--help`,
`--version`, `--build-info` and `--log-level=<level>`. `--build-info` prints
what went into the build.

## What a binary reads from its bundle

A package reads a file through a path that it computes from its own source
directory. That path is right in a checkout and wrong in a bundle, because the
checkout is not on the machine that gets the bundle. So the binary looks in
`share/projectured/` beside its `bin/` first, and a Julia session, which has no
such directory, reads the checkout as before.

| What | In the bundle | Who reads it |
| --- | --- | --- |
| the text faces | `share/projectured/font` | every backend, to measure and draw text |
| the web client | `share/projectured/web` | the web backend, for the browser |
| the guides | `share/projectured/documentation` | the assistant, to answer about the editor |

The assistant also writes: it keeps the vectors of its search index in
`$XDG_CACHE_HOME/projectured/meaning`, or in `~/.cache/projectured/meaning`. A
Julia session keeps them in `build/meaning/`.

**A new file that the program reads at run time needs two changes**: name it in
the `assets` of the build function, and make the reader look in the bundle
first. Miss one, and the binary works on the machine that built it and nowhere
else.

## Build a distribution

```bash
bin/build_projectured --distribution
```

A distribution is a fresh image for several processor families, so it runs on a
machine that did not build it. The build copies the bundle out of the checkout
and tests the copy before it writes the archive:

1. **The start test.** The copy answers `--build-info` with an empty depot.
2. **The program test.** The copy opens its web server and its MCP server, and
   it must serve the web client, a font, and the list of guides.

Both tests run under `bwrap`, which makes the checkout and the depot look empty
to the copy. **Install `bubblewrap`** (`bwrap`), or a distribution build stops.
The program test also needs `curl`, and the ports 8080 and 9876 free.

The archive lands beside the bundle, as
`build/<name>-<version>-linux-x86_64.tar.gz`, with a `README` that says what the
target machine still needs.

## Add a binary

A binary is a function. `source/builder/ProjecturedProgram.jl` holds the ones of
this repository; write the new one beside them, give the front end a row in its
`BINARIES` table, and add the two scripts in `bin/`: one that runs the program
from the checkout, and one that builds it.

The function calls `build_executable(context; …)` with:

- `packages` — the packages the binary holds, as names. The build finds each one
  and writes it into the package of the binary. Nothing here loads them.
- `main` — an expression whose value is the exit code, the body of `julia_main`.
- `workload` — an expression that runs while the image compiles, so the first
  frames of a real start need no compilation.
- `usage` — a [`Usage`](../../source/builder/Usage.jl): what the binary does,
  and the options it takes. **The options of the program live here**, and a test
  compares them with what the program parses.
- `fonts` and `assets` — what the bundle carries beside the code.

The generic half of the builder knows no program and no repository: a
`BuildContext` says which repository a build writes into and where it finds a
package. That is what lets another repository use the same builder.

## Where the pieces are

| Path | What |
| --- | --- |
| [source/builder/](../../source/builder/) | the builder: context, preferences, usage, app package, executable, distribution |
| [source/builder/ProjecturedProgram.jl](../../source/builder/ProjecturedProgram.jl) | the binaries of this repository |
| [source/builder/build_binary.jl](../../source/builder/build_binary.jl) | the shell front end |
| [bin/](../../bin/) | one script to run a program, one to build it |
| [package/ProjecturedBuilder/](../../package/ProjecturedBuilder/) | the package that holds them |
| [environment/build/](../../environment/build/) | the environment of a build: the builder and PackageCompiler |
| [test/builder/BuilderTest.jl](../../test/builder/BuilderTest.jl) | `test_builder()`: what a build writes, and what it refuses |

The tests compile nothing. Run them with the rest of the suite, or alone:

```julia
using ProjecturedTest                         # julia --project=environment/all
test_builder()
```
