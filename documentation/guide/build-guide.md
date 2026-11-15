# Build a binary

> **Kind:** procedure · **For:** developer · **Status:** current · **Stands on:** [package-rules.md](../rule/package-rules.md)

A build makes a native binary of this repository: a directory that holds an
executable, a system image, the shared libraries and the files that the program
reads while it runs. A person who gets that directory needs no Julia and no
checkout.

This guide says how to start a build, what the options do, how a distribution is
tested, and how to add a binary of your own. For the other compiler, `juliac
--trim`, read [static-compilation-guide.md](static-compilation-guide.md). That
one is an experiment; the builder here is the path that ships.

## Warnings

- **A build uses much memory.** A plain build went past 20 GB, and the
  founding of a reactive store reached 26 GB. Run one build at a time, and run
  no large model beside it.
- **A build takes minutes.** About 8 minutes for a build on top of the image of
  this Julia, and about 25 minutes for a distribution.

## Run the application without a build

```bash
bin/projectured                       # the window, from this checkout
bin/projectured a.json --root=.
bin/projectured --help
```

`bin/projectured` runs the same program that a build compiles: the build
function writes the package of the binary, and asked to compile nothing it
stops there. The script then starts `julia_main` of that package. A change is
tried in the time that Julia needs to compile it, and not in the minutes that a
build costs.

The script loads the packages as Julia does. With another Julia, a change of a
package makes Julia compile that package and every package above it again,
which takes minutes for a change of the platform. With the reactive Julia, the
first start after a small change takes seconds:

- **The changed package gets a patch.** Julia loads the compiled file of the
  package, applies the changed definitions, compiles again the code that they
  reach, and writes only that, as a patch beside the file. A later change adds
  a patch on top of the others.
- **The packages above keep their files.** Julia compiles again, at its first
  call, each function of theirs that called a changed method.
- **A read at the top level is recorded.** A package that expands a macro or
  reads a constant of a package below it at its top level compiles whole when
  that macro or constant changes. The packages that do not read it keep their
  files.
- **Some changes compile the package whole**, as with another Julia: a changed
  type, a changed global that is not constant, a changed `__init__`, a changed
  include of a file that is not a source file, and a change after 32 patches.
- **Revise reads the patch.** In a session, Revise compares an edit with the
  text that the patch applied, so it applies the edit and no more.
- `JULIA_REACTIVE_PACKAGE_PATCH=0` turns the patch off.

The binary has its own fast path: see [Rebuild in seconds](#rebuild-in-seconds).

The first start after an install or an update installs and compiles the
packages of the program, which takes some minutes. When that preparation runs
longer than ten seconds, the script says why the wait comes and shows each
package as it installs and compiles. A normal start spends about five seconds
there and prints nothing, and a failure shows its output. A launcher of another
program that the builder writes does the same, with `run_with_slow_output` of
[LauncherOutput.jl](../../source/tool/builder/LauncherOutput.jl).

## Start a build

```bash
bin/build_projectured --help
bin/build_projectured
```

The bundle goes to `build/projectured/`, and the executable is
`build/projectured/bin/projectured`. The script is `tool/build-binary.jl` under
a name of its own; that front end calls `run_build_command`, which reads the
command line and calls a build function, and every decision about a build is in
the function.

Without the script:

```bash
julia --project=environment/build tool/build-binary.jl --help
julia --project=environment/build tool/build-binary.jl projectured
```

The options of the front end:

| Option | What it does |
| --- | --- |
| `--distribution` | build for other machines, test the copy, and write an archive |
| `--backends=<list>` | the backends in the binary (default: `sdl,web`). The first one is its default |
| `--precompile-calls=<value>` | what each package compiles ahead: `recorded` (default), `live` or `none` |
| `--no-incremental` | compile a fresh system image, not one on top of the image of this Julia |
| `--filter-stdlibs` | hold only the standard libraries that the program uses. Needs `--no-incremental` |
| `--name=<name>` | the name of the executable and of its directory under `build/` |
| `--output=<dir>` | where the bundle goes |
| `--optimization=N`, `--debug-info=N`, `--strip-metadata` | how the image is compiled |
| `--cpu-target=<target>` | the processors the binary runs on (default: this machine) |
| `--log=<file>` | write the output of the compiler to a file |
| `--log-level=<level>` | the level the binary logs from |
| `--no-compile` | write the package of the binary under `build/app/`, and compile nothing |
| `--no-prelink` | leave the restore of the image to every start |
| the options of the reactive build | see [Rebuild in seconds](#rebuild-in-seconds) |

`--no-compile` is the fast way to see what a build would make. It writes the
package in a second and compiles nothing.

The same builds start from a Julia session:

```julia
using ProjecturedBuilder                      # julia --project=environment/build
build_projectured_executable()
build_projectured_executable(; compile = false, backends = (:sdl,))
build_projectured_distribution()
```

## Rebuild in seconds

With the reactive Julia, a build compiles only what changed since the build
before:

```bash
bin/build_projectured                 # the first build founds a store: a whole build
# edit a file of a package of the binary
bin/build_projectured                 # a rebuild: the edit and no more
bin/build_projectured --status
bin/build_projectured --stop-server
```

The first build founds a *store* under the output, `build/projectured/reactive-store`:
the sources that the build tracks, the trace of the workloads, and the snapshots.
Every later build of the output is a rebuild. It reads the tracked sources from
disk, applies what changed to a compiler server that keeps the image in memory,
compiles the edit and no more, and writes an overlay beside the image. The
tracked sources are the files of every package of this repository that the
binary holds. Nothing runs the program during a build.

`--dev --watch` is the loop in one process:

```bash
bin/build_projectured --dev --watch
```

`--dev` compiles the code of a rebuild at `-O1`, and `--watch` rebuilds at
every save of a tracked file until Ctrl-C. Do not press Ctrl-C before the line
`watch: N tracked files` appears: before it, the first build runs.

Every build command made with `ProjecturedBuilder` takes the same options of
the reactive build. `REACTIVE_BUILD_OPTIONS` lists them,
`apply_reactive_build_option!` reads one, and `run_reactive_build_action!`
runs `--status`, `--stop-server` and `--watch`:

| Option | What it does |
| --- | --- |
| `--reactive` | found the store or rebuild it, as a build does by default, and stop when this Julia has no reactive compiler |
| `--no-reactive` | compile the whole program, and found no store; a store under the output goes with the old output |
| `--found` | found the store again now: a whole build, and the chain starts over |
| `--dev` | `--reactive --delta-optimization=1 --debug-info=1` |
| `--watch` | build now, then rebuild at every save of a tracked file until Ctrl-C |
| `--refresh-trace` | before a rebuild, add what the workload compiles from the current binary to the trace of the store |
| `--no-server` | rebuild in a child process, not in the compiler server |
| `--image=overlay\|pages\|whole` | how a rebuild writes the image (default: `overlay`); on Linux only `overlay` |
| `--delta-optimization=N` | the `-O` level of the code of a rebuild, 0 to 3 (default: the level of the build) |
| `--compact=N,F` | found again by itself after a growth of F of the image, or after N rebuilds for `--image=pages` and `--image=whole` (default: `50,0.25`) |
| `--trim` | write the trimmed product too, under `<output>/trimmed` |
| `--status` | print what the store of the output holds, and exit |
| `--stop-server` | stop the compiler server of the store of the output, and exit |

- **The reactive Julia** is the branch `merged` of
  https://github.com/levy/julia, which also writes a pre-relocated image. The
  build environment takes PackageCompiler from the branch `reactive` of
  https://github.com/projectured/PackageCompiler.jl, which builds like the
  released one on another Julia.
- **With another Julia**, a build compiles the whole program, as before, and
  says how to get the reactive Julia. Over an output that holds a store it
  stops, because a plain build removes the store: start it with the reactive
  Julia, or pass `--no-reactive`.
- **The binary keeps what its founding build holds.** A change of the backends,
  of the options of the package, or of `--precompile-calls` is refused with the
  words "founded for another package": found the store again with `--found`.
- **An edit that calls new code** compiles that code at each start of the
  binary until `--refresh-trace` adds it to the trace.
- **The store founds again by itself** when its overlay grew the image by a
  quarter since the founding.
- **The program starts prelinked.** The founding links the image into
  `bin/projectured` and prelinks it, and a start applies the overlay of the
  last rebuild on top: about 60 ms after a founding, and about 110 ms with an
  overlay. `--no-prelink` turns the prelink off. The program reads no other
  image, so on Linux a build refuses `--image=pages` and `--image=whole`. A
  store founded before the program held its image keeps the slower launcher of
  PackageCompiler until `--found`.
- `--no-incremental`, `--distribution` and `PROJECTURED_PERFORMANCE_COUNTERS`
  compile the whole program: a rebuild keeps the image of its founding build.

## What a build makes

1. **A package for the binary**, under `build/app/<name>/`. It names the
   packages that go in, and its module holds the body of `julia_main`, the
   `--help` text and the build record. Its `LocalPreferences.toml` says what
   each package compiles ahead. A build that would write
   the same package again leaves it alone, so the compiler cache holds.
2. **The bundle**, under `build/<name>/`: `bin/`, `lib/`, `libexec/` and
   `share/`. PackageCompiler writes it, and the build adds the files that the
   program reads while it runs. On Linux, `bin/<name>` holds the image and is
   prelinked, so it starts fast; the image as a library, `sys.so`, and its
   object archive go beside the bundle, to `build/<name>.object/`.

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

## Release the packages

The packages reach a Julia programmer through a registry, not as a binary.
[release-guide.md](release-guide.md) says how to make a release of them.

## The agent claude-code-acp

`claude-code-acp`, the agent of the Agent Client Protocol that runs Claude Code,
is built in its own repository,
[ClaudeCodeACP.jl](https://github.com/projectured/ClaudeCodeACP.jl). Its README
says how. ProjecturEd needs no binary of it, because it runs the same agent in
its own process.

## Add a binary

A binary is a function. `source/tool/builder/ProjecturedProgram.jl` holds the
ones of this repository; write the new one beside them, give the front end a row
in its `BUILD_BINARIES` table, and add the two scripts in `bin/`: one that runs
the program from the checkout, and one that builds it.

The function calls `build_executable(context; …)` with:

- `packages` — the packages the binary holds, as names. The build finds each one
  and writes it into the package of the binary. Nothing here loads them.
- `main` — an expression whose value is the exit code, the body of `julia_main`.
- `precompile_calls` — what each package of the binary compiles ahead, as the
  preference of that name says: `"recorded"`, `"live"` or `"none"`. The workload
  of a binary is in its own package, such as `ProjecturedBuild`.
- `usage` — a [`Usage`](../../source/tool/builder/Usage.jl): what the binary does,
  and the options it takes. **The options of the program live here**, and a test
  compares them with what the program parses.
- `fonts` and `assets` — what the bundle carries beside the code.

The generic half of the builder names no program and no repository: a
`BuildContext` says which repository a build writes into and where it finds a
package. That is what lets another repository use the same builder.

## Where the pieces are

| Path | What |
| --- | --- |
| [source/tool/builder/](../../source/tool/builder/) | the builder, `BuilderModule`: context, preferences, usage, app package, executable, distribution, release copy, and the command line (`BuildCommand.jl`) |
| [source/tool/builder/ProjecturedProgram.jl](../../source/tool/builder/ProjecturedProgram.jl) | the binaries of this repository, and what its release copy holds |
| [tool/build-binary.jl](../../tool/build-binary.jl) | the shell front end |
| [bin/](../../bin/) | one script to run a program, one to build it |
| [package/ProjecturedBuilder/](../../package/ProjecturedBuilder/) | the package that holds them |
| [environment/build/](../../environment/build/) | the environment of a build: the builder and PackageCompiler |
| [test/tool/builder/BuilderTest.jl](../../test/tool/builder/BuilderTest.jl) | `test_build_executable()`: what a build writes, and which inputs stop it |
| [test/tool/builder/PackageReleaseTest.jl](../../test/tool/builder/PackageReleaseTest.jl) | `test_package_release()`: the release copy, its versions and its scan |

The tests compile nothing. Their test package is `ProjecturedBuilderTest`, and
`test_builder()` runs both with the layering guard of the builder:

```julia
using ProjecturedBuilderTest     # julia --project=package/ProjecturedBuilderTest
test_builder()
```
